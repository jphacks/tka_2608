import DeviceActivity
import ManagedSettings
import SwiftUI

/// ホーム・使用時間の黄色いサマリーに出す値（AppStoreから計算する純粋な値）
struct DailySummary {
    var focusSeconds: Int
    var antDegree: Int
    var playSeconds: Int
    var playLimitSeconds: Int
    var grasshopperDegree: Int

    @MainActor
    static func make(store: AppStore, now: Date = .now) -> DailySummary {
        let selected = store.selectedSNS
        let ant = store.antDegree(now: now)
        return DailySummary(
            focusSeconds: store.focusSecondsToday(now: now),
            antDegree: ant,
            playSeconds: selected.reduce(0) { $0 + store.usageToday($1.id) },
            playLimitSeconds: selected.reduce(0) { $0 + store.effectiveLimit($1.id) },
            grasshopperDegree: 100 - ant
        )
    }
}

/// 黄色のサマリー（がんばった時間・遊んだ時間・「やることを始める」）。
/// Figma 65:2 に合わせ、目標の表記は出さない（目標の値は内部に残る）。
struct SummaryPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeLayout.summaryRefreshSeconds)) { context in
            let s = DailySummary.make(store: store, now: context.date)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    SummaryTile(
                        title: "がんばった時間",
                        sub: nil,
                        degreeLabel: "アリ度",
                        degree: s.antDegree,
                        dotColor: Theme.antGold
                    ) {
                        AntFace(stage: 4, size: HomeLayout.characterSize)
                    } value: {
                        SummaryValueText(text: TimeFormat.hm(s.focusSeconds))
                    }
                    SummaryTile(
                        title: "遊んだ時間",
                        sub: "/ \(TimeFormat.hm(s.playLimitSeconds))",
                        degreeLabel: "キリギリス度",
                        degree: s.grasshopperDegree,
                        dotColor: Theme.grasshopperGreen
                    ) {
                        GrasshopperFigure(stage: GrasshopperFigure.stage(forFocusSeconds: s.focusSeconds), size: HomeLayout.characterSize)
                    } value: {
                        PlayTimeValue(demoSeconds: s.playSeconds, now: context.date)
                    }
                }
                Button("やることを始める") {
                    router.push(.taskSelect(origin: .home))
                }
                .buttonStyle(.primary)
            }
            .padding(14)
            .card(Theme.summaryYellow)
        }
    }
}

private struct SummaryTile<Figure: View, Value: View>: View {
    var title: String
    var sub: String?
    var degreeLabel: String
    var degree: Int
    var dotColor: Color
    @ViewBuilder var figure: () -> Figure
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                figure()
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                value()
                if let sub {
                    Text(sub)
                        .font(HomeLayout.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(degreeLabel)
                    Spacer(minLength: 0)
                    Text("\(degree)%")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                DegreeDots(percent: degree, color: dotColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(degreeLabel) \(degree)%")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.summaryCard)
    }
}

/// アリ度・キリギリス度を5つのドットで表す（20%ごとに1つ）
struct DegreeDots: View {
    var percent: Int
    var color: Color

    static func filledCount(percent: Int, total: Int = HomeLayout.degreeDotCount) -> Int {
        let p = min(max(percent, 0), 100)
        return Int((Double(p) / 100 * Double(total)).rounded())
    }

    var body: some View {
        let filled = Self.filledCount(percent: percent)
        HStack(spacing: 3) {
            ForEach(0..<HomeLayout.degreeDotCount, id: \.self) { i in
                Circle()
                    .fill(i < filled ? color : Theme.dotEmpty)
                    .frame(width: HomeLayout.degreeDotSize, height: HomeLayout.degreeDotSize)
            }
        }
    }
}

/// サマリーの大きな数字
private struct SummaryValueText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(HomeLayout.summaryValue)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// 遊んだ時間。標準機能で選んだアプリがあり許可済みなら、スクリーンタイムの実際の使用時間を
/// Report拡張（PlayTimeReport）が描く。本体はこの数値を読めないので、上限判定やAIには使わない。
/// それ以外はアプリ内で記録した使用時間を出す。
private struct PlayTimeValue: View {
    @Environment(AppStore.self) private var store
    @Environment(ScreenTimeService.self) private var screenTime
    var demoSeconds: Int
    var now: Date

    var body: some View {
        #if TODOMERU_PERSONAL_DEMO
        VStack(alignment: .leading, spacing: 2) {
            SummaryValueText(text: "30分")
            DemoBadge()
        }
        #else
        let tokens = store.pickedTokens
        if screenTime.isAuthorized && !tokens.isEmpty {
            DeviceActivityReport(.playTime, filter: Self.filter(tokens: tokens, now: now))
                .frame(height: HomeLayout.reportValueHeight)
        } else {
            SummaryValueText(text: TimeFormat.hm(demoSeconds))
        }
        #endif
    }

    /// 今日（朝4時から今まで）の、選んだアプリの使用時間
    static func filter(tokens: Set<ApplicationToken>, now: Date) -> DeviceActivityFilter {
        let start = AppDay.interval(of: now).start
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: max(now, start.addingTimeInterval(60)))),
            applications: tokens
        )
    }
}
