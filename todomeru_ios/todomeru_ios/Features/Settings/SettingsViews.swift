import SwiftUI

// MARK: - 設定トップ（Figma 150:2）

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                LargeTitleHeader(title: "設定", backTitle: "ホーム") { router.pop() }
                section("リマインダーとルール") {
                    NavigationRow(title: "リマインダーのリスト", value: listSummary) {
                        router.push(.settingsLists)
                    }
                    NavigationRow(title: "ルール", value: "確認") {
                        router.push(.settingsRules)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
    }

    private var listSummary: String {
        "\(store.settings.selectedListIDs.count)つ選択中"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: title)
            DividedCard { content() }
                .padding(.horizontal, SettingsMetrics.gutter)
        }
    }
}

// MARK: - 設定：アプリと時間（旧 Figma 161:149。Figmaから削除され、設定トップからは開かない）

struct SettingsSNSTimeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LargeTitleHeader(title: "アプリと時間", backTitle: "設定") { router.pop() }
                SNSTimeEditor(subtitle: "アプリごとに、1日に使っていい時間を決めよう。")
                    .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            // 上限は＋／−の操作ごとに保存済み。ここでは設定トップへ戻る
            BottomActionButton(title: "保存する") { router.pop() }
        }
        .screenBackground()
    }
}

// MARK: - アプリを追加（Figma 161:150）

/// iOS標準のアプリ選択で制限対象を選ぶ。
struct SNSAddView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    private var pickedApps: [SNSApp] { store.selectedSNS.filter { $0.applicationToken != nil } }
    private var canApply: Bool { !pickedApps.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LargeTitleHeader(title: "アプリを追加", backTitle: "戻る", onBack: close)
                pickerSection
                    .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: canApply ? "選択を反映する" : "1つ以上選んでね", isEnabled: canApply, action: close)
        }
        .screenBackground()
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("制限するアプリを選んでね。")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            PickAppsButton()
            if !pickedApps.isEmpty {
                DividedCard {
                    ForEach(pickedApps) { sns in PickedAppRow(sns: sns) }
                }
            }
            FootNote(text: "iPhoneに入っているアプリから選びます。初めて使うときはスクリーンタイムの許可が必要です。")
        }
    }

    private func close() {
        router.pop()
    }
}

/// 標準機能で選んだアプリ（名前とアイコンはiOSが描く）
struct PickedAppRow: View {
    var sns: SNSApp

    var body: some View {
        HStack(spacing: 12) {
            SNSIcon(sns: sns, size: SettingsMetrics.rowIconSize)
            SNSNameLabel(sns: sns)
                .font(SettingsMetrics.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.antGold)
        }
        .padding(.horizontal, SettingsMetrics.gutter)
        .frame(minHeight: SettingsMetrics.rowMinHeight + 6)
    }
}

// MARK: - リスト設定（Figma 150:96）

struct ReminderListSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    @State private var draft: Set<String> = []
    @State private var autoAdd = false
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LargeTitleHeader(title: "リストを選択", backTitle: "設定") { router.pop() }
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    content
                }
                .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: "保存する", isEnabled: !isSaving) { Task { await save() } }
        }
        .screenBackground()
        .task {
            draft = store.settings.selectedListIDs
            autoAdd = store.settings.autoAddNewLists
            await reminders.reload(selectedListIDs: draft)
        }
    }

    private var intro: some View {
        HStack(alignment: .center, spacing: 12) {
            AntFace(stage: 4, size: SettingsMetrics.introCharacterSize)
            Text("選んだリストのやることをアリが確認して、やることを提案したり、完了をチェックしたりします。")
                .font(SettingsMetrics.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch reminders.state {
        case .denied:
            ReminderUnavailableNotice(message: "リマインダーへのアクセスが許可されていません。設定アプリで許可してください。")
        case .failed(let message):
            ReminderUnavailableNotice(message: "リストを取得できませんでした（\(message)）")
        case .idle where reminders.lists.isEmpty, .loading where reminders.lists.isEmpty:
            ProgressView().frame(maxWidth: .infinity).padding()
        default:
            if reminders.lists.isEmpty {
                FootNote(text: "リマインダーにリストがありません。リマインダーアプリでリストを作ると選べるようになります。")
            } else {
                ReminderListSelectionCard(lists: reminders.lists, selection: $draft)
            }
        }
    }

    private func save() async {
        isSaving = true
        store.settings.selectedListIDs = draft
        store.settings.autoAddNewLists = autoAdd
        await reminders.reload(selectedListIDs: draft)
        isSaving = false
        router.pop()
    }
}

// MARK: - ルール（Figma 150:114）

/// ルールの確認。数値は PolicyConstants の定数を表示する。
/// Figmaの「制限を解除する時間帯」はD010で対象外のため出さない。報酬・目標の行もFigma更新で非表示（値は内部に残る）。
struct RulesView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                LargeTitleHeader(title: "ルール", backTitle: "設定") { router.pop() }
                FootNote(text: "1日に相談できる回数を確認できます。")
                    .padding(.horizontal, SettingsMetrics.gutter)
                DividedCard {
                    ValueRow(title: "1日に相談できる回数", value: PolicyConstants.limitsPersuasionPerDay ? "\(PolicyConstants.persuasionDailyLimit)回" : "制限なし")
                }
                .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
    }
}
