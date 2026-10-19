import SwiftUI

enum ReflectionLayout {
    static let horizontalPadding: CGFloat = 16
    static let messageSpacing: CGFloat = 14
    static let antSize: CGFloat = 36
    static let bubbleCorner: CGFloat = 16
    static let innerCorner: CGFloat = 12
    static let bodyFont: CGFloat = 15
    static let smallFont: CGFloat = 12
}

/// アリの吹き出し（文と、その下に任意の内容）。Figmaでは内訳や候補が吹き出しの中に入る
struct AntBubble<Extra: View>: View {
    var text: String
    var stage: Int = 4
    @ViewBuilder var extra: () -> Extra

    init(_ text: String, stage: Int = 4, @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.text = text
        self.stage = stage
        self.extra = extra
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AntFace(stage: stage, size: ReflectionLayout.antSize)
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(.system(size: ReflectionLayout.bodyFont))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: ReflectionLayout.bubbleCorner))
            .overlay(RoundedRectangle(cornerRadius: ReflectionLayout.bubbleCorner).stroke(Theme.separator))
        }
    }
}

/// ユーザー（キリギリス）の発言
struct UserBubble: View {
    var text: String
    var body: some View {
        ChatBubble(message: ChatMessage(role: .user, text: text))
    }
}

/// 「完了にする」「まだ続ける」。決まったあとは選んだ方を強調して押せなくする
struct OutcomeChoiceButtons: View {
    var selected: FocusSession.Outcome?
    var isBusy: Bool
    var onComplete: () -> Void
    var onContinue: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            choice("終わった", outcome: .completed, action: onComplete)
            choice("まだ途中", outcome: .incomplete, action: onContinue)
        }
        .disabled(selected != nil || isBusy)
    }

    private func choice(_ title: String, outcome: FocusSession.Outcome, action: @escaping () -> Void) -> some View {
        let isOn = selected == outcome || (selected == nil && outcome == .completed)
        return Button(action: action) {
            HStack(spacing: 6) {
                if isBusy && outcome == .completed { ProgressView().tint(.white) }
                Text(title)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isOn ? Theme.brown : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Theme.brown : Theme.summaryYellow, lineWidth: 1.5))
            .opacity(selected != nil && selected != outcome ? 0.5 : 1)
        }
    }
}

/// 今回の内訳（やること○分 +○分 / 完了ボーナス +1分 / 合計）
struct RewardBreakdownCard: View {
    var taskTitle: String
    var outcome: FocusSession.Outcome
    var measuredSeconds: Int
    var focusSeconds: Int
    var completionSeconds: Int
    /// 合計行の後ろに付ける状態（例: 「追加済み」）
    var totalSuffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            taskRow
            Divider().overlay(Theme.separator)
            row("やること \(TimeFormat.hm(measuredSeconds))", "+\(TimeFormat.hm(focusSeconds))")
            if outcome == .completed {
                row("完了ボーナス", "+\(TimeFormat.hm(completionSeconds))")
            }
            HStack {
                Text("合計")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("+\(TimeFormat.hm(focusSeconds + completionSeconds))" + (totalSuffix.map { " \($0)" } ?? ""))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.antGold)
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(12)
        .background(Theme.summaryCard, in: RoundedRectangle(cornerRadius: ReflectionLayout.innerCorner))
    }

    private var taskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: outcome == .completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(taskTitle)
                    .font(.system(size: 14))
                    .strikethrough(outcome == .completed)
                    .foregroundStyle(outcome == .completed ? Theme.textSecondary : Theme.textPrimary)
                Text(outcome == .completed ? "リマインダーで完了済み" : "リマインダーは未完了のまま")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.antGold)
        }
    }
}

/// 「どのアプリに使う？」の候補一覧（182:81 / 182:337）
struct SNSChoiceList: View {
    var candidates: [SNSApp]
    var selectedID: String?
    var addMinutesText: String
    var isEnabled: Bool
    var usage: (SNSApp) -> (text: String, isOver: Bool)
    var onSelect: (SNSApp) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, sns in
                if index > 0 { Divider().overlay(Theme.separator) }
                Button { onSelect(sns) } label: { row(sns) }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
            }
        }
        .background(Theme.summaryCard, in: RoundedRectangle(cornerRadius: ReflectionLayout.innerCorner))
        .overlay(RoundedRectangle(cornerRadius: ReflectionLayout.innerCorner).stroke(Theme.separator))
        .clipShape(RoundedRectangle(cornerRadius: ReflectionLayout.innerCorner))
    }

    private func row(_ sns: SNSApp) -> some View {
        let u = usage(sns)
        let isSelected = selectedID == sns.id
        let dimmed = selectedID != nil && !isSelected
        return HStack(spacing: 12) {
            SNSIcon(sns: sns, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                SNSNameLabel(sns: sns)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(u.text)
                    .font(.system(size: 11))
                    .foregroundStyle(u.isOver ? Theme.danger : Theme.textSecondary)
            }
            Spacer()
            Text(addMinutesText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.antGold)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Theme.summaryYellow : Color.clear)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

/// 上部の見出し（閉じる・アリ）。状態帯は置かない（Figma 90:2）
struct ReflectionHeader: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AntFace(stage: 4, size: 34)
                Text("アリ").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
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
        }
        .padding(.horizontal, ReflectionLayout.horizontalPadding)
        .padding(.vertical, 6)
        .background(Theme.summaryYellow.ignoresSafeArea(edges: .top))
    }
}
