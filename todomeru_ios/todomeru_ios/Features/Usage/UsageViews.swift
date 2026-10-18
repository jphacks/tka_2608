import Charts
import SwiftUI

// MARK: - アプリの使用時間（79:2）

struct UsageView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    /// 上限のポップアップを出しているアプリ
    @State private var limitTarget: SNSLimitTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                TabScreenTitle(title: "アプリの使用時間")
                SummaryPanel()
                HStack {
                    Text("アプリごとの使用時間と上限")
                        .font(HomeLayout.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    DemoBadge(text: "デモの使用時間")
                }
                snsList
                Text("今週のアリとキリギリス")
                    .font(HomeLayout.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                WeeklyChartCard(bars: WeeklyStats.bars(store: store))
            }
            .padding(.horizontal, HomeLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .snsLimitSheet($limitTarget)
    }

    private var snsList: some View {
        VStack(spacing: 0) {
            ForEach(store.selectedSNS) { sns in
                SNSUsageRow(
                    sns: sns,
                    status: SNSUsageStatus.make(sns.id, store: store),
                    onSelect: { limitTarget = SNSLimitTarget(snsID: sns.id) },
                    onOpen: { router.openSNS(sns.id, store: store) },
                    onFillToLimit: { store.setDemoUsage(store.effectiveLimit(sns.id), for: sns.id) }
                )
                Divider().overlay(Theme.separator)
            }
            Button {
                router.push(.settingsSNSAdd)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(Theme.addIconBackground, in: Circle())
                    Text("アプリを追加・外す")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.antGold)
                    Spacer()
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

/// アプリ1件の行。タップで上限のポップアップ。下段にデモ操作（開く・上限まで進める）
private struct SNSUsageRow: View {
    var sns: SNSApp
    var status: SNSUsageStatus
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onFillToLimit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) { summary }
                .buttonStyle(.plain)
            demoActions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, HomeLayout.rowVerticalPadding)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SNSIcon(sns: sns, size: 26)
                SNSNameLabel(sns: sns)
                    .font(HomeLayout.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(status.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(status.isOverLimit ? Theme.barOver : Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            UsageBar(ratio: status.ratio, color: Theme.usageBar(ratio: status.ratio))
                .padding(.leading, 36)
            stateLabel.padding(.leading, 36)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch status.state {
        case .restricted:
            Text("アリが制限中")
                .font(HomeLayout.caption)
                .foregroundStyle(Theme.barOver)
        case .granted(let remaining):
            Text("一時的に利用できます（残り\(TimeFormat.clock(remaining))）")
                .font(HomeLayout.caption)
                .foregroundStyle(Theme.brown)
        case .normal:
            EmptyView()
        }
    }

    /// デモの候補は疑似アプリ画面を開ける。標準機能で選んだアプリは本体から起動できないので、
    /// ホーム画面から開くよう案内し、「上限まで進める」で本物の制限がかかるのを試せるようにする。
    private var demoActions: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if sns.tokenData != nil {
                    Text("ホーム画面から開いてください")
                        .font(HomeLayout.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if sns.tokenData == nil {
                    DemoActionButton(title: "開く（デモ）", icon: "arrow.up.forward.app", action: onOpen)
                }
                if !status.isOverLimit {
                    DemoActionButton(title: "上限まで進める", icon: "forward.end", action: onFillToLimit)
                }
            }
            if sns.tokenData != nil, !status.isOverLimit {
                Text("上限まで進めると、このアプリに実際の制限がかかります")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct DemoActionButton: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.brown)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.summaryCard, in: Capsule())
                .overlay(Capsule().stroke(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 使用時間／上限のバー
struct UsageBar: View {
    var ratio: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.barTrack)
                Capsule().fill(color).frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: HomeLayout.barHeight)
    }
}

/// 今週のがんばった時間と遊んだ時間（月〜日）
private struct WeeklyChartCard: View {
    var bars: [WeeklyBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(bars) { bar in
                BarMark(
                    x: .value("曜日", bar.dayLabel),
                    y: .value("分", bar.minutes),
                    width: .fixed(12)
                )
                .foregroundStyle(by: .value("種類", bar.series.rawValue))
                .position(by: .value("種類", bar.series.rawValue))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale([
                WeeklyBar.Series.focus.rawValue: Theme.barNormal,
                WeeklyBar.Series.play.rawValue: Theme.grasshopperGreen,
            ])
            .chartXScale(domain: WeeklyStats.weekdayLabels)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel { if let m = value.as(Int.self) { Text("\(m)分") } }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 160)
            Text("遊んだ時間はデモで記録した今日の分だけを表示しています。")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card()
    }
}

