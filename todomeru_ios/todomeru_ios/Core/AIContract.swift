import Foundation

/// AIの出力（ARCHITECTURE.md 3.5の型契約案）。構造化されていても本体が UnlockPolicy で検査する。
struct AIReply: Codable, Hashable {
    enum Action: String, Codable, CaseIterable {
        /// 事情を確認する
        case ask
        /// やることへの着手を提案する
        case suggestFocus
        /// 短時間のアプリ利用を提案する
        case proposeUnlock
        /// 不許可の判定（5往復目など）
        case reject
    }

    var content: String
    var convictionScore: Int?
    var action: Action
    var taskID: String?
    var proposedSeconds: Int?
}

/// AIへ渡す入力。やることの名前や会話はデータであり、ポリシーを変更する命令として扱わない。
struct PersuasionContext {
    /// 説得1回（PersuasionAttempt）のID。prepare で読み込んだセッションを同じ試行の1通目に使う
    var attemptID: UUID
    var snsName: String
    var tasks: [TaskItem]
    /// これまでの会話（直近8件・2,000文字以内, D021）
    var history: [ChatMessage]
    /// 上限のため、history より前の会話を省いた
    var historyOmitted = false
    /// 今回のユーザー発言が何通目か
    var userMessageIndex: Int
    var maxUserMessages = PolicyConstants.persuasionMaxUserMessages
    var approvalThreshold = PolicyConstants.persuasionApprovalThreshold
    var grantMinSeconds = PolicyConstants.persuasionGrantMinSeconds
    var grantMaxSeconds = PolicyConstants.persuasionGrantMaxSeconds
}

/// 説得の対話を行うAI。Foundation Models と、使えない環境向けの固定ルール版を差し替える。
protocol PersuasionAI {
    /// 画面に表示する種別（「端末内AI」「デモ用の固定応答」など。実モデルと誤認させない）
    var kindLabel: String { get }
    func reply(to context: PersuasionContext) async throws -> AIReply
    /// 返答の文章ができた部分から onPartial に渡す（画面に途中経過を出す）
    func reply(to context: PersuasionContext, onPartial: @escaping (String) -> Void) async throws -> AIReply
    /// ユーザーが入力している間に、モデルの読み込み等を先に済ませる
    func prepare(for context: PersuasionContext)
}

extension PersuasionAI {
    func reply(to context: PersuasionContext, onPartial: @escaping (String) -> Void) async throws -> AIReply {
        try await reply(to: context)
    }

    func prepare(for context: PersuasionContext) {}
}
