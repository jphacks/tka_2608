import Foundation
import Observation

/// Shield起点の「やることを選ぶ」から説得へ最初の発言を渡すための一時置き場
enum PersuasionDraft {
    private static var pending: [String: String] = [:]

    static func set(_ text: String, for snsID: String) { pending[snsID] = text }

    /// 取り出したら消す（同じ文を二度送らない）
    static func take(for snsID: String) -> String? { pending.removeValue(forKey: snsID) }
}

/// やることを選ぶ（72:2 / 72:286）の状態と処理
@Observable
final class TaskSelectViewModel {
    enum Content: Equatable {
        case loading
        case denied
        case failed(String)
        case empty
        case candidates(recommended: TaskItem, others: [TaskItem])
    }

    /// 候補として並べる最大件数（おすすめを含む）
    static let maxCandidates = 4

    let origin: Origin
    var selected: TaskItem?
    var isStarting = false
    var startError: String?
    var reasonText = ""

    init(origin: Origin) { self.origin = origin }

    /// 今日の未完了を優先し、なければすべての未完了から候補を出す
    static func candidates(from tasks: [TaskItem]) -> [TaskItem] {
        let today = TaskFilter.today(tasks).open
        let base = today.isEmpty ? TaskFilter.all(tasks) : today
        return Array(base.prefix(maxCandidates))
    }

    func content(reminders: ReminderService) -> Content {
        switch reminders.state {
        case .denied: return .denied
        case .failed(let msg): return .failed(msg)
        case .idle, .loading:
            // 再取得中は直前の候補を出したままにする（開始前の再確認で一覧が消えないように）
            let list = Self.candidates(from: reminders.tasks)
            guard let first = list.first else { return .loading }
            return .candidates(recommended: first, others: Array(list.dropFirst()))
        case .loaded:
            let list = Self.candidates(from: reminders.tasks)
            guard let first = list.first else { return .empty }
            return .candidates(recommended: first, others: Array(list.dropFirst()))
        }
    }

    func select(_ task: TaskItem) {
        guard !isStarting else { return }
        selected = task
        startError = nil
    }

    /// ユーザー発言（「○○をやる！」）
    func userLine(for task: TaskItem) -> String { "「\(task.title)」をやる！" }

    /// アリの案内（数値は PolicyConstants から）
    static var rewardLine: String {
        let interval = PolicyConstants.focusRewardIntervalSeconds / 60
        let focus = PolicyConstants.focusRewardSeconds / 60
        let done = PolicyConstants.completionRewardSeconds / 60
        return "えらい！\(interval)分ごとにSNS時間が+\(focus)分、終わったら+\(done)分 増えるよ。いってらっしゃい！"
    }

    /// 開始直前にやることを再取得して、存在・未完了を確認してから取り組みを始める
    func start(store: AppStore, reminders: ReminderService, router: Router) async {
        guard let task = selected, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs, useDemo: store.settings.useDemoTasks)
        guard let latest = reminders.task(id: task.id), !latest.isCompleted else {
            selected = nil
            startError = "「\(task.title)」は見つからないか、すでに完了しています。もう一度選んでね。"
            return
        }
        let session = store.startFocus(task: latest, origin: origin)
        router.replaceTop(with: .focus(sessionID: session.id))
    }

    /// 理由を入力して説得へ進む（Shield起点のみ）
    /// - Returns: 進めなかったときの理由
    func goPersuade(with text: String?, store: AppStore, router: Router) -> String? {
        guard let snsID = origin.snsID else { return nil }
        guard UnlockPolicy.canStartPersuasion(store: store) else { return PolicyError.quotaExceeded.errorDescription }
        if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            PersuasionDraft.set(t, for: snsID)
        }
        reasonText = ""
        router.replaceTop(with: .persuasion(snsID: snsID))
        return nil
    }
}
