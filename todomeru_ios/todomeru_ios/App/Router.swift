import Observation
import SwiftUI

/// 画面遷移。ナビゲーションバーは使わず、各画面が ScreenHeader 等で戻る操作を持つ。
enum Route: Hashable {
    // 設定
    case settings
    case settingsSNSTime
    case settingsLists
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

    /// OSのShieldから相談チャットを直接開く。対象と現在の制限状態を本体側で再確認する。
    func openShieldFromSystem(_ snsID: String, store: AppStore) {
        guard let app = store.sns(snsID), app.isSelected, app.tokenData != nil,
              store.isRestricted(snsID) else { return }
        // 同じ対象の相談や取り組みを、重複したOS要求で作り直さない。
        guard !path.contains(where: { route in
            switch route {
            case .persuasion(let id): return id == snsID
            case .taskSelect(let origin): return origin.snsID == snsID
            case .focus(let id), .reflection(let id): return store.session(id)?.origin.snsID == snsID
            default: return false
            }
        }) else { return }
        tab = .home
        path = [.persuasion(snsID: snsID)]
    }

    /// 既存のアプリ内制限画面があるときだけ戻す。OSから直接開いた場合はホームへ。
    func close(origin: Origin) {
        switch origin {
        case .home:
            popToRoot()
        case .shield(let id):
            if let i = path.lastIndex(of: .shield(snsID: id)) {
                path.removeSubrange((i + 1)...)
            } else {
                popToRoot()
            }
        }
    }
}
