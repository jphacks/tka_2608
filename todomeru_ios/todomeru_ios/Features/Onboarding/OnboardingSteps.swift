import SwiftUI

// MARK: - 1. ようこそ（Figma 64:2）

struct WelcomeStepView: View {
    var onStart: () -> Void

    var body: some View {
        OnboardingStepScaffold(buttonTitle: "はじめる", action: onStart) {
            VStack(spacing: 20) {
                characters
                Text("ToDoメーる")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("あなたは、やることがあるのに\nついSNSやゲームを開いてしまうキリギリス。\nそんなあなたを、アリがサポートします。\nついSNSを開いてしまっても、\nアリがあなたのやることを思い出させてくれます。")
                    .font(SettingsMetrics.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    private var characters: some View {
        HStack(spacing: 24) {
            CharacterImage(name: "hero_ant", fallback: "🐜", size: 110)
            CharacterImage(name: "hero_grasshopper", fallback: "🦗", size: 110)
        }
        .padding(30)
        .background(Theme.welcomeHalo, in: Circle())
    }
}

// MARK: - 2. アクセスを許可する（Figma 64:115）

struct PermissionsStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase
    var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(buttonTitle: "次へ", isEnabled: vm.canLeavePermissions(store: store)) {
            vm.goNext()
        } content: {
            AntIntroHeader(title: "アクセスを許可する", message: "SNSを制限したり、やることを確認したりするのに使います。")
            DividedCard {
                PermissionRow(icon: "hourglass", color: Theme.permissionScreenTime, title: "スクリーンタイム",
                              message: "SNSの使用時間を確認して、上限を超えたら制限します。",
                              status: vm.screenTimeAcknowledged ? .done("デモでは疑似制限") : .action("許可する")) {
                    vm.screenTimeAcknowledged = true
                }
                PermissionRow(icon: "list.bullet", color: Theme.permissionReminder, title: "リマインダー",
                              message: "やることを読み取り、完了したらチェックを付けます。",
                              status: reminderStatus) {
                    Task { await vm.requestReminderAccess(reminders, store: store) }
                }
                PermissionRow(icon: "bell.fill", color: Theme.permissionNotification, title: "通知",
                              message: "アリからの声かけに使います。",
                              status: .note("このデモでは使いません"), onTap: nil)
            }
            screenTimeNote
            reminderFallback
            FootNote(text: "制限するSNSの中身（投稿やメッセージ、ゲームの内容）は見ません。\n確認するのは、どのSNSをどれだけ使ったかのみです。")
        }
        .onAppear { vm.refreshReminderAccess(reminders) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.refreshReminderAccess(reminders) }
        }
    }

    private var reminderStatus: PermissionRow.Status {
        switch vm.reminderAccess {
        case .granted: return .done(nil)
        case .requesting: return .progress
        case .denied: return .action("再確認")
        case .notDetermined: return .action("許可する")
        }
    }

    @ViewBuilder
    private var screenTimeNote: some View {
        if vm.screenTimeAcknowledged {
            HStack(alignment: .top, spacing: 6) {
                DemoBadge()
                FootNote(text: "このデモ版ではスクリーンタイムの認可はせず、アプリ内の疑似制限で体験します。実際のSNSは制限されません。")
            }
        }
    }

    @ViewBuilder
    private var reminderFallback: some View {
        if store.settings.useDemoTasks {
            HStack(alignment: .top, spacing: 6) {
                DemoBadge()
                FootNote(text: "デモ用のやることで試します。あとから設定で切り替えられます。")
            }
        } else if vm.reminderAccess == .denied {
            ReminderUnavailableNotice(message: "リマインダーへのアクセスが許可されていません。設定アプリで許可するか、デモ用のやることで試せます。") {
                Task { await vm.chooseDemoTasks(reminders, store: store) }
            }
        }
    }
}

/// 権限の1行（アイコン・説明・右側の状態）
struct PermissionRow: View {
    enum Status {
        case action(String)
        case done(String?)
        case progress
        case note(String)
    }

    var icon: String
    var color: Color
    var title: String
    var message: String
    var status: Status
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsMetrics.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(SettingsMetrics.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .action(let label):
            Button(label) { onTap?() }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.summaryYellow, in: Capsule())
                .buttonStyle(.plain)
        case .done(let label):
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.grasshopperGreen)
                if let label {
                    Text(label).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
            }
        case .progress:
            ProgressView()
        case .note(let label):
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
        }
    }
}

// MARK: - 3. リストを選択する（Figma 67:2）

struct ListsStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(buttonTitle: "次へ", isEnabled: !vm.isWorking && vm.canLeaveLists(store: store, reminders: reminders)) {
            Task { await vm.commitLists(reminders, store: store) }
        } content: {
            AntIntroHeader(title: "リストを選択する", message: "選んだリストのやることをアリが確認して、やることを提案したり、完了をチェックしたりします。")
            content
            FootNote(text: "リストはあとから設定で変更できます。")
        }
        .task { await vm.loadLists(reminders, store: store) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isWorking && reminders.lists.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if store.settings.useDemoTasks {
            ReminderListSelectionCard(lists: reminders.lists, selection: .constant(vm.listSelection), isDemo: true)
            if reminders.hasFullAccess {
                Button("リマインダーのリストを使う") {
                    Task { await vm.chooseRealReminders(reminders, store: store) }
                }
                .buttonStyle(.secondary)
            }
        } else {
            realListContent
        }
    }

    @ViewBuilder
    private var realListContent: some View {
        switch reminders.state {
        case .denied:
            ReminderUnavailableNotice(message: "リマインダーへのアクセスが許可されていないため、リストを表示できません。", onUseDemo: useDemo)
        case .failed(let message):
            ReminderUnavailableNotice(message: "リストを取得できませんでした（\(message)）", onUseDemo: useDemo)
        default:
            if reminders.lists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    FootNote(text: "リマインダーにリストがありません。リマインダーアプリでリストを作るか、デモ用のやることで試せます。")
                    Button("デモ用のやることで試す", action: useDemo).buttonStyle(.secondary)
                }
                .padding(SettingsMetrics.gutter)
                .card()
            } else {
                ReminderListSelectionCard(lists: reminders.lists, selection: $vm.listSelection)
            }
        }
    }

    private func useDemo() {
        Task { await vm.chooseDemoTasks(reminders, store: store) }
    }
}

// MARK: - 4. SNSと時間（Figma 64:225。SNS追加は 161:150 をシートで）

struct SNSStepView: View {
    @Environment(AppStore.self) private var store
    var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(buttonTitle: "次へ", isEnabled: vm.canLeaveSNS(store: store)) {
            vm.goNext()
        } content: {
            SNSTimeEditor(subtitle: "SNSごとに、1日に使っていい時間を決めよう。") {
                vm.isShowingSNSAdd = true
            }
        }
    }
}

// MARK: - 5. 準備OK（Figma 64:395）

struct ReadyStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(buttonTitle: "ホームへ", isEnabled: !vm.isWorking) {
            Task { await vm.finish(reminders, store: store) }
        } content: {
            VStack(spacing: 16) {
                CharacterImage(name: "hero_ant", fallback: "🐜", size: 180)
                Text("準備OK！")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("一緒に頑張ろうね！")
                    .font(SettingsMetrics.body)
                    .foregroundStyle(Theme.textSecondary)
                summary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryLine("やること", store.settings.useDemoTasks ? "デモ用のやること" : "\(store.settings.selectedListIDs.count)つのリスト")
            summaryLine("制限するSNS", "\(store.selectedSNS.count)個")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.top, 12)
    }

    private func summaryLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(SettingsMetrics.body).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(SettingsMetrics.rowValue).foregroundStyle(Theme.textPrimary)
        }
    }
}
