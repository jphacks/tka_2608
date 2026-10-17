import EventKit
import Foundation
import Observation

/// リマインダー（EventKit）からやることを取得・完了する。
/// 権限がない場合やデモ設定時は、デモ用のやることを使う（画面で「デモ」と分かるように表示すること）。
@Observable
final class ReminderService {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
        /// 権限なし（0件と区別する）
        case denied
    }

    private(set) var lists: [ReminderListInfo] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var state: LoadState = .idle
    private(set) var isDemo = false

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var demoTasks = DemoData.tasks()

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    var hasFullAccess: Bool { authorizationStatus == .fullAccess }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    /// リスト一覧と、選択したリストのやることを再取得する
    func reload(selectedListIDs: Set<String>, useDemo: Bool) async {
        state = .loading
        if useDemo {
            loadDemo()
            return
        }
        guard hasFullAccess else {
            isDemo = false
            lists = []
            tasks = []
            state = .denied
            return
        }
        isDemo = false
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .reminder)
        let targets = calendars.filter { selectedListIDs.contains($0.calendarIdentifier) }

        let incomplete = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars))
        let today = AppDay.interval()
        let completedToday = targets.isEmpty ? [] : await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: today.start, ending: today.end, calendars: targets))

        var counts: [String: Int] = [:]
        for t in incomplete { counts[t.listID, default: 0] += 1 }
        lists = calendars.map {
            ReminderListInfo(id: $0.calendarIdentifier, title: $0.title, openCount: counts[$0.calendarIdentifier] ?? 0, colorHex: $0.cgColor.flatMap(Self.hex) ?? 0xF5A000)
        }
        tasks = incomplete.filter { selectedListIDs.contains($0.listID) } + completedToday
        state = .loaded
    }

    /// やることを完了にする。成功を確認できたときだけ true（AIの発言だけで完了にしない）
    func complete(taskID: String) async throws {
        if isDemo {
            guard let i = demoTasks.firstIndex(where: { $0.id == taskID }) else { throw ReminderError.notFound }
            demoTasks[i].isCompleted = true
            demoTasks[i].completionDate = .now
            tasks = demoTasks
            return
        }
        guard let item = store.calendarItem(withIdentifier: taskID) as? EKReminder else { throw ReminderError.notFound }
        item.isCompleted = true
        try store.save(item, commit: true)
        if let i = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[i].isCompleted = true
            tasks[i].completionDate = item.completionDate ?? .now
        }
    }

    func task(id: String) -> TaskItem? { tasks.first { $0.id == id } }

    // MARK: - private

    private func loadDemo() {
        isDemo = true
        lists = DemoData.lists
        tasks = demoTasks
        state = .loaded
    }

    private func fetch(_ predicate: NSPredicate) async -> [TaskItem] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map(Self.taskItem)
                cont.resume(returning: items)
            }
        }
    }

    nonisolated private static func taskItem(_ r: EKReminder) -> TaskItem {
        let due = r.dueDateComponents
        return TaskItem(
            id: r.calendarItemIdentifier,
            title: r.title ?? "",
            listID: r.calendar?.calendarIdentifier ?? "",
            listName: r.calendar?.title ?? "",
            dueDate: due.flatMap { Calendar.current.date(from: $0) },
            dueHasTime: due?.hour != nil,
            priority: r.priority,
            createdAt: r.creationDate,
            isCompleted: r.isCompleted,
            completionDate: r.completionDate
        )
    }

    nonisolated private static func hex(_ c: CGColor) -> UInt32? {
        guard let comps = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, comps.count >= 3 else { return nil }
        return (UInt32(comps[0] * 255) << 16) | (UInt32(comps[1] * 255) << 8) | UInt32(comps[2] * 255)
    }
}

enum ReminderError: LocalizedError {
    case notFound
    var errorDescription: String? { "リマインダーが見つかりませんでした" }
}

/// D027: ホームの「今日」「すべて」の分類と並び順
enum TaskFilter {
    static func today(_ tasks: [TaskItem], now: Date = .now) -> (open: [TaskItem], done: [TaskItem]) {
        let day = AppDay.interval(of: now)
        let dayDate = AppDay.day(of: now)
        let open = tasks.filter { t in
            guard !t.isCompleted, let due = t.dueDate else { return false }
            if t.dueHasTime { return due < day.end }
            return Calendar.current.startOfDay(for: due) <= dayDate
        }
        let done = tasks.filter { t in
            guard t.isCompleted, let c = t.completionDate else { return false }
            return AppDay.isSameDay(c, as: now)
        }.sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        return (sorted(open), done)
    }

    static func all(_ tasks: [TaskItem]) -> [TaskItem] {
        sorted(tasks.filter { !$0.isCompleted })
    }

    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case (nil, nil): break
            case (nil, _): return false
            case (_, nil): return true
            case let (da?, db?):
                let ka = sortKey(da, hasTime: a.dueHasTime), kb = sortKey(db, hasTime: b.dueHasTime)
                if ka != kb { return ka < kb }
            }
            let pa = priorityRank(a.priority), pb = priorityRank(b.priority)
            if pa != pb { return pa < pb }
            return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }

    /// 日付だけの期限はその日の最後として並べる
    private static func sortKey(_ d: Date, hasTime: Bool) -> Date {
        hasTime ? d : Calendar.current.startOfDay(for: d).addingTimeInterval(24 * 3600 - 1)
    }

    /// 高(1-4)・中(5)・低(6-9)・なし(0)
    private static func priorityRank(_ p: Int) -> Int {
        switch p {
        case 1...4: return 0
        case 5: return 1
        case 6...9: return 2
        default: return 3
        }
    }

    /// 「今日」「明日」「10/20」「期限なし」などの短い表示
    static func dueLabel(_ t: TaskItem, now: Date = .now) -> String {
        guard let due = t.dueDate else { return "期限なし" }
        let cal = Calendar.current
        let today = AppDay.day(of: now)
        let dueDay = cal.startOfDay(for: due)
        let diff = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
        let time = t.dueHasTime ? due.formatted(.dateTime.hour().minute()) : nil
        let base: String
        switch diff {
        case ..<0: base = "期限切れ"
        case 0: base = "今日"
        case 1: base = "明日"
        default: base = due.formatted(.dateTime.month(.defaultDigits).day())
        }
        return time.map { "\(base) \($0)" } ?? base
    }
}

enum DemoData {
    static let lists: [ReminderListInfo] = [
        ReminderListInfo(id: "demo-reminders", title: "リマインダー", openCount: 2, colorHex: 0xF5A000),
        ReminderListInfo(id: "demo-univ", title: "大学", openCount: 3, colorHex: 0x3B82F6),
        ReminderListInfo(id: "demo-english", title: "英語", openCount: 1, colorHex: 0x22C55E),
        ReminderListInfo(id: "demo-house", title: "家事", openCount: 1, colorHex: 0xA855F7),
        ReminderListInfo(id: "demo-shopping", title: "買い物", openCount: 1, colorHex: 0xEF4444),
    ]

    static func tasks(now: Date = .now) -> [TaskItem] {
        let cal = Calendar.current
        let today = AppDay.day(of: now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now }
        return [
            TaskItem(id: "demo-1", title: "【レポート】序論2段落目の続き", listID: "demo-univ", listName: "大学", dueDate: day(0), dueHasTime: false, priority: 1, createdAt: day(-3), isCompleted: false, completionDate: nil),
            TaskItem(id: "demo-2", title: "机の掃除", listID: "demo-reminders", listName: "リマインダー", dueDate: day(0), dueHasTime: false, priority: 0, createdAt: day(-1), isCompleted: false, completionDate: nil),
            TaskItem(id: "demo-3", title: "英単語を5個覚える", listID: "demo-english", listName: "英語", dueDate: day(0), dueHasTime: false, priority: 0, createdAt: day(-2), isCompleted: true, completionDate: at(9, 20)),
            TaskItem(id: "demo-4", title: "洗濯物をたたむ", listID: "demo-house", listName: "家事", dueDate: day(0), dueHasTime: false, priority: 0, createdAt: day(-1), isCompleted: true, completionDate: at(8, 40)),
            TaskItem(id: "demo-5", title: "ゼミ発表のスライド作成", listID: "demo-univ", listName: "大学", dueDate: day(2), dueHasTime: false, priority: 5, createdAt: day(-4), isCompleted: false, completionDate: nil),
            TaskItem(id: "demo-6", title: "統計の課題 第3回", listID: "demo-univ", listName: "大学", dueDate: day(4), dueHasTime: false, priority: 0, createdAt: day(-5), isCompleted: false, completionDate: nil),
            TaskItem(id: "demo-7", title: "TOEICの申し込み", listID: "demo-english", listName: "英語", dueDate: nil, dueHasTime: false, priority: 0, createdAt: day(-6), isCompleted: false, completionDate: nil),
            TaskItem(id: "demo-8", title: "部屋の本を整理する", listID: "demo-reminders", listName: "リマインダー", dueDate: nil, dueHasTime: false, priority: 0, createdAt: day(-7), isCompleted: false, completionDate: nil),
        ]
    }
}
