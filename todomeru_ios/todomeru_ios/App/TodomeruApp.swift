import SwiftUI
#if TODOMERU_PERSONAL_DEMO
import AppIntents
#endif

@main
struct TodomeruApp: App {
    @State private var store: AppStore
    @State private var reminders = ReminderService()
    @State private var router: Router
    @State private var screenTime = ScreenTimeService()
    @State private var ai: AIProvider = .makeDefault()

    init() {
        let store = AppStore()
        let router = Router()
        _store = State(initialValue: store)
        _router = State(initialValue: router)
        #if TODOMERU_PERSONAL_DEMO
        AppDependencyManager.shared.add(dependency: store)
        AppDependencyManager.shared.add(dependency: router)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminders)
                .environment(router)
                .environment(screenTime)
                .environment(ai)
                .tint(Theme.brown)
                .preferredColorScheme(.light)
        }
    }
}
