import SwiftUI
import UIKit

/// チャット共通の色（Figma 72:286 / 30:2 の吹き出し・入力欄）
extension Theme {
    /// ユーザーの吹き出し（やや濃い緑）と枠
    static let chatUserBubble = Color(hex: 0xCFEA9A)
    static let chatUserBubbleBorder = Color(hex: 0xB5D67A)
    /// アリの吹き出しの枠
    static let chatAIBubbleBorder = Color(hex: 0xEFE3C4)
    /// ユーザーアイコン（キリギリスの顔）の丸背景
    static let chatUserAvatarBackground = Color(hex: 0xE6F4CC)
    /// 入力欄の地
    static let chatInputField = Color(hex: 0xF5EEDD)
    /// 送信ボタン（黄色い丸）
    static let chatSendButton = Color(hex: 0xF5B400)
}

/// チャット共通の寸法
enum ChatBubbleMetrics {
    static let avatarSize: CGFloat = 32
    static let bubbleRadius: CGFloat = 16
    static let bubblePadding: CGFloat = 12
    static let bodyFont: CGFloat = 15
    static let sideSpacer: CGFloat = 40
    static let sendButtonSize: CGFloat = 38
}

/// 吹き出しの見た目（色・枠・角丸）
private struct BubbleBackground: ViewModifier {
    var fill: Color
    var border: Color

    func body(content: Content) -> some View {
        content
            .padding(ChatBubbleMetrics.bubblePadding)
            .background(fill, in: RoundedRectangle(cornerRadius: ChatBubbleMetrics.bubbleRadius))
            .overlay(RoundedRectangle(cornerRadius: ChatBubbleMetrics.bubbleRadius).stroke(border))
    }
}

extension View {
    /// アリ側（白）の吹き出し
    func aiBubbleStyle() -> some View { modifier(BubbleBackground(fill: Theme.surface, border: Theme.chatAIBubbleBorder)) }
    /// ユーザー側（緑）の吹き出し
    func userBubbleStyle() -> some View { modifier(BubbleBackground(fill: Theme.chatUserBubble, border: Theme.chatUserBubbleBorder)) }
}

/// ユーザーのアイコン（キリギリスの顔を丸く切り抜く。新しい画像アセットは使わない）
struct UserAvatar: View {
    var size: CGFloat = ChatBubbleMetrics.avatarSize

    /// 元画像のうち顔の中心（幅・高さに対する割合）と、顔を丸に収める拡大率
    private static let faceCenter = CGPoint(x: 0.48, y: 0.38)
    private static let zoom: CGFloat = 2.3

    var body: some View {
        ZStack {
            Circle().fill(Theme.chatUserAvatarBackground)
            if UIImage(named: "grasshopper_0") != nil {
                let side = size * Self.zoom
                Image("grasshopper_0")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .offset(x: (0.5 - Self.faceCenter.x) * side, y: (0.5 - Self.faceCenter.y) * side)
            } else {
                Text("🦗").font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// チャットの吹き出し。AIはアリ（左・白）、ユーザーはキリギリス（右・緑）（UI_UX.md 2.5）
struct ChatBubble: View {
    var message: ChatMessage
    var antStage: Int = 4

    var body: some View {
        switch message.role {
        case .ai:
            HStack(alignment: .bottom, spacing: 8) {
                AntFace(stage: antStage, size: ChatBubbleMetrics.avatarSize)
                Text(message.text)
                    .font(.system(size: ChatBubbleMetrics.bodyFont))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .aiBubbleStyle()
                Spacer(minLength: ChatBubbleMetrics.sideSpacer)
            }
        case .user:
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: ChatBubbleMetrics.sideSpacer)
                Text(message.text)
                    .font(.system(size: ChatBubbleMetrics.bodyFont))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .userBubbleStyle()
                UserAvatar()
            }
        case .system:
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// AI生成中の表示
struct TypingIndicator: View {
    @State private var phase = 0
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AntFace(stage: 2, size: ChatBubbleMetrics.avatarSize)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.textSecondary.opacity(phase == i ? 1 : 0.3)).frame(width: 7, height: 7)
                }
            }
            .padding(2)
            .aiBubbleStyle()
            Spacer()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                phase = (phase + 1) % 3
            }
        }
    }
}

/// 下部の文字入力欄（音声入力は対象外, D012。送信ボタンの見た目だけFigmaの黄色い丸に寄せる）
struct ChatInputBar: View {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool = true
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: ChatBubbleMetrics.bodyFont))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.chatInputField, in: RoundedRectangle(cornerRadius: 20))
                .disabled(!isEnabled)
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: ChatBubbleMetrics.sendButtonSize, height: ChatBubbleMetrics.sendButtonSize)
                    .background(canSend ? Theme.chatSendButton : Theme.disabled, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("送信")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
    }

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
