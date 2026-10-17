import Foundation

/// 「すべて」タブの期限表示（Figma 66:2）。Core の TaskFilter.dueLabel は変えずに、ホーム用に整形する。
/// 例: 「今日」「10/21（火）・あと4日」「11/30（日）」「期限なし」
struct HomeDueLabel: Equatable {
    var text: String
    /// 今日・期限切れはオレンジ文字で目立たせる
    var isEmphasized: Bool

    /// 「あと○日」を付ける最大日数（それより先は日付だけ）
    static let remainingDaysThreshold = 7

    static func make(_ t: TaskItem, now: Date = .now) -> HomeDueLabel {
        guard let due = t.dueDate else { return HomeDueLabel(text: "期限なし", isEmphasized: false) }
        let cal = Calendar.current
        let today = AppDay.day(of: now)
        let diff = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
        let time = t.dueHasTime ? " " + due.formatted(.dateTime.hour().minute()) : ""
        switch diff {
        case ..<0:
            return HomeDueLabel(text: "\(dateText(due))・期限切れ", isEmphasized: true)
        case 0:
            return HomeDueLabel(text: "今日" + time, isEmphasized: true)
        case 1...remainingDaysThreshold:
            return HomeDueLabel(text: "\(dateText(due))\(time)・あと\(diff)日", isEmphasized: false)
        default:
            return HomeDueLabel(text: dateText(due) + time, isEmphasized: false)
        }
    }

    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    /// 「10/21（火）」
    static func dateText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: date)
        let w = weekdaySymbols[((c.weekday ?? 1) - 1) % 7]
        return "\(c.month ?? 0)/\(c.day ?? 0)（\(w)）"
    }
}
