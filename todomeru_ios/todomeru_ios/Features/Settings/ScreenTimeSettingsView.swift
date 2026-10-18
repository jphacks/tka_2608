import FamilyControls
import SwiftUI

/// スクリーンタイムの実機能を試す画面（テスト中）。
/// 端末に入っているアプリをOS標準のピッカーで選び、今すぐ制限をかけたり外したりできる。
struct ScreenTimeSettingsView: View {
    @Environment(ScreenTimeService.self) private var screenTime
    @Environment(Router.self) private var router
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var screenTime = screenTime
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                LargeTitleHeader(title: "スクリーンタイム", backTitle: "設定") { router.pop() }
                #if TODOMERU_PERSONAL_DEMO
                VStack(alignment: .leading, spacing: 10) {
                    DemoBadge()
                    FootNote(text: "このデモでは、アプリ内の疑似画面で上限と一時解除を試せます。実際のアプリの使用時間取得や制限は行いません。")
                    Button("デモのアプリを選ぶ") { router.push(.settingsSNSAdd) }
                        .buttonStyle(.primary)
                }
                .padding(.horizontal, SettingsMetrics.gutter)
                #else
                ScreenTimeAuthorizationSection()
                if screenTime.isAuthorized {
                    ScreenTimeAppsSection { isPickerPresented = true }
                    ScreenTimeShieldSection()
                }
                FootNote(text: "テスト中の機能です。選んだアプリに今すぐ制限をかけたり外したりできます。上限や使用時間に応じた自動の制限・解除と、AIへの相談による一時解除とはまだつながっていません。")
                    .padding(.horizontal, SettingsMetrics.gutter)
                #endif
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        #if !TODOMERU_PERSONAL_DEMO
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $screenTime.selection)
        #endif
        .onAppear { screenTime.refreshStatus() }
    }
}

private struct ScreenTimeAuthorizationSection: View {
    @Environment(ScreenTimeService.self) private var screenTime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "許可")
            DividedCard {
                ValueRow(title: "スクリーンタイムへのアクセス", value: statusText)
                if !screenTime.isAuthorized {
                    Button("許可する") { Task { await screenTime.requestAuthorization() } }
                        .buttonStyle(.primary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, SettingsMetrics.gutter)
            if let error = screenTime.lastError {
                FootNote(text: error)
                    .padding(.horizontal, SettingsMetrics.gutter)
            }
        }
    }

    private var statusText: String {
        switch screenTime.authorizationStatus {
        case .approved: return "許可済み"
        case .denied: return "許可されていません"
        default: return "未設定"
        }
    }
}

private struct ScreenTimeAppsSection: View {
    @Environment(ScreenTimeService.self) private var screenTime
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "制限するアプリ")
            DividedCard {
                ForEach(Array(screenTime.selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .padding(.vertical, 4)
                }
                NavigationRow(title: "アプリを選ぶ", value: "\(screenTime.selectedAppCount)個", action: onPick)
            }
            .padding(.horizontal, SettingsMetrics.gutter)
        }
    }
}

private struct ScreenTimeShieldSection: View {
    @Environment(ScreenTimeService.self) private var screenTime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "制限（テスト）")
            VStack(spacing: 10) {
                Button("選んだアプリを今すぐ制限する") { screenTime.applyShield() }
                    .buttonStyle(.primary)
                    .disabled(screenTime.selectedAppCount == 0)
                Button("制限を外す") { screenTime.clearShield() }
                    .buttonStyle(.secondary)
                    .disabled(!screenTime.isShieldApplied)
                FootNote(text: screenTime.isShieldApplied ? "制限中です。ホーム画面から選んだアプリを開くと、OSの制限画面が出ます。" : "今は制限していません。")
            }
            .padding(.horizontal, SettingsMetrics.gutter)
        }
    }
}
