import Foundation
import Testing
@testable import todomeru_ios

/// D027（ARCHITECTURE.md 3.7.7）の「今日／すべて」と並び順
@Suite("TaskFilter（D027）")
struct TaskFilterTests {
    let noon = makeDate(2026, 10, 17, 12)

    @Test("今日: 期限が今日・期限切れの未完了を出し、明日以降・期限なしは出さない")
    func todayClassification() {
        let tasks = [
            makeTask(id: "today-date", due: makeDate(2026, 10, 17)),
            makeTask(id: "today-time-passed", due: makeDate(2026, 10, 17, 9), hasTime: true),
            makeTask(id: "today-time-later", due: makeDate(2026, 10, 17, 22), hasTime: true),
            makeTask(id: "overdue-date", due: makeDate(2026, 10, 15)),
            makeTask(id: "overdue-time", due: makeDate(2026, 10, 16, 10), hasTime: true),
            makeTask(id: "tomorrow-date", due: makeDate(2026, 10, 18)),
            makeTask(id: "tomorrow-time", due: boundary(2026, 10, 18), hasTime: true),
            makeTask(id: "no-due"),
        ]
        let ids = Set(TaskFilter.today(tasks, now: noon).open.map(\.id))
        #expect(ids == ["today-date", "today-time-passed", "today-time-later", "overdue-date", "overdue-time"])
    }

    @Test("今日: 深夜1時は前日の期限も「今日」。翌暦日の日付だけの期限は含めない")
    func todayAtLateNight() {
        let lateNight = makeDate(2026, 10, 18, 1)
        let tasks = [
            makeTask(id: "prev-date", due: makeDate(2026, 10, 17)),
            makeTask(id: "same-appday-time", due: makeDate(2026, 10, 18, 2), hasTime: true),
            makeTask(id: "next-date", due: makeDate(2026, 10, 18)),
            makeTask(id: "next-appday-time", due: boundary(2026, 10, 18), hasTime: true),
        ]
        let ids = Set(TaskFilter.today(tasks, now: lateNight).open.map(\.id))
        #expect(ids == ["prev-date", "same-appday-time"])
        // 前日の日付だけの期限は「期限切れ」ではなく「今日」
        #expect(TaskFilter.dueLabel(tasks[0], now: lateNight) == "今日")
    }

    @Test("今日: その「アプリの1日」に完了したものを完了済みとして新しい順に出す")
    func todayDone() {
        let tasks = [
            makeTask(id: "done-morning", completed: true, completionDate: makeDate(2026, 10, 17, 8)),
            makeTask(id: "done-noon", completed: true, completionDate: makeDate(2026, 10, 17, 11)),
            makeTask(id: "done-at-boundary", completed: true, completionDate: boundary(2026, 10, 17)),
            makeTask(id: "done-before-boundary", completed: true, completionDate: boundary(2026, 10, 17).addingTimeInterval(-1)),
            makeTask(id: "done-yesterday", completed: true, completionDate: makeDate(2026, 10, 16, 12)),
            makeTask(id: "done-no-date", completed: true, completionDate: nil),
        ]
        let result = TaskFilter.today(tasks, now: noon)
        #expect(result.open.isEmpty)
        #expect(result.done.map(\.id) == ["done-noon", "done-morning", "done-at-boundary"])
    }

    @Test("今日: 翌日の切替時刻ちょうどに完了したものは今日の完了に含めない")
    func todayDoneExcludesNextBoundary() {
        let tasks = [makeTask(id: "done-next-boundary", completed: true, completionDate: boundary(2026, 10, 18))]
        #expect(TaskFilter.today(tasks, now: noon).done.isEmpty)
    }

    @Test("すべて: 未完了を全部出し（期限なし・明日以降を含む）、完了済みは出さない")
    func allClassification() {
        let tasks = [
            makeTask(id: "today", due: makeDate(2026, 10, 17)),
            makeTask(id: "overdue", due: makeDate(2026, 10, 15)),
            makeTask(id: "tomorrow", due: makeDate(2026, 10, 18)),
            makeTask(id: "no-due"),
            makeTask(id: "done", due: makeDate(2026, 10, 17), completed: true, completionDate: noon),
        ]
        #expect(TaskFilter.all(tasks).map(\.id) == ["overdue", "today", "tomorrow", "no-due"])
    }

    @Test("並び順: 期限の早い順、同じ期限は優先度（高・中・低・なし）、さらに作成日の古い順、期限なしは末尾")
    func sortOrder() {
        let due = makeDate(2026, 10, 17, 18)
        let old = makeDate(2026, 10, 1), new = makeDate(2026, 10, 10)
        let tasks = [
            makeTask(id: "no-due-high", priority: 1),
            makeTask(id: "none-old", due: due, hasTime: true, priority: 0, createdAt: old),
            makeTask(id: "low", due: due, hasTime: true, priority: 9, createdAt: old),
            makeTask(id: "high-new", due: due, hasTime: true, priority: 1, createdAt: new),
            makeTask(id: "mid", due: due, hasTime: true, priority: 5, createdAt: old),
            makeTask(id: "high-old", due: due, hasTime: true, priority: 4, createdAt: old),
            makeTask(id: "overdue-low", due: makeDate(2026, 10, 10), priority: 9),
            makeTask(id: "tomorrow-high", due: makeDate(2026, 10, 18), priority: 1),
        ]
        #expect(TaskFilter.sorted(tasks).map(\.id) == [
            "overdue-low", "high-old", "high-new", "mid", "low", "none-old", "tomorrow-high", "no-due-high",
        ])
    }

    @Test("並び順: 日付だけの期限は、その日の時刻付きの期限より後")
    func dateOnlyIsEndOfDay() {
        let tasks = [
            makeTask(id: "date-only-high", due: makeDate(2026, 10, 17), priority: 1),
            makeTask(id: "late-time-none", due: makeDate(2026, 10, 17, 23, 30), hasTime: true, priority: 0),
            makeTask(id: "next-day-early", due: makeDate(2026, 10, 18, 0, 10), hasTime: true),
        ]
        #expect(TaskFilter.sorted(tasks).map(\.id) == ["late-time-none", "date-only-high", "next-day-early"])
    }

    @Test("今日の未完了も同じ並び順")
    func todayIsSorted() {
        let tasks = [
            makeTask(id: "today", due: makeDate(2026, 10, 17)),
            makeTask(id: "overdue", due: makeDate(2026, 10, 16)),
            makeTask(id: "today-9", due: makeDate(2026, 10, 17, 9), hasTime: true),
        ]
        #expect(TaskFilter.today(tasks, now: noon).open.map(\.id) == ["overdue", "today-9", "today"])
    }
}
