import SwiftUI

/// チャット画面の上部（閉じる・中央のアリ）。Figma 72:2 / 30:2 の見出し部分。
/// 状態帯は廃止（figma-update）。相談中はアリの丸背景を納得度で変え、下に「納得度 70%」を出す。
struct AntChatHeader: View {
    var antStage: Int = 4
    /// アリの下の文字（「アリ」「納得度 70%」）
    var caption: String = "アリ"
    var captionColor: Color = Theme.textPrimary
    /// アリの丸背景（nil なら丸なし）
    var antBackground: Color?
    var onClose: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                ZStack {
                    if let antBackground {
                        Circle().fill(antBackground)
                            .frame(width: ChatMetrics.headerAntCircle, height: ChatMetrics.headerAntCircle)
                    }
                    AntFace(stage: antStage, size: ChatMetrics.headerAntSize)
                }
                .animation(.easeOut(duration: 0.3), value: antBackground)
                Text(caption)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(captionColor)
                    .contentTransition(.numericText())
            }
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("閉じる")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.chatHeader.ignoresSafeArea(edges: .top))
    }
}

/// チャット内の案内カード（時計アイコン＋太字＋補足）。
/// 見出しにSNS名（SNSPhrase）を入れるときは titleView を使う
struct ChatNoticeCard<Title: View>: View {
    var icon: String = "clock"
    var caption: String?
    @ViewBuilder var titleView: () -> Title

    init(icon: String = "clock", caption: String? = nil, @ViewBuilder titleView: @escaping () -> Title) {
        self.icon = icon
        self.caption = caption
        self.titleView = titleView
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.antGold)
                titleView()
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: ChatMetrics.captionFont))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.noticeCard, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension ChatNoticeCard where Title == Text {
    init(icon: String = "clock", title: String, caption: String? = nil) {
        self.init(icon: icon, caption: caption) { Text(title) }
    }
}

/// アリ側の吹き出しの枠（中に任意の内容を入れる。候補リストなど）
struct AntBubbleContainer<Content: View>: View {
    var antStage: Int = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AntFace(stage: antStage, size: ChatBubbleMetrics.avatarSize)
            VStack(alignment: .leading, spacing: 10) { content() }
                .aiBubbleStyle()
            Spacer(minLength: 16)
        }
    }
}

/// 吹き出しの中の本文
struct AntBubbleText: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: ChatMetrics.bodyFont))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// やることの候補一覧（72:2 / 210:39）。選んだ行を黄色で強調し、ほかを薄くする
struct TaskCandidateList: View {
    var tasks: [TaskItem]
    var recommendedID: String?
    var selectedID: String?
    var isEnabled: Bool = true
    var onSelect: (TaskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskCandidateRow(
                    task: task,
                    isRecommended: task.id == recommendedID,
                    isSelected: selectedID == task.id,
                    isDimmed: selectedID != nil && selectedID != task.id
                ) { onSelect(task) }
                .disabled(!isEnabled)
                if task.id != tasks.last?.id { Divider().overlay(Theme.separator) }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator))
    }
}

/// 候補のやること1行（チェック丸・題名・リスト・期限・おすすめ）
struct TaskCandidateRow: View {
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
