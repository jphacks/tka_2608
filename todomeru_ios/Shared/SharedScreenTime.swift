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

    /// 上限・一時利用に連動する制限のストア（本体・Monitorで共通）
    static let limitStoreName = ManagedSettingsStore.Name("todomeru.limits")

    /// 日次上限の監視（朝4時〜翌朝4時を毎日繰り返す）
    static let dailyActivity = DeviceActivityName("todomeru.daily")

    /// 一時利用枠の監視名
    static func grantActivity(_ grantID: UUID) -> DeviceActivityName {
        DeviceActivityName("todomeru.grant.\(grantID.uuidString)")
    }

    /// 上限のイベント名（アプリのIDごと）
    static func limitEvent(_ snsID: String) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("limit.\(snsID)")
    }

    static let grantEvent = DeviceActivityEvent.Name("grant")

    // MARK: - 本体が書き、拡張が読む

    /// イベント名や監視名 → 対象アプリのトークン（JSON）
    static func setToken(_ data: Data, for key: String) {
        var map = tokenMap
        map[key] = data
        defaults.set(map, forKey: Keys.tokenMap)
    }

    static func token(for key: String) -> ApplicationToken? {
        tokenMap[key].flatMap { try? JSONDecoder().decode(ApplicationToken.self, from: $0) }
    }

    /// 上限0分など、日付が変わっても制限を外さないアプリ
    static var alwaysShieldedTokens: Set<ApplicationToken> {
        get { decodeTokens(defaults.array(forKey: Keys.alwaysShielded) as? [Data] ?? []) }
        set { defaults.set(encodeTokens(newValue), forKey: Keys.alwaysShielded) }
    }

    // MARK: - 拡張が書き、本体が読む

    /// 拡張が上限到達で制限をかけたアプリのID（日付キーごと）
    static func markLimitReached(_ snsID: String, dayKey: String) {
        var map = defaults.dictionary(forKey: Keys.limitReached) as? [String: [String]] ?? [:]
        map[dayKey, default: []].append(snsID)
        defaults.set(map, forKey: Keys.limitReached)
    }

    static func limitReachedIDs(dayKey: String) -> Set<String> {
        let map = defaults.dictionary(forKey: Keys.limitReached) as? [String: [String]] ?? [:]
        return Set(map[dayKey] ?? [])
    }

    /// 拡張が終了させた一時利用枠のID
    static func markGrantEnded(_ grantID: String) {
        var ids = defaults.stringArray(forKey: Keys.grantEnded) ?? []
        ids.append(grantID)
        defaults.set(ids, forKey: Keys.grantEnded)
    }

    static var endedGrantIDs: Set<String> { Set(defaults.stringArray(forKey: Keys.grantEnded) ?? []) }

    // MARK: - private

    private enum Keys {
        static let tokenMap = "tokenMap"
        static let alwaysShielded = "alwaysShielded"
        static let limitReached = "limitReached"
        static let grantEnded = "grantEnded"
    }

    private static var tokenMap: [String: Data] {
        defaults.dictionary(forKey: Keys.tokenMap) as? [String: Data] ?? [:]
    }

    private static func encodeTokens(_ tokens: Set<ApplicationToken>) -> [Data] {
        tokens.compactMap { try? JSONEncoder().encode($0) }
    }

    private static func decodeTokens(_ data: [Data]) -> Set<ApplicationToken> {
        Set(data.compactMap { try? JSONDecoder().decode(ApplicationToken.self, from: $0) })
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
