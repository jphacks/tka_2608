import DeviceActivity
import Foundation
import ManagedSettings

/// 上限到達と一時利用枠の終了で、本物の制限（Shield）をかける Monitor 拡張。
/// 本体が背景にいても、OSがこの拡張を呼び出す。
class TodomeruMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: SharedScreenTime.limitStoreName)

    /// 朝4時と監視の再登録時に、当日の到達記録・有効な利用枠から制限を組み立てる。
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == SharedScreenTime.dailyActivity else { return }
        refreshDailyLimits()
        syncShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity == SharedScreenTime.dailyActivity {
            refreshDailyLimits()
            // 古い上限の通知を捨て、一時利用中なら到達記録だけを残す。
            guard SharedScreenTime.monitorState.markLimitReached(eventName: event.rawValue, dayKey: SharedDayKey.key()) else { return }
            syncShield()
        } else if event == SharedScreenTime.grantEvent, activity.rawValue.hasPrefix("todomeru.grant.") {
            // 一時利用枠を使い切った: もう一度制限する
            refreshDailyLimits()
            let grantID = String(activity.rawValue.dropFirst("todomeru.grant.".count))
            SharedScreenTime.monitorState.endGrant(id: grantID, dayKey: SharedDayKey.key())
            syncShield()
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }

    private func refreshDailyLimits() {
        do { try SharedScreenTime.registerDailyLimits() }
        catch { print("[TodomeruMonitor] 日次監視の更新に失敗: \(error)") }
    }

    private func syncShield() {
        let tokens = Set(SharedScreenTime.monitorState.restrictedTokenData(dayKey: SharedDayKey.key()).compactMap {
            try? JSONDecoder().decode(ApplicationToken.self, from: $0)
        })
        store.shield.applications = tokens.isEmpty ? nil : tokens
    }
}
