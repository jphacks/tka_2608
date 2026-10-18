import SwiftUI

/// アプリの制限画面（Figma 27:203）。
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
            message: ShieldText.shieldMessage(snsName: sns?.textName ?? "アプリ", status: status),
            caption: captionText,
            onClose: { router.popToRoot() }
        ) {
            if !store.isRestricted(snsID) { openNote }
            Button("やることを先に片付ける") {
                router.push(.taskSelect(origin: .shield(snsID: snsID)))
            }
            .buttonStyle(.secondary)
            PersuadeButton(canConsult: UnlockPolicy.canStartPersuasion(store: store)) {
                router.push(.persuasion(snsID: snsID))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 制限中でないときは、ホーム画面から対象アプリを開くよう案内する。
    @ViewBuilder
    private var openNote: some View {
        if let sns {
            SNSPhrase(sns: sns, suffix: "はホーム画面から開いてください")
                .font(.system(size: ShieldMetrics.captionSize, weight: .semibold))
                .foregroundStyle(Theme.brownDark)
        }
    }

    /// 補足（使用時間・上限は出さない。制限中でないことだけ）
    private var captionText: String? {
        var parts: [String] = []
        if !store.isRestricted(snsID) { parts.append("今は制限されていません") }
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
            caption: nil,
            onClose: { router.popToRoot() }
        ) {
            Button("やることを始める") {
                router.replaceTop(with: .taskSelect(origin: .shield(snsID: snsID)))
            }
            .buttonStyle(.primary)
            PersuadeButton(canConsult: UnlockPolicy.canStartPersuasion(store: store)) {
                router.replaceTop(with: .persuasion(snsID: snsID))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
