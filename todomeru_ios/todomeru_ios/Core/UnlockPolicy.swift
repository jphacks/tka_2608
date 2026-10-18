import Foundation

enum PolicyError: Error, Equatable, LocalizedError {
    case invalidProposal(String)
    case belowThreshold
    case quotaExceeded
    case grantAlreadyActive
    case notRestricted

    var errorDescription: String? {
        switch self {
        case .invalidProposal(let r): return "提案を受け付けられませんでした（\(r)）"
        case .belowThreshold: return "納得度が足りません"
        case .quotaExceeded: return "今日の相談はもう使えません"
        case .grantAlreadyActive: return "このアプリはすでに利用できる状態です"
        case .notRestricted: return "このアプリは今は制限されていません"
        }
    }
}

/// AIの返答だけで制限を解除しない。アプリのポリシーで検査する（AGENTS.md / ARCHITECTURE.md 3.4・3.5）。
enum UnlockPolicy {
    /// 説得の結果、利用枠を発行してよいかを検査し、許可する秒数を返す
    static func validate(reply: AIReply, attempt: PersuasionAttempt, store: AppStore) -> Result<Int, PolicyError> {
        guard reply.action == .proposeUnlock else { return .failure(.invalidProposal("許可の提案ではありません")) }
        guard let score = reply.convictionScore, (0...100).contains(score) else {
            return .failure(.invalidProposal("納得度が不正です"))
        }
        guard score >= PolicyConstants.persuasionApprovalThreshold else { return .failure(.belowThreshold) }
        guard let seconds = reply.proposedSeconds,
              (PolicyConstants.persuasionGrantMinSeconds...PolicyConstants.persuasionGrantMaxSeconds).contains(seconds) else {
            // 範囲外は丸めずに不採用（D023）
            return .failure(.invalidProposal("時間が範囲外です"))
        }
        guard attempt.status == .active, attempt.dayKey == AppDay.key() else { return .failure(.invalidProposal("古い相談です")) }
        // この試行は最初の1通で回数を確保済み。確保分を含めて上限内か
        guard !PolicyConstants.limitsPersuasionPerDay || store.persuasionsUsedToday() <= PolicyConstants.persuasionDailyLimit else { return .failure(.quotaExceeded) }
        guard store.activeGrant(attempt.snsID) == nil else { return .failure(.grantAlreadyActive) }
        return .success(seconds)
    }

    /// 新しい説得を始められるか
    static func canStartPersuasion(store: AppStore) -> Bool {
        store.persuasionsRemainingToday().map { $0 > 0 } ?? true
    }
}
