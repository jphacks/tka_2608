import Foundation
import Observation

/// 相談チャット（30:2 / 32:2 / 210:39 / 210:359）の状態と処理。回数の数え方は D024、納得度は D025。
@Observable
final class PersuasionViewModel {
    enum Phase: Equatable {
        /// 今日の相談を使い切っていて始められない
        case quotaExhausted
        /// 会話中
        case chatting
        /// UnlockPolicy を通った許可の提案（未発行）
        case approvable(seconds: Int)
        /// 不許可
        case rejected(reason: String)
        /// AIのエラー（回数に数えない）
        case failed(message: String)
    }

    /// 履歴としてAIへ渡す上限（D021）
    static let historyMaxCount = 8
    static let historyMaxCharacters = 2000

    let snsID: String
    private(set) var phase: Phase = .chatting
    private(set) var messages: [ChatMessage] = []
    private(set) var conviction = 0
    private(set) var isGenerating = false
    /// 生成中の返答（できた部分から表示する）
    private(set) var streamingText: String?
    private(set) var aiKindLabel = ""
    /// 最後に提案されたやること（不許可カードで勧める）
    private(set) var suggestedTask: TaskItem?
    var input = ""
    /// 相談が終わったあと、同じ画面でやることを選んでいる（210:39 / 210:359）
    private(set) var isPickingTask = false
    /// 「えらい！どれをやる？」のメッセージ（この下に候補一覧を出す）
    private(set) var pickPromptID: UUID?
    /// 判定（利用できる／できない）を出したアリの発言。この中に結果カードを出す
    private(set) var resultMessageID: UUID?
    /// やることの選択と開始は「やることを選ぶ」と同じ処理を使う
    let picker: TaskSelectViewModel

    @ObservationIgnored private var attempt: PersuasionAttempt?
    @ObservationIgnored private var lastReply: AIReply?
    @ObservationIgnored private var ai: any PersuasionAI = FallbackPersuasionAI()
    @ObservationIgnored private var didStart = false

    init(snsID: String) {
        self.snsID = snsID
        picker = TaskSelectViewModel(origin: .shield(snsID: snsID))
    }

    var antStage: Int { AntFace.stage(forConviction: conviction) }
    var userMessageCount: Int { attempt?.userMessageCount ?? 0 }
    var canSend: Bool { phase == .chatting && !isGenerating && attempt != nil && !isPickingTask }
    /// 相談が終わっている（結果が出た・失敗・回数切れ）
    var isFinished: Bool {
        switch phase {
        case .chatting, .approvable: return false
        case .rejected, .failed, .quotaExhausted: return true
        }
    }

    // MARK: - 開始

    /// 画面表示時に1回だけ呼ぶ。画面を開いただけでは回数に数えない（試行は作るが countsTowardQuota は false）
    func start(store: AppStore, provider: AIProvider, reminders: ReminderService) async {
        guard !didStart else { return }
        didStart = true
        provider.useBestAvailable()
        ai = provider.persuasion
        aiKindLabel = ai.kindLabel
        beginNewAttempt(store: store, reminders: reminders)
        if phase == .chatting, let draft = PersuasionDraft.take(for: snsID) {
            await send(draft, store: store, reminders: reminders)
        }
    }

    /// 新しい試行（再挑戦を含む）。納得度は0から
    func beginNewAttempt(store: AppStore, reminders: ReminderService) {
        conviction = 0
        lastReply = nil
        suggestedTask = nil
        isPickingTask = false
        pickPromptID = nil
        resultMessageID = nil
        picker.selected = nil
        picker.startError = nil
        guard UnlockPolicy.canStartPersuasion(store: store) else {
            attempt = nil
            phase = .quotaExhausted
            return
        }
        var a = store.beginAttempt(snsID: snsID)
        let name = snsName(store)
        let opening = ChatMessage(role: .ai, text: "\(name)を開きたいんだね。どうして今\(name)が必要なのか、教えてくれる？")
        messages.append(ChatMessage(role: .system, text: "新しい相談（今日あと\(store.persuasionsRemainingToday())回）"))
        messages.append(opening)
        a.messages = [opening]
        store.updateAttempt(a)
        attempt = a
        phase = .chatting
        // ユーザーが入力している間にモデルを読み込んでおく
        ai.prepare(for: makeContext(attempt: a, store: store, reminders: reminders))
    }

    // MARK: - 送信

    func sendInput(store: AppStore, reminders: ReminderService) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        input = ""
        await send(text, store: store, reminders: reminders)
    }

    func send(_ text: String, store: AppStore, reminders: ReminderService) async {
        guard canSend, var a = attempt else { return }
        // 最初の1通で回数を確保する（D024）
        if a.userMessageCount == 0 {
            guard store.persuasionsRemainingToday() > 0 else {
                store.finishAttempt(a.id, status: .cancelled)
                attempt = nil
                phase = .quotaExhausted
                return
            }
            a.countsTowardQuota = true
        }
        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        a.messages.append(userMessage)
        a.userMessageCount += 1
        store.updateAttempt(a)
        attempt = a

        isGenerating = true
        let context = makeContext(attempt: a, store: store, reminders: reminders)
        let reply = await generate(context)
        isGenerating = false
        streamingText = nil

        // 閉じた・別の試行に変わったあとに戻った応答は使わない
        guard let current = attempt, current.id == a.id, store.attempt(a.id)?.status == .active else { return }
        guard let reply else {
            store.finishAttempt(a.id, status: .failed)
            attempt = nil
            phase = .failed(message: "AIの応答を作れませんでした。この相談は回数に数えません。")
            return
        }
        apply(reply, store: store, reminders: reminders)
    }

    /// AIを呼ぶ。端末内AIが失敗したら固定応答に切り替えてもう一度試す
    private func generate(_ context: PersuasionContext) async -> AIReply? {
        let started = Date.now
        var firstPartial: Date?
        defer {
            let first = firstPartial.map { String(format: "%.1f", $0.timeIntervalSince(started)) } ?? "-"
            print("[Persuasion] \(ai.kindLabel) 最初の文字まで: \(first)秒 / 応答時間: \(String(format: "%.1f", Date.now.timeIntervalSince(started)))秒")
        }
        do {
            return try await ai.reply(to: context) { [weak self] partial in
                if firstPartial == nil { firstPartial = .now }
                self?.streamingText = partial
            }
        } catch {
            streamingText = nil
            print("[Persuasion] \(ai.kindLabel) の生成に失敗: \(error)")
            guard !(ai is FallbackPersuasionAI) else { return nil }
            ai = FallbackPersuasionAI()
            aiKindLabel = ai.kindLabel
            messages.append(ChatMessage(role: .system, text: "端末内AIが使えないため、デモ用の固定応答に切り替えました"))
            return try? await ai.reply(to: context)
        }
    }

    private func apply(_ reply: AIReply, store: AppStore, reminders: ReminderService) {
        guard var a = attempt else { return }
        let scoreIsValid = reply.convictionScore.map { (0...100).contains($0) } ?? false
        if scoreIsValid, let s = reply.convictionScore { conviction = s }
        // 納得度がない・範囲外の応答では許可の提案を受け付けない（D025）
        var checked = reply
        if !scoreIsValid && checked.action == .proposeUnlock { checked.action = .ask }

        let aiMessage = ChatMessage(role: .ai, text: reply.content)
        messages.append(aiMessage)
        a.messages.append(aiMessage)
        a.convictionScore = conviction
        store.updateAttempt(a)
        attempt = a
        lastReply = checked
        if let id = checked.taskID, let t = reminders.task(id: id), !t.isCompleted { suggestedTask = t }

        let isLast = a.userMessageCount >= PolicyConstants.persuasionMaxUserMessages
        defer { if isFinished || phase != .chatting { resultMessageID = aiMessage.id } }
        switch checked.action {
        case .proposeUnlock:
            switch UnlockPolicy.validate(reply: checked, attempt: a, store: store) {
            case .success(let seconds): phase = .approvable(seconds: seconds)
            case .failure(let err): reject(reason: err.errorDescription ?? PersuasionText.notConvinced, store: store)
            }
        case .reject:
            reject(reason: PersuasionText.notConvinced, store: store)
        case .ask, .suggestFocus:
            // 5通目で許可でなければ不許可（D024）
            if isLast { reject(reason: PersuasionText.notConvinced, store: store) }
        }
    }

    private func reject(reason: String, store: AppStore) {
        guard let a = attempt else { return }
        store.finishAttempt(a.id, status: .rejected)
        // 共通のエラー文言に残る旧表記を、画面の用語（相談）に合わせる
        phase = .rejected(reason: reason)
    }

    // MARK: - 操作

    /// 「Xを開く」: 発行直前にもう一度検査してから一時利用枠を発行する
    func openSNS(store: AppStore, router: Router) {
        guard case .approvable = phase, let a = attempt, let reply = lastReply else { return }
        switch UnlockPolicy.validate(reply: reply, attempt: a, store: store) {
        case .success(let seconds):
            store.issueGrant(snsID: snsID, seconds: seconds, source: .persuasion)
            store.finishAttempt(a.id, status: .approved)
            attempt = nil
            router.replaceTop(with: .demoSNS(snsID: snsID))
        case .failure(let err):
            reject(reason: err.errorDescription ?? PersuasionText.notConvinced, store: store)
        }
    }

    /// 「やることを片付ける」
    /// - 相談中（未判定）: 回数に数えずに終え、「やることを選ぶ」へ移る
    /// - 相談が終わったあと: 同じ画面でやることを選ぶ（試行はすでに終わっているので状態・回数は変えない）
    func goToTasks(store: AppStore, router: Router) {
        guard isFinished else {
            if let a = attempt { store.finishAttempt(a.id, status: .redirectedToTask) }
            attempt = nil
            router.replaceTop(with: .taskSelect(origin: .shield(snsID: snsID)))
            return
        }
        beginTaskPicking()
    }

    /// 210:39：「やっぱり、やることを片付ける！」→「えらい！どれをやる？」
    func beginTaskPicking() {
        guard !isPickingTask else { return }
        isPickingTask = true
        input = ""
        messages.append(ChatMessage(role: .user, text: "やっぱり、やることを片付ける！"))
        let prompt = ChatMessage(role: .ai, text: "えらい！どれをやる？")
        messages.append(prompt)
        pickPromptID = prompt.id
    }

    /// 210:359：選んだやることで取り組みを始める（開始前に再取得して存在・未完了を確認）
    func startPickedTask(store: AppStore, reminders: ReminderService, router: Router) async {
        await picker.start(store: store, reminders: reminders, router: router)
    }

    /// 「閉じる」: 1通以上送っていれば回数に数える（store側で判定）。終わった試行は store 側で変更されない
    func close(store: AppStore, router: Router) {
        if let a = attempt { store.finishAttempt(a.id, status: .cancelled) }
        attempt = nil
        router.close(origin: .shield(snsID: snsID))
    }

    // MARK: - 入力の組み立て

    private func makeContext(attempt a: PersuasionAttempt, store: AppStore, reminders: ReminderService) -> PersuasionContext {
        PersuasionContext(
            attemptID: a.id,
            snsName: snsName(store),
            tasks: TaskSelectViewModel.candidates(from: reminders.tasks),
            history: Self.trimmedHistory(a.messages),
            userMessageIndex: a.userMessageCount,
            previousConviction: conviction
        )
    }

    /// 直近8件・2,000文字以内に絞る（新しいものを優先）
    static func trimmedHistory(_ all: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var total = 0
        for m in all.filter({ $0.role != .system }).reversed() {
            guard result.count < historyMaxCount, total + m.text.count <= historyMaxCharacters else { break }
            result.insert(m, at: 0)
            total += m.text.count
        }
        return result
    }

    func snsName(_ store: AppStore) -> String { store.sns(snsID)?.name ?? "SNS" }
}
