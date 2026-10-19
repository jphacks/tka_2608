import SwiftUI
import UIKit

/// ホームの「今日」「すべて」
enum HomeTab: String, CaseIterable, Identifiable {
    case today = "今日"
    case all = "すべて"
    var id: String { rawValue }
}

/// ホームの一覧に出す行（表示用に整えた値）
struct HomeTaskRow: Identifiable, Equatable {
    var id: String
    var task: TaskItem
    var title: String
    var detail: String
    /// 期限が今日・期限切れのとき、詳細をオレンジ文字にする
    var isDetailEmphasized = false
    var isDone: Bool
}

/// 一覧の中身（TaskFilterの結果を行と件数表示へ変換する純粋な関数）
struct HomeTaskSection {
    var rows: [HomeTaskRow]
    var countLabel: String

    static func make(tab: HomeTab, tasks: [TaskItem], now: Date = .now) -> HomeTaskSection {
        switch tab {
        case .today:
            let r = TaskFilter.today(tasks, now: now)
            let rows = r.open.map { openRow($0, now: now) } + r.done.map { doneRow($0) }
            return HomeTaskSection(rows: rows, countLabel: "\(r.done.count) / \(r.open.count + r.done.count) 完了")
        case .all:
            let open = TaskFilter.all(tasks)
            return HomeTaskSection(rows: open.map { allRow($0, now: now) }, countLabel: "未完了 \(open.count)件")
        }
    }

    private static func openRow(_ t: TaskItem, now: Date) -> HomeTaskRow {
        HomeTaskRow(id: t.id, task: t, title: t.title, detail: TaskFilter.dueLabel(t, now: now), isDone: false)
    }

    /// 「すべて」の行は「10/21（火）・あと4日」形式
    private static func allRow(_ t: TaskItem, now: Date) -> HomeTaskRow {
        let due = HomeDueLabel.make(t, now: now)
        return HomeTaskRow(id: t.id, task: t, title: t.title, detail: due.text, isDetailEmphasized: due.isEmphasized, isDone: false)
    }

    private static func doneRow(_ t: TaskItem) -> HomeTaskRow {
        let time = t.completionDate.map { "\($0.formatted(.dateTime.hour().minute())) に完了" } ?? "完了"
        return HomeTaskRow(id: t.id, task: t, title: t.title, detail: time, isDone: true)
    }
}

// MARK: - 画面

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(Router.self) private var router

    @State private var tab: HomeTab = .today
    @State private var taskToStart: TaskItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                TabScreenTitle(title: "やること")
                SummaryPanel()
                if let active = store.activeSession {
                    ActiveSessionBanner(session: active) {
                        router.push(.focus(sessionID: active.id))
                    }
                }
                taskHeader
                taskContent
            }
            .padding(.horizontal, HomeLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .refreshable { await reload() }
        .screenBackground()
    }

    private var taskHeader: some View {
        HStack {
            HomeSegment(selection: $tab)
            Spacer()
            if reminders.state == .loaded {
                Text(HomeTaskSection.make(tab: tab, tasks: reminders.tasks).countLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        switch reminders.state {
        case .idle, .loading:
            TaskStateCard(icon: nil, message: "やることを読み込んでいます…")
        case .failed(let message):
            TaskStateCard(icon: "exclamationmark.triangle", message: "やることを取得できませんでした。\n\(message)") {
                Button("もう一度読み込む") { Task { await reload() } }
                    .buttonStyle(.secondary)
            }
        case .denied:
            TaskStateCard(icon: "lock", message: "リマインダーへのアクセスが必要です。\n設定アプリで「フルアクセス」を許可してください。") {
                Button("設定アプリを開く") { openSystemSettings() }
                    .buttonStyle(.secondary)
            }
        case .loaded:
            let section = HomeTaskSection.make(tab: tab, tasks: reminders.tasks)
            if section.rows.isEmpty {
                TaskStateCard(icon: "checkmark.circle", message: tab == .today ? "今日のやることはありません。" : "未完了のやることはありません。")
            } else {
                TaskListCard(rows: section.rows, selectedID: taskToStart?.id, onStart: start) { row in
                    if !row.isDone { taskToStart = taskToStart?.id == row.id ? nil : row.task }
                }
            }
        }
    }

    // MARK: - 操作

    private func reload() async {
        await reminders.reload(selectedListIDs: store.settings.selectedListIDs)
    }

    private func start(_ task: TaskItem) {
        taskToStart = nil
        let session = store.startFocus(task: task, origin: .home)
        router.push(.focus(sessionID: session.id))
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 部品

/// 「今日」「すべて」の切替
private struct HomeSegment: View {
    @Binding var selection: HomeTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomeTab.allCases) { t in
                Button {
                    selection = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selection == t ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 64, height: 30)
                        .background(selection == t ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(Theme.segmentBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TaskListCard: View {
    var rows: [HomeTaskRow]
    var selectedID: String?
    var onStart: (TaskItem) -> Void
    var onTap: (HomeTaskRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 { Divider().overlay(Theme.separator) }
                VStack(spacing: 0) {
                    Button { onTap(row) } label: { TaskRowView(row: row) }
                        .buttonStyle(.plain)
                        .disabled(row.isDone)
                    if selectedID == row.id && !row.isDone {
                        Button("このやることをはじめる") { onStart(row.task) }
                            .buttonStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .card()
    }
}

/// 1行。完了はふりかえりでのみ行うため、チェック円は操作できない表示だけ
private struct TaskRowView: View {
    var row: HomeTaskRow

    var body: some View {
        HStack(spacing: 12) {
            TaskCheckCircle(isOn: row.isDone)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(HomeLayout.rowTitle)
                    .foregroundStyle(row.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(row.isDone, color: Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                Text(row.detail)
                    .font(HomeLayout.caption)
                    .foregroundStyle(row.isDetailEmphasized ? Theme.dueToday : Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, HomeLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

private struct TaskCheckCircle: View {
    var isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isOn ? Theme.orange : Theme.disabled, lineWidth: 2)
                .frame(width: 22, height: 22)
            if isOn {
                Circle().fill(Theme.orange).frame(width: 13, height: 13)
            }
        }
        .accessibilityLabel(isOn ? "完了済み" : "未完了")
    }
}

/// 読込中・失敗・権限なし・0件の表示（0件と失敗を混同しない）
private struct TaskStateCard<Actions: View>: View {
    var icon: String?
    var message: String
    @ViewBuilder var actions: () -> Actions

    init(icon: String?, message: String, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.icon = icon
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.brown)
            } else {
                ProgressView()
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// 進行中の取り組みへ戻る導線
private struct ActiveSessionBanner: View {
    var session: FocusSession
    var onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.brown)
                VStack(alignment: .leading, spacing: 2) {
                    Text("やることに戻る")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.brown)
                    Text(session.taskTitle)
                        .font(HomeLayout.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.brown)
            }
            .padding(14)
            .card()
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.brown, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
