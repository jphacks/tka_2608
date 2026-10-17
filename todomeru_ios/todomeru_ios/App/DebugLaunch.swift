#if DEBUG
import Foundation

/// 確認用の起動引数（Debugビルドのみ）。
/// 例: `-debugRoute shield:x` / `-debugRoute usage` / `-debugRoute persuasion:x -debugMessage "ゼミの連絡が…"`
enum DebugLaunch {
    static func apply(store: AppStore, router: Router) {
        guard let value = UserDefaults.standard.string(forKey: "debugRoute") else { return }
        let parts = value.split(separator: ":").map(String.init)
        let arg = parts.count > 1 ? parts[1] : "x"
        switch parts.first {
        case "usage": router.tab = .usage
        case "settings": router.push(.settings)
        case "shield":
            store.setDemoUsage(store.effectiveLimit(arg), for: arg)
            router.push(.shield(snsID: arg))
        case "persuasion":
            if let message = UserDefaults.standard.string(forKey: "debugMessage") {
                PersuasionDraft.set(message, for: arg)
            }
            router.push(.persuasion(snsID: arg))
        case "taskSelect": router.push(.taskSelect(origin: .home))
        case "demoSNS": router.push(.demoSNS(snsID: arg))
        default: break
        }
    }
}
#endif
