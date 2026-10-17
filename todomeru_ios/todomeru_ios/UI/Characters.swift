import SwiftUI
import UIKit

/// アリの表情（納得度で切替。UI_UX.md 2.5）。
/// アセット ant_0〜ant_4 があれば画像、なければ絵文字で代用する。
struct AntFace: View {
    /// 0:むっ 1:うーん 2:ふむ 3:まあいいか 4:OK！
    var stage: Int = 4
    var size: CGFloat = 44

    static func stage(forConviction score: Int) -> Int {
        switch score {
        case ..<20: return 0
        case ..<40: return 1
        case ..<60: return 2
        case ..<80: return 3
        default: return 4
        }
    }

    static let labels = ["むっ", "うーん", "ふむ", "まあいいか", "OK！"]

    var body: some View {
        CharacterImage(name: "ant_\(min(max(stage, 0), 4))", fallback: "🐜", size: size)
    }
}

/// キリギリス（取り組み時間で変化）。アセット grasshopper_0〜grasshopper_3
struct GrasshopperFigure: View {
    /// 0:だらだら 1:やる気スイッチ 2:集中 3:ひと仕事終えた
    var stage: Int = 0
    var size: CGFloat = 44

    static func stage(forFocusSeconds s: Int, completed: Bool = false) -> Int {
        if completed { return 3 }
        switch s {
        case 0: return 0
        case ..<(25 * 60): return 1
        case ..<(75 * 60): return 2
        default: return 3
        }
    }

    var body: some View {
        CharacterImage(name: "grasshopper_\(min(max(stage, 0), 3))", fallback: "🦗", size: size)
    }
}

struct CharacterImage: View {
    var name: String
    var fallback: String
    var size: CGFloat

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(fallback)
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
        }
    }
}

/// SNSのアイコン（実機ではScreen TimeのLabel(token)に置き換える想定）
struct SNSIcon: View {
    var sns: SNSApp
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color(hex: sns.tintHex))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: sns.symbol)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}
