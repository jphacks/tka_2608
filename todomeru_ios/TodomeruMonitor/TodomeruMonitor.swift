import DeviceActivity
import Foundation
import ManagedSettings

/// 上限到達と一時利用枠の終了で、本物の制限（Shield）をかける Monitor 拡張。
/// 本体が背景にいても、OSがこの拡張を呼び出す。
class TodomeruMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: SharedScreenTime.limitStoreName)

    /// 朝4時: 前日の上限による制限を外す（上限0分のアプリは制限したまま）
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == SharedScreenTime.dailyActivity else { return }
        let always = SharedScreenTime.alwaysShieldedTokens
        store.shield.applications = always.isEmpty ? nil : always
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity == SharedScreenTime.dailyActivity {
            // 日次上限に到達: そのアプリを制限し、本体が読めるよう記録する
            guard let token = SharedScreenTime.token(for: event.rawValue) else { return }
            let snsID = String(event.rawValue.dropFirst("limit.".count))
            SharedScreenTime.markLimitReached(snsID, dayKey: SharedDayKey.key())
            shield(token)
        } else if event == SharedScreenTime.grantEvent {
            // 一時利用枠を使い切った: もう一度制限する
            guard let token = SharedScreenTime.token(for: activity.rawValue) else { return }
            let grantID = String(activity.rawValue.dropFirst("todomeru.grant.".count))
            SharedScreenTime.markGrantEnded(grantID)
            shield(token)
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }

    private func shield(_ token: ApplicationToken) {
        var tokens = store.shield.applications ?? []
        tokens.insert(token)
        store.shield.applications = tokens
    }
}
