import Foundation

/// 仮実装（エージェントが置き換える）
struct FallbackPersuasionAI: PersuasionAI {
    var kindLabel: String { "デモ用の固定応答" }
    func reply(to context: PersuasionContext) async throws -> AIReply {
        AIReply(content: "どうしてSNSを使いたいの？", convictionScore: 0, action: .ask)
    }
}
