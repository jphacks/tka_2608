import Foundation
import Testing
@testable import todomeru_ios

@Suite("取り組み時間の合計")
@MainActor
struct FocusTimeTests {
    let now = makeDate(2026, 10, 18, 12)

    @Test("取り組み記録がなければ0分")
    func empty() throws {
        try withSessions([]) { store in
            let summary = DailySummary.make(store: store, now: now)
            #expect(summary.focusSeconds == 0)
            #expect(summary.antDegree == 0)
            #expect(summary.grasshopperDegree == 100)
        }
    }

    @Test("取り組み時間に応じて両方の度合いとドットが変わる（目標2時間）",
          arguments: [0, 24, 60, 72, 120, 150])
    func degreesFollowFocus(minutes: Int) throws {
        let expected = try #require([
            0: (percent: 0, antDots: 0, grasshopperDots: 5),
            24: (percent: 20, antDots: 1, grasshopperDots: 4),
            60: (percent: 50, antDots: 3, grasshopperDots: 3),
            72: (percent: 60, antDots: 3, grasshopperDots: 2),
            120: (percent: 100, antDots: 5, grasshopperDots: 0),
            150: (percent: 100, antDots: 5, grasshopperDots: 0)
        ][minutes])
        try withSessions([session(from: now.addingTimeInterval(-Double(minutes * 60)), to: now)]) { store in
            store.settings.dailyFocusGoalSeconds = 120 * 60
            let summary = DailySummary.make(store: store, now: now)
            #expect(summary.antDegree == expected.percent)
            #expect(summary.grasshopperDegree == 100 - expected.percent)
            #expect(DegreeDots.filledCount(percent: summary.antDegree) == expected.antDots)
            #expect(DegreeDots.filledCount(percent: summary.grasshopperDegree) == expected.grasshopperDots)

            // 利用時間は度合いの分母ではない（D011）。
            store.setDemoUsage(60 * 60, for: "x")
            let afterUsingApp = DailySummary.make(store: store, now: now)
            #expect(afterUsingApp.antDegree == summary.antDegree)
            #expect(afterUsingApp.grasshopperDegree == summary.grasshopperDegree)
        }
    }

    @Test("進行中の取り組みで度合いが増え、目標時間の変更も反映する")
    func degreesUpdateDuringFocus() throws {
        try withSessions([session(from: now.addingTimeInterval(-60 * 60))]) { store in
            store.settings.dailyFocusGoalSeconds = 120 * 60
            #expect(DailySummary.make(store: store, now: now).antDegree == 50)
            let later = DailySummary.make(store: store, now: now.addingTimeInterval(24 * 60))
            #expect(later.antDegree == 70)
            #expect(later.grasshopperDegree == 30)
            store.settings.dailyFocusGoalSeconds = 240 * 60
            #expect(DailySummary.make(store: store, now: now).antDegree == 25)
        }
    }

    @Test("目標時間が0以下の古い設定でも計算が壊れない", arguments: [0, -1])
    func invalidGoal(goal: Int) throws {
        try withSessions([session(from: now.addingTimeInterval(-60 * 60), to: now)]) { store in
            store.settings.dailyFocusGoalSeconds = goal
            let summary = DailySummary.make(store: store, now: now)
            #expect(summary.antDegree == 0)
            #expect(summary.grasshopperDegree == 100)
        }
    }

    @Test("完了・未完了・進行中の全タスクを合算し、経過時間に合わせて増える")
    func sumsAllTasksAndUpdates() throws {
        let sessions = [
            session(from: makeDate(2026, 10, 18, 9), to: makeDate(2026, 10, 18, 9, 10), outcome: .completed),
            session(from: makeDate(2026, 10, 18, 10), to: makeDate(2026, 10, 18, 10, 12), outcome: .incomplete),
            session(from: makeDate(2026, 10, 18, 11, 52))
        ]
        try withSessions(sessions) { store in
            let current = DailySummary.make(store: store, now: now)
            let later = DailySummary.make(store: store, now: now.addingTimeInterval(60))
            #expect(current.focusSeconds == 30 * 60)
            #expect(later.focusSeconds == 31 * 60)
            #expect(TimeFormat.hm(later.focusSeconds) == "31分")
        }
    }

    @Test("朝4時をまたぐ取り組みは各日に取り組んだ分だけを数える")
    func spansDayBoundary() throws {
        let start = makeDate(2026, 10, 18, 3, 50)
        let end = makeDate(2026, 10, 18, 4, 10)
        try withSessions([session(from: start, to: end)]) { store in
            #expect(store.focusSecondsToday(now: now) == 10 * 60)
            let previousDay = AppDay.interval(of: start)
            #expect(store.focusSeconds(in: previousDay, now: now) == 10 * 60)
        }
    }

    @Test("前日開始の進行中タスクも今日の経過分を数える")
    func ongoingAcrossBoundary() throws {
        let start = makeDate(2026, 10, 18, 3, 50)
        let at = makeDate(2026, 10, 18, 4, 20)
        try withSessions([session(from: start)]) { store in
            #expect(store.focusSecondsToday(now: at) == 20 * 60)
        }
    }

    @Test("前日の30分は午前4時ちょうどに0分になる（履歴は保持する）")
    func resetsAtFourAM() throws {
        let atBoundary = boundary(2026, 10, 18)
        let sessions = [session(from: makeDate(2026, 10, 18, 3), to: makeDate(2026, 10, 18, 3, 30))]
        try withSessions(sessions) { store in
            #expect(DailySummary.make(store: store, now: atBoundary.addingTimeInterval(-1)).focusSeconds == 30 * 60)
            let atFour = DailySummary.make(store: store, now: atBoundary)
            #expect(atFour.focusSeconds == 0)
            #expect(atFour.antDegree == 0)
            #expect(atFour.grasshopperDegree == 100)
            #expect(TimeFormat.hm(atFour.focusSeconds) == "0分")
            #expect(DailySummary.make(store: store, now: atBoundary.addingTimeInterval(60)).focusSeconds == 0)
            #expect(store.sessions == sessions)
        }
    }

    @Test("取り組み中でも午前4時に0へ切り替わり、4時以降の時間だけを加算する")
    func ongoingResetsAtFourAM() throws {
        let atBoundary = boundary(2026, 10, 18)
        try withSessions([session(from: makeDate(2026, 10, 18, 3, 50))]) { store in
            #expect(DailySummary.make(store: store, now: atBoundary.addingTimeInterval(-1)).focusSeconds == 10 * 60 - 1)
            #expect(DailySummary.make(store: store, now: atBoundary).focusSeconds == 0)
            #expect(DailySummary.make(store: store, now: atBoundary.addingTimeInterval(60)).focusSeconds == 60)
        }
    }

    @Test("終了済みの取り組み時間は増えず、前日と未来の取り組みは含めない")
    func completedTimeIsStable() throws {
        let sessions = [
            session(from: makeDate(2026, 10, 18, 3), to: makeDate(2026, 10, 18, 3, 30)),
            session(from: makeDate(2026, 10, 18, 9), to: makeDate(2026, 10, 18, 9, 7)),
            session(from: makeDate(2026, 10, 18, 14))
        ]
        try withSessions(sessions) { store in
            #expect(store.focusSecondsToday(now: now) == 7 * 60)
            #expect(store.focusSecondsToday(now: now.addingTimeInterval(60)) == 7 * 60)
        }
    }

    private func session(from start: Date, to end: Date? = nil, outcome: FocusSession.Outcome? = nil) -> FocusSession {
        FocusSession(taskID: UUID().uuidString, taskTitle: "テスト", listName: "テスト", origin: .home,
                     startedAt: start, endedAt: end, outcome: outcome)
    }

    /// 実際の保存形式で記録を読み込み、利用者のデータを触らずにホームの集計を確認する。
    private func withSessions(_ sessions: [FocusSession], body: (AppStore) -> Void) throws {
        let fileName = "todomeru-focus-test-\(UUID().uuidString).json"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: url) }
        var snapshot = AppStore.Snapshot()
        snapshot.sessions = sessions
        try JSONEncoder().encode(snapshot).write(to: url)
        body(AppStore(fileName: fileName))
    }
}
