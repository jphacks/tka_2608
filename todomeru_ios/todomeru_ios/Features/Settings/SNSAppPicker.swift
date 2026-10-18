import FamilyControls
import SwiftUI

/// 「アプリを選ぶ」：iOS標準のアプリ選択（FamilyActivityPicker）で制限するアプリを選ぶ。
/// スクリーンタイムが未許可なら、ピッカーの前に許可を求める。
/// 初回設定（64:225）と設定の「アプリを追加」（161:150）で共通。
struct PickAppsButton: View {
    @Environment(AppStore.self) private var store
    @Environment(ScreenTimeService.self) private var screenTime

    @State private var isPickerPresented = false
    @State private var selection = FamilyActivitySelection()
    @State private var isRequesting = false
    @State private var showsUnavailable = false

    var body: some View {
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
                ScreenTimeUnavailableNotice(error: screenTime.lastError)
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: isPickerPresented) { _, presented in
            if !presented { store.syncPickedApps(selection.applicationTokens) }
        }
    }

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
}

/// スクリーンタイムを許可できなかったときの案内
struct ScreenTimeUnavailableNotice: View {
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("スクリーンタイムを許可できなかったため、アプリを選べません。", systemImage: "exclamationmark.triangle.fill")
                .font(SettingsMetrics.body)
                .foregroundStyle(Theme.textPrimary)
            if let error { FootNote(text: error) }
        }
        .padding(SettingsMetrics.gutter)
        .card()
    }
}
