import DeviceActivity
import Foundation
import ManagedSettings
import SwiftUI

/// 本体と拡張（Monitor・Report）で共有する名前と保存領域。
/// 本体と拡張は別プロセスなので、App Group の UserDefaults を介してやり取りする。
enum SharedScreenTime {
    /// 署名と同じ設定値を各ターゲットのInfo.plist経由で受け取る。
    static let appGroupID: String = {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "TodomeruAppGroupIdentifier") as? String,
              identifier.hasPrefix("group."), !identifier.contains("$(") else {
            preconditionFailure("Signing.local.xcconfigのTODOMERU_APP_GROUP_IDENTIFIERを設定してください")
        }
        return identifier
    }()

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    static var shieldPresentation: ShieldPresentationInbox { .init(defaults: defaults) }
    static var monitorState: ScreenTimeMonitorState { .init(defaults: defaults) }

    /// 上限・一時利用に連動する制限のストア（本体・Monitorで共通）
    static let limitStoreName = ManagedSettingsStore.Name("todomeru.limits")

    /// 日次上限の監視（朝4時〜翌朝4時を毎日繰り返す）
    static let dailyActivity = DeviceActivityName("todomeru.daily")

    /// 一時利用枠の監視名
    static func grantActivity(_ grantID: UUID) -> DeviceActivityName {
        DeviceActivityName("todomeru.grant.\(grantID.uuidString)")
    }

    static let grantEvent = DeviceActivityEvent.Name("grant")

    /// 本体とMonitorの日付切替で、同じ日次監視を登録する。
    static func registerDailyLimits() throws {
        let center = DeviceActivityCenter()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for limit in monitorState.limits(on: SharedDayKey.key()) where limit.seconds > 0 {
            guard let token = try? JSONDecoder().decode(ApplicationToken.self, from: limit.tokenData) else { continue }
            events[DeviceActivityEvent.Name(limit.eventName)] = DeviceActivityEvent(
                applications: [token], threshold: DateComponents(second: limit.seconds), includesPastActivity: true
            )
        }
        guard !events.isEmpty else {
            center.stopMonitoring([dailyActivity])
            return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: SharedDayKey.boundaryHour, minute: 0),
            intervalEnd: DateComponents(hour: SharedDayKey.boundaryHour - 1, minute: 59), repeats: true
        )
        // 再登録直後のintervalDidStartでは同じ監視を再帰的に登録しない。
        guard center.events(for: dailyActivity) != events || center.schedule(for: dailyActivity) != schedule else { return }
        try center.startMonitoring(dailyActivity, during: schedule, events: events)
    }

    /// OSから渡された不透明なトークンを、本体が登録したアプリ内IDへ対応付ける。
    static func snsID(for token: ApplicationToken) -> String? {
        monitorState.limits.first { (try? JSONDecoder().decode(ApplicationToken.self, from: $0.tokenData)) == token }?.snsID
    }
}

extension DeviceActivityReport.Context {
    /// ホームの「遊んだ時間」を描く Report（PlayTimeReport 拡張）
    static let playTime = Self("PlayTime")
}

/// 朝4時区切りの日付キー（本体の AppDay.key と同じ規則。拡張から Core を使えないため共有側に置く）
enum SharedDayKey {
    static let boundaryHour = 4

    static func key(of date: Date = .now) -> String {
        let shifted = date.addingTimeInterval(-Double(boundaryHour) * 3600)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
