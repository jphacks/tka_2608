import SwiftUI

@main
struct TodomeruApp: App {
    @State private var store = AppStore()
    @State private var reminders = ReminderService()
    @State private var router = Router()
    @State private var ai: AIProvider = .makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminders)
                .environment(router)
                .environment(ai)
                .tint(Theme.brown)
                .preferredColorScheme(.light)
        }
    }
}
