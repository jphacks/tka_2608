import SwiftUI

/// チャットの吹き出し。AIはアリ（左・白）、ユーザーはキリギリス（右・緑）（UI_UX.md 2.5）
struct ChatBubble: View {
    var message: ChatMessage
    var antStage: Int = 4

    var body: some View {
        switch message.role {
        case .ai:
            HStack(alignment: .top, spacing: 8) {
                AntFace(stage: antStage, size: 36)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 40)
            }
        case .user:
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 14))
                GrasshopperFigure(stage: 1, size: 36)
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
        HStack(alignment: .top, spacing: 8) {
            AntFace(stage: 2, size: 36)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.textSecondary.opacity(phase == i ? 1 : 0.3)).frame(width: 7, height: 7)
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
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

/// 下部の文字入力欄（音声入力は対象外, D012）
struct ChatInputBar: View {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool = true
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.separator))
                .disabled(!isEnabled)
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.brown : Theme.disabled)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.background)
    }

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
