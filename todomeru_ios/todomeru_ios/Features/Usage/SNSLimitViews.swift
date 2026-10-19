import SwiftUI

// MARK: - アプリ別の上限（31:131 / 279:69 / 279:87 / 279:105）
// 使用時間画面の行タップで出すカード型のシート。

/// シートの寸法・フォント
enum SNSLimitLayout {
    /// Figmaのポップアップ（393×250）に合わせたシートの高さ
    static let sheetHeight: CGFloat = 260
    static let sheetCornerRadius: CGFloat = 28
    static let padding: CGFloat = 20
    static let title = Font.system(size: 20, weight: .heavy)
    static let description = Font.system(size: 12)
    static let iconSize: CGFloat = 32
    static let stepperValue = Font.system(size: 15, weight: .bold)
    static let stepperButton = Font.system(size: 18, weight: .semibold)
    static let stepperValueWidth: CGFloat = 94
}

extension Theme {
    /// 上限の行の背景
    static let limitRowBackground = Theme.summaryCard
    /// −／＋ の背景
    static let limitStepperBackground = Theme.segmentBackground
    /// −／＋ の記号
    static let limitStepperSymbol = Theme.antGold
    /// 「アプリを追加・外す」の黄色い丸
    static let addIconBackground = Theme.orange
}

/// シートで開く対象（sheet(item:) 用）
struct SNSLimitTarget: Identifiable, Equatable {
    var snsID: String
    var id: String { snsID }
}

/// 上限の増減（5分単位）。値の計算だけを持つ純粋な型
enum SNSLimitStep {
    static var step: Int { PolicyConstants.dailyLimitStepSeconds }
    /// 0分も可（最初から制限する, D022）
    static let minimum = 0
    static var maximum: Int { PolicyConstants.dailyLimitMaxSeconds }

    static func decreased(_ seconds: Int) -> Int { max(minimum, seconds - step) }
    static func increased(_ seconds: Int) -> Int { min(maximum, seconds + step) }
    static func canDecrease(_ seconds: Int) -> Bool { seconds > minimum }
    static func canIncrease(_ seconds: Int) -> Bool { seconds < maximum }
}

/// ポップアップの中身（タイトル・説明・アプリの行と −／＋・完了）
struct SNSLimitEditor: View {
    var snsID: String
    var onDone: () -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sns = store.sns(snsID) {
                VStack(alignment: .leading, spacing: 6) {
                    SNSPhrase(sns: sns, suffix: "の1日の上限")
                        .font(SNSLimitLayout.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text("1日ごとの上限を、5分単位で変更できます。")
                        .font(SNSLimitLayout.description)
                        .foregroundStyle(Theme.textSecondary)
                }
                SNSLimitStepperRow(sns: sns) { store.setDailyLimit($0, for: snsID) }
                extraNote(sns)
            } else {
                Text("アプリが見つかりませんでした")
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("完了", action: onDone)
                .buttonStyle(.primary)
        }
        .padding(SNSLimitLayout.padding)
    }

    /// 今日だけアプリ時間で上限を増やしているときの補足
    @ViewBuilder
    private func extraNote(_ sns: SNSApp) -> some View {
        let effective = store.effectiveLimit(snsID)
        let extra = effective - sns.dailyLimitSeconds
        if extra > 0 {
            Text("今日はアプリ時間で\(TimeFormat.hm(extra))追加しています（今日の上限は\(TimeFormat.hm(effective))）。")
                .font(HomeLayout.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// アプリアイコン・名前と −／＋ の1行
private struct SNSLimitStepperRow: View {
    var sns: SNSApp
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SNSIcon(sns: sns, size: SNSLimitLayout.iconSize)
            SNSNameLabel(sns: sns)
                .font(HomeLayout.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            stepper
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.limitRowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var stepper: some View {
        let value = sns.dailyLimitSeconds
        return HStack(spacing: 0) {
            stepButton("minus", label: "5分減らす", enabled: SNSLimitStep.canDecrease(value)) {
                onChange(SNSLimitStep.decreased(value))
            }
            Text(TimeFormat.hm(value))
                .font(SNSLimitLayout.stepperValue)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: SNSLimitLayout.stepperValueWidth)
                .contentTransition(.numericText())
            stepButton("plus", label: "5分増やす", enabled: SNSLimitStep.canIncrease(value)) {
                onChange(SNSLimitStep.increased(value))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(Theme.limitStepperBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(SNSLimitLayout.stepperButton)
                .foregroundStyle(enabled ? Theme.limitStepperSymbol : Theme.disabled)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

extension View {
    /// 使用時間画面から上限のポップアップをシートで出す
    func snsLimitSheet(_ target: Binding<SNSLimitTarget?>) -> some View {
        sheet(item: target) { t in
            SNSLimitEditor(snsID: t.snsID) { target.wrappedValue = nil }
                .presentationDetents([.height(SNSLimitLayout.sheetHeight)])
                .presentationCornerRadius(SNSLimitLayout.sheetCornerRadius)
                .presentationBackground(Theme.surface)
                .presentationDragIndicator(.hidden)
        }
    }
}

/// Route.snsLimit 用に残している型。今後は使用時間画面のシートから開く想定で、
/// Route経由で開かれた場合も同じ部品をカードで表示する。
struct SNSLimitView: View {
    var snsID: String

    @Environment(Router.self) private var router

    var body: some View {
        VStack {
            Spacer()
            SNSLimitEditor(snsID: snsID) { router.pop() }
                .card()
                .padding(.horizontal, HomeLayout.screenPadding)
            Spacer()
        }
        .screenBackground()
    }
}
