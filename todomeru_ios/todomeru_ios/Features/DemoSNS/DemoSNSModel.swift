import Foundation
import Observation

/// 疑似アプリ画面の状態と計測。実際のアプリの利用時間は本体から読めないため、
/// デモではこの画面を開いている間だけ使用時間を進める。
@Observable
final class DemoSNSModel {
    /// デモ用の倍速（1秒ごとに進める秒数）
    enum Speed: Int, CaseIterable, Identifiable {
        case x1 = 1, x10 = 10, x60 = 60
        var id: Int { rawValue }
        var label: String { "\(rawValue)x" }
    }

    let snsID: String
    var speed: Speed = .x1

    init(snsID: String) { self.snsID = snsID }

    /// 表示時点で制限中なら制限画面へ
    func initialRedirect(store: AppStore) -> Route? {
        store.isRestricted(snsID) ? .shield(snsID: snsID) : nil
    }

    /// 1秒ぶん利用を進め、次に移る画面があれば返す。
    /// 一時利用枠を使い切ったら利用終了画面、上限に達したら制限画面。
    func tick(store: AppStore) -> Route? {
        let grantEnded = store.consumeUsage(snsID, seconds: speed.rawValue)
        if grantEnded { return .grantEnded(snsID: snsID) }
        if store.isRestricted(snsID) { return .shield(snsID: snsID) }
        return nil
    }
}

/// 疑似タイムラインの投稿（固定のダミー）
struct DemoPost: Identifiable {
    let id = UUID()
    var author: String
    var handle: String
    var minutesAgo: Int
    var text: String
    var likes: Int

    static let samples: [DemoPost] = [
        DemoPost(author: "ねこ好き", handle: "neko_daisuki", minutesAgo: 2, text: "うちの猫、今日も箱に入ってる。", likes: 128),
        DemoPost(author: "カフェ巡り", handle: "cafe_walk", minutesAgo: 8, text: "駅前の新しいカフェ、プリンが最高でした。", likes: 54),
        DemoPost(author: "ゼミ連絡", handle: "seminar_info", minutesAgo: 15, text: "来週のゼミは教室が変わります。詳細はDMで。", likes: 12),
        DemoPost(author: "まとめ速報", handle: "matome_news", minutesAgo: 21, text: "【話題】気づいたら3時間SNSを見ていた人、多数", likes: 893),
        DemoPost(author: "ゲーム実況", handle: "game_live", minutesAgo: 34, text: "今夜21時から配信します！", likes: 301),
        DemoPost(author: "朝活の人", handle: "asakatsu", minutesAgo: 47, text: "今日のやること、午前中に3つ終わった。", likes: 76),
        DemoPost(author: "料理メモ", handle: "cook_memo", minutesAgo: 59, text: "10分でできる親子丼のレシピ。", likes: 210),
    ]
}
