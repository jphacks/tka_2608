import Foundation

enum InstagramDemo {
    static let snsID = "instagram"
    static let instagramURL = URL(string: "instagram://app")!
}

#if TODOMERU_PERSONAL_DEMO
import AppIntents

/// 許可中はInstagramに留まるため、画面を開く前に確認する。
struct CheckInstagramDemoShieldIntent: AppIntent {
    static var title: LocalizedStringResource = "Instagramのデモ制限を確認"
    static var supportedModes: IntentModes { .background }
    @Dependency private var store: AppStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        store.rolloverIfNeeded()
        guard let app = store.sns(InstagramDemo.snsID), app.isSelected, app.tokenData == nil else {
            return .result(value: false)
        }
        return .result(value: store.isRestricted(app.id))
    }
}

/// URL・引数なしで前面へ移り、既存の画面遷移へ固定IDを渡す。
struct OpenInstagramDemoShieldIntent: AppIntent {
    static var title: LocalizedStringResource = "Instagramの制限画面を開く"
    static var supportedModes: IntentModes { .foreground }
    @Dependency private var store: AppStore
    @Dependency private var router: Router

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = store.sns(InstagramDemo.snsID), app.isSelected, app.tokenData == nil else { return .result() }
        // Instagramから再び切り替えても、進行中の会話・取り組みを破棄しない。
        guard !router.path.contains(where: {
            switch $0 {
            case .persuasion, .taskSelect, .focus, .reflection: return true
            default: return false
            }
        }) else { return .result() }
        router.tab = .home
        router.path = [.shield(snsID: InstagramDemo.snsID)]
        return .result()
    }
}
#endif
