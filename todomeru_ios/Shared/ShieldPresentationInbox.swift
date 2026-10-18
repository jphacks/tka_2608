import Foundation

/// Shieldのボタン操作を本体へ渡す。制限解除の許可や使用時間は含めない。
struct ShieldPresentationInbox {
    private let defaults: UserDefaults
    private static let key = "pendingShieldPresentation"
    private static let lifetime: TimeInterval = 5 * 60

    private struct Request: Codable {
        var snsID: String
        var createdAt: Date
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    @discardableResult
    func request(snsID: String, now: Date = .now) -> Bool {
        guard !snsID.isEmpty,
              let data = try? JSONEncoder().encode(Request(snsID: snsID, createdAt: now)) else { return false }
        defaults.set(data, forKey: Self.key)
        // 拡張が終了し、本体へ切り替わる前に別プロセスから読める状態へ反映する。
        defaults.synchronize()
        return true
    }

    /// 一度だけ受け取る。古い操作や日付切替前の操作では画面を切り替えない。
    func take(now: Date = .now) -> String? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        defaults.removeObject(forKey: Self.key)
        defaults.synchronize()
        guard let request = try? JSONDecoder().decode(Request.self, from: data) else { return nil }
        let age = now.timeIntervalSince(request.createdAt)
        guard !request.snsID.isEmpty, age >= 0, age <= Self.lifetime,
              SharedDayKey.key(of: request.createdAt) == SharedDayKey.key(of: now) else { return nil }
        return request.snsID
    }
}
