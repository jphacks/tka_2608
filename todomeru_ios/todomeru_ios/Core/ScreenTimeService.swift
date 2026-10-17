import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Screen Time（Family Controls / Managed Settings）の薄いラッパー。
/// アプリの選択はOS標準のピッカーで行い、選んだアプリはトークン（中身の見えない参照）として扱う。
/// 上限・使用時間による自動の制限と解除には DeviceActivity Monitor 拡張が必要で、ここでは扱わない。
@Observable
final class ScreenTimeService {
    private(set) var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var lastError: String?
    private(set) var isShieldApplied = false

    /// ピッカーで選んだアプリ（端末内に保存して次回も使う）
    var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }

    @ObservationIgnored private let store = ManagedSettingsStore(named: .init("todomeru"))
    /// 上限・一時利用に連動する制限（テスト画面の手動の制限とは別のストア）
    @ObservationIgnored private let limitStore = ManagedSettingsStore(named: SharedScreenTime.limitStoreName)
    @ObservationIgnored private let center = DeviceActivityCenter()
    /// 監視を登録済みの一時利用枠
    @ObservationIgnored private var monitoredGrantIDs: Set<UUID> = []
    private(set) var monitoringError: String?
    @ObservationIgnored private let selectionKey = "screenTimeSelection"

    init() {
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        isShieldApplied = !(store.shield.applications ?? []).isEmpty
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    var selectedAppCount: Int { selection.applicationTokens.count }

    func refreshStatus() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    /// 本人の端末での利用として許可を求める（本人はいつでも取り消せる）
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "スクリーンタイムの許可を得られませんでした（\(error.localizedDescription)）"
        }
        refreshStatus()
    }

    /// 選んだアプリに、今すぐ制限（Shield）をかける
    func applyShield() {
        guard isAuthorized else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        isShieldApplied = !selection.applicationTokens.isEmpty
    }

    /// このアプリがかけた制限をすべて外す
    func clearShield() {
        store.shield.applications = nil
        isShieldApplied = false
    }

    /// 上限に達して制限中のアプリに本物の制限（Shield）をかけ、一時利用中・上限前のアプリは外す。
    /// 使用時間は疑似（アプリ内のデモ）なので、上限到達の判定もデモの値で行う。
    func syncLimitShield(restricted tokens: Set<ApplicationToken>) {
        guard isAuthorized else { return }
        limitStore.shield.applications = tokens.isEmpty ? nil : tokens
    }

    struct MonitoredLimit: Equatable {
        var snsID: String
        var token: ApplicationToken
        var tokenData: Data
        var limitSeconds: Int
    }

    struct MonitoredGrant: Equatable {
        var grantID: UUID
        var tokenData: Data
        var seconds: Int
    }

    /// 日次上限の監視を登録し直す（朝4時〜翌朝4時を毎日繰り返す, D024）。
    /// しきい値は区間の開始から数える（includesPastActivity）。0分のアプリは監視せず常に制限する（D022）。
    func scheduleDailyLimits(_ limits: [MonitoredLimit]) {
        guard isAuthorized else { return }
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        var always: Set<ApplicationToken> = []
        for l in limits {
            if l.limitSeconds <= 0 {
                always.insert(l.token)
                continue
            }
            let name = SharedScreenTime.limitEvent(l.snsID)
            SharedScreenTime.setToken(l.tokenData, for: name.rawValue)
            events[name] = DeviceActivityEvent(
                applications: [l.token],
                threshold: DateComponents(second: l.limitSeconds),
                includesPastActivity: true
            )
        }
        SharedScreenTime.alwaysShieldedTokens = always
        center.stopMonitoring([SharedScreenTime.dailyActivity])
        guard !events.isEmpty else { return }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: PolicyConstants.dayBoundaryHour, minute: 0),
            intervalEnd: DateComponents(hour: PolicyConstants.dayBoundaryHour - 1, minute: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(SharedScreenTime.dailyActivity, during: schedule, events: events)
            monitoringError = nil
        } catch {
            monitoringError = "上限の監視を登録できませんでした（\(error.localizedDescription)）"
        }
    }

    /// 新しく発行された一時利用枠の監視を登録する。実利用時間が枠の秒数に達したらMonitor拡張が再び制限する（D023）
    func monitorGrants(_ grants: [MonitoredGrant], now: Date = .now) {
        guard isAuthorized else { return }
        for g in grants where !monitoredGrantIDs.contains(g.grantID) {
            guard let token = try? JSONDecoder().decode(ApplicationToken.self, from: g.tokenData) else { continue }
            let activity = SharedScreenTime.grantActivity(g.grantID)
            SharedScreenTime.setToken(g.tokenData, for: activity.rawValue)
            // 監視の区間は最短15分（A11）。次の朝4時までを基本に、足りなければ15分確保する
            let dayEnd = AppDay.interval(of: now).end
            let end = max(dayEnd, now.addingTimeInterval(15 * 60))
            let cal = Calendar.current
            let schedule = DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now),
                intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
                repeats: false
            )
            let event = DeviceActivityEvent(applications: [token], threshold: DateComponents(second: max(1, g.seconds)), includesPastActivity: false)
            do {
                try center.startMonitoring(activity, during: schedule, events: [SharedScreenTime.grantEvent: event])
                monitoredGrantIDs.insert(g.grantID)
            } catch {
                monitoringError = "一時利用の監視を登録できませんでした（\(error.localizedDescription)）"
            }
        }
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: selectionKey)
    }
}
