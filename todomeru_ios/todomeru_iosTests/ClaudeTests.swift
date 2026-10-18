import Foundation
import Testing
@testable import todomeru_ios

/// Claude API版の相談AI（通信はせず、出力の読み取りだけを確かめる）
@Suite("Claude API")
struct ClaudeTests {
    private func context() -> PersuasionContext {
        PersuasionContext(attemptID: UUID(), snsName: "このアプリ", tasks: [makeTask(title: "レポート")],
                          history: [], userMessageIndex: 1)
    }

    @Test("生成途中のJSONから返答文を読める部分まで取り出す")
    func partialContent() {
        #expect(PartialJSON.stringValue(forKey: "content", in: #"{"convictionScore":80,"action":"ask""#) == nil)
        #expect(PartialJSON.stringValue(forKey: "content", in: #"{"action":"ask","content":""#) == "")
        #expect(PartialJSON.stringValue(forKey: "content", in: #"{"action":"ask","content": "集合場所の"#) == "集合場所の")
        #expect(PartialJSON.stringValue(forKey: "content", in: #"{"content":"「確認」\"だね\"\n次"}"#) == "「確認」\"だね\"\n次")
        #expect(PartialJSON.stringValue(forKey: "content", in: #"{"content":"\u3042い\"#) == "あい")
    }

    @Test("構造化出力を端末内AI版と同じ形の返答にする。やることは番号から選ぶ")
    func decodesReply() throws {
        let json = #"{"convictionScore":80,"action":"proposeUnlock","proposedSeconds":120,"taskNumber":1,"content":"2分で確認したら、やることに戻ろう。"}"#
        let c = context()
        let reply = try ClaudePersuasionAI.reply(fromJSON: json, context: c)
        #expect(reply.convictionScore == 80)
        #expect(reply.action == .proposeUnlock)
        #expect(reply.proposedSeconds == 120)
        #expect(reply.taskID == c.tasks.first?.id)
        #expect(reply.content == "2分で確認したら、やることに戻ろう。")
    }

    @Test("知らないactionは確認扱い、一覧にない番号のやることは使わない")
    func unknownValues() throws {
        let json = #"{"convictionScore":10,"action":"unlockNow","proposedSeconds":null,"taskNumber":9,"content":"どうしたの？"}"#
        let reply = try ClaudePersuasionAI.reply(fromJSON: json, context: context())
        #expect(reply.action == .ask)
        #expect(reply.taskID == nil)
    }

    @Test("出力の形はすべての項目を必須にし、余分な項目を許さない")
    func schemaIsStrict() throws {
        let schema = ClaudePersuasionAI.outputSchema
        let properties = try #require(schema["properties"] as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        #expect(Set(required) == Set(properties.keys))
        #expect(schema["additionalProperties"] as? Bool == false)
    }
}
