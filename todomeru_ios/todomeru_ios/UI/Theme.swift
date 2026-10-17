import SwiftUI
import UIKit

/// Figma（JPhack 採用ページ）の配色。淡い黄色・白・ブラウン（UI_UX.md 2.5）
enum Theme {
    static let background = Color(hex: 0xFFF7E3)
    static let surface = Color.white
    static let summaryYellow = Color(hex: 0xFFE38C)
    static let summaryCard = Color(hex: 0xFFF9EA)
    static let brown = Color(hex: 0xA0602A)
    static let brownDark = Color(hex: 0x7A4519)
    static let antGold = Color(hex: 0xB07F00)
    static let orange = Color(hex: 0xF59E0B)
    static let grasshopperGreen = Color(hex: 0x7CC24B)
    static let userBubble = Color(hex: 0xDDF3C8)
    static let textPrimary = Color(hex: 0x2B2118)
    static let textSecondary = Color(hex: 0x7A6A55)
    static let separator = Color(hex: 0xEFE6D2)
    static let segmentBackground = Color(hex: 0xF1E8D3)
    static let disabled = Color(hex: 0xD9D2C3)
    static let danger = Color(hex: 0xD9534F)

    static let cornerRadius: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - ボタン

/// ブラウンの大きなボタン（「やることを始める」など）
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Theme.brown : Theme.disabled, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 白地・ブラウン枠のボタン（「やることを片付ける」など）
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.brown)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.brown, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - カード

struct CardModifier: ViewModifier {
    var color: Color = Theme.surface
    func body(content: Content) -> some View {
        content
            .background(color, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

extension View {
    func card(_ color: Color = Theme.surface) -> some View { modifier(CardModifier(color: color)) }

    /// 画面全体の背景
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// 画面上部の見出し（左に戻る、中央または左に題名、右に任意の操作）
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var backTitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, backTitle: String? = nil, onBack: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.backTitle = backTitle
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            if let backTitle { Text(backTitle) }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.brown)
                    }
                }
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

/// 「デモ」などの注意バッジ（モック・固定文を実データと誤認させない）
struct DemoBadge: View {
    var text: String = "デモ"
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.brownDark)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.summaryYellow, in: Capsule())
    }
}
