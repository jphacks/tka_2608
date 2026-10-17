import SwiftUI

/// ホーム・使用時間で使う色の別名（Themeの定数だけを参照する）
extension Theme {
    /// 進捗バーの下地
    static let barTrack = Theme.separator
    /// 上限未到達のバー・取り組み時間のグラフ
    static let barNormal = Theme.orange
    /// 上限到達・制限中
    static let barOver = Theme.danger
    /// 未達のドット
    static let dotEmpty = Theme.disabled
}

/// ホーム・使用時間で繰り返し使う寸法・フォント
enum HomeLayout {
    static let screenPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let largeTitle = Font.system(size: 30, weight: .heavy)
    static let sectionTitle = Font.system(size: 17, weight: .bold)
    static let rowTitle = Font.system(size: 16, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let summaryValue = Font.system(size: 22, weight: .heavy)
    static let barHeight: CGFloat = 6
    static let rowVerticalPadding: CGFloat = 12
    static let degreeDotCount = 5
    static let degreeDotSize: CGFloat = 8
    static let characterSize: CGFloat = 36
    /// 画面上の取り組み時間・アリ度の再計算間隔（秒）
    static let summaryRefreshSeconds: TimeInterval = 30
}

/// 大きな見出し＋右上の設定ボタン（ホーム・使用時間で共通）
struct TabScreenTitle: View {
    @Environment(Router.self) private var router
    var title: String

    var body: some View {
        HStack {
            Text(title)
                .font(HomeLayout.largeTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                router.push(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.antGold)
            }
            .accessibilityLabel("設定")
        }
        .padding(.top, 8)
    }
}
