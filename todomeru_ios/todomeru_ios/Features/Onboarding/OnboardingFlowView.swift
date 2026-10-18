import SwiftUI

/// 初回設定（Figma 64:2 → 64:115 → 67:2 → 64:225 → 64:395）
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @State private var vm = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(step: vm.step, onBack: vm.step == .welcome ? nil : { vm.goBack() })
            stepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(vm.step)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.step)
        .screenBackground()
    }

    @ViewBuilder
    private var stepView: some View {
        switch vm.step {
        case .welcome: WelcomeStepView { vm.goNext() }
        case .permissions: PermissionsStepView(vm: vm)
        case .lists: ListsStepView(vm: vm)
        case .sns: SNSStepView(vm: vm)
        case .ready: ReadyStepView(vm: vm)
        }
    }
}

// MARK: - 共通部品

/// 上部の「< 戻る」と5段階の進捗
struct OnboardingTopBar: View {
    var step: OnboardingStep
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            OnboardingProgress(current: step.rawValue, total: OnboardingStep.allCases.count)
            HStack {
                if let onBack { BackLink(title: "戻る", action: onBack) }
                Spacer()
            }
        }
        .padding(.horizontal, SettingsMetrics.gutter)
        .frame(height: 44)
    }
}

struct OnboardingProgress: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Theme.antGold : Theme.progressInactive)
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(total)段階中\(current + 1)段階目")
    }
}

/// スクロールする本文と、下部に固定したボタン
struct OnboardingStepScaffold<Content: View>: View {
    var buttonTitle: String
    var isEnabled: Bool = true
    var action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, SettingsMetrics.gutter)
                .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: buttonTitle, isEnabled: isEnabled, action: action)
        }
    }
}

/// アリと見出し・説明（Figma 64:115 / 67:2 の上部）
struct AntIntroHeader: View {
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AntFace(stage: 4, size: SettingsMetrics.introCharacterSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SettingsMetrics.stepTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(SettingsMetrics.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
