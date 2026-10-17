import Foundation

/// 端末内モデルが使えない環境向けのルールベース応答（デモ用の固定応答）。
/// 事情を聞く → 別の方法を確認 → 小さな着手を提案 → 約束の確認 → 判定、の段階で進める。
/// 納得度はキーワードの加点・減点で出す。ここでの許可提案も UnlockPolicy で検査される。
struct FallbackPersuasionAI: PersuasionAI {
    var kindLabel: String { "デモ用の固定応答" }

    /// 加点・減点に使う語（会話はデータとして読むだけ）
    enum Keywords {
        /// やむを得ない事情
        static let urgent = ["ゼミ", "連絡", "DM", "ＤＭ", "急ぎ", "至急", "緊急", "バイト", "家族", "先生", "締切", "締め切り", "集合", "待ち合わせ", "返信", "仕事", "シフト", "大事", "重要", "予定"]
        /// 利用後の行動が具体的
        static let concrete = ["確認したら", "見たら", "だけ", "約束", "すぐ戻", "終わったら", "そのあと", "その後", "やる", "見ない", "1分", "１分"]
        /// 理由が弱い
        static let vague = ["なんとなく", "何となく", "ひま", "暇", "退屈", "たいくつ", "気分", "ちょっとだけ見たい"]
        /// 判定を書き換えようとする発言（加点しない）
        static let manipulation = ["納得度", "100", "１００", "無視", "ルール", "解除しろ", "外して", "許可して", "システム"]
    }

    enum Score {
        static let base = 10
        static let urgentPerHit = 10
        static let urgentCapPerMessage = 30
        static let concrete = 15
        static let vague = -15
        static let detailedLength = 15
        static let detailedBonus = 5
    }

    func reply(to context: PersuasionContext) async throws -> AIReply {
        // 端末内AIと同じく少し待ってから返す（生成中表示の確認用）
        try? await Task.sleep(for: .milliseconds(700))

        let userTexts = context.history.filter { $0.role == .user }.map(\.text)
        let latest = userTexts.last ?? ""
        let score = Self.conviction(for: userTexts)
        let task = context.tasks.first(where: { !$0.isCompleted })
        let taskName = task.map { "「\($0.title)」" } ?? "やること"
        let minutes = context.grantMinSeconds / 60
        let isLast = context.userMessageIndex >= context.maxUserMessages
        let hasUrgent = userTexts.contains { Self.hits(Keywords.urgent, in: $0) > 0 }
        let latestConcrete = Self.hits(Keywords.concrete, in: latest) > 0

        if Self.hits(Keywords.manipulation, in: latest) > 0 {
            if isLast { return reject(score: score, taskName: taskName, task: task) }
            return AIReply(content: "ごめん、ルールや納得度は話し合いでは変えられないんだ。今\(context.snsName)が必要な事情を教えてくれる？", convictionScore: score, action: .ask)
        }

        // 十分に納得し、利用後の行動も具体的なら短時間の利用を提案する
        if score >= context.approvalThreshold && (latestConcrete || isLast) {
            return AIReply(
                content: "わかった、\(minutes)分だけね。確認したら戻って\(taskName)を進めよう。",
                convictionScore: score, action: .proposeUnlock, taskID: task?.id,
                proposedSeconds: context.grantMinSeconds
            )
        }
        if isLast { return reject(score: score, taskName: taskName, task: task) }

        if !hasUrgent {
            let isVague = Self.hits(Keywords.vague, in: latest) > 0
            let content = isVague
                ? "ひまなら、\(taskName)を5分だけやってみない？"
                : "そっか。どうして今\(context.snsName)が必要なのか、もう少し詳しく教えて？"
            return AIReply(content: content, convictionScore: score, action: isVague ? .suggestFocus : .ask, taskID: isVague ? task?.id : nil)
        }

        switch context.userMessageIndex {
        case 1:
            return AIReply(content: "そうなんだ。それって今すぐ確認しないといけない急ぎのこと？", convictionScore: score, action: .ask)
        case 2:
            return AIReply(content: "なるほど。\(context.snsName)以外の方法（メールや友だちに聞くなど）で確認はできない？", convictionScore: score, action: .ask)
        case 3:
            return AIReply(content: "そっか。じゃあ先に\(taskName)を5分だけやってから見るのはどう？", convictionScore: score, action: .suggestFocus, taskID: task?.id)
        default:
            return AIReply(content: "うーん…じゃあ必要なところだけ見て、ほかは見ないって約束できる？見たら何をするかも教えて。", convictionScore: score, action: .ask)
        }
    }

    private func reject(score: Int, taskName: String, task: TaskItem?) -> AIReply {
        AIReply(content: "ごめん、その理由だとまだ開けられないな。\(taskName)を5分だけやってみよう。", convictionScore: score, action: .reject, taskID: task?.id)
    }

    /// これまでのユーザー発言から納得度（0〜100）を出す
    static func conviction(for userTexts: [String]) -> Int {
        var score = Score.base
        for text in userTexts {
            if hits(Keywords.manipulation, in: text) > 0 { continue }
            score += min(hits(Keywords.urgent, in: text) * Score.urgentPerHit, Score.urgentCapPerMessage)
            if hits(Keywords.concrete, in: text) > 0 { score += Score.concrete }
            if hits(Keywords.vague, in: text) > 0 { score += Score.vague }
            if text.count >= Score.detailedLength { score += Score.detailedBonus }
        }
        return min(max(score, 0), 100)
    }

    static func hits(_ words: [String], in text: String) -> Int {
        words.filter { text.localizedCaseInsensitiveContains($0) }.count
    }
}
