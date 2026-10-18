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

    /// 開こうとしているアプリ（見つからないときは名前だけの仮のアプリ）
    private var sns: SNSApp { model.sns(store) }
    private var recommendedTask: TaskItem? {
        model.suggestedTask ?? TaskSelectViewModel.candidates(from: reminders.tasks).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chatScroll
            bottomActions
            ChatInputBar(text: $model.input, placeholder: inputPlaceholder, isEnabled: model.canType(store: store)) {
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
        if model.isPickingTask {
            if model.picker.selected == nil { return "やることを選んでね" }
            return model.canAnswerFirstStep ? "どこまで進んでるか教えて（任意）…" : "メッセージを入力…"
        }
        if model.canRetryBySending(store: store) { return "理由を入力してもう一度相談する…" }
        return "理由を入力して相談する…"
    }

    // MARK: - 会話

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatMetrics.messageSpacing) {
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
            .onChange(of: model.firstStep) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    /// 1通分。結果カードは最後のアリの発言の中に、候補一覧は「どれをやる？」の中に入れる
    @ViewBuilder private func messageRow(_ m: ChatMessage) -> some View {
        if m.id == model.pickPromptID {
            pickBubble(m)
        } else if m.id == model.deviceGrantMessageID, let seconds = model.deviceGrantSeconds {
            deviceGrantBubble(seconds: seconds)
        } else if m.id == resultHostID {
            AntBubbleContainer(antStage: model.antStage) {
                AntBubbleText(text: m.text)
                resultCard
            }
        } else {
            ChatBubble(message: m, antStage: model.antStage)
        }
    }

    /// 結果カードを入れるアリの発言（判定を出したアリの発言）
    private var resultHostID: UUID? {
        hasResultCard ? model.resultMessageID : nil
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
            ChatNoticeCard(caption: "\(TimeFormat.hm(seconds))使えます") { SNSPhrase(sns: sns, suffix: "が使用可能になりました！") }
        case .rejected(let reason):
            // しきい値に届いたのに許可できなかった（回数・既存の枠）ときは、やることを勧めず理由を出す
            let reached = model.conviction >= PolicyConstants.persuasionApprovalThreshold
            ChatNoticeCard(
                title: reached ? reason : recommendedTask.map { "「\($0.title)」を5分だけやってみよう" } ?? reason,
                caption: rejectedCaption(reason: reached ? nil : reason)
            )
            retryButton
        default:
            EmptyView()
        }
    }

    /// 標準機能で選んだアプリの利用枠を出したあと：本体からは開けないので、ホーム画面から開くよう案内する
    private func deviceGrantBubble(seconds: Int) -> some View {
        AntBubbleContainer(antStage: model.antStage) {
            AntBubbleText(text: "使えるようにしたよ。")
            ChatNoticeCard(icon: "house", caption: "\(TimeFormat.hm(seconds))たつとまた制限されます") {
                SNSPhrase(prefix: "ホーム画面から", sns: sns, suffix: "を開いてね")
            }
        }
    }

    private func rejectedCaption(reason: String?) -> String? {
        let detail = reason == PersuasionText.notConvinced ? nil : reason
        guard let left = store.persuasionsRemainingToday() else { return detail }
        let remaining = "今日の相談：あと\(left)回"
        return detail.map { "\($0)・\(remaining)" } ?? remaining
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
                        caption: "朝\(PolicyConstants.dayBoundaryHour)時に回数が戻ります。やることを片付けてアプリ時間を増やそう"
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
        }
    }

    /// 選んだあとの「『…』をやるよ！」と、アリの見送り
    @ViewBuilder private var pickedTaskLines: some View {
        if model.isPickingTask {
            if let task = model.picker.selected {
                ChatBubble(message: ChatMessage(role: .user, text: TaskSelectViewModel.userLine(for: task)))
                ChatBubble(message: ChatMessage(role: .ai, text: PersuasionViewModel.firstStepQuestion(for: task)), antStage: model.antStage)
                firstStepLines
            }
            if let err = model.picker.startError {
                ChatBubble(message: ChatMessage(role: .ai, text: err), antStage: 1)
            }
        }
    }

    /// 進み具合の答えと最初の一歩。答える前・提案のあとに見送りを出す
    @ViewBuilder private var firstStepLines: some View {
        if let step = model.firstStepForSelected {
            ChatBubble(message: ChatMessage(role: .user, text: step.answer))
            if let suggestion = step.suggestion {
                ChatBubble(message: ChatMessage(role: .ai, text: suggestion), antStage: model.antStage)
                ChatBubble(message: ChatMessage(role: .ai, text: TaskSelectViewModel.rewardLineAfterConsultation), antStage: model.antStage)
            } else if let partial = step.streamingText {
                ChatBubble(message: ChatMessage(role: .ai, text: partial), antStage: model.antStage)
            } else {
                TypingIndicator()
            }
        } else {
            ChatBubble(message: ChatMessage(role: .ai, text: TaskSelectViewModel.rewardLineBeforeFirstStep), antStage: model.antStage)
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
        } else if model.deviceGrantSeconds != nil {
            Button("ホームに戻る") { model.goHome(router: router) }
                .buttonStyle(.primary)
                .padding(.horizontal, ChatMetrics.horizontalPadding)
                .padding(.vertical, 8)
        } else {
            PersuasionActionBar(
                sns: sns,
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
    var sns: SNSApp
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
                        SNSPhrase(sns: sns, suffix: "を開く")
                        Text(TimeFormat.hm(grantSeconds)).font(.system(size: 10, weight: .regular))
                    }
                }
                .buttonStyle(.primary)
            } else {
                LockedOpenButton(sns: sns, caption: lockedCaption)
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
    var sns: SNSApp
    var caption: String

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                SNSPhrase(sns: sns, suffix: "を開く")
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
