import SwiftUI

/// SNSの制限画面（Figma 27:203）。
/// 本番ではOSのShield（ManagedSettings）が出す画面。デモではアプリ内で同じ体験を再現する。
struct ShieldView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    private var sns: SNSApp? { store.sns(snsID) }
    private var status: ShieldTaskStatus { .make(reminders: reminders) }

    var body: some View {
        ShieldScaffold(
            illustration: "shield_ant",
            fallback: "🐜",
            title: ShieldText.shieldTitle,
            message: ShieldText.shieldMessage(snsName: sns?.textName ?? "SNS", status: status),
            caption: captionText,
            onClose: { router.popToRoot() }
        ) {
            if !store.isRestricted(snsID) { openButton }
            Button("やることを先に片付ける") {
                router.push(.taskSelect(origin: .shield(snsID: snsID)))
            }
            .buttonStyle(.secondary)
            PersuadeButton(remaining: store.persuasionsRemainingToday()) {
                router.push(.persuasion(snsID: snsID))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 制限中でないときの「○○を開く（デモ）」。標準機能で選んだアプリは本体から起動できないので案内だけ出す
    @ViewBuilder
    private var openButton: some View {
        if let sns, sns.tokenData == nil {
            Button { router.replaceTop(with: .demoSNS(snsID: snsID)) } label: {
                SNSPhrase(sns: sns, suffix: "を開く（デモ）")
            }
            .buttonStyle(.secondary)
        } else if let sns {
            SNSPhrase(sns: sns, suffix: "はホーム画面から開いてください")
                .font(.system(size: ShieldMetrics.captionSize, weight: .semibold))
                .foregroundStyle(Theme.brownDark)
        }
    }

    /// 補足（使用時間・上限は出さない。デモであることと、制限中でないことだけ）
    private var captionText: String? {
        var parts: [String] = []
        if !store.isRestricted(snsID) { parts.append("今は制限されていません") }
        if reminders.isDemo { parts.append("デモのやること") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }
}

/// 一時利用枠が終わったあとの制限画面（Figma 32:309）。
struct GrantEndedView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    private var status: ShieldTaskStatus { .make(reminders: reminders) }

    var body: some View {
        ShieldScaffold(
            illustration: "ant_wave",
            fallback: "🐜",
            title: ShieldText.grantEndedTitle(grantedSeconds: store.lastEndedGrant(snsID)?.grantedSeconds),
            message: ShieldText.grantEndedMessage(status: status),
            caption: reminders.isDemo ? "デモのやること" : nil,
            onClose: { router.popToRoot() }
        ) {
            Button("やることを始める") {
                router.replaceTop(with: .taskSelect(origin: .shield(snsID: snsID)))
            }
            .buttonStyle(.primary)
            PersuadeButton(remaining: store.persuasionsRemainingToday()) {
                router.replaceTop(with: .persuasion(snsID: snsID))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
