import Observation
import SwiftUI

/// 画面遷移。ナビゲーションバーは使わず、各画面が ScreenHeader 等で戻る操作を持つ。
enum Route: Hashable {
    // 設定
    case settings
    case settingsSNSTime
    case settingsSNSAdd
    case settingsLists
    case settingsRules
    case snsLimit(snsID: String)
    // 制限と対話
    case shield(snsID: String)
    case taskSelect(origin: Origin)
    case persuasion(snsID: String)
    case grantEnded(snsID: String)
    // 取り組み
    case focus(sessionID: UUID)
    case reflection(sessionID: UUID)
}

enum MainTab: Hashable { case home, usage }

@Observable
final class Router {
    var path: [Route] = []
    var tab: MainTab = .home

    func push(_ r: Route) { path.append(r) }

    func pop() { if !path.isEmpty { path.removeLast() } }

    func popToRoot() { path.removeAll() }

    /// 一番上の画面を置き換える（戻るで前の状態に戻らないように）
    func replaceTop(with r: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(r)
    }

    /// OSのShieldから本体を開いたときの遷移。対象と現在の制限状態を本体側で再確認する。
    func openShieldFromSystem(_ snsID: String, store: AppStore) {
        guard let app = store.sns(snsID), app.isSelected, app.tokenData != nil,
              store.isRestricted(snsID) else { return }
        tab = .home
        path = [.shield(snsID: snsID)]
    }

    /// 起点に応じて閉じる。ホーム起点ならホームへ、Shield起点なら制限画面へ戻す（U03）
    func close(origin: Origin) {
        switch origin {
        case .home:
            popToRoot()
        case .shield(let id):
            if let i = path.lastIndex(of: .shield(snsID: id)) {
                path.removeSubrange((i + 1)...)
            } else {
                path = [.shield(snsID: id)]
            }
        }
    }
}
