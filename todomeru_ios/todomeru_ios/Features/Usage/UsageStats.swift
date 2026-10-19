import Foundation

/// アプリ1件分の使用状況（表示用）
struct SNSUsageStatus {
    enum State: Equatable {
        case normal
        /// 上限に到達し、一時利用枠もない
        case restricted
        /// 上限に到達しているが一時利用枠が残っている
        case granted(remainingSeconds: Int)
    }

    var usedSeconds: Int
    /// 表示上の今日の上限（元の上限＋上乗せ分。上乗せ分はやることで増やした分と一時利用枠の合計）
    var limitSeconds: Int
    /// 設定した元の上限
    var baseLimitSeconds: Int
    var state: State

    /// 元の上限に今日上乗せした時間（やることで増やした分＋一時利用枠）
    var extraSeconds: Int { max(0, limitSeconds - baseLimitSeconds) }

    /// バーの割合（0〜1）。元の上限と増やした分の和を100%とする
    var ratio: Double {
        guard limitSeconds > 0 else { return usedSeconds > 0 ? 1 : 0 }
        return min(1, Double(usedSeconds) / Double(limitSeconds))
    }

    var isOverLimit: Bool { usedSeconds >= limitSeconds }

    /// 「使用 / 上限分」の表記
    var label: String { Self.label(usedSeconds: usedSeconds, limitSeconds: baseLimitSeconds, extraSeconds: extraSeconds) }

    /// 合計上限を1つの数字で表示する（Issue #33）。
    static func label(usedSeconds: Int, limitSeconds: Int, extraSeconds: Int) -> String {
        "\(usedSeconds / 60) / \((limitSeconds + extraSeconds) / 60)分"
    }

    /// バー全体に占める元の上限の割合。0上限・追加なしでも有限値を返す。
    var baseLimitRatio: Double {
        guard limitSeconds > 0 else { return 0 }
        return min(max(Double(baseLimitSeconds) / Double(limitSeconds), 0), 1)
    }

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
        let base = store.sns(snsID)?.dailyLimitSeconds ?? 0
        #if TODOMERU_PERSONAL_DEMO
        let used = snsID == InstagramDemo.snsID ? 30 * 60 : store.usageToday(snsID)
        #else
        let used = store.usageToday(snsID)
        #endif
        return SNSUsageStatus(usedSeconds: used, limitSeconds: base + store.addedLimitSeconds(snsID),
                              baseLimitSeconds: base, state: state)
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

    /// 取り組み時間は記録した取り組みから集計する。アプリの使用時間はデモでは当日分しか持たないため、当日以外は0。
    @MainActor
    static func bars(store: AppStore, now: Date = .now) -> [WeeklyBar] {
        let todayKey = AppDay.key(of: now)
        #if TODOMERU_PERSONAL_DEMO
        let playToday = 30 * 60
        #else
        let playToday = store.selectedSNS.reduce(0) { $0 + store.usageToday($1.id) }
        #endif
        return zip(weekDays(now: now), weekdayLabels).flatMap { day, label -> [WeeklyBar] in
            // その日の正午は必ずその「アプリの1日」に入る
            let interval = AppDay.interval(of: day.addingTimeInterval(12 * 3600))
            let isToday = AppDay.key(of: interval.start) == todayKey
            let focus = store.focusSeconds(in: interval, now: now)
            return [
                WeeklyBar(dayLabel: label, series: .focus, minutes: focus / 60, isToday: isToday),
                WeeklyBar(dayLabel: label, series: .play, minutes: isToday ? playToday / 60 : 0, isToday: isToday),
            ]
        }
    }
}
