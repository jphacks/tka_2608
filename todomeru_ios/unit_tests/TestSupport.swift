import Foundation
@testable import todomeru_ios

/// テスト用の固定日時を端末のカレンダー（Calendar.current）で作る。
/// AppDay / TaskFilter が Calendar.current を使うため、テストも同じカレンダーで組み立てる。
func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    let c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return Calendar.current.date(from: c)!
}

/// 「アプリの1日」の切替時刻（その暦日の dayBoundaryHour:00）
func boundary(_ year: Int, _ month: Int, _ day: Int) -> Date {
    makeDate(year, month, day, PolicyConstants.dayBoundaryHour)
}

/// テストごとに一意なファイル名で AppStore を作り、終了後に保存ファイルを消す。
func withTemporaryStore(_ body: (AppStore) throws -> Void) rethrows {
    let fileName = "todomeru-test-\(UUID().uuidString).json"
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let url = dir.appendingPathComponent(fileName)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = AppStore(fileName: fileName)
    try body(store)
}

func makeTask(
    id: String = UUID().uuidString,
    title: String = "テストのやること",
    due: Date? = nil,
    hasTime: Bool = false,
    priority: Int = 0,
    createdAt: Date? = nil,
    completed: Bool = false,
    completionDate: Date? = nil
) -> TaskItem {
    TaskItem(id: id, title: title, listID: "list", listName: "リスト", dueDate: due, dueHasTime: hasTime,
             priority: priority, createdAt: createdAt, isCompleted: completed, completionDate: completionDate)
}

func makeReply(
    action: AIReply.Action = .proposeUnlock,
    score: Int? = PolicyConstants.persuasionApprovalThreshold,
    seconds: Int? = PolicyConstants.persuasionGrantMinSeconds
) -> AIReply {
    AIReply(content: "テスト", convictionScore: score, action: action, taskID: nil, proposedSeconds: seconds)
}

func isSuccess<E: Error>(_ r: Result<Void, E>) -> Bool {
    if case .success = r { return true }
    return false
}

func failure<T, E: Error>(_ r: Result<T, E>) -> E? {
    if case .failure(let e) = r { return e }
    return nil
}

extension AppStore {
    /// テスト用: 取り組みを始めて、指定秒数ぶん経過させてから終える（報酬が記録される）
    func runFocus(seconds: Int, taskID: String = UUID().uuidString) -> FocusSession {
        let s = startFocus(task: makeTask(id: taskID), origin: .home)
        shiftFocusStart(s.id, by: seconds)
        let started = session(s.id)!.startedAt
        endFocus(s.id, at: started.addingTimeInterval(Double(seconds)))
        return session(s.id)!
    }
}
