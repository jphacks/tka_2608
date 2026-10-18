import SwiftUI

/// ふりかえり（Figma 90:2 完了 / 37:125 未完了 / 182:81 SNS選択前 / 182:337 選択後）。
/// 完了は本人の回答とリマインダー更新の成功で決める（U02）。追加先はD032に従う。
struct ReflectionView: View {
    var sessionID: UUID

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router
    @State private var model: ReflectionViewModel?

    var body: some View {
        Group {
            if let model, let session = model.session {
                ReflectionContent(model: model, session: session, router: router)
            } else if model != nil {
                VStack(spacing: 16) {
                    Text("取り組みが見つかりません").font(.system(size: 17, weight: .bold))
                    Button("ホームに戻る") { router.popToRoot() }.buttonStyle(.secondary).padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .screenBackground()
        .onAppear {
            if model == nil {
                let m = ReflectionViewModel(sessionID: sessionID, store: store, reminders: reminders)
                model = m
                m.onAppear()
            }
        }
    }
}

private struct ReflectionContent: View {
    var model: ReflectionViewModel
    var session: FocusSession
    var router: Router

    private let bottomID = "reflection-bottom"

    var body: some View {
        VStack(spacing: 0) {
            ReflectionHeader { router.close(origin: session.origin) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: ReflectionLayout.messageSpacing) {
                        conversation
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, ReflectionLayout.horizontalPadding)
                    .padding(.vertical, 12)
                }
                .onChange(of: model.stage) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.applyError) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.completionError) { _, _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy) }
            }
            footer
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
    }

    // MARK: - 会話

    @ViewBuilder
    private var conversation: some View {
        AntBubble("おつかれさま！\(TimeFormat.hm(model.measuredSeconds))がんばったね。どこまでできた？") {
            OutcomeChoiceButtons(selected: model.outcome, isBusy: model.isCompleting,
                                 onComplete: { Task { await model.markCompleted() } },
                                 onContinue: { Task { await model.markIncomplete() } })
        }
        if let error = model.completionError {
            AntBubble(error, stage: 1)
        }
        if let outcome = model.outcome {
            UserBubble(text: outcome == .completed ? "最後まで終わった！" : "まだ終わってない")
            AntBubble(ReflectionCopy.result(outcome: outcome, totalSeconds: model.totalSeconds,
                                            originSNS: originTarget)) {
                RewardBreakdownCard(taskTitle: session.taskTitle, outcome: outcome,
                                    measuredSeconds: model.measuredSeconds,
                                    focusSeconds: model.earned.focus,
                                    completionSeconds: model.earned.completion,
                                    totalLabel: "使える時間", totalSNS: model.targetSNS, totalSuffix: nil)
                if let sns = originTarget {
                    DemoBadge(text: ReflectionCopy.demoBadge(for: sns))
                }
            }
            destination
        }
    }

    /// Shield起点で、開こうとしていたSNSへ追加済みならそのSNS
    private var originTarget: SNSApp? {
        guard session.origin.snsID != nil else { return nil }
        return model.targetSNS
    }

    /// 追加先（Shield起点は自動で結果文に含める。ホーム起点はここで選ぶ）
    @ViewBuilder
    private var destination: some View {
        if model.totalSeconds > 0 {
            if session.origin.snsID == nil {
                AntBubble("どのSNSに使う？") {
                    SNSChoiceList(candidates: model.candidates,
                                  selectedID: session.rewardTargetSNSID,
                                  addMinutesText: "+\(TimeFormat.hm(model.totalSeconds))",
                                  isEnabled: model.stage == .choosingSNS,
                                  usage: model.usageText,
                                  onSelect: model.choose)
                }
                if let sns = model.targetSNS {
                    UserBubble(text: ReflectionCopy.userChoice)
                    AntBubble("OK！\(sns.textName)に\(TimeFormat.hm(model.totalSeconds))追加しておいたよ。好きなときに使ってね。") {
                        if sns.tokenData != nil { OpenFromHomeScreenNote(sns: sns) }
                        DemoBadge(text: ReflectionCopy.demoBadge(for: sns))
                    }
                }
            }
            if let error = model.applyError {
                AntBubble(error, stage: 1) {
                    if session.origin.snsID != nil {
                        Button("もう一度追加する") { model.retryApplyToOrigin() }
                            .buttonStyle(.secondary)
                    } else {
                        Text("もう一度SNSを選んでね").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - 下部

    private var footer: some View {
        VStack(spacing: 10) {
            if model.showsNextActions {
                HStack(spacing: 10) {
                    Button("ホームに戻る") { router.popToRoot() }
                        .buttonStyle(.primary)
                    Button("別のやることを選ぶ") { router.replaceTop(with: .taskSelect(origin: session.origin)) }
                        .buttonStyle(.secondary)
                }
                if let sns = model.openableSNS {
                    if sns.tokenData != nil {
                        // 標準機能で選んだアプリは本体から開けない（制限は本物のShieldが外す）
                        OpenFromHomeScreenNote(sns: sns)
                    } else {
                        Button { router.replaceTop(with: .demoSNS(snsID: sns.id)) } label: {
                            SNSPhrase(sns: sns, suffix: "を開く（デモ）")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.brown)
                    }
                }
            }
            ChatInputBar(text: .constant(""), placeholder: inputPlaceholder, isEnabled: false) {}
                .padding(.horizontal, -ReflectionLayout.horizontalPadding)
        }
        .padding(.horizontal, ReflectionLayout.horizontalPadding)
        .padding(.top, 10)
        .background(Theme.background)
    }

    private var inputPlaceholder: String {
        switch model.stage {
        case .askingProgress: return "ボタンで答えてね"
        case .choosingSNS: return "SNSを選んでね"
        case .applyingToOrigin, .finished: return "メッセージを入力…"
        }
    }
}

/// 標準機能で選んだアプリは本体から開けないので、ホーム画面から開くよう案内する
private struct OpenFromHomeScreenNote: View {
    var sns: SNSApp

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "house")
            SNSPhrase(prefix: "ホーム画面から", sns: sns, suffix: "を開いてね")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.brown)
    }
}

/// ふりかえりの結果文（Figma 90:2 / 37:125 / 182:81）。追加に成功したときだけ「追加しておいたよ」と言う
enum ReflectionCopy {
    /// 「どのSNSに使う？」で選んだときのユーザーの発言（Figma 182:337）
    static let userChoice = "このアプリの時間を増やすね！"

    /// 反映先の説明。標準機能で選んだアプリは本物の制限に反映されるが、使用時間はデモの値
    static func demoBadge(for sns: SNSApp) -> String {
        sns.tokenData == nil ? "デモ: アプリ内の疑似制限に反映" : "デモの使用時間に反映（制限は本物）"
    }

    static func result(outcome: FocusSession.Outcome, totalSeconds: Int, originSNS: SNSApp?) -> String {
        let total = TimeFormat.hm(totalSeconds)
        let head = outcome == .completed
            ? "リマインダーにチェックをつけておいたよ。"
            : "OK、リマインダーはそのままにしておくね。"
        if totalSeconds == 0 {
            let interval = PolicyConstants.focusRewardIntervalSeconds / 60
            let reward = PolicyConstants.focusRewardSeconds / 60
            return head + "今回はSNS時間の追加はないよ。\(interval)分ごとに+\(reward)分増えるよ。"
        }
        let completed = outcome == .completed
        switch (completed, originSNS) {
        case (true, let sns?):
            return head + "\(sns.textName)に\(total)追加しておいたよ。好きなときに使ってね。"
        case (true, nil):
            return head + "使える時間が\(total)増えたよ！"
        case (false, let sns?):
            return head + "やることを進めた分、\(sns.textName)に\(total)追加しておいたよ。"
        case (false, nil):
            return head + "やることを進めた分、\(total) SNS時間が増えたよ。"
        }
    }
}
