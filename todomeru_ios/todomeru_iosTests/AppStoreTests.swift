import Foundation
import Testing
@testable import todomeru_ios

/// AppStore の報酬・制限（デモ）・説得回数。数値は PolicyConstants から計算する。
@Suite("AppStore")
struct AppStoreTests {
    let interval = PolicyConstants.focusRewardIntervalSeconds
    let reward = PolicyConstants.focusRewardSeconds

    func focusRewardCount(_ store: AppStore, _ id: UUID) -> Int {
        store.rewards.filter { $0.kind == .focus && $0.idempotencyKey.hasPrefix("focus-\(id)-") }.count
    }

    // MARK: - 取り組み報酬

    @Test("取り組み報酬は ⌊秒÷interval⌋×reward",
          arguments: [0, 1, PolicyConstants.focusRewardIntervalSeconds - 1, PolicyConstants.focusRewardIntervalSeconds,
                      PolicyConstants.focusRewardIntervalSeconds * 2 - 1, PolicyConstants.focusRewardIntervalSeconds * 3 + 30])
    func focusRewardFormula(seconds: Int) {
        withTemporaryStore { store in
            let s = store.startFocus(task: makeTask(), origin: .home)
            store.recordFocusRewards(s.id, now: s.startedAt.addingTimeInterval(Double(seconds)))
            #expect(store.earnedSeconds(for: s.id).focus == seconds / interval * reward)
        }
    }

    @Test("24分（interval未満）の取り組みは報酬0")
    func focus24MinutesIsZero() {
        withTemporaryStore { store in
            // 現在の定数（interval=25分）では interval-60秒 が24分
            let s = store.runFocus(seconds: interval - 60)
            #expect(store.earnedSeconds(for: s.id).focus == 0)
            #expect(store.rewardBalanceToday() == 0)
        }
    }

    @Test("recordFocusRewards を2回呼んでも同じ単位は二重付与しない")
    func focusRewardIdempotent() {
        withTemporaryStore { store in
            let s = store.startFocus(task: makeTask(), origin: .home)
            let at = s.startedAt.addingTimeInterval(Double(interval * 2))
            store.recordFocusRewards(s.id, now: at)
            store.recordFocusRewards(s.id, now: at)
            #expect(focusRewardCount(store, s.id) == 2)
            #expect(store.earnedSeconds(for: s.id).focus == 2 * reward)
        }
    }

    @Test("途中で記録してから単位が増えても、既存の単位は重ねない")
    func focusRewardIncremental() {
        withTemporaryStore { store in
            let s = store.startFocus(task: makeTask(), origin: .home)
            store.recordFocusRewards(s.id, now: s.startedAt.addingTimeInterval(Double(interval)))
            store.recordFocusRewards(s.id, now: s.startedAt.addingTimeInterval(Double(interval * 2)))
            #expect(focusRewardCount(store, s.id) == 2)
            // endFocus でも再記録されるが増えない
            store.endFocus(s.id, at: s.startedAt.addingTimeInterval(Double(interval * 2 + 10)))
            #expect(focusRewardCount(store, s.id) == 2)
            #expect(store.rewardBalanceToday() == 2 * reward)
        }
    }

    @Test("shiftFocusStart は進行中の取り組みの開始を過去へずらし、終了後は変えない")
    func shiftFocusStart() {
        withTemporaryStore { store in
            let s = store.startFocus(task: makeTask(), origin: .home)
            store.shiftFocusStart(s.id, by: interval)
            let shifted = store.session(s.id)!.startedAt
            #expect(shifted == s.startedAt.addingTimeInterval(-Double(interval)))
            store.endFocus(s.id)
            store.shiftFocusStart(s.id, by: interval)
            #expect(store.session(s.id)!.startedAt == shifted)
            #expect(store.earnedSeconds(for: s.id).focus == reward)
        }
    }

    @Test("新しい取り組みを始めると進行中のものは終わる")
    func startFocusEndsActive() {
        withTemporaryStore { store in
            let first = store.startFocus(task: makeTask(), origin: .home)
            let second = store.startFocus(task: makeTask(), origin: .home)
            #expect(store.session(first.id)?.endedAt != nil)
            #expect(store.activeSession?.id == second.id)
        }
    }

    // MARK: - 完了報酬

    @Test("完了報酬は同じやること・同じ日に一度だけ")
    func completionRewardIdempotent() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: 60, taskID: "task-1")
            store.recordCompletionReward(sessionID: s.id, taskID: "task-1")
            store.recordCompletionReward(sessionID: s.id, taskID: "task-1")
            #expect(store.earnedSeconds(for: s.id).completion == PolicyConstants.completionRewardSeconds)
            #expect(store.rewards.filter { $0.kind == .completion }.count == 1)
            #expect(store.rewardBalanceToday() == PolicyConstants.completionRewardSeconds)
        }
    }

    // MARK: - applyReward

    @Test("残高不足なら insufficientBalance で、何も変えない")
    func applyRewardInsufficient() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: interval)
            let limit = store.effectiveLimit("x")
            #expect(failure(store.applyReward(seconds: reward + 1, to: "x", sessionID: s.id)) == .insufficientBalance)
            #expect(store.effectiveLimit("x") == limit)
            #expect(store.rewardBalanceToday() == reward)
        }
    }

    @Test("0秒・存在しないSNSは不採用")
    func applyRewardInvalid() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: interval)
            guard case .failure(.invalidProposal) = store.applyReward(seconds: 0, to: "x", sessionID: s.id) else {
                Issue.record("0秒が受理された"); return
            }
            guard case .failure(.invalidProposal) = store.applyReward(seconds: reward, to: "no-such-sns", sessionID: s.id) else {
                Issue.record("存在しないSNSが受理された"); return
            }
            #expect(store.rewardBalanceToday() == reward)
        }
    }

    @Test("上限未到達なら当日の上限に足す（一時利用枠は出さない）")
    func applyRewardUnderLimit() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: interval)
            let limit = store.effectiveLimit("x")
            #expect(isSuccess(store.applyReward(seconds: reward, to: "x", sessionID: s.id)))
            #expect(store.effectiveLimit("x") == limit + reward)
            #expect(store.activeGrant("x") == nil)
            #expect(store.rewardBalanceToday() == 0)
            #expect(store.session(s.id)?.rewardTargetSNSID == "x")
        }
    }

    @Test("同じ取り組みで2回適用しても二重に引き落とさない")
    func applyRewardIdempotent() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: interval * 2)
            let limit = store.effectiveLimit("x")
            #expect(isSuccess(store.applyReward(seconds: reward, to: "x", sessionID: s.id)))
            #expect(isSuccess(store.applyReward(seconds: reward, to: "x", sessionID: s.id)))
            #expect(store.effectiveLimit("x") == limit + reward)
            #expect(store.rewardBalanceToday() == reward)
            #expect(store.rewards.filter { $0.kind == .spend }.count == 1)
        }
    }

    @Test("上限到達（制限中）なら一時利用枠を発行し、上限は変えない")
    func applyRewardOverLimitIssuesGrant() {
        withTemporaryStore { store in
            let s = store.runFocus(seconds: interval)
            let limit = store.effectiveLimit("x")
            store.setDemoUsage(limit, for: "x")
            #expect(store.isRestricted("x"))
            #expect(isSuccess(store.applyReward(seconds: reward, to: "x", sessionID: s.id)))
            let g = store.activeGrant("x")
            #expect(g?.source == .reward)
            #expect(g?.grantedSeconds == reward)
            #expect(g?.remainingSeconds == reward)
            #expect(store.effectiveLimit("x") == limit)
            #expect(!store.isRestricted("x"))
        }
    }

    // MARK: - consumeUsage

    @Test("一時利用枠は利用で減り、0で終了して true を返す（再制限）")
    func consumeUsageEndsGrant() {
        withTemporaryStore { store in
            let limit = store.effectiveLimit("x")
            store.setDemoUsage(limit, for: "x")
            let grantSeconds = PolicyConstants.persuasionGrantMinSeconds * 2
            store.issueGrant(snsID: "x", seconds: grantSeconds, source: .persuasion)
            let half = grantSeconds / 2

            #expect(store.consumeUsage("x", seconds: half) == false)
            #expect(store.activeGrant("x")?.remainingSeconds == grantSeconds - half)
            #expect(!store.isRestricted("x"))

            #expect(store.consumeUsage("x", seconds: grantSeconds - half) == true)
            #expect(store.activeGrant("x") == nil)
            #expect(store.lastEndedGrant("x")?.remainingSeconds == 0)
            #expect(store.isRestricted("x"))
            #expect(store.usageToday("x") == limit + grantSeconds)
        }
    }

    @Test("使い過ぎても残りは0で止まり true")
    func consumeUsageOvershoot() {
        withTemporaryStore { store in
            store.setDemoUsage(store.effectiveLimit("x"), for: "x")
            let grantSeconds = PolicyConstants.persuasionGrantMinSeconds
            store.issueGrant(snsID: "x", seconds: grantSeconds, source: .persuasion)
            #expect(store.consumeUsage("x", seconds: grantSeconds * 3) == true)
            #expect(store.lastEndedGrant("x")?.remainingSeconds == 0)
        }
    }

    @Test("上限未到達のうちは枠を減らさず false")
    func consumeUsageUnderLimit() {
        withTemporaryStore { store in
            let grantSeconds = PolicyConstants.persuasionGrantMinSeconds
            store.issueGrant(snsID: "x", seconds: grantSeconds, source: .reward)
            #expect(store.consumeUsage("x", seconds: grantSeconds) == false)
            #expect(store.activeGrant("x")?.remainingSeconds == grantSeconds)
            #expect(store.usageToday("x") == grantSeconds)
        }
    }

    // MARK: - 説得回数（D024）

    /// 最初の1通を送った時点の確保を再現する
    func attempt(_ store: AppStore, messages: Int) -> PersuasionAttempt {
        var a = store.beginAttempt(snsID: "x")
        a.userMessageCount = messages
        a.countsTowardQuota = messages > 0
        store.updateAttempt(a)
        return a
    }

    @Test("cancelled: 0通なら数えない")
    func cancelledWithoutMessage() {
        withTemporaryStore { store in
            var a = store.beginAttempt(snsID: "x")
            a.countsTowardQuota = true // 確保していたとしても0通なら戻す
            store.updateAttempt(a)
            store.finishAttempt(a.id, status: .cancelled)
            #expect(store.attempt(a.id)?.countsTowardQuota == false)
            #expect(store.persuasionsUsedToday() == 0)
            #expect(store.persuasionsRemainingToday() == PolicyConstants.persuasionDailyLimit)
        }
    }

    @Test("cancelled: 1通以上なら数える")
    func cancelledWithMessage() {
        withTemporaryStore { store in
            let a = attempt(store, messages: 1)
            store.finishAttempt(a.id, status: .cancelled)
            #expect(store.attempt(a.id)?.status == .cancelled)
            #expect(store.attempt(a.id)?.countsTowardQuota == true)
            #expect(store.persuasionsUsedToday() == 1)
            #expect(store.persuasionsRemainingToday() == PolicyConstants.persuasionDailyLimit - 1)
        }
    }

    @Test("failed・redirectedToTask は数えない", arguments: [PersuasionAttempt.Status.failed, .redirectedToTask])
    func notCounted(status: PersuasionAttempt.Status) {
        withTemporaryStore { store in
            let a = attempt(store, messages: 3)
            store.finishAttempt(a.id, status: status)
            #expect(store.attempt(a.id)?.countsTowardQuota == false)
            #expect(store.persuasionsUsedToday() == 0)
        }
    }

    @Test("approved・rejected は数えたまま", arguments: [PersuasionAttempt.Status.approved, .rejected])
    func counted(status: PersuasionAttempt.Status) {
        withTemporaryStore { store in
            let a = attempt(store, messages: 2)
            store.finishAttempt(a.id, status: status)
            #expect(store.persuasionsUsedToday() == 1)
        }
    }

    @Test("終わった試行を再度終えても変わらない")
    func finishTwice() {
        withTemporaryStore { store in
            let a = attempt(store, messages: 1)
            store.finishAttempt(a.id, status: .approved)
            store.finishAttempt(a.id, status: .failed)
            #expect(store.attempt(a.id)?.status == .approved)
            #expect(store.persuasionsUsedToday() == 1)
        }
    }

    @Test("persuasionsRemainingToday は上限から引き、0未満にならない。別の日の試行は数えない")
    func remaining() {
        withTemporaryStore { store in
            var old = attempt(store, messages: 1)
            old.dayKey = "2000-01-01"
            store.updateAttempt(old)
            #expect(store.persuasionsRemainingToday() == PolicyConstants.persuasionDailyLimit)
            for _ in 0..<(PolicyConstants.persuasionDailyLimit + 1) { _ = attempt(store, messages: 1) }
            #expect(store.persuasionsUsedToday() == PolicyConstants.persuasionDailyLimit + 1)
            #expect(store.persuasionsRemainingToday() == 0)
        }
    }

    @Test("保存したファイルから読み直すと、進行中で1通以上の説得は cancelled として数える")
    func reloadCancelsStaleAttempt() {
        let fileName = "todomeru-test-\(UUID().uuidString).json"
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(fileName: fileName)
        let sent = attempt(store, messages: 1)
        let unsent = attempt(store, messages: 0)
        let reloaded = AppStore(fileName: fileName)
        #expect(reloaded.attempt(sent.id)?.status == .cancelled)
        #expect(reloaded.attempt(sent.id)?.countsTowardQuota == true)
        #expect(reloaded.attempt(unsent.id)?.status == .cancelled)
        #expect(reloaded.persuasionsUsedToday() == 1)
    }
}
