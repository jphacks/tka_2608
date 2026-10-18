import EventKit
import Foundation
import Observation

/// 初回設定の5ステップ（UI_UX.md 2.1）
enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, lists, sns, ready

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// リマインダー権限の表示用の状態（権限の正本はOS。毎回 ReminderService から読み直す）
enum ReminderAccessState: Equatable {
    case notDetermined, requesting, granted, denied
}

/// 初回設定の画面ロジック。保存先は AppStore.settings / snsApps。
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome
    var reminderAccess: ReminderAccessState = .notDetermined
    /// スクリーンタイムの許可を一度でも求めたか（許可の正本はOS。ScreenTimeService から読む）
    var screenTimeRequested = false
    var isRequestingScreenTime = false
    var listSelection: Set<String> = []
    var isWorking = false

    // MARK: 遷移

    func goNext() { if let n = step.next { step = n } }
    func goBack() { if let p = step.previous { step = p } }

    // MARK: 権限

    func refreshReminderAccess(_ reminders: ReminderService) {
        guard reminderAccess != .requesting else { return }
        switch reminders.authorizationStatus {
        case .fullAccess: reminderAccess = .granted
        case .notDetermined: reminderAccess = .notDetermined
        default: reminderAccess = .denied
        }
    }

    func requestReminderAccess(_ reminders: ReminderService) async {
        reminderAccess = .requesting
        let granted = await reminders.requestAccess()
        reminderAccess = granted ? .granted : .denied
    }

    /// スクリーンタイムの許可を求める。通常版で対象アプリを選ぶには認可が必要。
    func requestScreenTime(_ screenTime: ScreenTimeService) async {
        isRequestingScreenTime = true
        await screenTime.requestAuthorization()
        isRequestingScreenTime = false
        screenTimeRequested = true
    }

    func canLeavePermissions() -> Bool {
        reminderAccess == .granted
    }

    // MARK: リスト

    /// リスト一覧を取得し、初回は全リストを選択状態にする
    func loadLists(_ reminders: ReminderService) async {
        isWorking = true
        defer { isWorking = false }
        await reminders.reload(selectedListIDs: listSelection)
        let ids = Set(reminders.lists.map(\.id))
        listSelection = listSelection.isEmpty ? ids : listSelection.intersection(ids)
    }

    func canLeaveLists(reminders: ReminderService) -> Bool {
        guard reminders.state == .loaded else { return false }
        return !listSelection.intersection(reminders.lists.map(\.id)).isEmpty
    }

    func commitLists(_ reminders: ReminderService, store: AppStore) async {
        isWorking = true
        store.settings.selectedListIDs = listSelection
        await reminders.reload(selectedListIDs: listSelection)
        isWorking = false
        goNext()
    }

    // MARK: 完了

    func canLeaveSNS(store: AppStore) -> Bool { !store.selectedSNS.isEmpty }

    func finish(_ reminders: ReminderService, store: AppStore) async {
        isWorking = true
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs)
        isWorking = false
        store.settings.onboardingCompleted = true
    }
}
