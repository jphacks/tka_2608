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
    #endif

    /// トークンの中身は判定に使わないので、ダミーのデータで「標準機能で選んだアプリ」を作る
    private func addPickedApp(_ store: AppStore, id: String = "app-test") -> String {
        store.snsApps.append(SNSApp(id: id, name: "", symbol: "app.fill", tintHex: 0, isSelected: true,
                                    dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds, tokenData: Data([1])))
        return id
    }

    @Test("上限0分はMonitorの通知を待たず制限中になり、有効な一時利用枠だけを優先する")
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

    @Test("時計による保険は、枠の秒数＋猶予を過ぎるまで枠を終えない")
    func clockGrace() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            let seconds = PolicyConstants.persuasionGrantMinSeconds
            let grant = store.issueGrant(snsID: id, seconds: seconds, source: .persuasion)
            let justBefore = grant.createdAt.addingTimeInterval(Double(seconds + PolicyConstants.grantClockGraceSeconds - 1))
            store.expireGrantsByClock(now: justBefore)
            #expect(store.activeGrant(id) != nil)
            store.expireGrantsByClock(now: justBefore.addingTimeInterval(1))
            #expect(store.activeGrant(id) == nil)
        }
    }

    @Test("デモの候補（トークンなし）の枠は、時計では終えない")
    func clockIgnoresCatalogApps() {
        withTemporaryStore { store in
            let catalogID = SNSApp.catalog[0].id
            let grant = store.issueGrant(snsID: catalogID, seconds: PolicyConstants.persuasionGrantMinSeconds, source: .persuasion)
            store.expireGrantsByClock(now: grant.createdAt.addingTimeInterval(24 * 3600))
            #expect(store.activeGrant(catalogID) != nil)
        }
    }
}
