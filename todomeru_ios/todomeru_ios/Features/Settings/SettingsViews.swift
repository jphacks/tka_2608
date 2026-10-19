import SwiftUI

// MARK: - 設定トップ（Figma 150:2）

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                LargeTitleHeader(title: "設定", backTitle: "ホーム") { router.pop() }
                section("リマインダーと相談") {
                    NavigationRow(title: "リマインダーのリスト", value: listSummary) {
                        router.push(.settingsLists)
                    }
                    Stepper(value: Binding(
                        get: { store.settings.persuasionDailyLimit },
                        set: { store.settings.persuasionDailyLimit = max(1, $0) }
                    ), in: 1...Int.max) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("1日に相談できる回数")
                                .font(SettingsMetrics.rowTitle)
                            Text("\(store.settings.persuasionDailyLimit)回")
                                .font(SettingsMetrics.rowValue)
                                .foregroundStyle(Theme.antGold)
                        }
                    }
                    .padding(.horizontal, SettingsMetrics.gutter)
                    .padding(.vertical, 12)
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
