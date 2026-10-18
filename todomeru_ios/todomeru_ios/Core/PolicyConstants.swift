import Foundation

/// 開発側が調整するルールの定数（ARCHITECTURE.md 3.7.6 / D026）。
/// 処理の中に数値を直接書かず、必ずこの型を参照する。値を変えたら version を上げる。
nonisolated enum PolicyConstants {
    static let version = 1

    /// 説得の1日の回数（全SNS合計, D024）
    static let persuasionDailyLimit = 3
    /// 説得で許可を提案できる納得度のしきい値（%, D025）
    static let persuasionApprovalThreshold = 70
    /// 説得1回で許可できる時間の範囲（秒, D023）
    static let persuasionGrantMinSeconds = 60
    static let persuasionGrantMaxSeconds = 300
    /// 5往復目の応答で必ず判定する（D024）
    static let persuasionMaxUserMessages = 5

    /// 取り組み25分ごとにSNS時間+5分（5:1, D015・D018・D028）
    static let focusRewardIntervalSeconds = 1500
    static let focusRewardSeconds = 300
    /// やること完了1件につき+1分（D028）
    static let completionRewardSeconds = 60

    /// 「アプリの1日」の切替時刻（端末の現地時刻, D024）
    static let dayBoundaryHour = 4

    /// SNSの1日の上限の初期値と刻み（D022）
    static let defaultDailyLimitSeconds = 1800
    static let dailyLimitStepSeconds = 300
    static let dailyLimitMaxSeconds = 3 * 3600
    /// 一時利用枠を時計の時刻で終える保険の猶予（秒）。実利用時間での終了はMonitor拡張が行う（D023の提案）
    static let grantClockGraceSeconds = 900

    /// やることの1日の目標（ルール画面の表示例。アリ度の分母）
    static let defaultDailyFocusGoalSeconds = 7200
}
