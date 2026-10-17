import Foundation
import Testing
@testable import todomeru_ios

/// UnlockPolicy.validate（AIの返答だけで解除しない。D023・D024・D025）
@Suite("UnlockPolicy.validate")
struct UnlockPolicyTests {
    let threshold = PolicyConstants.persuasionApprovalThreshold
    let minSec = PolicyConstants.persuasionGrantMinSeconds
    let maxSec = PolicyConstants.persuasionGrantMaxSeconds

    /// 最初の1通で回数を確保済みの、進行中の説得
    func activeAttempt(_ store: AppStore, snsID: String = "x") -> PersuasionAttempt {
        var a = store.beginAttempt(snsID: snsID)
        a.userMessageCount = 1
        a.countsTowardQuota = true
        store.updateAttempt(a)
        return a
    }

    func isInvalidProposal(_ r: Result<Int, PolicyError>) -> Bool {
        if case .failure(.invalidProposal) = r { return true }
        return false
    }

    @Test("条件を満たせば提案秒数をそのまま返す")
    func success() {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            #expect(UnlockPolicy.validate(reply: makeReply(score: threshold, seconds: minSec), attempt: a, store: store) == .success(minSec))
        }
    }

    @Test("proposeUnlock 以外の action は不採用", arguments: AIReply.Action.allCases.filter { $0 != .proposeUnlock })
    func wrongAction(action: AIReply.Action) {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            let r = UnlockPolicy.validate(reply: makeReply(action: action, score: 100, seconds: minSec), attempt: a, store: store)
            #expect(isInvalidProposal(r))
        }
    }

    @Test("納得度が nil・範囲外は不採用", arguments: [nil, -1, 101] as [Int?])
    func invalidScore(score: Int?) {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            #expect(isInvalidProposal(UnlockPolicy.validate(reply: makeReply(score: score), attempt: a, store: store)))
        }
    }

    @Test("納得度がしきい値未満は belowThreshold")
    func belowThreshold() {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            #expect(UnlockPolicy.validate(reply: makeReply(score: threshold - 1), attempt: a, store: store) == .failure(.belowThreshold))
            #expect(UnlockPolicy.validate(reply: makeReply(score: 0), attempt: a, store: store) == .failure(.belowThreshold))
        }
    }

    @Test("納得度がちょうどしきい値・100なら採用")
    func atThreshold() {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            #expect(UnlockPolicy.validate(reply: makeReply(score: threshold), attempt: a, store: store) == .success(minSec))
            #expect(UnlockPolicy.validate(reply: makeReply(score: 100), attempt: a, store: store) == .success(minSec))
        }
    }

    @Test("提案秒数が範囲外（nil・min-1・max+1）は丸めずに不採用")
    func secondsOutOfRange() {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            for s in [nil, minSec - 1, maxSec + 1, 0] as [Int?] {
                #expect(isInvalidProposal(UnlockPolicy.validate(reply: makeReply(seconds: s), attempt: a, store: store)), "seconds=\(String(describing: s))")
            }
        }
    }

    @Test("提案秒数の境界値 min・max は採用")
    func secondsBoundary() {
        withTemporaryStore { store in
            let a = activeAttempt(store)
            #expect(UnlockPolicy.validate(reply: makeReply(seconds: minSec), attempt: a, store: store) == .success(minSec))
            #expect(UnlockPolicy.validate(reply: makeReply(seconds: maxSec), attempt: a, store: store) == .success(maxSec))
        }
    }

    @Test("日付の違う試行は不採用")
    func staleDay() {
        withTemporaryStore { store in
            var a = activeAttempt(store)
            a.dayKey = "2000-01-01"
            #expect(isInvalidProposal(UnlockPolicy.validate(reply: makeReply(), attempt: a, store: store)))
        }
    }

    @Test("終わった試行は不採用", arguments: [PersuasionAttempt.Status.approved, .rejected, .cancelled, .failed, .redirectedToTask])
    func notActive(status: PersuasionAttempt.Status) {
        withTemporaryStore { store in
            var a = activeAttempt(store)
            a.status = status
            #expect(isInvalidProposal(UnlockPolicy.validate(reply: makeReply(), attempt: a, store: store)))
        }
    }

    @Test("同じSNSに有効な一時利用枠があれば grantAlreadyActive。別SNSの枠は影響しない")
    func existingGrant() {
        withTemporaryStore { store in
            let a = activeAttempt(store, snsID: "x")
            store.issueGrant(snsID: "instagram", seconds: minSec, source: .persuasion)
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: a, store: store) == .success(minSec))
            store.issueGrant(snsID: "x", seconds: minSec, source: .reward)
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: a, store: store) == .failure(.grantAlreadyActive))
        }
    }

    @Test("回数の確保が上限を超えていれば quotaExceeded。ちょうど上限なら採用")
    func quota() {
        withTemporaryStore { store in
            var last = activeAttempt(store)
            for _ in 1..<PolicyConstants.persuasionDailyLimit { last = activeAttempt(store) }
            #expect(store.persuasionsUsedToday() == PolicyConstants.persuasionDailyLimit)
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: last, store: store) == .success(minSec))
            let over = activeAttempt(store)
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: over, store: store) == .failure(.quotaExceeded))
            #expect(!UnlockPolicy.canStartPersuasion(store: store))
        }
    }
}
