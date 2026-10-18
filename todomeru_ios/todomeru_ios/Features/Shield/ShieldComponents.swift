import SwiftUI

// MARK: - 画面のロジック（純粋関数）

/// 制限画面・利用終了画面で使う「やること」の状況。取得失敗・権限なしを0件と混同しない。
enum ShieldTaskStatus: Equatable {
    case loading
    case denied
    case failed
    /// 今日の未完了の件数と、おすすめ1件（今日のものがなければ、すべてから1件）
    case loaded(openToday: Int, recommended: TaskItem?)

    static func make(reminders: ReminderService) -> ShieldTaskStatus {
        switch reminders.state {
        case .idle, .loading: return .loading
        case .denied: return .denied
        case .failed: return .failed
        case .loaded:
            let today = TaskFilter.today(reminders.tasks).open
            return .loaded(openToday: today.count, recommended: today.first ?? TaskFilter.all(reminders.tasks).first)
        }
    }

    var recommended: TaskItem? {
        if case .loaded(_, let t) = self { return t }
        return nil
    }
}

enum ShieldText {
    static let shieldTitle = "やることやろう！"

    /// 制限画面の本文（例:「やることがあと2件残っています。」）
    static func shieldMessage(snsName: String, status: ShieldTaskStatus) -> String {
        switch status {
        case .loading: return "やることを確認しています…"
        case .denied: return "リマインダーの許可がないため、\n残っているやることを確認できません。"
        case .failed: return "やることを読み込めませんでした。"
        case .loaded(let n, _):
            return n > 0 ? "やることがあと\(n)件残っています。" : "一緒に頑張ろう！"
        }
    }

    /// 許可された量の表示（固定の1分にしない）。60秒未満は秒、それ以上は分。
    static func grantedAmount(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)秒" : TimeFormat.hm(seconds)
    }

    static func grantEndedTitle(grantedSeconds: Int?) -> String {
        guard let s = grantedSeconds else { return "約束の時間が終わったよ！" }
        return "\(grantedAmount(s))たったよ！"
    }

    /// 利用終了後の本文（32:309）。「次はこのやることを進めよう」とやること名の2行
    static func grantEndedMessage(status: ShieldTaskStatus) -> String {
        if let t = status.recommended {
            return "次はこのやることを進めよう\n【\(t.listName)】\(t.title)"
        }
        switch status {
        case .loading: return "やることを確認しています…"
        case .denied: return "リマインダーの許可がないため、\nやることを確認できません。"
        case .failed: return "やることを読み込めませんでした。"
        case .loaded: return "一緒に頑張ろう！"
        }
    }

    static let consultLabel = "アリに相談する"

    static let consultationUsedUp = "今日の相談は使い切りました"
}

// MARK: - 共通レイアウト

/// 制限画面・利用終了画面の共通レイアウト（黄色の背景、ぼかした一覧、中央のアリ、下部のボタン）
struct ShieldScaffold<Buttons: View>: View {
    var illustration: String
    var fallback: String
    var title: String
    var message: String
    var caption: String?
    var onClose: () -> Void
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        ZStack {
            Theme.shieldBackground.ignoresSafeArea()
            ShieldGhostList().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                center
                Spacer()
                VStack(spacing: 12) { buttons() }
                    .padding(.horizontal, ShieldMetrics.horizontalPadding)
                    .padding(.bottom, 16)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.brownDark)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("閉じる")
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var center: some View {
        VStack(spacing: 14) {
            CharacterImage(name: illustration, fallback: fallback, size: ShieldMetrics.illustrationSize)
            Text(title)
                .font(.system(size: ShieldMetrics.titleSize, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: ShieldMetrics.bodySize))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(ShieldMetrics.bodyLineSpacing)
            if let caption {
                Text(caption)
                    .font(.system(size: ShieldMetrics.captionSize, weight: .semibold))
                    .foregroundStyle(Theme.brownDark)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.surface.opacity(0.6), in: Capsule())
            }
        }
        .padding(.horizontal, ShieldMetrics.horizontalPadding)
    }
}

/// 「アリに相談する」のリンク（回数は出さない。残り0回なら押せない状態と短い理由だけ）
struct PersuadeButton: View {
    var canConsult: Bool
    var action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                Text(ShieldText.consultLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canConsult ? Theme.textPrimary : Theme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .disabled(!canConsult)
            if !canConsult {
                Text(ShieldText.consultationUsedUp)
                    .font(.system(size: ShieldMetrics.captionSize))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// 背後のアプリを思わせる、ぼかした一覧（飾り）
struct ShieldGhostList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            ForEach(0..<9, id: \.self) { i in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Theme.shieldGhostDots[i % Theme.shieldGhostDots.count])
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 10) {
                        Capsule().fill(Theme.shieldGhostRow).frame(width: 120, height: 12)
                        Capsule().fill(Theme.shieldGhostRow).frame(height: 8)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .blur(radius: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
