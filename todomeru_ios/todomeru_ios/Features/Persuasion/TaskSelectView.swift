import SwiftUI

/// やることを選ぶ（Figma 72:2 選択前 / 72:286 選択後）
struct TaskSelectView: View {
    var origin: Origin

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router
    @State private var model: TaskSelectViewModel
    @State private var persuadeError: String?

    init(origin: Origin) {
        self.origin = origin
        _model = State(initialValue: TaskSelectViewModel(origin: origin))
    }

    private var snsName: String { origin.snsID.flatMap { store.sns($0)?.textName } ?? "アプリ" }
    private var content: TaskSelectViewModel.Content { model.content(reminders: reminders) }

    var body: some View {
        VStack(spacing: 0) {
            AntChatHeader(onClose: { router.close(origin: origin) })
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: ChatMetrics.messageSpacing) {
                        Text("今日 \(Date.now.formatted(.dateTime.hour().minute()))")
                            .font(.system(size: ChatMetrics.captionFont))
                            .foregroundStyle(Theme.textSecondary)
                        conversation
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, ChatMetrics.horizontalPadding)
                    .padding(.vertical, 16)
                }
                .onChange(of: model.selected) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            bottomArea
        }
        .screenBackground()
    }

    // MARK: - 会話

    @ViewBuilder private var conversation: some View {
        switch content {
        case .loading:
            AntBubbleContainer {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("やることを読み込み中…").font(.system(size: ChatMetrics.bodyFont))
                }
            }
        case .denied:
            statusBubble(
                "リマインダーへのアクセスが許可されていないため、やることを読み込めませんでした。設定アプリでアクセスを許可してね。",
                retry: true
            )
        case .failed(let msg):
            statusBubble("やることの読み込みに失敗しました（\(msg)）。", retry: true)
        case .empty:
            statusBubble(
                origin.snsID == nil
                    ? "未完了のやることがないよ。リマインダーにやることを追加してね。"
                    : "未完了のやることがないよ。どうしても今\(snsName)を使いたいなら、理由を教えて。",
                retry: false
            )
        case .candidates(let rec, let others):
            candidateBubble(recommended: rec, others: others)
            if let task = model.selected {
                ChatBubble(message: ChatMessage(role: .user, text: model.userLine(for: task)))
                ChatBubble(message: ChatMessage(role: .ai, text: TaskSelectViewModel.rewardLine))
            } else if origin.snsID != nil {
                ChatBubble(message: ChatMessage(role: .ai, text: "それとも、どうしても今\(snsName)を見たい理由がある？"))
            }
            if let err = model.startError {
                ChatBubble(message: ChatMessage(role: .ai, text: err), antStage: 1)
            }
        }
    }

    private func statusBubble(_ text: String, retry: Bool) -> some View {
        AntBubbleContainer(antStage: 1) {
            AntBubbleText(text: text)
            if retry {
                Button("もう一度読み込む") { Task { await reload() } }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.brown)
            }
        }
    }

    private func candidateBubble(recommended: TaskItem, others: [TaskItem]) -> some View {
        AntBubbleContainer {
            AntBubbleText(text: openingLine)
            TaskCandidateList(
                tasks: [recommended] + others,
                recommendedID: recommended.id,
                selectedID: model.selected?.id,
                isEnabled: !model.isStarting
            ) { model.select($0) }
        }
    }

    /// 冒頭のアリの問いかけ（起点に合わせる）
    private var openingLine: String {
        origin.snsID == nil ? "どれかひとつやってみない？" : "\(snsName)を開く前に、どれかひとつやっていかない？"
    }

    // MARK: - 下部

    @ViewBuilder private var bottomArea: some View {
        VStack(spacing: 8) {
            if model.selected != nil {
                Button {
                    Task { await model.start(store: store, reminders: reminders, router: router) }
                } label: {
                    if model.isStarting { ProgressView().tint(.white) } else { Text("やることを始める") }
                }
                .buttonStyle(.primary)
                .disabled(model.isStarting)
                .padding(.horizontal, 12)
            }
            if let persuadeError {
                Text(persuadeError)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
            }
            if origin.snsID != nil {
                if content == .empty || content == .denied {
                    Button("アリに相談する") { persuade(nil) }
                        .buttonStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                ChatInputBar(text: $model.reasonText, placeholder: model.selected == nil ? "理由を入力して相談する…" : "メッセージを入力…", isEnabled: !model.isStarting) {
                    persuade(model.reasonText)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, origin.snsID == nil ? 12 : 0)
    }

    private func persuade(_ text: String?) {
        persuadeError = model.goPersuade(with: text, store: store, router: router)
    }

    private func reload() async {
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs)
    }
}
