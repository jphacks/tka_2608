import FamilyControls
import SwiftUI

/// 「アプリを選ぶ」：iOS標準のアプリ選択（FamilyActivityPicker）で制限するSNSを選ぶ。
/// スクリーンタイムが未許可なら、ピッカーの前に許可を求める。許可できなければデモの候補へ案内する。
/// 初回設定（64:225）と設定の「SNSを追加」（161:150）で共通。
struct PickAppsButton: View {
    @Environment(AppStore.self) private var store
    @Environment(ScreenTimeService.self) private var screenTime
    /// 許可できなかったときに「デモの候補から選ぶ」へ進む操作（nil なら案内文のみ）
    var onUseDemo: (() -> Void)?

    @State private var isPickerPresented = false
    @State private var selection = FamilyActivitySelection()
    @State private var isRequesting = false
    @State private var showsUnavailable = false

    var body: some View {
        #if TODOMERU_PERSONAL_DEMO
        VStack(alignment: .leading, spacing: 8) {
            if let onUseDemo {
                Button("デモの候補から選ぶ", action: onUseDemo)
                    .buttonStyle(.primary)
            }
            HStack(alignment: .top, spacing: 6) {
                DemoBadge()
                FootNote(text: "アプリ内の疑似SNSで、上限と一時解除を試せます。実際のSNSは制限されません。")
            }
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
                ScreenTimeUnavailableNotice(error: screenTime.lastError, onUseDemo: onUseDemo)
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

/// スクリーンタイムを許可できなかったときの案内（デモの候補で続けられる）
struct ScreenTimeUnavailableNotice: View {
    var error: String?
    var onUseDemo: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("スクリーンタイムを許可できなかったため、アプリを選べません。", systemImage: "exclamationmark.triangle.fill")
                .font(SettingsMetrics.body)
                .foregroundStyle(Theme.textPrimary)
            if let error { FootNote(text: error) }
            HStack(alignment: .top, spacing: 6) {
                DemoBadge()
                FootNote(text: "デモの候補から選ぶと、アプリ内の疑似制限で試せます。")
            }
            if let onUseDemo {
                Button("デモの候補から選ぶ", action: onUseDemo)
                    .buttonStyle(.secondary)
            }
        }
        .padding(SettingsMetrics.gutter)
        .card()
    }
}
