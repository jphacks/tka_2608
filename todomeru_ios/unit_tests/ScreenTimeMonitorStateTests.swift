import Foundation
import Testing
@testable import todomeru_ios

@Suite("Monitorの上限・利用枠・Shieldの整合")
struct ScreenTimeMonitorStateTests {
    private let day = "2026-10-19"
    private let token = Data([1])

    @Test("上限を30分から60分へ増やすと、旧到達記録と遅れた旧通知を採用しない")
    func raisingLimitInvalidatesOldThreshold() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit(seconds: 30 * 60)]).first)
            #expect(state.markLimitReached(eventName: old.eventName, dayKey: day))
            // 本体側の上限だけが先に変わっても、古い上限の記録を取り込まない。
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 60 * 60]).isEmpty)

            let current = try #require(state.updateLimits([limit(seconds: 60 * 60)]).first)
            #expect(current.eventName != old.eventName)
            #expect(!state.markLimitReached(eventName: old.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 60 * 60]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)

            #expect(state.markLimitReached(eventName: current.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 60 * 60]) == ["app"])
            #expect(state.restrictedTokenData(dayKey: day) == [token])
        }
    }

    @Test("同じ条件の再登録ではイベント名と到達記録を保持する")
    func unchangedRegistrationPreservesThreshold() throws {
        try withState { state in
            let first = try #require(state.updateLimits([limit()]).first)
            #expect(state.markLimitReached(eventName: first.eventName, dayKey: day))
            let registered = try #require(state.updateLimits([limit()]).first)
            #expect(registered == first)
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]) == ["app"])
            #expect(state.restrictedTokenData(dayKey: day) == [token])
        }
    }

    @Test("別アプリの上限を変更しても、変更していないアプリの到達記録は消えない")
    func changingOtherAppPreservesReachedLimit() throws {
        try withState { state in
            let first = state.updateLimits([limit(), limit(id: "other", token: Data([2]))])
            let app = try #require(first.first { $0.snsID == "app" })
            let other = try #require(first.first { $0.snsID == "other" })
            #expect(state.markLimitReached(eventName: app.eventName, dayKey: day))
            #expect(state.markLimitReached(eventName: other.eventName, dayKey: day))

            let next = state.updateLimits([limit(), limit(id: "other", token: Data([2]), seconds: 3600)])
            #expect(next.first { $0.snsID == "app" }?.eventName == app.eventName)
            #expect(next.first { $0.snsID == "other" }?.eventName != other.eventName)
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800, "other": 3600]) == ["app"])
            #expect(state.restrictedTokenData(dayKey: day) == [token])
        }
    }

    @Test("同じIDでもトークンが変われば旧到達を引き継がない")
    func replacingTokenInvalidatesThreshold() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit()]).first)
            #expect(state.markLimitReached(eventName: old.eventName, dayKey: day))
            let replacement = try #require(state.updateLimits([limit(token: Data([2]))]).first)
            #expect(replacement.eventName != old.eventName)
            #expect(!state.markLimitReached(eventName: old.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
            #expect(state.markLimitReached(eventName: replacement.eventName, dayKey: day))
            #expect(state.restrictedTokenData(dayKey: day) == [Data([2])])
        }
    }

    @Test("対象から外したアプリは古い通知で再制限せず、再選択でも旧到達を復活させない")
    func removingAppInvalidatesThreshold() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit()]).first)
            #expect(state.markLimitReached(eventName: old.eventName, dayKey: day))
            state.updateLimits([])
            #expect(!state.markLimitReached(eventName: old.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)

            let selected = try #require(state.updateLimits([limit()]).first)
            #expect(selected.eventName != old.eventName)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
        }
    }

    @Test("上限を識別できない旧形式の到達記録とイベントは無視する")
    func ignoresLegacyLimitReachedRecord() throws {
        try withState { state in
            state.defaults.set([day: ["app"]], forKey: "limitReached")
            state.updateLimits([limit()])
            #expect(!state.markLimitReached(eventName: "limit.app", dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
        }
    }

    @Test("利用枠が有効なら日次到達通知や監視の再登録でもShieldせず、枠終了時に再制限する")
    func activeGrantTakesPriorityOverDailyThreshold() throws {
        try withState { state in
            let registered = try #require(state.updateLimits([limit()]).first)
            state.updateGrants([grant()])
            #expect(state.markLimitReached(eventName: registered.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]) == ["app"])
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
            state.updateLimits([limit()])
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)

            #expect(state.endGrant(id: "grant", dayKey: day))
            #expect(state.endedGrantIDs == ["grant"])
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            #expect(!state.endGrant(id: "grant", dayKey: day))
            #expect(state.endedGrantIDs == ["grant"])
        }
    }

    @Test("古い利用枠の通知は新しい利用枠を終了・制限しない")
    func staleGrantDoesNotOverrideNewGrant() throws {
        try withState { state in
            let registered = try #require(state.updateLimits([limit()]).first)
            #expect(state.markLimitReached(eventName: registered.eventName, dayKey: day))
            state.updateGrants([grant(id: "old")])
            state.updateGrants([grant(id: "new")])
            #expect(!state.endGrant(id: "old", dayKey: day))
            #expect(!state.endGrant(id: "unknown", dayKey: day))
            #expect(state.endedGrantIDs.isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)

            #expect(state.endGrant(id: "new", dayKey: day))
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            state.updateGrants([])
            #expect(!state.endGrant(id: "new", dayKey: day))
        }
    }

    @Test("朝4時で日付が変わった後は旧日の利用枠通知を拒否し、当日未達のアプリをShieldしない")
    func previousDayGrantCannotRestrictNewDay() throws {
        try withState { state in
            let previous = "2026-10-18"
            let registered = try #require(state.updateLimits([limit(dayKey: previous)]).first)
            #expect(state.markLimitReached(eventName: registered.eventName, dayKey: previous))
            state.updateGrants([grant(dayKey: previous)])
            let current = try #require(state.limits(on: day).first)
            #expect(current.dayKey == day)
            #expect(current.eventName != registered.eventName)
            #expect(!state.endGrant(id: "grant", dayKey: day))
            #expect(state.endedGrantIDs.isEmpty)
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
        }
    }

    @Test("利用枠中に上限を引き上げた場合、枠終了だけでは新上限未達のアプリをShieldしない")
    func grantEndingAfterLimitIncreaseDoesNotRestrict() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit()]).first)
            #expect(state.markLimitReached(eventName: old.eventName, dayKey: day))
            state.updateGrants([grant()])
            state.updateLimits([limit(seconds: 3600)])
            #expect(state.endGrant(id: "grant", dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 3600]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
        }
    }

    @Test("0分の対象は日次通知なしで制限し、当日の利用枠だけで解除する")
    func zeroLimitRespectsGrantAndDayBoundary() throws {
        try withState { state in
            let zero = try #require(state.updateLimits([limit(seconds: 0)]).first)
            #expect(!state.markLimitReached(eventName: zero.eventName, dayKey: day))
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            state.updateGrants([grant()])
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
            #expect(state.endGrant(id: "grant", dayKey: day))
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            #expect(state.limits(on: "2026-10-20").first?.seconds == 0)
            #expect(state.restrictedTokenData(dayKey: "2026-10-20") == [token])
        }
    }

    @Test("朝4時に前日分の追加時間が消え、基準上限0分のアプリは本体なしでも制限する")
    func newDayRestoresZeroBaseLimitWithoutMutatingSettings() throws {
        try withState { state in
            let previous = "2026-10-18"
            let old = try #require(state.updateLimits([limit(seconds: 300, baseSeconds: 0, dayKey: previous)]).first)
            state.updateGrants([grant(dayKey: previous)])
            #expect(state.restrictedTokenData(dayKey: previous).isEmpty)

            let current = try #require(state.limits(on: day).first)
            #expect(current.seconds == 0)
            #expect(current.baseSeconds == 0)
            #expect(current.dayKey == day)
            #expect(current.eventName != old.eventName)
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            #expect(state.limits == [old])
        }
    }

    @Test("朝4時に前日の追加5分を取り除き、基準上限30分へ戻す")
    func newDayRemovesPreviousDayExtraTimeWithoutMutatingSettings() throws {
        try withState { state in
            let previous = "2026-10-18"
            let old = try #require(state.updateLimits([limit(seconds: 2100, baseSeconds: 1800, dayKey: previous)]).first)
            #expect(state.markLimitReached(eventName: old.eventName, dayKey: previous))

            let current = try #require(state.limits(on: day).first)
            #expect(current.seconds == 1800)
            #expect(current.baseSeconds == 1800)
            #expect(current.dayKey == day)
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
            #expect(state.markLimitReached(eventName: current.eventName, dayKey: day))
            #expect(state.restrictedTokenData(dayKey: day) == [token])
            #expect(state.limits == [old])
        }
    }

    @Test("日替わり後に届いた前日の日次イベントは当日の上限到達として扱わない")
    func previousDayDailyEventIsRejected() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit(dayKey: "2026-10-18")]).first)
            // 区間開始より先に通知されても、前日の条件で当日に到達したと記録しない。
            #expect(!state.markLimitReached(eventName: old.eventName, dayKey: day))
            let current = try #require(state.limits(on: day).first)
            #expect(current.eventName != old.eventName)
            #expect(!state.markLimitReached(eventName: old.eventName, dayKey: day))
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]).isEmpty)
            #expect(state.restrictedTokenData(dayKey: day).isEmpty)
            #expect(state.limits == [old])
        }
    }

    @Test("同じ日の有効条件を繰り返し取得してもイベント名と当日の到達記録を維持する")
    func repeatedDayDerivationPreservesCurrentDayThreshold() throws {
        try withState { state in
            let old = try #require(state.updateLimits([limit(seconds: 2100, baseSeconds: 1800, dayKey: "2026-10-18")]).first)
            let current = try #require(state.limits(on: day).first)
            #expect(state.markLimitReached(eventName: current.eventName, dayKey: day))
            #expect(state.limits(on: day) == [current])
            #expect(state.limits == [old])
            #expect(state.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]) == ["app"])
            #expect(state.restrictedTokenData(dayKey: day) == [token])
        }
    }

    @Test("別のUserDefaultsインスタンスから監視条件・到達・利用枠終了を復元できる")
    func restoresStateAcrossDefaultsInstances() throws {
        let suite = "monitor-state-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = ScreenTimeMonitorState(defaults: defaults)
        let registered = try #require(state.updateLimits([limit()]).first)
        #expect(state.markLimitReached(eventName: registered.eventName, dayKey: day))
        state.updateGrants([grant()])

        let restored = ScreenTimeMonitorState(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(restored.limits == [registered])
        #expect(restored.limitReachedIDs(dayKey: day, expectedLimits: ["app": 1800]) == ["app"])
        #expect(restored.restrictedTokenData(dayKey: day).isEmpty)
        #expect(restored.endGrant(id: "grant", dayKey: day))

        let afterEnd = ScreenTimeMonitorState(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(afterEnd.endedGrantIDs == ["grant"])
        #expect(!afterEnd.endGrant(id: "grant", dayKey: day))
        #expect(afterEnd.restrictedTokenData(dayKey: day) == [token])
    }

    private func limit(id: String = "app", token: Data = Data([1]), seconds: Int = 1800,
                       baseSeconds: Int? = nil, dayKey: String = "2026-10-19") -> ScreenTimeMonitorState.Limit {
        .init(snsID: id, tokenData: token, seconds: seconds, baseSeconds: baseSeconds ?? seconds, dayKey: dayKey)
    }

    private func grant(id: String = "grant", dayKey: String = "2026-10-19") -> ScreenTimeMonitorState.Grant {
        .init(id: id, tokenData: token, dayKey: dayKey)
    }

    private func withState(_ body: (ScreenTimeMonitorState) throws -> Void) throws {
        let suite = "monitor-state-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(ScreenTimeMonitorState(defaults: defaults))
    }
}
