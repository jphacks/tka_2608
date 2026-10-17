import Foundation

/// SNS1件分の使用状況（表示用）
struct SNSUsageStatus {
    enum State: Equatable {
        case normal
        /// 上限に到達し、一時利用枠もない
        case restricted
        /// 上限に到達しているが一時利用枠が残っている
        case granted(remainingSeconds: Int)
    }

    var usedSeconds: Int
    var limitSeconds: Int
    var state: State

    /// バーの割合（0〜1）
    var ratio: Double {
        guard limitSeconds > 0 else { return usedSeconds > 0 ? 1 : 0 }
        return min(1, Double(usedSeconds) / Double(limitSeconds))
    }

    var isOverLimit: Bool { usedSeconds >= limitSeconds }

    @MainActor
    static func make(_ snsID: String, store: AppStore) -> SNSUsageStatus {
        let state: State
        if store.isRestricted(snsID) {
            state = .restricted
        } else if store.isOverLimit(snsID), let g = store.activeGrant(snsID) {
            state = .granted(remainingSeconds: g.remainingSeconds)
        } else {
            state = .normal
        }
        return SNSUsageStatus(usedSeconds: store.usageToday(snsID), limitSeconds: store.effectiveLimit(snsID), state: state)
    }
}

/// 週次グラフの1本（1日・1系列）
struct WeeklyBar: Identifiable {
    enum Series: String, CaseIterable {
        case focus = "がんばった時間"
        case play = "遊んだ時間"
    }

    var id: String { "\(dayLabel)-\(series.rawValue)" }
    var dayLabel: String
    var series: Series
    var minutes: Int
    var isToday: Bool
}

enum WeeklyStats {
    static let weekdayLabels = ["月", "火", "水", "木", "金", "土", "日"]

    /// 今日（朝4時区切り）を含む月〜日の「アプリの1日」の日付（各日0:00）
    static func weekDays(now: Date = .now) -> [Date] {
        var cal = AppDay.calendar
        cal.firstWeekday = 2
        let today = AppDay.day(of: now)
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// 取り組み時間は記録した取り組みから集計する。SNSの使用時間はデモでは当日分しか持たないため、当日以外は0。
    @MainActor
    static func bars(store: AppStore, now: Date = .now) -> [WeeklyBar] {
        let todayKey = AppDay.key(of: now)
        let playToday = store.selectedSNS.reduce(0) { $0 + store.usageToday($1.id) }
        return zip(weekDays(now: now), weekdayLabels).flatMap { day, label -> [WeeklyBar] in
            // その日の正午は必ずその「アプリの1日」に入る
            let interval = AppDay.interval(of: day.addingTimeInterval(12 * 3600))
            let isToday = AppDay.key(of: interval.start) == todayKey
            let focus = store.sessions
                .filter { interval.contains($0.startedAt) }
                .reduce(0) { $0 + $1.measuredSeconds(now: now) }
            return [
                WeeklyBar(dayLabel: label, series: .focus, minutes: focus / 60, isToday: isToday),
                WeeklyBar(dayLabel: label, series: .play, minutes: isToday ? playToday / 60 : 0, isToday: isToday),
            ]
        }
    }
}
