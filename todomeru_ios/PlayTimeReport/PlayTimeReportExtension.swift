import Charts
import DeviceActivity
import ExtensionKit
import ManagedSettings
import SwiftUI

/// 実使用時間はReport内だけで集計・表示する。本体へ書き出さない。
@main
struct PlayTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        UsageReport(context: .playTime) { ReportContent(data: $0, style: .total) }
        UsageReport(context: .appUsageMinutes) { ReportContent(data: $0, style: .minutes) }
        UsageReport(context: .appUsageBar) { ReportContent(data: $0, style: .bar) }
        UsageReport(context: .weeklyUsage) { ReportContent(data: $0, style: .weekly) }
    }
}

nonisolated struct ReportData {
    var totals = UsageReportTotals<ApplicationToken>()
    var days: [String: UsageReportTotals<ApplicationToken>] = [:]
    var settings: UsageReportSettings?
    var updatedAt: Date?
}

/// 合計・各アプリ・グラフをすべて同じアプリ単位の集計にする。
/// ActivitySegment.totalActivityDuration（画面点灯時間）は利用しない。
nonisolated struct UsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let content: (ReportData) -> ReportContent

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ReportData {
        var result = ReportData(settings: UsageReportSettings.load(from: SharedScreenTime.defaults))
        for await device in data {
            result.updatedAt = max(result.updatedAt ?? device.lastUpdatedDate, device.lastUpdatedDate)
            for await segment in device.activitySegments {
                let day = SharedDayKey.key(of: segment.dateInterval.start)
                for await category in segment.categories {
                    for await app in category.applications {
                        guard let token = app.application.token else { continue }
                        result.totals.add(app.totalActivityDuration, for: token)
                        result.days[day, default: UsageReportTotals()].add(app.totalActivityDuration, for: token)
                    }
                }
            }
        }
        return result
    }
}

private enum ReportColors {
    static let text = Color(red: 0x2B / 255, green: 0x21 / 255, blue: 0x18 / 255)
    static let remaining = Color(red: 0xE6 / 255, green: 0xD2 / 255, blue: 0xB5 / 255)
    static let used = Color(red: 0xD9 / 255, green: 0x53 / 255, blue: 0x4F / 255)
}

struct ReportContent: View {
    enum Style { case total, minutes, bar, weekly }
    var data: ReportData
    var style: Style

    var body: some View {
        Group {
            switch style {
            case .total: total
            case .minutes:
                Text("\(data.totals.totalMinutes)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .bar: bar
            case .weekly: weekly
            }
        }
        .foregroundStyle(ReportColors.text)
    }

    private var total: some View {
        let minutes = data.totals.totalMinutes
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            if minutes >= 60 {
                Text("\(minutes / 60)").font(.system(size: 22, weight: .heavy))
                Text("時間").font(.system(size: 14, weight: .bold))
            }
            if minutes < 60 || minutes % 60 > 0 {
                Text("\(minutes % 60)").font(.system(size: 22, weight: .heavy))
                Text("分").font(.system(size: 14, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("遊んだ時間 \(minutes)分")
    }

    /// 単一アプリでフィルターした結果。上限は本体からの入力だけを読む。
    private var ratio: Double? {
        guard data.totals.totalSeconds > 0 else { return 0 }
        guard let token = data.totals.seconds.keys.first,
              let limit = data.settings?.limit(for: token, on: SharedDayKey.key()) else { return nil }
        return limit > 0 ? min(1, data.totals.totalSeconds / Double(limit)) : 1
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(ReportColors.remaining)
                if let ratio {
                    Rectangle().fill(ReportColors.used)
                        .frame(width: geometry.size.width * ratio)
                } else {
                    // 設定を読めなかった状態を使用時間0として塗らない。
                    Capsule().fill(.gray.opacity(0.3))
                        .accessibilityLabel("上限設定を読み込めませんでした")
                }
            }
            .clipShape(Capsule())
        }
    }

    private struct WeekBar: Identifiable {
        var day: String
        var series: String
        var minutes: Int
        var id: String { day + series }
    }

    private var weekBars: [WeekBar] {
        let labels = ["月", "火", "水", "木", "金", "土", "日"]
        return zip(UsageReportPeriod.weekDays(.now), labels).flatMap { date, label in
            let key = SharedDayKey.key(of: date)
            return [
                WeekBar(day: label, series: "がんばった時間", minutes: data.settings?.focusDays.first { $0.dayKey == key }?.minutes ?? 0),
                WeekBar(day: label, series: "遊んだ時間", minutes: data.days[key]?.totalMinutes ?? 0),
            ]
        }
    }

    private var weekly: some View {
        Chart(weekBars) { bar in
            BarMark(x: .value("曜日", bar.day), y: .value("分", bar.minutes), width: .fixed(12))
                .foregroundStyle(by: .value("種類", bar.series))
                .position(by: .value("種類", bar.series))
                .cornerRadius(2)
        }
        .chartForegroundStyleScale([
            "がんばった時間": Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255),
            "遊んだ時間": Color(red: 0x7C / 255, green: 0xC2 / 255, blue: 0x4B / 255),
        ])
        .chartXScale(domain: ["月", "火", "水", "木", "金", "土", "日"])
        .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel() } }
        .chartLegend(position: .top, alignment: .leading)
    }
}
