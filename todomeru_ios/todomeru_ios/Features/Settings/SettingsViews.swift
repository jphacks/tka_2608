import SwiftUI

// MARK: - 設定トップ（Figma 150:2）

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ScreenTimeService.self) private var screenTime
    @Environment(ReminderService.self) private var reminders
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
                // Figmaにはない開発用の項目（実機のスクリーンタイム検証）
                section("開発用") {
                    NavigationRow(title: "スクリーンタイム（テスト中）", value: screenTime.isShieldApplied ? "制限中" : "\(screenTime.selectedAppCount)個のアプリ") {
                        router.push(.settingsScreenTime)
                    }
                }
                DemoSettingsSection()
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
    }

    private var listSummary: String {
        store.settings.useDemoTasks ? "デモ" : "\(store.settings.selectedListIDs.count)つ選択中"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: title)
            DividedCard { content() }
                .padding(.horizontal, SettingsMetrics.gutter)
        }
    }
}

/// 設定トップ下部のデモ用操作（Figmaにはない。発表・検証用）
struct DemoSettingsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionCaption(text: "デモ用")
                DemoBadge()
            }
            DividedCard {
                Toggle(isOn: $store.settings.useDemoTasks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("デモ用のやることを使う")
                            .font(SettingsMetrics.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("リマインダーの代わりに、用意した例のやることを表示します。")
                            .font(SettingsMetrics.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.brown)
                .padding(.horizontal, SettingsMetrics.gutter)
                .padding(.vertical, 10)

                Button(role: .destructive) {
                    isConfirmingReset = true
                } label: {
                    Text("データをリセットして初回設定からやり直す")
                        .font(SettingsMetrics.rowTitle)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SettingsMetrics.gutter)
                        .frame(minHeight: SettingsMetrics.rowMinHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SettingsMetrics.gutter)
        }
        .onChange(of: store.settings.useDemoTasks) { _, useDemo in
            Task { await reminders.reload(selectedListIDs: store.settings.selectedListIDs, useDemo: useDemo) }
        }
        .confirmationDialog("すべてのデータをリセットしますか？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("リセットする", role: .destructive, action: reset)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("設定・取り組み・SNS時間・相談の記録を消して、初回設定に戻ります。リマインダーの内容は変わりません。")
        }
    }

    private func reset() {
        router.popToRoot()
        router.tab = .home
        store.resetAll()
    }
}

// MARK: - 設定：SNSと時間（旧 Figma 161:149。Figmaから削除され、設定トップからは開かない）

struct SettingsSNSTimeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LargeTitleHeader(title: "SNSと時間", backTitle: "設定") { router.pop() }
                SNSTimeEditor(subtitle: "SNSごとに、1日に使っていい時間を決めよう。") {
                    router.push(.settingsSNSAdd)
                }
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

// MARK: - SNSを追加（Figma 161:150）

/// 制限するSNSの候補を選ぶ。初回設定ではシート、設定からは画面遷移で開く。
struct SNSAddView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    /// シート表示のときに閉じる処理。nil なら router.pop()
    var onDone: (() -> Void)? = nil

    @State private var draft: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LargeTitleHeader(title: "SNSを追加", backTitle: "戻る", onBack: close)
                VStack(alignment: .leading, spacing: 12) {
                    Text("制限するSNSを選んでね。")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    DividedCard {
                        ForEach(store.snsApps) { sns in
                            SNSCandidateRow(sns: sns, isSelected: draft.contains(sns.id)) { toggle(sns.id) }
                        }
                    }
                    FootNote(text: "使う時間は、戻った画面で調整できます。")
                    FootNote(text: "デモでは決まった候補から選びます（実機ではスクリーンタイムのアプリ選択に置き換える想定です）。")
                }
                .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: draft.isEmpty ? "1つ以上選んでね" : "選択を反映する", isEnabled: !draft.isEmpty, action: apply)
        }
        .screenBackground()
        .onAppear { draft = Set(store.selectedSNS.map(\.id)) }
    }

    private func toggle(_ id: String) {
        if draft.contains(id) { draft.remove(id) } else { draft.insert(id) }
    }

    private func apply() {
        var apps = store.snsApps
        for i in apps.indices { apps[i].isSelected = draft.contains(apps[i].id) }
        store.snsApps = apps
        close()
    }

    private func close() {
        if let onDone { onDone() } else { router.pop() }
    }
}

struct SNSCandidateRow: View {
    var sns: SNSApp
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                SNSIcon(sns: sns, size: SettingsMetrics.rowIconSize)
                Text(sns.name)
                    .font(SettingsMetrics.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.segmentBackground)
                    .frame(width: 26, height: 26)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.antGold)
                        }
                    }
            }
            .padding(.horizontal, SettingsMetrics.gutter)
            .frame(minHeight: SettingsMetrics.rowMinHeight + 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    autoAddCard
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
            await reminders.reload(selectedListIDs: draft, useDemo: store.settings.useDemoTasks)
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
            ReminderUnavailableNotice(message: "リマインダーへのアクセスが許可されていません。設定アプリで許可するか、設定トップの「デモ用のやることを使う」で試せます。", onUseDemo: nil)
        case .failed(let message):
            ReminderUnavailableNotice(message: "リストを取得できませんでした（\(message)）", onUseDemo: nil)
        case .idle where reminders.lists.isEmpty, .loading where reminders.lists.isEmpty:
            ProgressView().frame(maxWidth: .infinity).padding()
        default:
            if reminders.lists.isEmpty {
                FootNote(text: "リマインダーにリストがありません。リマインダーアプリでリストを作ると選べるようになります。")
            } else {
                if store.settings.useDemoTasks {
                    FootNote(text: "デモ用のやることを使用中です。リストの選択はデモの表示には反映されません。")
                }
                ReminderListSelectionCard(lists: reminders.lists, selection: $draft, isDemo: reminders.isDemo)
            }
        }
    }

    private var autoAddCard: some View {
        Toggle(isOn: $autoAdd) {
            VStack(alignment: .leading, spacing: 2) {
                Text("新しいリストを自動で追加")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("ONにすると、新しいリストも対象にします。")
                    .font(SettingsMetrics.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.brown)
        .padding(SettingsMetrics.gutter)
        .card()
    }

    private func save() async {
        isSaving = true
        store.settings.selectedListIDs = draft
        store.settings.autoAddNewLists = autoAdd
        await reminders.reload(selectedListIDs: draft, useDemo: store.settings.useDemoTasks)
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
                    ValueRow(title: "1日に相談できる回数", value: "\(PolicyConstants.persuasionDailyLimit)回")
                }
                .padding(.horizontal, SettingsMetrics.gutter)
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
    }
}
