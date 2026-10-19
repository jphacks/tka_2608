import Foundation
import Testing
@testable import todomeru_ios

@Suite("OSのShieldから本体への遷移")
@MainActor
struct ShieldPresentationTests {
    @Test("拡張の要求を本体側の別インスタンスで一度だけ受け取る")
    func takesRequestOnce() throws {
        try withInbox { defaults in
            let now = makeDate(2026, 10, 19, 12)
            #expect(ShieldPresentationInbox(defaults: defaults).request(snsID: "app-test", now: now))
            let reader = ShieldPresentationInbox(defaults: defaults)
            #expect(reader.take(now: now.addingTimeInterval(1)) == "app-test")
            #expect(reader.take(now: now.addingTimeInterval(2)) == nil)
        }
    }

    @Test("空の対象は要求できない")
    func ignoresEmptyID() throws {
        try withInbox { defaults in
            let inbox = ShieldPresentationInbox(defaults: defaults)
            #expect(!inbox.request(snsID: ""))
            #expect(inbox.take() == nil)
        }
    }

    @Test("5分を過ぎた要求と未来時刻の要求は使わない")
    func ignoresStaleAndFutureRequests() throws {
        try withInbox { defaults in
            let now = makeDate(2026, 10, 19, 12)
            let inbox = ShieldPresentationInbox(defaults: defaults)
            inbox.request(snsID: "app-test", now: now)
            #expect(inbox.take(now: now.addingTimeInterval(301)) == nil)
            inbox.request(snsID: "app-test", now: now.addingTimeInterval(1))
            #expect(inbox.take(now: now) == nil)
            #expect(inbox.take(now: now.addingTimeInterval(1)) == nil)
        }
    }

    @Test("朝4時の日付切替前の要求は引き継がない")
    func ignoresPreviousDayRequest() throws {
        try withInbox { defaults in
            let atBoundary = boundary(2026, 10, 19)
            let inbox = ShieldPresentationInbox(defaults: defaults)
            inbox.request(snsID: "app-test", now: atBoundary.addingTimeInterval(-1))
            #expect(inbox.take(now: atBoundary) == nil)
        }
    }

    @Test("Monitorで制限された対象の相談チャットを開き、制限や利用枠を変更しない")
    func opensRestrictedApp() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.monitorLimitReached = [id]
            let router = Router()
            router.path = [.settings]
            router.openShieldFromSystem(id, store: store)
            #expect(router.path == [.persuasion(snsID: id)])
            #expect(store.isRestricted(id))
            #expect(store.activeGrant(id) == nil)
            router.openShieldFromSystem(id, store: store)
            #expect(router.path.count == 1)
        }
    }

    @Test("一時利用中・選択解除済み・未知の対象では相談チャットへ遷移しない")
    func ignoresUnrestrictedTargets() {
        withTemporaryStore { store in
            let id = addPickedApp(store)
            store.monitorLimitReached = [id]
            let router = Router()
            let grant = store.issueGrant(snsID: id, seconds: 60, source: .persuasion)
            router.openShieldFromSystem(id, store: store)
            #expect(router.path.isEmpty)
            store.endGrants(ids: [grant.id.uuidString])
            let index = store.snsApps.firstIndex { $0.id == id }!
            store.snsApps[index].isSelected = false
            router.openShieldFromSystem(id, store: store)
            router.openShieldFromSystem("unknown", store: store)
            #expect(router.path.isEmpty)
        }
    }

    private func addPickedApp(_ store: AppStore) -> String {
        let id = "app-test"
        store.snsApps.append(SNSApp(id: id, name: "", symbol: "app.fill", tintHex: 0, isSelected: true,
                                   dailyLimitSeconds: 60, tokenData: Data([1])))
        return id
    }

    private func withInbox(_ body: (UserDefaults) -> Void) throws {
        let name = "todomeru-shield-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
