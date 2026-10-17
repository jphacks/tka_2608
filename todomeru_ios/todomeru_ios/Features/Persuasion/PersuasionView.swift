import SwiftUI

/// AIとの相談チャット（Figma 30:2 利用できる / 32:2 利用できない / 210:39・210:359 相談のあとでやることを選ぶ）
struct PersuasionView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router
    @Environment(AIProvider.self) private var provider
    @State private var model: PersuasionViewModel

    init(snsID: String) {
        self.snsID = snsID
        _model = State(initialValue: PersuasionViewModel(snsID: snsID))
    }

    private var snsName: String { model.snsName(store) }
    private var recommendedTask: TaskItem? {
        model.suggestedTask ?? TaskSelectViewModel.candidates(from: reminders.tasks).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chatScroll
            bottomActions
            ChatInputBar(text: $model.input, placeholder: inputPlaceholder, isEnabled: model.canSend) {
                Task { await model.sendInput(store: store, reminders: reminders) }
            }
        }
        .screenBackground()
        .task { await model.start(store: store, provider: provider, reminders: reminders) }
    }

    // MARK: - ヘッダー

    @ViewBuilder private var header: some View {
        if model.phase == .quotaExhausted && model.userMessageCount == 0 {
            AntChatHeader(antStage: model.antStage, onClose: close)
        } else {
            AntChatHeader(
                antStage: model.antStage,
                caption: "納得度 \(model.conviction)%",
                captionColor: Theme.convictionText(score: model.conviction),
                antBackground: Theme.convictionBackground(score: model.conviction),
                onClose: close
            )
        }
    }

    private func close() { model.close(store: store, router: router) }

    private var inputPlaceholder: String {
        if model.isPickingTask { return model.picker.selected == nil ? "やることを選んでね" : "メッセージを入力…" }
        return "理由を入力して相談する…"
    }

    // MARK: - 会話

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatMetrics.messageSpacing) {
                    demoNotice
                    ForEach(model.messages) { m in
                        messageRow(m)
                    }
                    if let partial = model.streamingText {
                        ChatBubble(message: ChatMessage(role: .ai, text: partial), antStage: model.antStage)
                    } else if model.isGenerating {
                        TypingIndicator()
                    }
                    standalonePhaseCard
                    pickedTaskLines
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, ChatMetrics.horizontalPadding)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.isGenerating) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: model.phase) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.picker.selected) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    /// 疑似制限であること・使っているAIの種類（実際のSNSの制限を変えたと誤認させない）
    private var demoNotice: some View {
        HStack(spacing: 6) {
            if !model.aiKindLabel.isEmpty { DemoBadge(text: model.aiKindLabel) }
            Text("デモの疑似制限です。実際の\(snsName)の制限は変更しません")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 1通分。結果カードは最後のアリの発言の中に、候補一覧は「どれをやる？」の中に入れる
    @ViewBuilder private func messageRow(_ m: ChatMessage) -> some View {
        if m.id == model.pickPromptID {
            pickBubble(m)
        } else if m.id == resultHostID {
            AntBubbleContainer(antStage: model.antStage) {
                AntBubbleText(text: m.text)
                resultCard
            }
        } else {
            ChatBubble(message: m, antStage: model.antStage)
        }
    }

    /// 結果カードを入れるアリの発言（判定が出たときの最後のアリの発言）
    private var resultHostID: UUID? {
        guard hasResultCard, model.streamingText == nil else { return nil }
        let candidates = model.pickPromptID.map { id in model.messages.prefix { $0.id != id } } ?? model.messages[...]
        guard let last = candidates.last(where: { $0.role != .system }), last.role == .ai else { return nil }
        return last.id
    }

    private var hasResultCard: Bool {
        switch model.phase {
        case .approvable, .rejected: return true
        default: return false
        }
    }

    /// 30:2 / 32:2 の結果カード
    @ViewBuilder private var resultCard: some View {
        switch model.phase {
        case .approvable(let seconds):
            ChatNoticeCard(title: "\(snsName)を\(TimeFormat.hm(seconds)) 利用できます")
        case .rejected(let reason):
            ChatNoticeCard(
                title: recommendedTask.map { "「\($0.title)」を5分だけやってみよう" } ?? reason,
                caption: rejectedCaption(reason: reason)
            )
            retryButton
        default:
            EmptyView()
        }
    }

    private func rejectedCaption(reason: String) -> String {
        let remaining = "今日の相談：あと\(store.persuasionsRemainingToday())回"
        return reason == PersuasionText.notConvinced ? remaining : "\(reason)・\(remaining)"
    }

    /// 発言にくっつけない案内（AIの失敗・回数切れ・結果を入れる発言がない場合）
    @ViewBuilder private var standalonePhaseCard: some View {
        if !model.isPickingTask {
            switch model.phase {
            case .chatting:
                EmptyView()
            case .approvable, .rejected:
                if resultHostID == nil && model.streamingText == nil && !model.isGenerating {
                    AntBubbleContainer(antStage: model.antStage) { resultCard }
                }
            case .failed(let message):
                AntBubbleContainer(antStage: 1) {
                    ChatNoticeCard(icon: "exclamationmark.triangle", title: message)
                    retryButton
                }
            case .quotaExhausted:
                AntBubbleContainer(antStage: 0) {
                    ChatNoticeCard(
                        icon: "hand.raised",
                        title: TaskSelectViewModel.consultationUsedUp,
                        caption: "朝\(PolicyConstants.dayBoundaryHour)時に回数が戻ります。やることを片付けてSNS時間をためよう"
                    )
                }
            }
        }
    }

    @ViewBuilder private var retryButton: some View {
        if !model.isPickingTask && UnlockPolicy.canStartPersuasion(store: store) {
            Button("もう一度相談する") { model.beginNewAttempt(store: store, reminders: reminders) }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.brown)
        }
    }

    // MARK: - 相談のあとでやることを選ぶ（210:39 / 210:359）

    @ViewBuilder private func pickBubble(_ m: ChatMessage) -> some View {
        let tasks = TaskSelectViewModel.candidates(from: reminders.tasks)
        AntBubbleContainer(antStage: model.antStage) {
            AntBubbleText(text: m.text)
            switch reminders.state {
            case .denied:
                AntBubbleText(text: "リマインダーへのアクセスが許可されていないため、やることを読み込めませんでした。")
            case .failed(let msg):
                AntBubbleText(text: "やることの読み込みに失敗しました（\(msg)）。")
            default:
                if tasks.isEmpty {
                    AntBubbleText(text: reminders.state == .loaded ? "未完了のやることがないよ。リマインダーにやることを追加してね。" : "やることを読み込み中…")
                } else {
                    TaskCandidateList(
                        tasks: tasks,
                        recommendedID: recommendedTask?.id ?? tasks.first?.id,
                        selectedID: model.picker.selected?.id,
                        isEnabled: !model.picker.isStarting
                    ) { model.picker.select($0) }
                }
            }
            if reminders.isDemo { DemoBadge(text: "デモのやること") }
        }
    }

    /// 選んだあとの「『…』をやるよ！」と、アリの見送り
    @ViewBuilder private var pickedTaskLines: some View {
        if model.isPickingTask {
            if let task = model.picker.selected {
                ChatBubble(message: ChatMessage(role: .user, text: TaskSelectViewModel.userLine(for: task)))
                ChatBubble(message: ChatMessage(role: .ai, text: TaskSelectViewModel.rewardLineAfterConsultation), antStage: model.antStage)
            }
            if let err = model.picker.startError {
                ChatBubble(message: ChatMessage(role: .ai, text: err), antStage: 1)
            }
        }
    }

    // MARK: - 下部の操作

    @ViewBuilder private var bottomActions: some View {
        if model.isPickingTask {
            if model.picker.selected != nil {
                Button {
                    Task { await model.startPickedTask(store: store, reminders: reminders, router: router) }
                } label: {
                    if model.picker.isStarting { ProgressView().tint(.white) } else { Text("やることを始める") }
                }
                .buttonStyle(.primary)
                .disabled(model.picker.isStarting)
                .padding(.horizontal, ChatMetrics.horizontalPadding)
                .padding(.vertical, 8)
            }
        } else {
            PersuasionActionBar(
                snsName: snsName,
                phase: model.phase,
                onOpen: { model.openSNS(store: store, router: router) },
                onTasks: { model.goToTasks(store: store, router: router) }
            )
        }
    }
}

/// 相談まわりの決まった文言
enum PersuasionText {
    /// 不許可の標準の理由（PersuasionViewModel と同じ文言）
    static let notConvinced = "納得度が足りません"
}

/// 下部の「Xを開く」（主）「やることを片付ける」（副）
private struct PersuasionActionBar: View {
    var snsName: String
    var phase: PersuasionViewModel.Phase
    var onOpen: () -> Void
    var onTasks: () -> Void

    private var grantSeconds: Int? {
        if case .approvable(let s) = phase { return s }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            if let grantSeconds {
                Button(action: onOpen) {
                    VStack(spacing: 1) {
                        Text("\(snsName)を開く")
                        Text(TimeFormat.hm(grantSeconds)).font(.system(size: 10, weight: .regular))
                    }
                }
                .buttonStyle(.primary)
            } else {
                LockedOpenButton(snsName: snsName, caption: lockedCaption)
            }
            Button("やることを片付ける", action: onTasks)
                .buttonStyle(.secondary)
        }
        .padding(.horizontal, ChatMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }

    private var lockedCaption: String {
        switch phase {
        case .chatting, .approvable: return "相談中"
        case .rejected, .quotaExhausted: return "まだ納得していないようです"
        case .failed: return "利用できません"
        }
    }
}

/// 押せない「🔒 Xを開く」（32:2 のグレーのボタン）
private struct LockedOpenButton: View {
    var snsName: String
    var caption: String

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("\(snsName)を開く")
            }
            .font(.system(size: 16, weight: .bold))
            Text(caption).font(.system(size: 10))
        }
        .foregroundStyle(Theme.lockedButtonText)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Theme.lockedButton, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("まだ利用できません")
    }
}
