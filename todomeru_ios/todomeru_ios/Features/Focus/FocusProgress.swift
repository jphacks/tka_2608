import Foundation

/// やること実行中の表示に使う計算（純粋な値。正本は FocusSession.startedAt からの経過秒）
struct FocusProgress: Equatable {
    /// 経過秒（startedAt から計算。画面のTimerを正本にしない）
    let elapsedSeconds: Int

    static let interval = PolicyConstants.focusRewardIntervalSeconds
    static let rewardPerUnit = PolicyConstants.focusRewardSeconds
    /// 目安として表示する単位数（25／50／75分）
    static let milestoneCount = 3

    /// 達成した25分単位の数
    var units: Int { max(0, elapsedSeconds) / Self.interval }

    /// 獲得したSNS時間（⌊経過÷25分⌋×5分）
    var earnedSeconds: Int { units * Self.rewardPerUnit }

    /// 次の+5分までの残り秒
    var secondsToNextReward: Int { Self.interval - max(0, elapsedSeconds) % Self.interval }

    /// 目安バー（0〜75分）の進み具合 0...1
    var barFraction: Double {
        let total = Double(Self.interval * Self.milestoneCount)
        return min(1, Double(max(0, elapsedSeconds)) / total)
    }

    struct Milestone: Identifiable {
        let index: Int
        let minutes: Int
        let rewardMinutes: Int
        let reached: Bool
        var id: Int { index }
        var fraction: Double { Double(index) / Double(FocusProgress.milestoneCount) }
    }

    var milestones: [Milestone] {
        (1...Self.milestoneCount).map { n in
            Milestone(index: n,
                      minutes: n * Self.interval / 60,
                      rewardMinutes: n * Self.rewardPerUnit / 60,
                      reached: units >= n)
        }
    }

    /// キリギリスの段階（UI_UX.md 2.5）
    var grasshopperStage: Int { GrasshopperFigure.stage(forFocusSeconds: elapsedSeconds) }

    /// キャラクターの吹き出し
    var cheerText: String {
        switch units {
        case 0 where elapsedSeconds < 60: return "さあ、始めよう！"
        case 0: return "まずは\(Self.interval / 60)分を目指そう！"
        default: return "\(units * Self.interval / 60)分クリア！その調子！"
        }
    }

    /// 「17分50秒」
    static func minuteSecond(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60)分\(String(format: "%02d", s % 60))秒"
    }
}
