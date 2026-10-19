import Foundation
import Testing
@testable import todomeru_ios

/// 標準機能で選んだアプリ（トークンあり）と Monitor 拡張の記録に関わる AppStore の判定
@Suite("AppStore と Monitor 拡張の連動")
struct ScreenTimeStoreTests {
    #if !TODOMERU_PERSONAL_DEMO
    @Test("通常版では固定候補を0分にしても実アプリの設定行として表示しない")
    func excludesCatalogFromRealAppSelection() {
        withTemporaryStore { store in
            // 旧版から保存されている固定候補を残しても、実アプリを選んだ扱いにしない。
            store.setDailyLimit(0, for: "instagram")
            #expect(store.isRestricted("instagram"))
            #expect(store.selectedSNS.isEmpty)
            #expect(store.monitoredLimits.isEmpty)
            #expect(store.restrictedPickedTokens.isEmpty)
            #expect(store.sns("instagram") != nil)
        }
    }

    @Test("読めないトークンの保存項目も実アプリの設定行として表示しない")
    func excludesUnreadableTokenFromRealAppSelection() {
        withTemporaryStore { store in
            _ = addPickedApp(store)
            #expect(store.selectedSNS.isEmpty)
        }
    }

    @Test("使用済みの一時利用枠は、基本上限を変更した後も今日の総上限に含む")
    func totalLimitIncludesConsumedGrantAfterLimitChange() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.setDailyLimit(30 * 60, for: id)
            let grant = store.issueGrant(snsID: id, seconds: 5 * 60, source: .persuasion)
            store.endGrants(ids: [grant.id.uuidString])

            store.setDailyLimit(60 * 60, for: id)
            #expect(store.effectiveLimit(id) == 60 * 60)
            // Reportへの入力と日次監視は、ともにこの総上限を使う。
            #expect(store.totalLimitToday(id) == 65 * 60)
            #expect(SNSUsageStatus.make(id, store: store).limitSeconds == 65 * 60)
        }
    }

    @Test("基本上限0分でも、重なる利用枠の終了だけでは総上限未達のアプリを再制限しない")
    func overlappingGrantsEndBeforeTotalLimit() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.setDailyLimit(0, for: id)
            let first = store.issueGrant(snsID: id, seconds: 60, source: .reward)
            let second = store.issueGrant(snsID: id, seconds: 120, source: .reward)
            store.endGrants(ids: [first.id.uuidString, second.id.uuidString])

            #expect(store.totalLimitToday(id) == 180)
            #expect(store.activeGrant(id) == nil)
            #expect(store.monitorLimitReached.isEmpty)
            #expect(!store.isOverLimit(id))
            #expect(!store.isRestricted(id))

            store.monitorLimitReached = [id]
            #expect(store.isRestricted(id))
        }
    }

    @Test("実アプリの制限判定に保存済みのデモ使用量を混ぜない")
    func ignoresLegacyDemoUsageForRealApp() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.setDemoUsage(45 * 60, for: id)
            #expect(store.usageToday(id) > store.totalLimitToday(id))
            #expect(!store.isOverLimit(id))
            #expect(!store.isRestricted(id))

            store.monitorLimitReached = [id]
            #expect(store.isRestricted(id))
        }
    }

    @Test("日次の総上限到達前でも、有効な一時利用枠の案内を表示する")
    func showsActiveGrantBeforeDailyThreshold() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            let grant = store.issueGrant(snsID: id, seconds: 60, source: .persuasion)
            #expect(!store.isOverLimit(id))
            #expect(SNSUsageStatus.make(id, store: store).state == .granted(remainingSeconds: grant.remainingSeconds))
        }
    }
    #endif

    /// トークンの中身は判定に使わないので、ダミーのデータで「標準機能で選んだアプリ」を作る
    private func addPickedApp(_ store: AppStore, id: String = "app-test") -> String {
        store.snsApps.append(SNSApp(id: id, name: "", symbol: "app.fill", tintHex: 0, isSelected: true,
                                    dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds, tokenData: Data([1])))
        return id
    }

    @Test("上限0分はすぐ制限し、一時利用枠の追加後は総上限への到達で再制限する")
    func zeroLimitWithoutMonitorRecord() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.setDailyLimit(0, for: id)
            #expect(store.effectiveLimit(id) == 0)
            #expect(store.monitorLimitReached.isEmpty)
            #expect(store.isRestricted(id))
            let grant = store.issueGrant(snsID: id, seconds: 60, source: .persuasion)
            #expect(!store.isRestricted(id))
            store.endGrants(ids: [grant.id.uuidString])
            store.monitorLimitReached = [id]
            #expect(store.isRestricted(id))
        }
    }

    @Test("Monitor拡張が上限到達を記録したアプリは、デモの使用時間が0でも制限中")
    func monitorRecordRestricts() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            #expect(!store.isRestricted(id))
            store.monitorLimitReached = [id]
            #expect(store.isRestricted(id))
        }
    }

    @Test("一時利用枠があれば、Monitorの記録があっても制限しない。拡張が枠を終えたら再び制限")
    func grantEndedByMonitor() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.monitorLimitReached = [id]
            let grant = store.issueGrant(snsID: id, seconds: PolicyConstants.persuasionGrantMinSeconds, source: .persuasion)
            #expect(!store.isRestricted(id))
            store.endGrants(ids: [grant.id.uuidString])
            #expect(store.activeGrant(id) == nil)
            #expect(store.isRestricted(id))
        }
    }

    @Test("未使用の一時利用枠は時間経過だけでは減らず、次の朝4時に失効する")
    func unusedGrantLastsUntilDayBoundary() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.monitorLimitReached = [id]
            let seconds = PolicyConstants.persuasionGrantMinSeconds
            let grant = store.issueGrant(snsID: id, seconds: seconds, source: .persuasion)
            let dayEnd = AppDay.interval(of: grant.createdAt).end

            store.rolloverIfNeeded(now: dayEnd.addingTimeInterval(-1))
            #expect(store.activeGrant(id)?.remainingSeconds == seconds)
            #expect(!store.isRestricted(id))

            store.rolloverIfNeeded(now: dayEnd)
            #expect(store.activeGrant(id) == nil)
            #expect(store.lastEndedGrant(id)?.id == grant.id)
        }
    }

}
