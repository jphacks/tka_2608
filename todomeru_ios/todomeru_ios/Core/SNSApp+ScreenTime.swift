import FamilyControls
import Foundation
import ManagedSettings

/// iOS標準のアプリ選択（FamilyActivityPicker）で選んだアプリと、SNS一覧の対応
extension SNSApp {
    var applicationToken: ApplicationToken? {
        tokenData.flatMap { try? JSONDecoder().decode(ApplicationToken.self, from: $0) }
    }

    /// 標準機能で選んだアプリから作るSNS。名前はアプリから読めないため空（表示は Label(token) で行う）
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

    /// ピッカーの選択結果をSNS一覧へ反映する。既存のアプリは上限を保ち、外したアプリは選択を外すだけにする
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

    /// いま制限すべき、標準機能で選んだアプリ（疑似の使用時間で上限に達し、一時利用枠がないもの）
    var restrictedPickedTokens: Set<ApplicationToken> {
        Set(snsApps.filter { $0.isSelected && isRestricted($0.id) }.compactMap(\.applicationToken))
    }
}
