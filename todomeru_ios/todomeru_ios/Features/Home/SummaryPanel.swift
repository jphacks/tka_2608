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
/// Figma 65:2 に合わせ、獲得済みのSNS時間の行と目標の表記は出さない（報酬・目標の値は内部に残る）。
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
                        value: TimeFormat.hm(s.focusSeconds),
                        sub: nil,
                        degreeLabel: "アリ度",
                        degree: s.antDegree,
                        dotColor: Theme.antGold
                    ) {
                        AntFace(stage: 4, size: HomeLayout.characterSize)
                    }
                    SummaryTile(
                        title: "遊んだ時間",
                        value: TimeFormat.hm(s.playSeconds),
                        sub: "/ \(TimeFormat.hm(s.playLimitSeconds))",
                        degreeLabel: "キリギリス度",
                        degree: s.grasshopperDegree,
                        dotColor: Theme.grasshopperGreen
                    ) {
                        GrasshopperFigure(stage: GrasshopperFigure.stage(forFocusSeconds: s.focusSeconds), size: HomeLayout.characterSize)
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

private struct SummaryTile<Figure: View>: View {
    var title: String
    var value: String
    var sub: String?
    var degreeLabel: String
    var degree: Int
    var dotColor: Color
    @ViewBuilder var figure: () -> Figure

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
                Text(value)
                    .font(HomeLayout.summaryValue)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sub {
                    Text(sub)
                        .font(HomeLayout.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(spacing: 4) {
                Text(degreeLabel)
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
