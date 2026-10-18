import Foundation
import Observation

/// ふりかえり画面のロジック（Figma 90:2 / 37:125 / 182:81 / 182:337、ARCHITECTURE.md 2.5・3.7.8、D032）。
/// 状態は session.outcome と session.rewardTargetSNSID から復元するので、開き直しても壊れない。
/// 画面上だけの一時状態（処理中・エラー）だけをここで持つ。
@Observable
final class ReflectionViewModel {
    /// 画面の段階
    enum Stage: Equatable {
        /// 本人に「どこまでできた？」を聞いている
        case askingProgress
        /// 追加先アプリを選ぶ（ホーム起点）
        case choosingSNS
        /// Shield起点で対象アプリへ追加する前（自動で追加を試みる）
        case applyingToOrigin
        /// 追加まで終わった、または追加する時間がない
        case finished
    }

    let sessionID: UUID
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let reminders: ReminderService

    private(set) var isCompleting = false
    private(set) var completionError: String?
    private(set) var applyError: String?
    /// 選択したがまだ追加に成功していないアプリ（失敗時の表示用）
    private(set) var pendingSNSID: String?

    init(sessionID: UUID, store: AppStore, reminders: ReminderService) {
        self.sessionID = sessionID
        self.store = store
        self.reminders = reminders
    }

    // MARK: - 読み取り

    var session: FocusSession? { store.session(sessionID) }

    var measuredSeconds: Int { session?.measuredSeconds() ?? 0 }

    var earned: (focus: Int, completion: Int) { store.earnedSeconds(for: sessionID) }

    var totalSeconds: Int { earned.focus + earned.completion }

    var origin: Origin { session?.origin ?? .home }

    var outcome: FocusSession.Outcome? { session?.outcome }

    var targetSNS: SNSApp? { session?.rewardTargetSNSID.flatMap { store.sns($0) } }

    /// 追加先の候補（制限対象のアプリ）
    var candidates: [SNSApp] { store.selectedSNS }

    var stage: Stage {
        guard outcome != nil else { return .askingProgress }
        if totalSeconds == 0 || session?.rewardTargetSNSID != nil { return .finished }
        if origin.snsID != nil { return .applyingToOrigin }
        return .choosingSNS
    }

    /// 次の行動（ホームに戻る・別のやることを選ぶ）を出してよいか。選択前は出さない（U09）。
    /// Shield起点で自動追加に失敗したときは、行き止まりにしないため出す
    var showsNextActions: Bool {
        stage == .finished || (stage == .applyingToOrigin && applyError != nil)
    }

    /// Shield起点で対象アプリへ追加できたとき、疑似アプリを開く操作を出す
    var openableSNS: SNSApp? {
        guard stage == .finished, let id = origin.snsID, session?.rewardTargetSNSID == id else { return nil }
        return store.sns(id)
    }

    func usageText(_ sns: SNSApp) -> (text: String, isOver: Bool) {
        let status = SNSUsageStatus.make(sns.id, store: store)
        // 標準機能で選んだアプリはMonitor拡張の記録でも制限中になる（isRestricted）
        if status.isOverLimit || store.isRestricted(sns.id) { return ("上限に到達", true) }
        return (status.label, false)
    }

    // MARK: - 操作

    /// 画面を開いたとき。計測が続いていれば終える（終了時点の未計上分を記録）
    func onAppear() {
        if session?.endedAt == nil { store.endFocus(sessionID) }
        Task { await applyToOriginIfNeeded() }
    }

    /// 「完了にする」: リマインダーの更新に成功したときだけ完了扱いにして報酬を付ける
    func markCompleted() async {
        guard let session, !isCompleting, outcome == nil else { return }
        isCompleting = true
        completionError = nil
        defer { isCompleting = false }
        do {
            try await reminders.complete(taskID: session.taskID)
            store.recordCompletionReward(sessionID: sessionID, taskID: session.taskID)
            store.setOutcome(.completed, for: sessionID)
            await applyToOriginIfNeeded()
        } catch {
            completionError = "リマインダーを完了にできなかったよ（\(error.localizedDescription)）。もう一度試すか、「まだ続ける」を選んでね。"
        }
    }

    /// 「まだ続ける」: リマインダーは未完了のまま。時間分だけ（完了ボーナスなし）
    func markIncomplete() async {
        guard outcome == nil, !isCompleting else { return }
        completionError = nil
        store.setOutcome(.incomplete, for: sessionID)
        await applyToOriginIfNeeded()
    }

    /// ホーム起点: 候補をタップして追加先を決める
    func choose(_ sns: SNSApp) {
        guard stage == .choosingSNS else { return }
        pendingSNSID = sns.id
        apply(to: sns.id)
    }

    /// Shield起点: 開こうとしていたアプリへそのまま追加する（D032）
    func applyToOriginIfNeeded() async {
        guard stage == .applyingToOrigin, let id = origin.snsID else { return }
        apply(to: id)
    }

    func retryApplyToOrigin() {
        guard let id = origin.snsID else { return }
        apply(to: id)
    }

    private func apply(to snsID: String) {
        applyError = nil
        switch store.applyReward(to: snsID, sessionID: sessionID) {
        case .success:
            pendingSNSID = nil
        case .failure(let error):
            applyError = Self.message(for: error)
        }
    }

    static func message(for error: PolicyError) -> String {
        "アプリ時間を追加できなかったよ（\(error.localizedDescription)）。"
    }
}
