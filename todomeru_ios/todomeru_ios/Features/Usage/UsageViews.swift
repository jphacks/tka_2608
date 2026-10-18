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
                    onSelect: { limitTarget = SNSLimitTarget(snsID: sns.id) },
                    onFillToLimit: { store.fillUsageToLimit(sns.id) }
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

/// アプリ1件の行。タップで上限のポップアップ。下段に「上限まで進める」操作。
private struct SNSUsageRow: View {
    var sns: SNSApp
    var status: SNSUsageStatus
    var onSelect: () -> Void
    var onFillToLimit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) { summary }
                .buttonStyle(.plain)
            actions
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

    /// 標準機能で選んだアプリは本体から起動できないので、
    /// ホーム画面から開くよう案内し、「上限まで進める」で本物の制限がかかるのを試せるようにする。
    /// ボタンは文字を出さずアイコンだけにする（Issue #19）
    private var actions: some View {
        HStack(spacing: 8) {
            if sns.tokenData != nil {
                Text("ホーム画面から開いてください")
                    .font(HomeLayout.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // 上限に到達しても表示を保ち、押下前後でレイアウトを変えない（Issue #25）。
            IconActionButton(label: "上限まで進める", icon: "arrow.right.to.line", action: onFillToLimit)
        }
    }
}

/// アイコンだけの小さな操作ボタン（読み上げ用の名前は label）
private struct IconActionButton: View {
    var label: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brown)
                .frame(width: 36, height: 28)
                .background(Theme.summaryCard, in: Capsule())
                .overlay(Capsule().stroke(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            Text("遊んだ時間は今日の分だけを表示しています。")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card()
    }
}
