import Charts
import SwiftUI

// MARK: - アプリの使用時間（79:2）

struct UsageView: View {
    @Environment(AppStore.self) private var store

    /// 上限のポップアップを出しているアプリ
    @State private var limitTarget: SNSLimitTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                TabScreenTitle(title: "アプリの使用時間")
                SummaryPanel()
                Text("アプリごとの使用時間と上限")
                    .font(HomeLayout.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
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
                    onSelect: { limitTarget = SNSLimitTarget(snsID: sns.id) }
                )
                Divider().overlay(Theme.separator)
            }
            PickAppsButton(title: "アプリを追加・外す", compact: true)
        }
        .card()
    }
}

/// アプリ1件の行。タップで上限のポップアップ。
/// 使用時間はスクリーンタイムの実際の利用から取り込むため、手で進める操作は置かない（Issue #35）。
private struct SNSUsageRow: View {
    var sns: SNSApp
    var status: SNSUsageStatus
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) { summary }
            .buttonStyle(.plain)
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
            UsageBar(ratio: status.ratio, baseRatio: status.baseLimitRatio)
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
}

/// 使用時間／上限のバー
struct UsageBar: View {
    var ratio: Double
    /// 元の上限と追加分の境界。追加分がなければ区切り線を出さない。
    var baseRatio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.usageBarRemaining)
                Rectangle().fill(Theme.barOver)
                    .frame(width: geo.size.width * min(max(ratio, 0), 1))
                if baseRatio > 0 && baseRatio < 1 {
                    Rectangle().fill(Theme.textPrimary)
                        .frame(width: 2)
                        .offset(x: max(0, geo.size.width * baseRatio - 1))
                }
            }
            .clipShape(Capsule())
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
            Text("遊んだ時間は今日の分だけを表示しています。")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card()
    }
}
