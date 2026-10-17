import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button("はじめる（仮）") { store.settings.useDemoTasks = true; store.settings.onboardingCompleted = true }
    }
}
