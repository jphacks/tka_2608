import Foundation
import Testing
@testable import todomeru_ios

@Suite("Reportの使用時間集計")
struct UsageReportTests {
    @Test("同じアプリの時間区間を足してから分に変換する")
    func combinesSegmentsBeforeRounding() {
        var totals = UsageReportTotals<String>()
        totals.add(35, for: "a")
        totals.add(40, for: "a")
        #expect(totals.minutes(for: "a") == 1)
        #expect(totals.totalMinutes == 1)
        #expect(totals.totalSeconds == 75)
    }

    @Test("遊んだ時間は、表示した各アプリの分数の合計になる")
    func sumsDisplayedRows() {
        var totals = UsageReportTotals<String>()
        totals.add(119, for: "a")
        totals.add(179, for: "b")
        totals.add(59, for: "c")
        #expect(totals.minutes(for: "a") == 1)
        #expect(totals.minutes(for: "b") == 2)
        #expect(totals.minutes(for: "c") == 0)
        #expect(totals.totalMinutes == 3)
    }

    @Test("0件、負値、NaN、無限大から不正な分数を作らない")
    func invalidDurations() {
        var totals = UsageReportTotals<String>()
        for seconds in [-1, 0, Double.nan, Double.infinity] {
            totals.add(seconds, for: "a")
        }
        #expect(totals.totalMinutes == 0)
        #expect(totals.seconds.isEmpty)
    }

    @Test("朝4時の前後で集計対象の日が切り替わる")
    func dayBoundary() {
        let before = makeDate(2026, 10, 19, 3, 59)
        let after = makeDate(2026, 10, 19, 4)
        #expect(UsageReportPeriod.dayStart(before) == makeDate(2026, 10, 18, 4))
        #expect(UsageReportPeriod.dayStart(after) == after)
    }

    @Test("月曜の朝4時より前は先週、以後は今週のグラフにする")
    func weekBoundary() {
        #expect(UsageReportPeriod.weekDays(makeDate(2026, 10, 19, 3, 59)).first == makeDate(2026, 10, 12, 4))
        let days = UsageReportPeriod.weekDays(makeDate(2026, 10, 19, 4))
        #expect(days.first == makeDate(2026, 10, 19, 4))
        #expect(days.last == makeDate(2026, 10, 25, 4))
    }

    @Test("本体から渡した上限・取り組み時間の入力を保存できる")
    func reportInputRoundTrip() throws {
        let suite = "usage-report-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let input = UsageReportSettings(dayKey: "2026-10-19", apps: [.init(tokenData: Data([1]), limitSeconds: 31 * 60)],
                                        focusDays: [.init(dayKey: "2026-10-19", minutes: 25)])
        input.save(to: defaults)
        #expect(UsageReportSettings.load(from: defaults) == input)
        let data = try JSONEncoder().encode(input)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["dayKey", "apps", "focusDays"])
    }

}
