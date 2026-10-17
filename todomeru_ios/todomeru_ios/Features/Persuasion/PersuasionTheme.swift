import SwiftUI

/// やることを選ぶ・説得チャット専用の色と寸法（Figma 72:2 / 30:2 / 32:2）
extension Theme {
    /// 上部（閉じる・アリ）の背景
    static let chatHeader = Color(hex: 0xFFE38C)
    /// 状態帯（「Xを開く前に」「説得中」）の背景
    static let chatStatusBand = Color(hex: 0xFFF1BF)
    /// 納得度ゲージの地
    static let gaugeTrack = Color.white
    /// 納得度が低いとき（Figma 32:2 の赤）
    static let convictionLow = Color(hex: 0xE5533D)
    /// 納得度がしきい値に近い・以上のとき（Figma 30:2 の黄）
    static let convictionHigh = Color(hex: 0xF5B400)
    /// 納得度の数値（しきい値以上）
    static let convictionHighText = Color(hex: 0xB07F00)
    /// 候補の選択・おすすめバッジ
    static let taskSelected = Color(hex: 0xFFE38C)
    static let checkYellow = Color(hex: 0xF5B400)
    /// チャット内の案内カード（「Xを1分利用できます」）
    static let noticeCard = Color(hex: 0xFFF6D6)
}

enum ChatMetrics {
    static let horizontalPadding: CGFloat = 12
    static let messageSpacing: CGFloat = 12
    static let bodyFont: CGFloat = 15
    static let captionFont: CGFloat = 11
    static let rowRadius: CGFloat = 14
    static let gaugeHeight: CGFloat = 8
}
