import SwiftUI
import UIKit

// MARK: - 見出し・枠

/// 設定系の画面上部（左上の戻る＋大きな題名。Figma 150:2 ほか）
struct LargeTitleHeader: View {
    var title: String
    var backTitle: String
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BackLink(title: backTitle, action: onBack)
            Text(title)
                .font(SettingsMetrics.largeTitle)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.gutter)
        .padding(.top, 8)
    }
}

/// 「< 戻る」形式のリンク
struct BackLink: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.antGold)
        }
    }
}

/// 白いカードの中に行を並べ、行の間に区切り線を入れる
struct DividedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { i in
                    if i > subviews.startIndex {
                        Divider().overlay(Theme.separator)
                    }
                    subviews[i]
                }
            }
        }
        .card()
    }
}

/// セクションの小見出し
struct SectionCaption: View {
    var text: String
    var body: some View {
        Text(text)
            .font(SettingsMetrics.sectionTitle)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, SettingsMetrics.gutter)
    }
}

/// 補足の小さな文
struct FootNote: View {
    var text: String
    var body: some View {
        Text(text)
            .font(SettingsMetrics.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 下部に固定する大きなボタン
struct BottomActionButton: View {
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.primary)
            .disabled(!isEnabled)
            .padding(.horizontal, SettingsMetrics.gutter)
            .padding(.vertical, 12)
            .background(Theme.background)
    }
}

/// 押すと次の画面へ進む設定の行（右に値と＞）
struct NavigationRow: View {
    var title: String
    var value: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(SettingsMetrics.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(value)
                    .font(SettingsMetrics.rowValue)
                    .foregroundStyle(Theme.antGold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, SettingsMetrics.gutter)
            .frame(minHeight: SettingsMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 値を表示するだけの行
struct ValueRow: View {
    var title: String
    var value: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsMetrics.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let note {
                    Text(note)
                        .font(SettingsMetrics.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(SettingsMetrics.rowValue)
                .foregroundStyle(Theme.antGold)
        }
        .padding(.horizontal, SettingsMetrics.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
    }
}

// MARK: - ＋／− の操作

/// 「− 30分 ＋」の切替（Figma 64:225 の上限編集）
struct TimeStepper: View {
    var seconds: Int
    var step: Int
    var range: ClosedRange<Int>
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", delta: -step, enabled: seconds - step >= range.lowerBound)
            Text(TimeFormat.hm(seconds))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: SettingsMetrics.stepperValueWidth)
            stepButton("plus", delta: step, enabled: seconds + step <= range.upperBound)
        }
        .padding(.vertical, 6)
        .background(Theme.segmentBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(_ symbol: String, delta: Int, enabled: Bool) -> some View {
        Button {
            onChange(seconds + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Theme.antGold : Theme.disabled)
                .frame(width: 36, height: 28)
        }
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "増やす" : "減らす")
    }
}

// MARK: - SNSと時間（初回設定 64:225 と 設定 161:149 で共通）

/// キリギリス・SNSごとの1日の上限をまとめた編集部品（完了報酬カードはFigma更新で削除）
struct SNSTimeEditor: View {
    var subtitle: String
    var showsHero: Bool = true
    var onAddSNS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHero {
                CharacterImage(name: "hero_grasshopper", fallback: "🦗", size: SettingsMetrics.heroSize)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("制限するSNSを選ぶ")
                    .font(SettingsMetrics.stepTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(SettingsMetrics.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            PickAppsButton(onUseDemo: onAddSNS)
            #if !TODOMERU_PERSONAL_DEMO
            Button(action: onAddSNS) {
                HStack(spacing: 6) {
                    Label("デモの候補から選ぶ", systemImage: "plus")
                    DemoBadge()
                }
                .font(SettingsMetrics.sectionTitle)
                .foregroundStyle(Theme.antGold)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
            SNSLimitList()
            #if !TODOMERU_PERSONAL_DEMO
            FootNote(text: "「アプリを選ぶ」で選んだアプリは、上限に達するとiOSの制限がかかります（デモでは使用時間はアプリ内の疑似の値で数えます）。")
            #endif
            HStack(alignment: .top, spacing: 6) {
                DemoBadge()
                FootNote(text: "デモの候補は、上限に達するとアプリ内の疑似制限がかかります。実際のSNSは制限しません。")
            }
        }
    }
}

/// 選択中のSNSと、それぞれの1日の上限
struct SNSLimitList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.selectedSNS.isEmpty {
            #if TODOMERU_PERSONAL_DEMO
            FootNote(text: "制限するSNSがありません。「デモの候補から選ぶ」で選んでね。")
                .padding(SettingsMetrics.gutter)
                .card()
            #else
            FootNote(text: "制限するSNSがありません。「アプリを選ぶ」か「デモの候補から選ぶ」で選んでね。")
                .padding(SettingsMetrics.gutter)
                .card()
            #endif
        } else {
            DividedCard {
                ForEach(store.selectedSNS) { sns in
                    SNSLimitRow(sns: sns)
                }
            }
        }
    }
}

struct SNSLimitRow: View {
    @Environment(AppStore.self) private var store
    var sns: SNSApp

    var body: some View {
        HStack(spacing: 12) {
            SNSIcon(sns: sns, size: SettingsMetrics.rowIconSize)
            SNSNameLabel(sns: sns)
                .font(SettingsMetrics.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if sns.tokenData == nil { DemoBadge() }
            Spacer(minLength: 4)
            TimeStepper(
                seconds: sns.dailyLimitSeconds,
                step: PolicyConstants.dailyLimitStepSeconds,
                range: 0...PolicyConstants.dailyLimitMaxSeconds
            ) { store.setDailyLimit($0, for: sns.id) }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: SettingsMetrics.rowMinHeight + 6)
    }
}

// MARK: - リマインダーのリスト（初回 67:2 と 設定 150:96 で共通）

struct ReminderListSelectionCard: View {
    var lists: [ReminderListInfo]
    @Binding var selection: Set<String>
    var isDemo: Bool = false

    private var selectedCount: Int { lists.filter { selection.contains($0.id) }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isDemo ? "デモ用のリスト" : "iCloud のリスト")
                    .font(SettingsMetrics.caption)
                    .foregroundStyle(Theme.textSecondary)
                if isDemo { DemoBadge() }
                Spacer()
                Text("\(selectedCount)つ選択中")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, SettingsMetrics.gutter)
            .padding(.vertical, 8)
            Divider().overlay(Theme.separator)
            ForEach(lists) { list in
                Button {
                    toggle(list.id)
                } label: {
                    ReminderListRow(list: list, isSelected: selection.contains(list.id))
                }
                .buttonStyle(.plain)
                if list.id != lists.last?.id { Divider().overlay(Theme.separator) }
            }
        }
        .card()
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

struct ReminderListRow: View {
    var list: ReminderListInfo
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: list.colorHex))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "list.bullet").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            Text(list.title)
                .font(SettingsMetrics.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(list.openCount)件")
                .font(SettingsMetrics.caption)
                .foregroundStyle(Theme.textSecondary)
            CheckCircle(isOn: isSelected)
        }
        .padding(.horizontal, SettingsMetrics.gutter)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CheckCircle: View {
    var isOn: Bool
    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Theme.checkFill)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Circle().stroke(Theme.disabled, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// リマインダーを取得できないときの案内（0件と区別する）
struct ReminderUnavailableNotice: View {
    var message: String
    var onUseDemo: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(SettingsMetrics.body)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                Button("設定アプリを開く") { SystemSettings.open() }
                    .buttonStyle(.secondary)
                if let onUseDemo {
                    Button("デモ用のやることで試す", action: onUseDemo)
                        .buttonStyle(.secondary)
                }
            }
        }
        .padding(SettingsMetrics.gutter)
        .card()
    }
}

enum SystemSettings {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
