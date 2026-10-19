import DeviceActivity
import ManagedSettings
import Observation
import SwiftUI

/// 全Reportで同じ取得期間・更新世代を使う。OS側の集計を強制更新するAPIではない。
@Observable
final class UsageReportClock {
    private(set) var date = Date.now
    func refresh(now: Date = .now) { date = now }
}

struct UsageReportHost: View {
    @Environment(UsageReportClock.self) private var clock
    @Environment(ScreenTimeService.self) private var screenTime
    @Environment(AppStore.self) private var store
    var context: DeviceActivityReport.Context
    var tokens: Set<ApplicationToken>
    var weekly = false

    private struct Request: Hashable {
        var context: DeviceActivityReport.Context
        var tokens: Set<ApplicationToken>
        var date: Date
        var settings: UsageReportSettings
    }

    var body: some View {
        Group {
            if !screenTime.isAuthorized {
                Text("—")
                    .accessibilityLabel("スクリーンタイムの許可が必要です")
            } else if tokens.isEmpty {
                Text("0分")
            } else {
                DeviceActivityReport(context, filter: UsageReportPeriod.filter(tokens: tokens, now: clock.date, weekly: weekly))
                    .id(Request(context: context, tokens: tokens, date: clock.date,
                                settings: store.usageReportSettings(now: clock.date)))
                    .allowsHitTesting(false)
            }
        }
    }
}

extension AppStore {
    /// 本体→Reportの入力。実使用時間・会話・タスク名は含めない。
    func usageReportSettings(now: Date = .now) -> UsageReportSettings {
        UsageReportSettings(
            dayKey: AppDay.key(of: now),
            apps: selectedSNS.compactMap { app in
                guard let token = app.tokenData else { return nil }
                return .init(tokenData: token, limitSeconds: totalLimitToday(app.id))
            },
            focusDays: UsageReportPeriod.weekDays(now).map { start in
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                return .init(dayKey: SharedDayKey.key(of: start), minutes: focusSeconds(in: DateInterval(start: start, end: end), now: now) / 60)
            }
        )
    }
}
