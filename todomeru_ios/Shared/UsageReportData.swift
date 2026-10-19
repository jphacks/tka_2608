import DeviceActivity
import Foundation
import ManagedSettings
import SwiftUI

/// Reportへの入力だけを共有する。実使用時間を本体へ書き戻さない。
nonisolated struct UsageReportSettings: Codable, Hashable {
    struct App: Codable, Hashable {
        var tokenData: Data
        var limitSeconds: Int
    }
    struct FocusDay: Codable, Hashable {
        var dayKey: String
        var minutes: Int
    }
    var dayKey: String
    var apps: [App]
    var focusDays: [FocusDay]

    static let key = "usageReportSettings.v1"

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
        defaults.synchronize()
    }

    static func load(from defaults: UserDefaults) -> Self? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func limit(for token: ApplicationToken, on dayKey: String) -> Int? {
        guard self.dayKey == dayKey else { return nil }
        return apps.first { (try? JSONDecoder().decode(ApplicationToken.self, from: $0.tokenData)) == token }?.limitSeconds
    }
}

/// 各時間区間をアプリ単位に積算した後、分に切り捨てる。合計も表示した各行の分数の和。
/// キーをジェネリックにして、Report外へ実データを出さずに集計ロジックだけテストできる。
nonisolated struct UsageReportTotals<Key: Hashable> {
    private(set) var seconds: [Key: TimeInterval] = [:]

    mutating func add(_ duration: TimeInterval, for key: Key) {
        guard duration.isFinite, duration > 0 else { return }
        seconds[key, default: 0] += duration
    }

    func minutes(for key: Key) -> Int { Int((seconds[key] ?? 0) / 60) }
    var totalMinutes: Int { seconds.keys.reduce(0) { $0 + minutes(for: $1) } }
    var totalSeconds: TimeInterval { seconds.values.reduce(0, +) }
}

nonisolated enum UsageReportPeriod {
    static let refreshSeconds: TimeInterval = 60

    static func dayStart(_ now: Date, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -4, to: now)!
        return calendar.date(byAdding: .hour, value: 4, to: calendar.startOfDay(for: shifted))!
    }

    static func weekDays(_ now: Date, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: dayStart(now, calendar: cal))!.start
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .hour, value: 4, to: cal.date(byAdding: .day, value: offset, to: start)!)
        }
    }

    static func filter(tokens: Set<ApplicationToken>, now: Date, weekly: Bool) -> DeviceActivityFilter {
        let start = weekly ? weekDays(now)[0] : dayStart(now)
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: max(now, start.addingTimeInterval(1)))),
            applications: tokens
        )
    }
}

extension DeviceActivityReport.Context {
    static let appUsageMinutes = Self("AppUsageMinutes")
    static let appUsageBar = Self("AppUsageBar")
    static let weeklyUsage = Self("WeeklyUsage")
}
