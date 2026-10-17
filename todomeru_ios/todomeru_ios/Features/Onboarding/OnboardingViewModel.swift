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
    /// デモではFamilyControls認可をせず、疑似制限を使うことの確認だけを記録する
    var screenTimeAcknowledged = false
    var listSelection: Set<String> = []
    var isShowingSNSAdd = false
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

    func requestReminderAccess(_ reminders: ReminderService, store: AppStore) async {
        reminderAccess = .requesting
        let granted = await reminders.requestAccess()
        reminderAccess = granted ? .granted : .denied
        if granted { store.settings.useDemoTasks = false }
    }

    func canLeavePermissions(store: AppStore) -> Bool {
        reminderAccess == .granted || store.settings.useDemoTasks
    }

    // MARK: リスト

    /// 権限なし・リスト0件のときに選べる代替手段
    func chooseDemoTasks(_ reminders: ReminderService, store: AppStore) async {
        let ids = Set(DemoData.lists.map(\.id))
        store.settings.useDemoTasks = true
        store.settings.selectedListIDs = ids
        listSelection = ids
        await reminders.reload(selectedListIDs: ids, useDemo: true)
    }

    /// デモから実際のリマインダーへ切り替える（権限がある場合）
    func chooseRealReminders(_ reminders: ReminderService, store: AppStore) async {
        store.settings.useDemoTasks = false
        listSelection = []
        await loadLists(reminders, store: store)
    }

    /// リスト一覧を取得し、初回は全リストを選択状態にする
    func loadLists(_ reminders: ReminderService, store: AppStore) async {
        isWorking = true
        defer { isWorking = false }
        if store.settings.useDemoTasks {
            listSelection = Set(DemoData.lists.map(\.id))
            await reminders.reload(selectedListIDs: listSelection, useDemo: true)
            return
        }
        await reminders.reload(selectedListIDs: listSelection, useDemo: false)
        let ids = Set(reminders.lists.map(\.id))
        listSelection = listSelection.isEmpty ? ids : listSelection.intersection(ids)
    }

    func canLeaveLists(store: AppStore, reminders: ReminderService) -> Bool {
        if store.settings.useDemoTasks { return true }
        guard reminders.state == .loaded else { return false }
        return !listSelection.intersection(reminders.lists.map(\.id)).isEmpty
    }

    func commitLists(_ reminders: ReminderService, store: AppStore) async {
        guard !store.settings.useDemoTasks else { goNext(); return }
        isWorking = true
        store.settings.selectedListIDs = listSelection
        await reminders.reload(selectedListIDs: listSelection, useDemo: false)
        isWorking = false
        goNext()
    }

    // MARK: 完了

    func canLeaveSNS(store: AppStore) -> Bool { !store.selectedSNS.isEmpty }

    func finish(_ reminders: ReminderService, store: AppStore) async {
        isWorking = true
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs, useDemo: store.settings.useDemoTasks)
        isWorking = false
        store.settings.onboardingCompleted = true
    }
}
