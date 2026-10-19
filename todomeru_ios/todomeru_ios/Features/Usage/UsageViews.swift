import Charts
import DeviceActivity
import SwiftUI

// MARK: - アプリの使用時間（79:2）

struct UsageView: View {
    @Environment(AppStore.self) private var store
    @Environment(UsageReportClock.self) private var reportClock

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
                #if TODOMERU_PERSONAL_DEMO
                WeeklyChartCard(bars: WeeklyStats.bars(store: store))
                #else
                if store.pickedTokens.isEmpty {
                    WeeklyChartCard(bars: WeeklyStats.bars(store: store))
                } else {
                    UsageReportHost(context: .weeklyUsage, tokens: store.pickedTokens, weekly: true)
                        .frame(height: 180)
                        .padding(14)
                        .card()
                }
                #endif
            }
            .padding(.horizontal, HomeLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear { reportClock.refresh() }
        .refreshable { reportClock.refresh() }
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
                usageLabel
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            usageBar.padding(.leading, 36)
            stateLabel.padding(.leading, 36)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var usageLabel: some View {
        if let token = sns.applicationToken {
            HStack(spacing: 3) {
                UsageReportHost(context: .appUsageMinutes, tokens: [token])
                    .frame(width: 44, height: 20)
                Text("/ \(status.limitSeconds / 60)分")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text(status.label).font(.system(size: 14, weight: .bold))
        }
    }

    @ViewBuilder
    private var usageBar: some View {
        if let token = sns.applicationToken {
            UsageReportHost(context: .appUsageBar, tokens: [token])
                .frame(height: HomeLayout.barHeight)
                .overlay {
                    GeometryReader { geometry in
                        if status.baseLimitRatio > 0 && status.baseLimitRatio < 1 {
                            Rectangle().fill(.white)
                                .overlay(Rectangle().strokeBorder(.black, lineWidth: 0.5))
                                .frame(width: 4)
                                .offset(x: max(0, geometry.size.width * status.baseLimitRatio - 2))
                        }
                    }
                    .allowsHitTesting(false)
                }
        } else {
            UsageBar(ratio: status.ratio, baseRatio: status.baseLimitRatio)
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch status.state {
        case .restricted:
            Text("アリが制限中")
                .font(HomeLayout.caption)
                .foregroundStyle(Theme.barOver)
        case .granted, .normal:
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
                    Rectangle().fill(.white)
                        .overlay(Rectangle().strokeBorder(.black, lineWidth: 0.5))
                        .frame(width: 4)
                        .offset(x: max(0, geo.size.width * baseRatio - 2))
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
