import DeviceActivity
import ExtensionKit
import SwiftUI

/// ホームの「遊んだ時間」を、スクリーンタイムの実際の使用時間から描く Report 拡張。
/// 使用時間はこの拡張の中だけで扱い、本体アプリへは渡さない（表示専用）。
@main
struct PlayTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        PlayTimeReport { seconds in
            PlayTimeView(seconds: seconds)
        }
    }
}

/// 渡された期間・アプリの使用時間を合計する
nonisolated struct PlayTimeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .playTime
    let content: (Int) -> PlayTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        let total = await data.flatMap { $0.activitySegments }.reduce(0) { $0 + $1.totalActivityDuration }
        return Int(total)
    }
}

/// 本体のサマリーカードの数字と同じ見た目（「55分」「1時間12分」）
struct PlayTimeView: View {
    let seconds: Int

    private enum Style {
        static let number = Font.system(size: 22, weight: .heavy)
        static let unit = Font.system(size: 14, weight: .bold)
        static let text = Color(red: 0x2B / 255, green: 0x21 / 255, blue: 0x18 / 255)
    }

    var body: some View {
        let minutes = max(0, seconds) / 60
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            if minutes >= 60 {
                Text("\(minutes / 60)").font(Style.number)
                Text("時間").font(Style.unit)
                if minutes % 60 > 0 {
                    Text("\(minutes % 60)").font(Style.number)
                    Text("分").font(Style.unit)
                }
            } else {
                Text("\(minutes)").font(Style.number)
                Text("分").font(Style.unit)
            }
        }
        .foregroundStyle(Style.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
