import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Screen Time（Family Controls / Managed Settings）の薄いラッパー。
/// アプリの選択はOS標準のピッカーで行い、選んだアプリはトークン（中身の見えない参照）として扱う。
/// 日次上限・一時利用枠の監視をMonitor拡張へ登録し、制限状態を照合する。
@Observable
final class ScreenTimeService: UnlockMonitoring {
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
        let held = Set(SharedScreenTime.monitorState.preparationBlockedTokenData(dayKey: AppDay.key())
            .union(SharedScreenTime.monitorState.failedRegistrationTokens(dayKey: AppDay.key())).compactMap {
            try? JSONDecoder().decode(ApplicationToken.self, from: $0)
        })
        let restricted = tokens.union(held)
        limitStore.shield.applications = restricted.isEmpty ? nil : restricted
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
            SharedScreenTime.monitorState.clearFailedRegistrations()
            scheduledLimits = limits
            scheduledLimitDayKey = dayKey
            monitoringError = nil
        } catch {
            scheduledLimits = nil
            monitoringError = "上限の監視を登録できませんでした（\(error.localizedDescription)）"
        }
        #endif
    }

    /// 全登録が成功するまでShared Stateの準備中トークンを制限したままにする。
    func prepare(_ grant: UnlockGrant, limits: [ScreenTimeMonitorState.Limit]) throws {
        #if !TODOMERU_PERSONAL_DEMO
        guard isAuthorized, let limit = limits.first(where: { $0.snsID == grant.snsID }),
              SharedScreenTime.monitorState.beginPreparation(.init(id: grant.id.uuidString, tokenData: limit.tokenData, dayKey: grant.dayKey)) else {
            throw PolicyError.monitoringUnavailable
        }
        scheduledLimits = nil
        try registerGrant(.init(grantID: grant.id, tokenData: limit.tokenData, seconds: grant.remainingSeconds, dayKey: grant.dayKey))
        let stagedLimits = SharedScreenTime.monitorState.updateLimits(limits)
        guard SharedScreenTime.monitorState.limits == stagedLimits else { throw PolicyError.monitoringUnavailable }
        try SharedScreenTime.registerDailyLimits()
        #endif
    }

    func commit(_ grant: UnlockGrant, temporary: Bool) throws {
        #if !TODOMERU_PERSONAL_DEMO
        guard SharedScreenTime.monitorState.commitPreparation(id: grant.id.uuidString, temporary: temporary, dayKey: AppDay.key()) else {
            throw PolicyError.monitoringUnavailable
        }
        if !temporary { center.stopMonitoring([SharedScreenTime.grantActivity(grant.id)]) }
        syncSharedShield()
        monitoringError = nil
        #endif
    }

    func rollback(_ grant: UnlockGrant) {
        #if !TODOMERU_PERSONAL_DEMO
        rollbackPreparation(id: grant.id.uuidString)
        #endif
    }

    #if !TODOMERU_PERSONAL_DEMO
    private func rollbackPreparation(id: String) {
        guard SharedScreenTime.monitorState.preparation?.grant.id == id else { return }
        scheduledLimits = nil
        SharedScreenTime.monitorState.restorePreparationLimits()
        do {
            try SharedScreenTime.registerDailyLimits()
            center.stopMonitoring([DeviceActivityName("todomeru.grant." + id)])
            SharedScreenTime.monitorState.clearPreparation()
        } catch {
            // 復元も失敗したら準備中の制限を残し、復帰時に再試行する。
            monitoringError = "解除の準備を取り消せませんでした（\(error.localizedDescription)）"
        }
        syncSharedShield()
    }

    private func syncSharedShield() {
        let tokens = Set(SharedScreenTime.monitorState.restrictedTokenData(dayKey: AppDay.key()).compactMap {
            try? JSONDecoder().decode(ApplicationToken.self, from: $0)
        })
        limitStore.shield.applications = tokens.isEmpty ? nil : tokens
    }

    private func registerGrant(_ grant: MonitoredGrant, now: Date = .now) throws {
        guard grant.dayKey == AppDay.key(of: now), grant.seconds > 0,
              let token = try? JSONDecoder().decode(ApplicationToken.self, from: grant.tokenData) else {
            throw PolicyError.monitoringUnavailable
        }
        let end = max(AppDay.interval(of: now).end, now.addingTimeInterval(15 * 60))
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end), repeats: false
        )
        let event = DeviceActivityEvent(applications: [token],
            threshold: DateComponents(second: grant.seconds), includesPastActivity: false)
        try center.startMonitoring(SharedScreenTime.grantActivity(grant.grantID), during: schedule,
                                   events: [SharedScreenTime.grantEvent: event])
    }
    #endif

    /// 復帰時は登録が確認できた枠だけを共有する。失敗した枠は本体側でも取消す。
    @discardableResult
    func monitorGrants(_ grants: [MonitoredGrant], now: Date = .now) -> Set<UUID> {
        #if TODOMERU_PERSONAL_DEMO
        return []
        #else
        guard isAuthorized else { return [] }
        if let pending = SharedScreenTime.monitorState.preparation {
            if let grant = grants.first(where: { $0.grantID.uuidString == pending.grant.id }),
               center.activities.contains(SharedScreenTime.grantActivity(grant.grantID)) {
                do {
                    try SharedScreenTime.registerDailyLimits()
                    guard SharedScreenTime.monitorState.commitPreparation(id: pending.grant.id, temporary: true, dayKey: AppDay.key()) else {
                        throw PolicyError.monitoringUnavailable
                    }
                } catch { rollbackPreparation(id: pending.grant.id) }
            } else { rollbackPreparation(id: pending.grant.id) }
        }
        let registered = Set(center.activities)
        let active = Set(grants.map { SharedScreenTime.grantActivity($0.grantID) })
        let ended = registered.filter { $0.rawValue.hasPrefix("todomeru.grant.") && !active.contains($0) }
        if !ended.isEmpty { center.stopMonitoring(Array(ended)) }
        var verified: [ScreenTimeMonitorState.Grant] = []
        var failed: Set<UUID> = []
        for grant in grants {
            do {
                if SharedScreenTime.monitorState.preparation?.grant.id == grant.grantID.uuidString {
                    throw PolicyError.monitoringUnavailable
                }
                if !registered.contains(SharedScreenTime.grantActivity(grant.grantID)) {
                    try registerGrant(grant, now: now)
                }
                verified.append(.init(id: grant.grantID.uuidString, tokenData: grant.tokenData, dayKey: grant.dayKey))
            } catch {
                failed.insert(grant.grantID)
                scheduledLimits = nil
                SharedScreenTime.monitorState.holdFailedRegistration(grant.tokenData, dayKey: AppDay.key())
                monitoringError = "一時利用の監視を登録できませんでした（\(error.localizedDescription)）"
            }
        }
        SharedScreenTime.monitorState.updateGrants(verified)
        return failed
        #endif
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: selectionKey)
    }
}
