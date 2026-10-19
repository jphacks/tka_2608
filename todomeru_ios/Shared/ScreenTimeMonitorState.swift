import Foundation

/// 本体が監視条件を書き、Monitorが到達だけを記録する。Reportの実使用量は扱わない。
nonisolated struct ScreenTimeMonitorState {
    struct Limit: Codable, Equatable {
        var snsID: String
        var tokenData: Data
        var seconds: Int
        var baseSeconds: Int
        var dayKey: String
        var eventName = "limit.\(UUID().uuidString)"
    }

    struct Grant: Codable, Equatable {
        var id: String
        var tokenData: Data
        var dayKey: String
    }

    let defaults: UserDefaults

    var limits: [Limit] { load([Limit].self, key: "monitorLimits.v2") ?? [] }
    private var grants: [Grant] { load([Grant].self, key: "monitorGrants.v2") ?? [] }

    /// 同じ条件ならイベント名を維持し、変更した対象だけ新しい名前にする。
    @discardableResult
    func updateLimits(_ proposed: [Limit]) -> [Limit] {
        let current = limits
        let updated = proposed.map { next in
            current.first {
                $0.snsID == next.snsID && $0.tokenData == next.tokenData && $0.seconds == next.seconds
                    && $0.baseSeconds == next.baseSeconds && $0.dayKey == next.dayKey
            } ?? next
        }
        save(updated, key: "monitorLimits.v2")
        return updated
    }

    func updateGrants(_ active: [Grant]) { save(active, key: "monitorGrants.v2") }

    /// 前日の追加分を持ち越さず、日付ごとの通知名を導出する。本体の設定は書き換えない。
    func limits(on dayKey: String) -> [Limit] {
        limits.map { saved in
            guard saved.dayKey != dayKey else { return saved }
            var current = saved
            current.seconds = saved.baseSeconds
            current.dayKey = dayKey
            current.eventName = "\(saved.eventName).\(dayKey)"
            return current
        }
    }

    /// 旧設定から遅れて届いた通知は、到達記録にもShieldにも反映しない。
    @discardableResult
    func markLimitReached(eventName: String, dayKey: String) -> Bool {
        guard limits(on: dayKey).contains(where: { $0.eventName == eventName && $0.seconds > 0 }) else { return false }
        defaults.set(dayKey, forKey: "limitReached.v2.\(eventName)")
        defaults.synchronize()
        return true
    }

    func limitReachedIDs(dayKey: String, expectedLimits: [String: Int]) -> Set<String> {
        Set(limits(on: dayKey).filter { expectedLimits[$0.snsID] == $0.seconds && hasReached($0, dayKey: dayKey) }.map(\.snsID))
    }

    var endedGrantIDs: Set<String> {
        defaults.synchronize()
        return Set(defaults.stringArray(forKey: "grantEnded") ?? [])
    }

    @discardableResult
    func endGrant(id: String, dayKey: String) -> Bool {
        guard activeGrants(dayKey: dayKey).contains(where: { $0.id == id }) else { return false }
        defaults.set(Array(endedGrantIDs.union([id])), forKey: "grantEnded")
        defaults.synchronize()
        return true
    }

    /// 日次通知・区間開始・枠終了のどの通知でも、同じ条件からShieldを組み立てる。
    func restrictedTokenData(dayKey: String) -> Set<Data> {
        let unlocked = Set(activeGrants(dayKey: dayKey).map(\.tokenData))
        return Set(limits(on: dayKey).filter { $0.seconds <= 0 || hasReached($0, dayKey: dayKey) }.map(\.tokenData)).subtracting(unlocked)
    }

    private func activeGrants(dayKey: String) -> [Grant] {
        let ended = endedGrantIDs
        return grants.filter { $0.dayKey == dayKey && !ended.contains($0.id) }
    }

    private func hasReached(_ limit: Limit, dayKey: String) -> Bool {
        defaults.synchronize()
        return limit.dayKey == dayKey && defaults.string(forKey: "limitReached.v2.\(limit.eventName)") == dayKey
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
