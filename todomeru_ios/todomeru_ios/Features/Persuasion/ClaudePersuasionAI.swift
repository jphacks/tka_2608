import Foundation

/// Claude API による説得AI。指示・入力データ・出力の項目は端末内AI版と同じものを使い、
/// 構造化出力（JSON）で返答と候補アクションを受け取る。許可の可否は本体の UnlockPolicy が検査する。
///
/// やることの名前と会話はAnthropicのサーバーへ送られる。
final class ClaudePersuasionAI: PersuasionAI {
    var kindLabel: String { "Claude API" }

    private let client: ClaudeClient

    init?() {
        guard let client = ClaudeClient() else { return nil }
        self.client = client
    }

    func reply(to context: PersuasionContext) async throws -> AIReply {
        try await reply(to: context, onPartial: { _ in })
    }

    func reply(to context: PersuasionContext, onPartial: @escaping (String) -> Void) async throws -> AIReply {
        let json = try await client.stream(
            system: FoundationModelsPersuasionAI.instructions(for: context),
            user: FoundationModelsPersuasionAI.prompt(for: context),
            schema: Self.outputSchema
        ) { partial in
            if let text = PartialJSON.stringValue(forKey: "content", in: partial), !text.isEmpty {
                onPartial(text)
            }
        }
        return try Self.reply(fromJSON: json, context: context)
    }

    /// 構造化出力のJSONを、端末内AI版と同じ整形で AIReply にする
    static func reply(fromJSON json: String, context: PersuasionContext) throws -> AIReply {
        let output = try JSONDecoder().decode(Output.self, from: Data(json.utf8))
        return PersuasionOutput(
            convictionScore: output.convictionScore,
            action: output.action,
            proposedSeconds: output.proposedSeconds,
            taskNumber: output.taskNumber,
            content: output.content
        ).reply(tasks: FoundationModelsPersuasionAI.tasks(for: context))
    }

    private struct Output: Decodable {
        var convictionScore: Int
        var action: String
        var proposedSeconds: Int?
        var taskNumber: Int?
        var content: String
    }

    /// 出力の形（端末内AI版の PersuasionOutput と同じ項目・順番）。
    /// 判断項目を先に、返答文を最後に生成させる。値の範囲は本体の UnlockPolicy で検査する
    static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "convictionScore": ["type": "integer", "description": "事情への納得度。0〜100の整数"],
            "action": ["type": "string", "enum": AIReply.Action.allCases.map(\.rawValue), "description": "候補アクション"],
            "proposedSeconds": ["type": ["integer", "null"], "description": "proposeUnlockのときだけ、提案する利用時間（秒）"],
            "taskNumber": ["type": ["integer", "null"], "description": "勧めるやることの番号。やること一覧にあるものだけ"],
            "content": ["type": "string", "description": "ユーザーに話しかける日本語の返答だけ。1〜2文・120文字以内。ラベルや注記は書かない"],
        ],
        "required": ["convictionScore", "action", "proposedSeconds", "taskNumber", "content"],
        "additionalProperties": false,
    ]
}
