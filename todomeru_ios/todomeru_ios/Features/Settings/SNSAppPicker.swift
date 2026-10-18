import FamilyControls
import SwiftUI

/// 「アプリを選ぶ」：iOS標準のアプリ選択（FamilyActivityPicker）で制限するアプリを選ぶ。
/// スクリーンタイムが未許可なら、ピッカーの前に許可を求める。許可できなければ固定の候補へ案内する。
/// PersonalDemoでは固定の候補を選ぶ画面を開く。
/// 初回設定（64:225）と設定の「アプリを追加」（161:150）で共通。
struct PickAppsButton: View {
    @Environment(AppStore.self) private var store
    @Environment(ScreenTimeService.self) private var screenTime
    /// 固定の候補を選ぶ画面へ進む操作（nil なら案内文のみ）
    var onSelectCandidates: (() -> Void)?

    @State private var isPickerPresented = false
    @State private var selection = FamilyActivitySelection()
    @State private var isRequesting = false
    @State private var showsUnavailable = false

    var body: some View {
        #if TODOMERU_PERSONAL_DEMO
        if let onSelectCandidates {
            Button(action: onSelectCandidates) {
                HStack(spacing: 8) {
                    Image(systemName: "apps.iphone")
                    Text("アプリを選ぶ")
                }
            }
            .buttonStyle(.primary)
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await open() }
            } label: {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Image(systemName: "apps.iphone")
                    }
                    Text("アプリを選ぶ")
                }
            }
            .buttonStyle(.primary)
            .disabled(isRequesting)
            if showsUnavailable && !screenTime.isAuthorized {
                ScreenTimeUnavailableNotice(error: screenTime.lastError, onSelectCandidates: onSelectCandidates)
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: isPickerPresented) { _, presented in
            if !presented { store.syncPickedApps(selection.applicationTokens) }
        }
        #endif
    }

    #if !TODOMERU_PERSONAL_DEMO
    private func open() async {
        if !screenTime.isAuthorized {
            isRequesting = true
            await screenTime.requestAuthorization()
            isRequesting = false
        }
        guard screenTime.isAuthorized else {
            showsUnavailable = true
            return
        }
        showsUnavailable = false
        var initial = FamilyActivitySelection()
        initial.applicationTokens = store.pickedTokens
        selection = initial
        isPickerPresented = true
    }
    #endif
}

/// スクリーンタイムを許可できなかったときの案内（固定の候補で続けられる）
struct ScreenTimeUnavailableNotice: View {
    var error: String?
    var onSelectCandidates: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("スクリーンタイムを許可できなかったため、アプリを選べません。", systemImage: "exclamationmark.triangle.fill")
                .font(SettingsMetrics.body)
                .foregroundStyle(Theme.textPrimary)
            if let error { FootNote(text: error) }
            if let onSelectCandidates {
                Button("候補から選ぶ", action: onSelectCandidates)
                    .buttonStyle(.secondary)
            }
        }
        .padding(SettingsMetrics.gutter)
        .card()
    }
}
