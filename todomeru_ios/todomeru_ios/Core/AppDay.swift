import Foundation

/// 朝4時区切りの「アプリの1日」（D024）。
enum AppDay {
    static var calendar: Calendar { Calendar.current }

    /// 朝4時区切りで、その時刻が属する日の 0:00（暦上の日付）
    static func day(of date: Date = .now) -> Date {
        let shifted = date.addingTimeInterval(-Double(PolicyConstants.dayBoundaryHour) * 3600)
        return calendar.startOfDay(for: shifted)
    }

    /// 回数・残高の区切りに使うキー（例: 2026-10-17）
    static func key(of date: Date = .now) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day(of: date))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// その「アプリの1日」の開始・終了時刻（4:00〜翌4:00）
    static func interval(of date: Date = .now) -> DateInterval {
        let start = calendar.date(byAdding: .hour, value: PolicyConstants.dayBoundaryHour, to: day(of: date))!
        return DateInterval(start: start, duration: 24 * 3600)
    }

    /// その時刻が date と同じ「アプリの1日」に入るか（翌日の4:00ちょうどは含めない）
    static func isSameDay(_ target: Date, as date: Date = .now) -> Bool {
        let day = interval(of: date)
        return target >= day.start && target < day.end
    }
}

enum TimeFormat {
    /// 72分 → 「1時間12分」、55分 → 「55分」
    static func hm(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m >= 60 {
            let h = m / 60, r = m % 60
            return r == 0 ? "\(h)時間" : "\(h)時間\(r)分"
        }
        return "\(m)分"
    }

    /// 1930秒 → 「32:10」
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
