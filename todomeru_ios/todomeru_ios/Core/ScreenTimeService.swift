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
    @ObservationIgnored private let limitStore = ManagedSettingsStore(named: .init("todomeru.limits"))
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

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: selectionKey)
    }
}
