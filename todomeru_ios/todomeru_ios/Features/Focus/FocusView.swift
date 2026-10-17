import SwiftUI

/// やること実行中（Figma 37:2 / ARCHITECTURE.md 2.5 F01）。
/// 経過時間は session.startedAt から毎秒計算する。画面を離れても取り組みは続き、ホームから戻れる。
struct FocusView: View {
    var sessionID: UUID

    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if let session = store.session(sessionID) {
                content(session)
            } else {
                missing
            }
        }
        .screenBackground()
    }

    // MARK: - 本体

    private func content(_ session: FocusSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = FocusProgress(elapsedSeconds: session.measuredSeconds(now: context.date))
            VStack(spacing: 0) {
                FocusTopBar(origin: session.origin, snsName: session.origin.snsID.flatMap { store.sns($0)?.name }) {
                    router.popToRoot()
                }
                ScrollView {
                    VStack(spacing: FocusLayout.sectionSpacing) {
                        FocusCharacter(stage: progress.grasshopperStage, text: progress.cheerText)
                        FocusTaskCard(session: session, dueText: dueText(session), progress: progress)
                        if session.endedAt == nil {
                            DemoAdvanceButton { advanceDemo() }
                        }
                    }
                    .padding(.horizontal, FocusLayout.horizontalPadding)
                    .padding(.bottom, 16)
                }
                bottomButton(session)
            }
            .onChange(of: progress.units) { _, _ in
                // 画面表示中に25分単位へ達したら台帳に記録する（同じ単位は二重に記録されない）
                if session.endedAt == nil { store.recordFocusRewards(sessionID) }
            }
        }
        .onAppear { store.recordFocusRewards(sessionID) }
    }

    private func bottomButton(_ session: FocusSession) -> some View {
        Button(session.endedAt == nil ? "終わってふりかえる" : "ふりかえりへ") {
            store.endFocus(sessionID)
            router.replaceTop(with: .reflection(sessionID: sessionID))
        }
        .buttonStyle(.primary)
        .padding(.horizontal, FocusLayout.horizontalPadding)
        .padding(.vertical, 12)
    }

    private var missing: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("取り組みが見つかりません")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Button("ホームに戻る") { router.popToRoot() }
                .buttonStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - 補助

    /// 「リマインダー ・ 大学 ・ 10/24まで」の期限部分
    private func dueText(_ session: FocusSession) -> String? {
        guard let task = reminders.task(id: session.taskID), task.dueDate != nil else { return nil }
        return "\(TaskFilter.dueLabel(task))まで"
    }

    /// デモ用: 経過時間を5分進める（25分待たずに報酬を見せる）。
    private func advanceDemo() {
        store.shiftFocusStart(sessionID, by: FocusLayout.demoAdvanceSeconds)
    }
}

// MARK: - 部品

enum FocusLayout {
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let characterSize: CGFloat = 150
    static let timerFontSize: CGFloat = 44
    static let rewardFontSize: CGFloat = 30
    static let barHeight: CGFloat = 8
    static let markerSize: CGFloat = 14
    /// デモの「時間を進める」で進める秒数
    static let demoAdvanceSeconds = 300
}

/// 上部の「やること実行中」バッジと、Shield起点なら対象SNSの制限中表示
private struct FocusTopBar: View {
    var origin: Origin
    var snsName: String?
    var onHome: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onHome) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                    Text("ホーム")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.brown)
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.danger).frame(width: 8, height: 8)
                Text("やること実行中")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.summaryYellow, in: Capsule())
            Spacer()
            if let snsName {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text("\(snsName) 制限中")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, FocusLayout.horizontalPadding)
        .frame(height: 48)
    }
}

/// キリギリスと吹き出し
private struct FocusCharacter: View {
    var stage: Int
    var text: String

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.textPrimary, lineWidth: 2))
                .frame(maxWidth: .infinity, alignment: .trailing)
            GrasshopperFigure(stage: stage, size: FocusLayout.characterSize)
        }
        .padding(.top, 8)
    }
}

/// やること・経過時間・獲得したSNS時間・目安バーのカード
private struct FocusTaskCard: View {
    var session: FocusSession
    var dueText: String?
    var progress: FocusProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            taskInfo
            Divider().overlay(Theme.separator)
            timeRow
            FocusMilestoneBar(progress: progress)
            nextReward
        }
        .padding(18)
        .card()
    }

    private var taskInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("いまやっていること")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(session.taskTitle)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(([session.listName] + (dueText.map { [$0] } ?? [])).joined(separator: " ・ "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var timeRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("やることの時間")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(TimeFormat.clock(progress.elapsedSeconds))
                    .font(.system(size: FocusLayout.timerFontSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("獲得したSNS時間")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("+\(progress.earnedSeconds / 60)")
                        .font(.system(size: FocusLayout.rewardFontSize, weight: .bold))
                    Text("分").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Theme.antGold)
            }
        }
    }

    private var nextReward: some View {
        Text("次の +\(FocusProgress.rewardPerUnit / 60)分 まで あと \(FocusProgress.minuteSecond(progress.secondsToNextReward))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.summaryCard, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 25／50／75分の目安
private struct FocusMilestoneBar: View {
    var progress: FocusProgress

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.segmentBackground)
                        .frame(height: FocusLayout.barHeight)
                    Capsule().fill(Theme.orange)
                        .frame(width: width * progress.barFraction, height: FocusLayout.barHeight)
                    ForEach(progress.milestones) { m in
                        Circle()
                            .fill(m.reached ? Theme.orange : Theme.surface)
                            .overlay(Circle().stroke(m.reached ? Theme.antGold : Theme.disabled, lineWidth: 2))
                            .frame(width: FocusLayout.markerSize, height: FocusLayout.markerSize)
                            .position(x: min(width - FocusLayout.markerSize / 2, width * m.fraction), y: FocusLayout.markerSize / 2)
                    }
                }
                .frame(height: FocusLayout.markerSize)
            }
            .frame(height: FocusLayout.markerSize)
            HStack {
                ForEach(progress.milestones) { m in
                    Text("\(m.minutes)分 +\(m.rewardMinutes)分")
                        .font(.system(size: 11, weight: m.reached ? .bold : .regular))
                        .foregroundStyle(m.reached ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: m.index == FocusProgress.milestoneCount ? .trailing : .center)
                }
            }
        }
    }
}

/// デモ用に経過時間を進めるボタン
private struct DemoAdvanceButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                DemoBadge()
                Text("時間を進める（+\(FocusLayout.demoAdvanceSeconds / 60)分）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brown)
            }
        }
    }
}
