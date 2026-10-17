import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        Group {
            if store.settings.onboardingCompleted {
                NavigationStack(path: $router.path) {
                    MainTabView()
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Route.self) { route in
                            destination(route)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                }
            } else {
                OnboardingFlowView()
            }
        }
        .task {
            await refresh()
            #if DEBUG
            DebugLaunch.apply(store: store, router: router)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // 復帰時に最新のやること・日付の切替を照合する
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        store.rolloverIfNeeded()
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs, useDemo: store.settings.useDemoTasks)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .settings: SettingsView()
        case .settingsSNSTime: SettingsSNSTimeView()
        case .settingsSNSAdd: SNSAddView()
        case .settingsLists: ReminderListSettingsView()
        case .settingsRules: RulesView()
        case .settingsScreenTime: ScreenTimeSettingsView()
        case .snsLimit(let id): SNSLimitView(snsID: id)
        case .shield(let id): ShieldView(snsID: id)
        case .taskSelect(let origin): TaskSelectView(origin: origin)
        case .persuasion(let id): PersuasionView(snsID: id)
        case .grantEnded(let id): GrantEndedView(snsID: id)
        case .focus(let id): FocusView(sessionID: id)
        case .reflection(let id): ReflectionView(sessionID: id)
        case .demoSNS(let id): DemoSNSView(snsID: id)
        }
    }
}

/// 下部の「やること」「使用時間」タブ（Figmaのボトムバー）
struct MainTabView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch router.tab {
                case .home: HomeView()
                case .usage: UsageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .screenBackground()
    }

    private var bottomBar: some View {
        HStack {
            tabButton(.home, title: "やること", icon: "checklist")
            tabButton(.usage, title: "使用時間", icon: "chart.bar.fill")
        }
        .padding(.top, 10)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(_ tab: MainTab, title: String, icon: String) -> some View {
        Button {
            router.tab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(router.tab == tab ? Theme.brown : Theme.textSecondary.opacity(0.6))
            .frame(maxWidth: .infinity)
        }
    }
}
