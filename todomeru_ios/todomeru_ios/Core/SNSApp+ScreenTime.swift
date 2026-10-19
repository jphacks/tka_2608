import FamilyControls
import Foundation
import ManagedSettings

/// iOS標準のアプリ選択（FamilyActivityPicker）で選んだアプリと、アプリ一覧の対応
extension SNSApp {
    var applicationToken: ApplicationToken? {
        tokenData.flatMap { try? JSONDecoder().decode(ApplicationToken.self, from: $0) }
    }

    /// 標準機能で選んだアプリから作るアプリ。名前はアプリから読めないため空（表示は Label(token) で行う）
    static func picked(_ token: ApplicationToken) -> SNSApp? {
        guard let data = try? JSONEncoder().encode(token) else { return nil }
        return SNSApp(
            id: "app-\(UUID().uuidString)",
            name: "",
            symbol: "app.fill",
            tintHex: 0xA0602A,
            isSelected: true,
            dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds,
            tokenData: data
        )
    }
}

extension AppStore {
    /// 標準機能で選んだアプリ（選択中のもの）のトークン
    var pickedTokens: Set<ApplicationToken> {
        Set(snsApps.filter(\.isSelected).compactMap(\.applicationToken))
    }

    /// ピッカーの選択結果をアプリ一覧へ反映する。既存のアプリは上限を保ち、外したアプリは選択を外すだけにする
    func syncPickedApps(_ tokens: Set<ApplicationToken>) {
        var apps = snsApps
        var known = Set<ApplicationToken>()
        for i in apps.indices {
            guard let token = apps[i].applicationToken else { continue }
            known.insert(token)
            apps[i].isSelected = tokens.contains(token)
        }
        for token in tokens.subtracting(known) {
            if let app = SNSApp.picked(token) { apps.append(app) }
        }
        snsApps = apps
    }

    /// いま制限すべき、標準機能で選んだアプリ（上限に達し、一時利用枠がないもの）
    var restrictedPickedTokens: Set<ApplicationToken> {
        Set(snsApps.filter { $0.isSelected && isRestricted($0.id) }.compactMap(\.applicationToken))
    }
}

extension AppStore {
    /// Monitor拡張の記録（上限到達・一時利用枠の終了）を取り込む。起動・復帰時と定期的に呼ぶ
    func reconcileWithMonitor() {
        #if !TODOMERU_PERSONAL_DEMO
        // 別プロセスのMonitorが書いた記録を、画面遷移や制限同期より先に読む。
        SharedScreenTime.defaults.synchronize()
        let reached = SharedScreenTime.monitorState.limitReachedIDs(
            dayKey: AppDay.key(), expectedLimits: monitoredLimits.reduce(into: [:]) { $0[$1.snsID] = $1.limitSeconds }
        )
        if reached != monitorLimitReached { monitorLimitReached = reached }
        endGrants(ids: SharedScreenTime.monitorState.endedGrantIDs)
        #endif
    }

    /// 日次監視にもReportと同じ総上限（今日の一時利用枠を含む）を渡す。
    var monitoredLimits: [ScreenTimeService.MonitoredLimit] {
        snsApps.filter(\.isSelected).compactMap { app in
            guard let data = app.tokenData, let token = app.applicationToken else { return nil }
            return .init(snsID: app.id, token: token, tokenData: data, limitSeconds: totalLimitToday(app.id),
                         baseLimitSeconds: app.dailyLimitSeconds)
        }
    }

    /// 有効な一時利用枠のうち、標準機能で選んだアプリのもの
    var activePickedGrants: [ScreenTimeService.MonitoredGrant] {
        grants.filter { $0.status == .active }.compactMap { g in
            guard let app = sns(g.snsID), let data = app.tokenData else { return nil }
            return .init(grantID: g.id, tokenData: data, seconds: g.remainingSeconds, dayKey: g.dayKey)
        }
    }
}
