import Foundation
import Testing
@testable import todomeru_ios

@MainActor
final class FailingUnlockMonitor: UnlockMonitoring {
    enum Failure { case none, grantRegistration, dailyRegistration, commit }
    var failure: Failure = .none
    var calls: [String] = []
    var onPrepare: (() -> Void)?

    func prepare(_ grant: UnlockGrant, limits: [ScreenTimeMonitorState.Limit]) throws {
        calls.append("grant")
        onPrepare?()
        if failure == .grantRegistration { throw PolicyError.monitoringUnavailable }
        calls.append("daily")
        if failure == .dailyRegistration { throw PolicyError.monitoringUnavailable }
    }
    func commit(_ grant: UnlockGrant, temporary: Bool) throws {
        calls.append("commit")
        if failure == .commit { throw PolicyError.monitoringUnavailable }
    }
    func rollback(_ grant: UnlockGrant) { calls.append("rollback") }
}

@Suite("解除前の監視登録")
@MainActor
struct UnlockPreparationTests {
    private func addApp(_ store: AppStore, limit: Int = 1800) -> String {
        store.snsApps.append(SNSApp(id: "picked", name: "", symbol: "app", tintHex: 0, isSelected: true,
                                   dailyLimitSeconds: limit, tokenData: Data([1])))
        return "picked"
    }

    @Test("準備中は制限と旧上限を維持し、全登録成功後に解除する")
    func commitsAfterRegistration() {
        withTemporaryStore { store in
            let id = addApp(store)
            store.monitorLimitReached = [id]
            let monitor = FailingUnlockMonitor()
            store.unlockMonitoring = monitor
            monitor.onPrepare = {
                #expect(store.isRestricted(id))
                #expect(store.activeGrant(id) == nil)
                #expect(store.totalLimitToday(id) == 1800)
                #expect(store.grants.last?.status == .preparing)
            }
            let result = store.issueMonitoredGrant(snsID: id, seconds: 60, source: .persuasion)
            #expect(failure(result) == nil)
            #expect(monitor.calls == ["grant", "daily", "commit"])
            #expect(store.totalLimitToday(id) == 1860)
            #expect(!store.isRestricted(id))
            if let grant = store.activeGrant(id) {
                store.endGrants(ids: [grant.id.uuidString])
                #expect(store.isRestricted(id))
            } else { Issue.record("利用枠が発行されていません") }
        }
    }

    @Test("一時監視・日次監視・確定の失敗で解除せず、再試行は1回分だけ追加する",
          arguments: [FailingUnlockMonitor.Failure.grantRegistration, .dailyRegistration, .commit])
    func failuresDoNotUnlock(_ failedAt: FailingUnlockMonitor.Failure) {
        withTemporaryStore { store in
            let id = addApp(store)
            store.monitorLimitReached = [id]
            let monitor = FailingUnlockMonitor()
            store.unlockMonitoring = monitor
            monitor.failure = failedAt
            #expect(failure(store.issueMonitoredGrant(snsID: id, seconds: 60, source: .persuasion)) == .monitoringUnavailable)
            #expect(store.isRestricted(id))
            #expect(store.activeGrant(id) == nil)
            #expect(store.totalLimitToday(id) == 1800)
            #expect(monitor.calls.last == "rollback")
            monitor.failure = .none
            #expect(failure(store.issueMonitoredGrant(snsID: id, seconds: 60, source: .persuasion)) == nil)
            #expect(store.totalLimitToday(id) == 1860)
            #expect(store.grants.filter { $0.status == .active }.count == 1)
        }
    }

    @Test("報酬は上限前・到達後とも、失敗時に未適用へ戻り二重付与しない", arguments: [false, true])
    func rewardFailurePreservesCredit(restricted: Bool) {
        withTemporaryStore { store in
            let id = addApp(store)
            if restricted { store.monitorLimitReached = [id] }
            let session = store.runFocus(seconds: PolicyConstants.focusRewardIntervalSeconds)
            let monitor = FailingUnlockMonitor()
            store.unlockMonitoring = monitor
            monitor.failure = .commit
            #expect(failure(store.applyReward(to: id, sessionID: session.id)) == .monitoringUnavailable)
            #expect(store.session(session.id)?.rewardTargetSNSID == nil)
            #expect(store.totalLimitToday(id) == 1800)
            #expect(store.activeGrant(id) == nil)
            monitor.failure = .none
            #expect(isSuccess(store.applyReward(to: id, sessionID: session.id)))
            #expect(isSuccess(store.applyReward(to: id, sessionID: session.id)))
            #expect(store.totalLimitToday(id) == 1800 + PolicyConstants.focusRewardSeconds)
            #expect(store.session(session.id)?.rewardTargetSNSID == id)
            #expect(monitor.calls.filter { $0 == "grant" }.count == 2)
        }
    }

    @Test("新規登録失敗で既存の有効な枠を取り消さない")
    func preservesExistingGrant() {
        withTemporaryStore { store in
            let id = addApp(store)
            let existing = store.issueGrant(snsID: id, seconds: 120, source: .reward)
            let monitor = FailingUnlockMonitor()
            monitor.failure = .dailyRegistration
            store.unlockMonitoring = monitor
            #expect(failure(store.issueMonitoredGrant(snsID: id, seconds: 60, source: .reward)) == .monitoringUnavailable)
            #expect(store.activeGrant(id)?.id == existing.id)
            #expect(store.totalLimitToday(id) == 1920)
        }
    }

    @Test("登録先がなければ実アプリを解除しない")
    func noRegistrarDoesNotUnlock() {
        withTemporaryStore { store in
            let id = addApp(store, limit: 0)
            #expect(failure(store.issueMonitoredGrant(snsID: id, seconds: 60, source: .persuasion)) == .monitoringUnavailable)
            #expect(store.grants.isEmpty)
            #expect(store.isRestricted(id))
        }
    }

    @Test("保存された準備中の枠は再起動で取消し、使用可能時間へ含めない")
    func cancelsInterruptedPreparation() throws {
        let name = "unlock-prepare-\(UUID().uuidString).json"
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        var snapshot = AppStore.Snapshot()
        var attempt = PersuasionAttempt(snsID: "x", dayKey: AppDay.key())
        attempt.countsTowardQuota = true
        attempt.userMessageCount = 1
        snapshot.attempts = [attempt]
        snapshot.grants = [UnlockGrant(snsID: "x", source: .persuasion, grantedSeconds: 60, remainingSeconds: 60,
                                      dayKey: AppDay.key(), status: .preparing, persuasionAttemptID: attempt.id)]
        try JSONEncoder().encode(snapshot).write(to: url)
        let store = AppStore(fileName: name)
        #expect(store.grants.first?.status == .cancelled)
        #expect(store.activeGrant("x") == nil)
        #expect(store.persuasionsUsedToday() == 0)
        #expect(store.attempt(attempt.id)?.status == .failed)
        #expect(store.addedLimitSeconds("x") == 0)
        #expect(AppStore(fileName: name).grants.first?.status == .cancelled)
    }

    @Test("相談の登録失敗は回数を返し、成功案内を出さず再挑戦できる")
    func persuasionFailureRefundsQuota() async {
        let name = "unlock-chat-\(UUID().uuidString).json"
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(fileName: name)
        let id = addApp(store, limit: 0)
        let monitor = FailingUnlockMonitor()
        monitor.failure = .grantRegistration
        store.unlockMonitoring = monitor
        let model = PersuasionViewModel(snsID: id)
        let reminders = ReminderService()
        model.beginNewAttempt(store: store, reminders: reminders)
        for _ in 0..<2 {
            model.input = "急ぎのゼミの連絡を先生に確認したら、1分だけで課題に戻ります。"
            await model.sendInput(store: store, reminders: reminders)
        }
        guard case .approvable = model.phase else { Issue.record("許可の提案になっていません"); return }
        #expect(store.persuasionsUsedToday() == 1)
        model.openSNS(store: store)
        #expect(store.persuasionsUsedToday() == 0)
        #expect(model.deviceGrantSeconds == nil)
        #expect(model.deviceGrantMessageID == nil)
        #expect(store.isRestricted(id))
        if case .failed = model.phase {} else { Issue.record("失敗を表示していません") }
        #expect(UnlockPolicy.canStartPersuasion(store: store))
    }
}
