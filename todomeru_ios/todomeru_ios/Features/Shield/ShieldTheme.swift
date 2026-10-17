import SwiftUI

/// 制限画面・利用終了画面（Figma 27:203 / 32:309）の色
extension Theme {
    /// 制限画面全体の黄色
    static let shieldBackground = Color(hex: 0xFFE37E)
    /// 背景のぼかした一覧（背後のアプリを思わせる飾り）
    static let shieldGhostRow = Color(hex: 0xF0D372)
    static let shieldGhostDots: [Color] = [
        Color(hex: 0xC9C08A), Color(hex: 0xF1CF5F), Color(hex: 0xC8C79A), Color(hex: 0xF4B45F),
    ]
}

/// 制限画面まわりの寸法
enum ShieldMetrics {
    static let illustrationSize: CGFloat = 120
    static let titleSize: CGFloat = 22
    static let bodySize: CGFloat = 15
    static let captionSize: CGFloat = 12
    static let horizontalPadding: CGFloat = 32
    static let bodyLineSpacing: CGFloat = 6
}
