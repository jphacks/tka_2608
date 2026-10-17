import Charts
import SwiftUI

// MARK: - SNSの使用時間（79:2）

struct UsageView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                TabScreenTitle(title: "SNSの使用時間")
                SummaryPanel()
                HStack {
                    Text("SNSごとの使用時間と上限")
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
    }

    private var snsList: some View {
        VStack(spacing: 0) {
            ForEach(store.selectedSNS) { sns in
                SNSUsageRow(
                    sns: sns,
                    status: SNSUsageStatus.make(sns.id, store: store),
                    onSelect: { router.push(.snsLimit(snsID: sns.id)) },
                    onOpen: { router.openSNS(sns.id, store: store) },
                    onFillToLimit: { store.setDemoUsage(store.effectiveLimit(sns.id), for: sns.id) }
                )
                Divider().overlay(Theme.separator)
            }
            Button {
                router.push(.settingsSNSAdd)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.antGold)
                    Text("SNSを追加・外す")
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

/// SNS1件の行。タップで上限の設定へ。下段にデモ操作（開く・上限まで進める）
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
                Text(sns.name)
                    .font(HomeLayout.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(status.usedSeconds / 60) / \(status.limitSeconds / 60)分")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(status.isOverLimit ? Theme.barOver : Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            UsageBar(ratio: status.ratio, color: status.isOverLimit ? Theme.barOver : Theme.barNormal)
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

    private var demoActions: some View {
        HStack(spacing: 8) {
            Spacer()
            DemoActionButton(title: "開く（デモ）", icon: "arrow.up.forward.app", action: onOpen)
            if !status.isOverLimit {
                DemoActionButton(title: "上限まで進める", icon: "forward.end", action: onFillToLimit)
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

// MARK: - SNS別の上限（31:131）

struct SNSLimitView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private static let hourOptions = Array(0...(PolicyConstants.dailyLimitMaxSeconds / 3600))
    private static let minuteOptions = Array(stride(from: 0, to: 60, by: PolicyConstants.dailyLimitStepSeconds / 60))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("", backTitle: "戻る", onBack: { router.pop() })
            if let sns = store.sns(snsID) {
                content(sns)
            } else {
                Text("SNSが見つかりませんでした")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(HomeLayout.screenPadding)
            }
            Spacer()
        }
        .screenBackground()
    }

    private func content(_ sns: SNSApp) -> some View {
        let status = SNSUsageStatus.make(snsID, store: store)
        let extra = store.effectiveLimit(snsID) - sns.dailyLimitSeconds
        return VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
            Text("\(sns.name)の制限")
                .font(HomeLayout.largeTitle)
                .foregroundStyle(Theme.textPrimary)
            statusCard(sns, status: status)
            VStack(alignment: .leading, spacing: 6) {
                Text("1日の上限時間")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 12)
                limitPicker(sns)
                if extra > 0 {
                    Text("今日はSNS時間で\(TimeFormat.hm(extra))追加しています（今日の上限は\(TimeFormat.hm(store.effectiveLimit(snsID)))）。")
                        .font(HomeLayout.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.horizontal, HomeLayout.screenPadding)
    }

    private func statusCard(_ sns: SNSApp, status: SNSUsageStatus) -> some View {
        HStack(spacing: 14) {
            SNSIcon(sns: sns, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("今日\(TimeFormat.hm(status.usedSeconds))使用")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                statusText(status)
                    .font(HomeLayout.caption)
                DemoBadge(text: "デモの使用時間")
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private func statusText(_ status: SNSUsageStatus) -> Text {
        switch status.state {
        case .restricted:
            return Text("アリが制限中").foregroundStyle(Theme.barOver)
        case .granted(let remaining):
            return Text("一時的に利用できます（残り\(TimeFormat.clock(remaining))）").foregroundStyle(Theme.brown)
        case .normal:
            return Text("上限まであと\(TimeFormat.hm(status.limitSeconds - status.usedSeconds))").foregroundStyle(Theme.textSecondary)
        }
    }

    private func limitPicker(_ sns: SNSApp) -> some View {
        let hours = Binding<Int>(
            get: { sns.dailyLimitSeconds / 3600 },
            set: { store.setDailyLimit($0 * 3600 + (sns.dailyLimitSeconds % 3600), for: snsID) }
        )
        let minutes = Binding<Int>(
            get: { sns.dailyLimitSeconds % 3600 / 60 },
            set: { store.setDailyLimit((sns.dailyLimitSeconds / 3600) * 3600 + $0 * 60, for: snsID) }
        )
        return HStack(spacing: 0) {
            Picker("時間", selection: hours) {
                ForEach(Self.hourOptions, id: \.self) { Text("\($0) 時間").tag($0) }
            }
            Picker("分", selection: minutes) {
                ForEach(Self.minuteOptions, id: \.self) { Text("\($0) 分").tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 150)
        .padding(.horizontal, 8)
        .card()
    }
}
