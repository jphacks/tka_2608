import Foundation
import Testing
@testable import todomeru_ios

/// 標準機能で選んだアプリ（トークンあり）と Monitor 拡張の記録に関わる AppStore の判定
@Suite("AppStore と Monitor 拡張の連動")
struct ScreenTimeStoreTests {
    /// トークンの中身は判定に使わないので、ダミーのデータで「標準機能で選んだアプリ」を作る
    private func addPickedApp(_ store: AppStore, id: String = "app-test") -> String {
        store.snsApps.append(SNSApp(id: id, name: "", symbol: "app.fill", tintHex: 0, isSelected: true,
                                    dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds, tokenData: Data([1])))
        return id
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
