import SwiftUI

/// チャット画面の上部（閉じる・アリ）と状態帯。Figma 72:2 / 30:2 の見出し部分
struct AntChatHeader<Band: View>: View {
    var antStage: Int = 4
    var antCaption: String = "アリ"
    var onClose: () -> Void
    @ViewBuilder var band: () -> Band

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    AntFace(stage: antStage, size: 40)
                    Text(antCaption)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            Text("閉じる")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.chatHeader.ignoresSafeArea(edges: .top))

            band()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chatStatusBand)
                .overlay(alignment: .bottom) { Theme.separator.frame(height: 1) }
        }
    }
}

/// 状態帯の1行目（左に題名、右に補足）
struct StatusBandTitle: View {
    var title: String
    var trailing: String
    var trailingColor: Color = Theme.antGold

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(trailing)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(trailingColor)
        }
    }
}

/// 状態帯の小さな補足（「おすすめ：…」など）
struct StatusBandCaption: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: ChatMetrics.captionFont))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

/// 納得度ゲージ（%）
struct ConvictionGauge: View {
    var score: Int
    var threshold: Int

    static func color(score: Int, threshold: Int) -> Color {
        score >= threshold / 2 ? Theme.convictionHigh : Theme.convictionLow
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.gaugeTrack)
                Capsule()
                    .fill(Self.color(score: score, threshold: threshold))
                    .frame(width: geo.size.width * CGFloat(min(max(score, 0), 100)) / 100)
            }
        }
        .frame(height: ChatMetrics.gaugeHeight)
        .animation(.easeOut(duration: 0.4), value: score)
        .accessibilityLabel("納得度 \(score)%")
    }
}

/// チャット内の案内カード（時計アイコン＋太字＋補足）
struct ChatNoticeCard: View {
    var icon: String = "clock"
    var title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.antGold)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: ChatMetrics.captionFont))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.noticeCard, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// アリ側の吹き出しの枠（中に任意の内容を入れる。候補リストなど）
struct AntBubbleContainer<Content: View>: View {
    var antStage: Int = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AntFace(stage: antStage, size: 36)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: ChatMetrics.rowRadius))
            Spacer(minLength: 16)
        }
    }
}
