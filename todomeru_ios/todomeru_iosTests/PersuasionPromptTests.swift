import Foundation
import Testing
@testable import todomeru_ios

/// AIへ渡す指示と会話履歴（Issue #6）
@Suite("相談AIへの入力")
struct PersuasionPromptTests {
    private func context(history: [ChatMessage] = [], omitted: Bool = false) -> PersuasionContext {
        PersuasionContext(attemptID: UUID(), snsName: "このアプリ", tasks: [makeTask(title: "レポート")],
                          history: history, historyOmitted: omitted, userMessageIndex: 1)
    }

    @Test("固定の指示と例は定数を埋め込んだあと1,800文字以内")
    func instructionsFitBudget() {
        let text = FoundationModelsPersuasionAI.instructions(for: context())
        #expect(text.count <= 1800)
        #expect(text.contains("\(PolicyConstants.persuasionApprovalThreshold)以上"))
        #expect(text.contains("\(PolicyConstants.persuasionGrantMinSeconds)〜\(PolicyConstants.persuasionGrantMaxSeconds)秒"))
    }

    @Test("厳しさの各段階の文面は1,800文字以内に収まる")
    func strictnessLevelsFitBudget() {
        let base = FoundationModelsPersuasionAI.instructions(for: context())
        let current = Strictness.level(FoundationModelsPersuasionAI.strictness, threshold: PolicyConstants.persuasionApprovalThreshold)
        for level in 1...10 {
            let s = Strictness.level(level, threshold: PolicyConstants.persuasionApprovalThreshold)
            let extra = [s.band, s.first, s.rule, s.contactExample, s.breakExample, s.pretextExample].joined().count
                - [current.band, current.first, current.rule, current.contactExample, current.breakExample, current.pretextExample].joined().count
            #expect(base.count + extra <= 1800, "厳しさ\(level): \(base.count + extra)文字")
        }
    }

    @Test("対象アプリ・やること・会話は指示ではなく入力に入り、前回の納得度は渡さない")
    func promptCarriesData() {
        let history = [ChatMessage(role: .ai, text: "どうして？"), ChatMessage(role: .user, text: "ゼミの連絡")]
        let instructions = FoundationModelsPersuasionAI.instructions(for: context(history: history))
        let prompt = FoundationModelsPersuasionAI.prompt(for: context(history: history, omitted: true))
        #expect(!instructions.contains("レポート"))
        #expect(prompt.contains("【対象アプリ（データ）】このアプリ"))
        #expect(prompt.contains("1. レポート"))
        #expect(prompt.contains("（これより前の会話は省略）"))
        #expect(prompt.hasSuffix("ゼミの連絡"))
        #expect(!prompt.contains("前回の納得度"))
    }

    @Test("最新の発言が長くても履歴が空にならず、切り詰めた分を明示する。原文は変えない")
    func longLatestMessageIsTruncated() {
        let long = String(repeating: "あ", count: 2500)
        let all = [ChatMessage(role: .ai, text: "どうして？"), ChatMessage(role: .user, text: long)]
        let trimmed = PersuasionViewModel.trimmedHistory(all)
        #expect(trimmed.messages.count == 1)
        #expect(trimmed.omitted)
        let sent = trimmed.messages[0].text
        #expect(sent.count == PersuasionViewModel.historyMaxCharacters)
        #expect(sent.hasSuffix(PersuasionViewModel.truncationMark))
        #expect(all[1].text.count == 2500)
    }

    @Test("上限内なら全件を渡し、省略なし。システムの行は渡さない")
    func shortHistoryKeepsAll() {
        let all = [ChatMessage(role: .system, text: "新しい相談"), ChatMessage(role: .ai, text: "どうして？"),
                   ChatMessage(role: .user, text: "連絡を見たい")]
        let trimmed = PersuasionViewModel.trimmedHistory(all)
        #expect(trimmed.messages.map(\.text) == ["どうして？", "連絡を見たい"])
        #expect(!trimmed.omitted)
    }

    @Test("件数の上限を超えたら古いものから省く")
    func countLimit() {
        let all = (0..<10).map { ChatMessage(role: $0 % 2 == 0 ? .ai : .user, text: "\($0)") }
        let trimmed = PersuasionViewModel.trimmedHistory(all)
        #expect(trimmed.messages.map(\.text) == (2..<10).map { "\($0)" })
        #expect(trimmed.omitted)
    }
}
