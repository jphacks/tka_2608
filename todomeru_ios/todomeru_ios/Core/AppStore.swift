import Foundation
import Observation

/// アプリ独自データ（設定・取り組み・SNS時間の台帳・説得・一時利用枠・デモの使用時間）の正本。
/// ハッカソン用にJSONファイルへ保存する（ARCHITECTURE.mdのSwiftData案は未採用）。
@Observable
final class AppStore {
    struct Snapshot: Codable {
        var settings = AppSettings()
        var snsApps = SNSApp.catalog
        var sessions: [FocusSession] = []
        var rewards: [RewardTransaction] = []
        var attempts: [PersuasionAttempt] = []
        var grants: [UnlockGrant] = []
        var demoUsage = DemoUsage()

        init() {}

        /// 項目が欠けた保存ファイル（古い版など）でも、欠けた項目だけ初期値で補う
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Snapshot()
            settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? d.settings
            snsApps = try c.decodeIfPresent([SNSApp].self, forKey: .snsApps) ?? d.snsApps
            sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? d.sessions
            rewards = try c.decodeIfPresent([RewardTransaction].self, forKey: .rewards) ?? d.rewards
            attempts = try c.decodeIfPresent([PersuasionAttempt].self, forKey: .attempts) ?? d.attempts
            grants = try c.decodeIfPresent([UnlockGrant].self, forKey: .grants) ?? d.grants
            demoUsage = try c.decodeIfPresent(DemoUsage.self, forKey: .demoUsage) ?? d.demoUsage
        }

        init(settings: AppSettings, snsApps: [SNSApp], sessions: [FocusSession], rewards: [RewardTransaction], attempts: [PersuasionAttempt], grants: [UnlockGrant], demoUsage: DemoUsage) {
            self.settings = settings
            self.snsApps = snsApps
            self.sessions = sessions
            self.rewards = rewards
            self.attempts = attempts
            self.grants = grants
            self.demoUsage = demoUsage
        }
    }

    /// 本体が実利用時間を読めないため、デモでは疑似SNS画面での利用を記録する
    struct DemoUsage: Codable {
        var dayKey = AppDay.key()
        var usageSeconds: [String: Int] = [:]
        /// SNS時間で当日の上限に足した分
        var extraLimitSeconds: [String: Int] = [:]
    }

    var settings: AppSettings { didSet { save() } }
    var snsApps: [SNSApp] { didSet { save() } }
    private(set) var sessions: [FocusSession] { didSet { save() } }
    private(set) var rewards: [RewardTransaction] { didSet { save() } }
    private(set) var attempts: [PersuasionAttempt] { didSet { save() } }
    private(set) var grants: [UnlockGrant] { didSet { save() } }
    private(set) var demoUsage: DemoUsage { didSet { save() } }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isLoading = true

    init(fileName: String = "todomeru-state.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        let snap = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        settings = snap.settings
        snsApps = snap.snsApps
        sessions = snap.sessions
        rewards = snap.rewards
        attempts = snap.attempts
        grants = snap.grants
        demoUsage = snap.demoUsage
        isLoading = false
        rolloverIfNeeded()
        cancelStaleAttempts()
    }

    private func save() {
        guard !isLoading else { return }
        let snap = Snapshot(settings: settings, snsApps: snsApps, sessions: sessions, rewards: rewards, attempts: attempts, grants: grants, demoUsage: demoUsage)
        do {
            try JSONEncoder().encode(snap).write(to: fileURL, options: .atomic)
        } catch {
            print("[AppStore] 保存に失敗: \(error)")
        }
    }

    /// デモ用: すべてのデータを初期化して初回設定からやり直す
    func resetAll() {
        settings = AppSettings()
        snsApps = SNSApp.catalog
        sessions = []
        rewards = []
        attempts = []
        grants = []
        demoUsage = DemoUsage()
    }

    // MARK: - 日付の切替（朝4時）

    /// 朝4時を過ぎていたら、デモの使用時間と一時利用枠を切り替える（SNS時間・回数はdayKeyで区切る）
    func rolloverIfNeeded(now: Date = .now) {
        let key = AppDay.key(of: now)
        if demoUsage.dayKey != key { demoUsage = DemoUsage(dayKey: key) }
        for i in grants.indices where grants[i].status == .active && grants[i].dayKey != key {
            grants[i].status = .ended
        }
    }

    // MARK: - SNS

    var selectedSNS: [SNSApp] { snsApps.filter(\.isSelected) }

    func sns(_ id: String) -> SNSApp? { snsApps.first { $0.id == id } }

    func setDailyLimit(_ seconds: Int, for snsID: String) {
        guard let i = snsApps.firstIndex(where: { $0.id == snsID }) else { return }
        let step = PolicyConstants.dailyLimitStepSeconds
        let clamped = min(max(0, seconds / step * step), PolicyConstants.dailyLimitMaxSeconds)
        snsApps[i].dailyLimitSeconds = clamped
    }

    // MARK: - 取り組み

    func session(_ id: UUID) -> FocusSession? { sessions.first { $0.id == id } }

    /// 進行中の取り組み（終了していないもの）
    var activeSession: FocusSession? { sessions.last { $0.endedAt == nil } }

    func startFocus(task: TaskItem, origin: Origin) -> FocusSession {
        // 進行中のものがあれば先に終える（同時に1つだけ）
        if let active = activeSession { endFocus(active.id) }
        let s = FocusSession(taskID: task.id, taskTitle: task.title, listName: task.listName, origin: origin, startedAt: .now)
        sessions.append(s)
        return s
    }

    /// 計測を終える（完了かどうかはふりかえりで本人が決める）。到達した25分単位の報酬を記録する
    func endFocus(_ id: UUID, at date: Date = .now) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].endedAt == nil else { return }
        sessions[i].endedAt = date
        recordFocusRewards(id)
    }

    /// デモ用: 取り組みの開始時刻を過去へずらし、経過時間を進める
    func shiftFocusStart(_ id: UUID, by seconds: Int) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].endedAt == nil else { return }
        sessions[i].startedAt.addTimeInterval(-Double(seconds))
    }

    func setOutcome(_ outcome: FocusSession.Outcome, for id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].outcome = outcome
    }

    /// 25分ごとに+5分。同じ取り組み・同じ単位番号は一度だけ（D028）
    func recordFocusRewards(_ id: UUID, now: Date = .now) {
        guard let s = session(id) else { return }
        let units = s.measuredSeconds(now: now) / PolicyConstants.focusRewardIntervalSeconds
        guard units > 0 else { return }
        for n in 1...units {
            appendReward(kind: .focus, seconds: PolicyConstants.focusRewardSeconds, key: "focus-\(id)-\(n)", dayKey: AppDay.key(of: s.startedAt))
        }
    }

    /// やること完了の報酬。リマインダーの更新成功後にだけ呼ぶ
    func recordCompletionReward(sessionID: UUID, taskID: String) {
        // earnedSeconds と同じく、取り組みを終えた日のキーで記録する
        let s = session(sessionID)
        let dayKey = AppDay.key(of: s?.endedAt ?? s?.startedAt ?? .now)
        appendReward(kind: .completion, seconds: PolicyConstants.completionRewardSeconds, key: "completion-\(taskID)-\(dayKey)", dayKey: dayKey)
    }

    /// その取り組みで獲得したSNS時間（取り組み分・完了分）
    func earnedSeconds(for sessionID: UUID) -> (focus: Int, completion: Int) {
        guard let s = session(sessionID) else { return (0, 0) }
        let focus = rewards.filter { $0.kind == .focus && $0.idempotencyKey.hasPrefix("focus-\(sessionID)-") }.reduce(0) { $0 + $1.seconds }
        let completion = rewards.filter { $0.kind == .completion && $0.idempotencyKey == "completion-\(s.taskID)-\(AppDay.key(of: s.endedAt ?? s.startedAt))" }.reduce(0) { $0 + $1.seconds }
        return (focus, completion)
    }

    /// 今日（朝4時区切り）の取り組み時間の合計
    func focusSecondsToday(now: Date = .now) -> Int {
        return sessions.filter { AppDay.isSameDay($0.startedAt, as: now) }.reduce(0) { $0 + $1.measuredSeconds(now: now) }
    }

    /// アリ度（%）= 取り組み時間 ÷ 目標時間 × 100（D011）。100で打ち止めにするかはAQ11で未決のため表示側で丸める
    func antDegree(now: Date = .now) -> Int {
        let goal = settings.dailyFocusGoalSeconds
        guard goal > 0 else { return 0 }
        return min(100, focusSecondsToday(now: now) * 100 / goal)
    }

    var grasshopperDegree: Int { 100 - antDegree() }

    // MARK: - SNS時間（台帳）

    /// 今日の残高（今日計上した取引の合計。朝4時で失効）
    func rewardBalanceToday() -> Int {
        let key = AppDay.key()
        return rewards.filter { $0.dayKey == key }.reduce(0) { $0 + $1.seconds }
    }

    /// 今日獲得したSNS時間の合計
    func rewardEarnedToday() -> Int {
        let key = AppDay.key()
        return rewards.filter { $0.dayKey == key && $0.seconds > 0 }.reduce(0) { $0 + $1.seconds }
    }

    private func appendReward(kind: RewardTransaction.Kind, seconds: Int, key: String, dayKey: String, snsID: String? = nil) {
        guard !rewards.contains(where: { $0.idempotencyKey == key }) else { return }
        rewards.append(RewardTransaction(kind: kind, seconds: seconds, dayKey: dayKey, idempotencyKey: key, snsID: snsID))
    }

    /// 獲得したSNS時間をSNSへ追加する（D032）。残高の検査と引落しを同時に行う。
    /// 上限に達して制限中なら一時利用枠を発行し、未到達なら当日の上限に足す（3.7.8の実装案）。
    @discardableResult
    func applyReward(seconds: Int, to snsID: String, sessionID: UUID) -> Result<Void, PolicyError> {
        let key = "spend-\(sessionID)"
        if rewards.contains(where: { $0.idempotencyKey == key }) { return .success(()) }
        guard seconds > 0 else { return .failure(.invalidProposal("追加するSNS時間がありません")) }
        guard rewardBalanceToday() >= seconds else { return .failure(.insufficientBalance) }
        guard sns(snsID) != nil else { return .failure(.invalidProposal("SNSが見つかりません")) }

        rewards.append(RewardTransaction(kind: .spend, seconds: -seconds, dayKey: AppDay.key(), idempotencyKey: key, snsID: snsID))
        if isOverLimit(snsID) {
            issueGrant(snsID: snsID, seconds: seconds, source: .reward)
        } else {
            demoUsage.extraLimitSeconds[snsID, default: 0] += seconds
        }
        if let i = sessions.firstIndex(where: { $0.id == sessionID }) { sessions[i].rewardTargetSNSID = snsID }
        return .success(())
    }

    // MARK: - 制限（デモ）

    func usageToday(_ snsID: String) -> Int { demoUsage.usageSeconds[snsID] ?? 0 }

    func effectiveLimit(_ snsID: String) -> Int {
        (sns(snsID)?.dailyLimitSeconds ?? 0) + (demoUsage.extraLimitSeconds[snsID] ?? 0)
    }

    func isOverLimit(_ snsID: String) -> Bool { usageToday(snsID) >= effectiveLimit(snsID) }

    func activeGrant(_ snsID: String) -> UnlockGrant? {
        grants.last { $0.snsID == snsID && $0.status == .active }
    }

    /// 制限中か（上限に達していて、有効な一時利用枠がない）
    func isRestricted(_ snsID: String) -> Bool { isOverLimit(snsID) && activeGrant(snsID) == nil }

    /// 疑似SNS画面での利用を記録する。一時利用枠があれば残りを減らし、0で終了（再制限）する。
    /// 戻り値: 枠を使い切って終了した場合 true
    @discardableResult
    func consumeUsage(_ snsID: String, seconds: Int) -> Bool {
        rolloverIfNeeded()
        let wasOver = isOverLimit(snsID)
        demoUsage.usageSeconds[snsID, default: 0] += seconds
        guard wasOver, let g = activeGrant(snsID), let i = grants.firstIndex(where: { $0.id == g.id }) else { return false }
        grants[i].remainingSeconds -= seconds
        if grants[i].remainingSeconds <= 0 {
            grants[i].remainingSeconds = 0
            grants[i].status = .ended
            return true
        }
        return false
    }

    /// デモ操作用: 使用時間を直接設定する
    func setDemoUsage(_ seconds: Int, for snsID: String) {
        demoUsage.usageSeconds[snsID] = max(0, seconds)
    }

    @discardableResult
    func issueGrant(snsID: String, seconds: Int, source: UnlockGrant.Source) -> UnlockGrant {
        let g = UnlockGrant(snsID: snsID, source: source, grantedSeconds: seconds, remainingSeconds: seconds, dayKey: AppDay.key())
        grants.append(g)
        return g
    }

    func lastEndedGrant(_ snsID: String) -> UnlockGrant? {
        grants.last { $0.snsID == snsID && $0.status == .ended }
    }

    // MARK: - 説得

    func attempt(_ id: UUID) -> PersuasionAttempt? { attempts.first { $0.id == id } }

    /// 今日回数に数えた説得
    func persuasionsUsedToday() -> Int {
        let key = AppDay.key()
        return attempts.filter { $0.dayKey == key && $0.countsTowardQuota }.count
    }

    func persuasionsRemainingToday() -> Int {
        max(0, PolicyConstants.persuasionDailyLimit - persuasionsUsedToday())
    }

    func beginAttempt(snsID: String) -> PersuasionAttempt {
        let a = PersuasionAttempt(snsID: snsID, dayKey: AppDay.key())
        attempts.append(a)
        return a
    }

    func updateAttempt(_ attempt: PersuasionAttempt) {
        guard let i = attempts.firstIndex(where: { $0.id == attempt.id }) else { return }
        attempts[i] = attempt
    }

    /// 説得を終える。数えない終わり方（1通も送っていない・失敗・やることへ着手）では回数の確保を戻す（D024）
    func finishAttempt(_ id: UUID, status: PersuasionAttempt.Status) {
        guard let i = attempts.firstIndex(where: { $0.id == id }), attempts[i].status == .active else { return }
        attempts[i].status = status
        switch status {
        case .failed, .redirectedToTask: attempts[i].countsTowardQuota = false
        case .cancelled: attempts[i].countsTowardQuota = attempts[i].userMessageCount > 0
        default: break
        }
    }

    /// 前回アプリが途中で終了した説得は、1通以上送っていればcancelledとして数える
    private func cancelStaleAttempts() {
        for a in attempts where a.status == .active { finishAttempt(a.id, status: .cancelled) }
    }
}
