import SwiftUI

/// AIの説得チャット（Figma 30:2 利用できる / 32:2 利用できない）
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
    private var threshold: Int { PolicyConstants.persuasionApprovalThreshold }
    private var recommendedTask: TaskItem? {
        model.suggestedTask ?? TaskSelectViewModel.candidates(from: reminders.tasks).first
    }

    var body: some View {
        VStack(spacing: 0) {
            AntChatHeader(
                antStage: model.antStage,
                antCaption: "アリ・\(AntFace.labels[model.antStage])",
                onClose: { model.close(store: store, router: router) }
            ) { band }
            chatScroll
            PersuasionActionBar(
                snsName: snsName,
                phase: model.phase,
                onOpen: { model.openSNS(store: store, router: router) },
                onTasks: { model.goToTasks(store: store, router: router) }
            )
            ChatInputBar(text: $model.input, placeholder: "理由を入力して説得する…", isEnabled: model.canSend) {
                Task { await model.sendInput(store: store, reminders: reminders) }
            }
        }
        .screenBackground()
        .task { await model.start(store: store, provider: provider, reminders: reminders) }
    }

    // MARK: - 状態帯

    private var band: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusBandTitle(
                title: "\(snsName)を開くための説得中",
                trailing: "納得度 \(model.conviction)%",
                trailingColor: model.conviction >= threshold / 2 ? Theme.convictionHighText : Theme.convictionLow
            )
            ConvictionGauge(score: model.conviction, threshold: threshold)
            HStack(spacing: 6) {
                if let t = recommendedTask { StatusBandCaption(text: "おすすめ：\(t.title)") }
                Spacer(minLength: 4)
                Text("今日の説得 あと\(store.persuasionsRemainingToday())回")
                    .font(.system(size: ChatMetrics.captionFont, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                if !model.aiKindLabel.isEmpty { DemoBadge(text: model.aiKindLabel) }
                Text("デモの疑似制限です。実際の\(snsName)の制限は変更しません")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - 会話

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatMetrics.messageSpacing) {
                    ForEach(model.messages) { m in
                        ChatBubble(message: m, antStage: model.antStage)
                    }
                    if model.isGenerating { TypingIndicator() }
                    phaseCard
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, ChatMetrics.horizontalPadding)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.isGenerating) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.phase) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    @ViewBuilder private var phaseCard: some View {
        switch model.phase {
        case .chatting:
            EmptyView()
        case .approvable(let seconds):
            AntBubbleContainer(antStage: model.antStage) {
                ChatNoticeCard(
                    title: "\(snsName)を\(TimeFormat.hm(seconds))利用できます",
                    caption: "「\(snsName)を開く」を押すと、デモのSNS画面で利用時間を数えます"
                )
            }
        case .rejected(let reason):
            AntBubbleContainer(antStage: model.antStage) {
                ChatNoticeCard(
                    title: recommendedTask.map { "「\($0.title)」を5分だけやってみよう" } ?? reason,
                    caption: "\(reason)・今日の説得 あと\(store.persuasionsRemainingToday())回"
                )
                retryButton
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
                    title: "今日の説得はもう使えません",
                    caption: "朝\(PolicyConstants.dayBoundaryHour)時に回数が戻ります。やることを片付けてSNS時間をためよう"
                )
            }
        }
    }

    @ViewBuilder private var retryButton: some View {
        if UnlockPolicy.canStartPersuasion(store: store) {
            Button("もう一度説得する") { model.beginNewAttempt(store: store, reminders: reminders) }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.brown)
        }
    }
}

/// 下部の「Xを開く」「やることを片付ける」
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
            Button(action: onOpen) {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        if grantSeconds == nil { Image(systemName: "lock.fill") }
                        Text("\(snsName)を開く")
                    }
                    Text(caption).font(.system(size: 10, weight: .regular))
                }
            }
            .buttonStyle(.primary)
            .disabled(grantSeconds == nil)

            Button("やることを片付ける", action: onTasks)
                .buttonStyle(grantSeconds == nil ? AnyButtonStyle(.primary) : AnyButtonStyle(.secondary))
        }
        .padding(.horizontal, ChatMetrics.horizontalPadding)
        .padding(.top, 8)
    }

    private var caption: String {
        switch phase {
        case .approvable(let s): return TimeFormat.hm(s)
        case .chatting: return "説得中"
        case .rejected, .quotaExhausted: return "納得度が足りません"
        case .failed: return "利用できません"
        }
    }
}

/// 状態でボタンの見た目を切り替えるための型消去
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
