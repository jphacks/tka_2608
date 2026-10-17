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

    private var snsName: String { origin.snsID.flatMap { store.sns($0)?.name } ?? "SNS" }
    private var content: TaskSelectViewModel.Content { model.content(reminders: reminders) }

    var body: some View {
        VStack(spacing: 0) {
            AntChatHeader(onClose: { router.close(origin: origin) }) { band }
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

    // MARK: - 状態帯

    @ViewBuilder private var band: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusBandTitle(
                title: origin.snsID == nil ? "やることを選ぶ" : "\(snsName)を開く前に",
                trailing: model.selected == nil ? (origin.snsID == nil ? "やることを選ぶ" : "やることを選ぶ or 説得") : "やることを選んだよ"
            )
            if case .candidates(let rec, _) = content {
                StatusBandCaption(text: "おすすめ：\(rec.title)")
            }
        }
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
                "リマインダーへのアクセスが許可されていないため、やることを読み込めませんでした。設定アプリでアクセスを許可するか、設定でデモのやることに切り替えてね。",
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
            Text(text)
                .font(.system(size: ChatMetrics.bodyFont))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Button("もう一度読み込む") { Task { await reload() } }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.brown)
            }
            if reminders.isDemo { DemoBadge(text: "デモのやること") }
        }
    }

    private func candidateBubble(recommended: TaskItem, others: [TaskItem]) -> some View {
        AntBubbleContainer {
            Text(origin.snsID == nil ? "どのやることから始める？" : "\(snsName)を開く前に、\nどれかひとつやっていかない？")
                .font(.system(size: ChatMetrics.bodyFont))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 0) {
                ForEach([recommended] + others) { task in
                    TaskCandidateRow(
                        task: task,
                        isRecommended: task.id == recommended.id,
                        isSelected: model.selected?.id == task.id,
                        isDimmed: model.selected != nil && model.selected?.id != task.id
                    ) { model.select(task) }
                    if task.id != (others.last ?? recommended).id { Divider().overlay(Theme.separator) }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator))
            if reminders.isDemo { DemoBadge(text: "デモのやること") }
        }
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
                    Button("AIを説得する") { persuade(nil) }
                        .buttonStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                ChatInputBar(text: $model.reasonText, placeholder: "理由を入力して説得する…", isEnabled: !model.isStarting) {
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
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs, useDemo: store.settings.useDemoTasks)
    }
}

/// 候補のやること1行（チェック丸・題名・リスト・期限・おすすめ）
private struct TaskCandidateRow: View {
    var task: TaskItem
    var isRecommended: Bool
    var isSelected: Bool
    var isDimmed: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.checkYellow : Theme.disabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(task.listName) ・ \(TaskFilter.dueLabel(task))")
                        .font(.system(size: ChatMetrics.captionFont))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                if isRecommended {
                    Text("おすすめ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(isSelected ? Theme.surface : Theme.taskSelected, in: Capsule())
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.taskSelected : Color.clear)
            .opacity(isDimmed ? 0.4 : 1)
        }
        .buttonStyle(.plain)
    }
}
