import SwiftUI

/// やることを選ぶ・相談チャット専用の色と寸法（Figma 72:2 / 30:2 / 32:2 / 210:39）
extension Theme {
    /// 上部（閉じる・アリ）の背景
    static let chatHeader = Color(hex: 0xFFE38C)
    /// ヘッダーのアリの丸背景：納得度が低い（Figma 32:2 の薄い赤）
    static let convictionBackgroundLow = Color(hex: 0xFBD9CF)
    /// 納得度が中くらい
    static let convictionBackgroundMid = Color(hex: 0xFFF1BF)
    /// 納得度がしきい値以上（Figma 30:2 の薄い緑）
    static let convictionBackgroundHigh = Color(hex: 0xE3F2C2)
    /// 納得度が低いときの文字色
    static let convictionLow = Color(hex: 0xE5533D)
    /// 納得度がしきい値以上のときの文字色
    static let convictionHighText = Color(hex: 0x5E8A1E)
    /// 候補の選択・おすすめバッジ
    static let taskSelected = Color(hex: 0xFFE38C)
    static let checkYellow = Color(hex: 0xF5B400)
    /// チャット内の案内カード（「Xを1分 利用できます」）
    static let noticeCard = Color(hex: 0xFFF6D6)
    /// 押せない「Xを開く」ボタンの地と文字
    static let lockedButton = Color(hex: 0xEFE9DC)
    static let lockedButtonText = Color(hex: 0xB8AE9C)

    /// 納得度に応じたアリの丸背景
    static func convictionBackground(score: Int, threshold: Int = PolicyConstants.persuasionApprovalThreshold) -> Color {
        if score >= threshold { return convictionBackgroundHigh }
        if score >= threshold / 2 { return convictionBackgroundMid }
        return convictionBackgroundLow
    }

    /// 納得度の文字色
    static func convictionText(score: Int, threshold: Int = PolicyConstants.persuasionApprovalThreshold) -> Color {
        if score >= threshold { return convictionHighText }
        if score >= threshold / 2 { return textPrimary }
        return convictionLow
    }
}

enum ChatMetrics {
    static let horizontalPadding: CGFloat = 12
    static let messageSpacing: CGFloat = 12
    static let bodyFont: CGFloat = 15
    static let captionFont: CGFloat = 11
    static let rowRadius: CGFloat = 14
    static let headerAntSize: CGFloat = 40
    static let headerAntCircle: CGFloat = 46
}
