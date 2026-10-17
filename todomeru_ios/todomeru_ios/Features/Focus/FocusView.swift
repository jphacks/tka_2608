import SwiftUI

/// やること実行中（Figma 37:2 / ARCHITECTURE.md 2.5 F01）。
/// 経過時間は session.startedAt から毎秒計算する。画面を離れても取り組みは続き、ホームから戻れる。
struct FocusView: View {
    var sessionID: UUID

    @Environment(AppStore.self) private var store
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
                FocusTopBar(isRestricting: session.origin.snsID != nil) {
                    router.popToRoot()
                }
                ScrollView {
                    VStack(spacing: FocusLayout.sectionSpacing) {
                        FocusCharacter(text: progress.cheerText)
                        FocusTaskCard(taskTitle: session.taskTitle, progress: progress)
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

    /// デモ用: 経過時間を5分進める（25分待たずに報酬を見せる）。
    private func advanceDemo() {
        store.shiftFocusStart(sessionID, by: FocusLayout.demoAdvanceSeconds)
    }
}

// MARK: - 部品

enum FocusLayout {
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let characterSize: CGFloat = 220
    static let timerFontSize: CGFloat = 44
    static let rewardFontSize: CGFloat = 30
    static let labelFont: CGFloat = 12
    static let barHeight: CGFloat = 8
    static let markerSize: CGFloat = 14
    static let bubbleCorner: CGFloat = 14
    static let bubbleTail: CGFloat = 12
    /// デモの「時間を進める」で進める秒数
    static let demoAdvanceSeconds = 300
}

/// 上部: 左に「‹ ● やること中」（タップでホームへ）、Shield起点なら右に鍵アイコン（Figma 37:2）
private struct FocusTopBar: View {
    var isRestricting: Bool
    var onHome: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onHome) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.brown)
                    Circle().fill(Theme.danger).frame(width: 8, height: 8)
                    Text("やること中")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.summaryYellow, in: Capsule())
            }
            .accessibilityLabel("ホームへ戻る（やること中）")
            Spacer()
            if isRestricting {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("SNSは制限中")
            }
        }
        .padding(.horizontal, FocusLayout.horizontalPadding)
        .frame(height: 48)
    }
}

/// 応援するアリと、右上のしっぽ付き吹き出し
private struct FocusCharacter: View {
    var text: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharacterImage(name: "ant_cheer", fallback: "🐜", size: FocusLayout.characterSize)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            SpeechBubble(text: text)
        }
        .padding(.top, 4)
    }
}

/// 左下にしっぽのある吹き出し
private struct SpeechBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: FocusLayout.bubbleCorner))
            .overlay(RoundedRectangle(cornerRadius: FocusLayout.bubbleCorner).stroke(Theme.textPrimary, lineWidth: 2))
            .overlay(alignment: .bottomLeading) {
                BubbleTail()
                    .fill(Theme.surface)
                    .overlay(BubbleTail().stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, lineJoin: .round)))
                    .frame(width: FocusLayout.bubbleTail, height: FocusLayout.bubbleTail)
                    .offset(x: 20, y: FocusLayout.bubbleTail - 1)
            }
    }
}

/// 吹き出しのしっぽ（上辺は吹き出しの枠に重ねるので描かない）
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}

/// やること・経過時間・獲得した時間・目安バーのカード
private struct FocusTaskCard: View {
    var taskTitle: String
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
            label("いまやっていること")
            Text(taskTitle)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var timeRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                label("やった時間")
                Text(TimeFormat.clock(progress.elapsedSeconds))
                    .font(.system(size: FocusLayout.timerFontSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                label("獲得した時間")
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
        Text("次の\(FocusProgress.rewardPerUnit / 60)分獲得まで：あと\(FocusProgress.minuteSecond(progress.secondsToNextReward))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.summaryCard, in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: FocusLayout.labelFont))
            .foregroundStyle(Theme.textSecondary)
    }
}

/// +5分／+10分／+15分の目安（25分ごと）。ラベルは各目盛りの真下に置く
private struct FocusMilestoneBar: View {
    var progress: FocusProgress

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.segmentBackground)
                    .frame(height: FocusLayout.barHeight)
                    .offset(y: (FocusLayout.markerSize - FocusLayout.barHeight) / 2)
                Capsule().fill(Theme.orange)
                    .frame(width: width * progress.barFraction, height: FocusLayout.barHeight)
                    .offset(y: (FocusLayout.markerSize - FocusLayout.barHeight) / 2)
                ForEach(progress.milestones) { m in
                    let x = min(width - FocusLayout.markerSize / 2, width * m.fraction)
                    Circle()
                        .fill(m.reached ? Theme.orange : Theme.surface)
                        .overlay(Circle().stroke(m.reached ? Theme.antGold : Theme.disabled, lineWidth: 2))
                        .frame(width: FocusLayout.markerSize, height: FocusLayout.markerSize)
                        .position(x: x, y: FocusLayout.markerSize / 2)
                    Text("+\(m.rewardMinutes)分")
                        .font(.system(size: 11, weight: m.reached ? .bold : .regular))
                        .foregroundStyle(m.reached ? Theme.textPrimary : Theme.textSecondary)
                        .fixedSize()
                        .position(x: min(width - 16, x), y: FocusLayout.markerSize + 12)
                }
            }
        }
        .frame(height: FocusLayout.markerSize + 22)
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
