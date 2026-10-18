import Foundation
import Testing
@testable import todomeru_ios

@Suite("AppDay（朝4時区切り）")
struct AppDayTests {
    @Test("切替時刻の1分前は前日、ちょうどは当日")
    func boundaryMinute() {
        let atBoundary = boundary(2026, 10, 17)
        let justBefore = atBoundary.addingTimeInterval(-60)
        #expect(AppDay.key(of: justBefore) == "2026-10-16")
        #expect(AppDay.key(of: atBoundary) == "2026-10-17")
        #expect(AppDay.day(of: justBefore) == makeDate(2026, 10, 16))
        #expect(AppDay.day(of: atBoundary) == makeDate(2026, 10, 17))
    }

    @Test("深夜（0時台）は前日、昼は当日")
    func midnightBelongsToPreviousDay() {
        #expect(AppDay.key(of: makeDate(2026, 10, 18, 0, 30)) == "2026-10-17")
        #expect(AppDay.key(of: makeDate(2026, 10, 17, 12)) == "2026-10-17")
    }

    @Test("月・年をまたぐ key")
    func keyAcrossMonthAndYear() {
        #expect(AppDay.key(of: makeDate(2026, 11, 1, 1)) == "2026-10-31")
        #expect(AppDay.key(of: makeDate(2027, 1, 1, 1)) == "2026-12-31")
        #expect(AppDay.key(of: boundary(2027, 1, 1)) == "2027-01-01")
    }

    @Test("interval は 当日の切替時刻〜翌日の切替時刻")
    func interval() {
        let i = AppDay.interval(of: makeDate(2026, 10, 18, 1))
        #expect(i.start == boundary(2026, 10, 17))
        #expect(i.end == boundary(2026, 10, 18))
        #expect(i.duration == 24 * 3600)
        #expect(i.contains(boundary(2026, 10, 17)))
        #expect(i.contains(boundary(2026, 10, 18).addingTimeInterval(-1)))
        #expect(!i.contains(boundary(2026, 10, 17).addingTimeInterval(-1)))
    }
}
