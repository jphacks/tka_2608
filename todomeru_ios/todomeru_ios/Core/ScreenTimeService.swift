import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Screen Time（Family Controls / Managed Settings）の薄いラッパー。
/// アプリの選択はOS標準のピッカーで行い、選んだアプリはトークン（中身の見えない参照）として扱う。
/// 日次上限・一時利用枠の監視をMonitor拡張へ登録し、制限状態を照合する。
@Observable
final class ScreenTimeService {
    #if TODOMERU_PERSONAL_DEMO
    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    #else
    private(set) var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    #endif
    private(set) var lastError: String?
    private(set) var isShieldApplied = false

    /// ピッカーで選んだアプリ（端末内に保存して次回も使う）
    var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }

    #if !TODOMERU_PERSONAL_DEMO
    @ObservationIgnored private let store = ManagedSettingsStore(named: .init("todomeru"))
    /// 上限・一時利用に連動する制限（テスト画面の手動の制限とは別のストア）
    @ObservationIgnored private let limitStore = ManagedSettingsStore(named: SharedScreenTime.limitStoreName)
    @ObservationIgnored private let center = DeviceActivityCenter()
    #endif
    @ObservationIgnored private var scheduledLimits: [MonitoredLimit]?
    @ObservationIgnored private var scheduledLimitDayKey: String?
    private(set) var monitoringError: String?
    @ObservationIgnored private let selectionKey = "screenTimeSelection"

    init() {
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        #if !TODOMERU_PERSONAL_DEMO
        isShieldApplied = !(store.shield.applications ?? []).isEmpty
        #endif
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    var selectedAppCount: Int { selection.applicationTokens.count }

    func refreshStatus() {
        #if !TODOMERU_PERSONAL_DEMO
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if !isAuthorized {
            scheduledLimits = nil
        }
        #endif
    }

    /// 本人の端末での利用として許可を求める（本人はいつでも取り消せる）
    func requestAuthorization() async {
        #if TODOMERU_PERSONAL_DEMO
        lastError = "この版ではスクリーンタイムを使いません。"
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "スクリーンタイムの許可を得られませんでした（\(error.localizedDescription)）"
        }
        refreshStatus()
        #endif
    }

    /// 選んだアプリに、今すぐ制限（Shield）をかける
    func applyShield() {
        #if !TODOMERU_PERSONAL_DEMO
        guard isAuthorized else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        isShieldApplied = !selection.applicationTokens.isEmpty
        #endif
    }

    /// このアプリがかけた制限をすべて外す
    func clearShield() {
        #if !TODOMERU_PERSONAL_DEMO
        store.shield.applications = nil
        #endif
        isShieldApplied = false
    }

    /// 上限に達して制限中のアプリに本物の制限（Shield）をかけ、一時利用中・上限前のアプリは外す。
    /// 本体が取り込んだMonitorの記録と利用枠に従って反映する。
    func syncLimitShield(restricted tokens: Set<ApplicationToken>) {
        #if !TODOMERU_PERSONAL_DEMO
        guard isAuthorized else { return }
        limitStore.shield.applications = tokens.isEmpty ? nil : tokens
        #endif
    }

    struct MonitoredLimit: Equatable {
        var snsID: String
        var token: ApplicationToken
        var tokenData: Data
        var limitSeconds: Int
        var baseLimitSeconds: Int
    }

    struct MonitoredGrant: Equatable {
        var grantID: UUID
        var tokenData: Data
        var seconds: Int
        var dayKey: String
    }

    /// 日次上限の監視を登録し直す（朝4時〜翌朝4時を毎日繰り返す, D024）。
    /// しきい値は区間の開始から数える（includesPastActivity）。0分のアプリは監視せず常に制限する（D022）。
    func scheduleDailyLimits(_ limits: [MonitoredLimit]) {
        #if !TODOMERU_PERSONAL_DEMO
        guard isAuthorized else {
            scheduledLimits = nil
            return
        }
        let dayKey = AppDay.key()
        guard scheduledLimits != limits || scheduledLimitDayKey != dayKey else { return }
        SharedScreenTime.monitorState.updateLimits(limits.map {
            .init(snsID: $0.snsID, tokenData: $0.tokenData, seconds: $0.limitSeconds,
                  baseSeconds: $0.baseLimitSeconds, dayKey: dayKey)
        })
        do {
            try SharedScreenTime.registerDailyLimits()
            scheduledLimits = limits
            scheduledLimitDayKey = dayKey
            monitoringError = nil
        } catch {
            scheduledLimits = nil
            monitoringError = "上限の監視を登録できませんでした（\(error.localizedDescription)）"
        }
        #endif
    }

    /// 新しく発行された一時利用枠の監視を登録する。実利用時間が枠の秒数に達したらMonitor拡張が再び制限する（D023）
    func monitorGrants(_ grants: [MonitoredGrant], now: Date = .now) {
        #if !TODOMERU_PERSONAL_DEMO
        guard isAuthorized else { return }
        SharedScreenTime.monitorState.updateGrants(grants.map {
            .init(id: $0.grantID.uuidString, tokenData: $0.tokenData, dayKey: $0.dayKey)
        })
        // 本体の再起動でも既存の監視窓を維持し、実使用時間を起算し直さない。
        let registered = Set(center.activities)
        let active = Set(grants.map { SharedScreenTime.grantActivity($0.grantID) })
        let ended = registered.filter { $0.rawValue.hasPrefix("todomeru.grant.") && !active.contains($0) }
        if !ended.isEmpty { center.stopMonitoring(Array(ended)) }
        for g in grants where !registered.contains(SharedScreenTime.grantActivity(g.grantID)) {
            guard let token = try? JSONDecoder().decode(ApplicationToken.self, from: g.tokenData) else { continue }
            let activity = SharedScreenTime.grantActivity(g.grantID)
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
            } catch {
                monitoringError = "一時利用の監視を登録できませんでした（\(error.localizedDescription)）"
            }
        }
        #endif
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: selectionKey)
    }
}
