import SwiftUI

/// SNSの制限画面（Figma 27:203）。
/// 本番ではOSのShield（ManagedSettings）が出す画面。デモではアプリ内で同じ体験を再現する。
struct ShieldView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    private var snsName: String { store.sns(snsID)?.name ?? "SNS" }
    private var status: ShieldTaskStatus { .make(reminders: reminders) }

    var body: some View {
        ShieldScaffold(
            illustration: "shield_ant",
            fallback: "🐜",
            title: "キリギリス化 注意報！",
            message: ShieldText.shieldMessage(snsName: snsName, status: status),
            caption: captionText,
            onClose: { router.popToRoot() }
        ) {
            if !store.isRestricted(snsID) {
                Button("\(snsName)を開く（デモ）") { router.replaceTop(with: .demoSNS(snsID: snsID)) }
                    .buttonStyle(.secondary)
            }
            Button("やることを先に片付ける") {
                router.push(.taskSelect(origin: .shield(snsID: snsID)))
            }
            .buttonStyle(.primary)
            PersuadeButton(remaining: store.persuasionsRemainingToday()) {
                router.push(.persuasion(snsID: snsID))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var captionText: String {
        var parts = [ShieldText.usageLine(store: store, snsID: snsID)]
        if !store.isRestricted(snsID) { parts.append("今は制限されていません") }
        if reminders.isDemo { parts.append("デモのやること") }
        return parts.joined(separator: "・")
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
            Button("ホームへ") { router.popToRoot() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.brownDark)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
