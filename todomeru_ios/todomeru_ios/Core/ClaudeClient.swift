import Foundation

/// Claude API（Anthropic Messages API）をストリーミングで呼ぶ最小のクライアント。
/// Swift向けの公式SDKはないため、HTTPとServer-Sent Eventsを直接扱う
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ClaudeError: LocalizedError {
        case http(status: Int, body: String)
        /// 安全上の理由で応答が断られた（フォールバック先のモデルも断った）
        case refusal
        /// 最後まで生成されなかった（max_tokens・通信の途切れなど）
        case incomplete(stopReason: String?)

        var errorDescription: String? {
            switch self {
            case .http(let status, let body): return "Claude APIのエラー（\(status)）: \(body)"
            case .refusal: return "Claudeが応答を断りました"
            case .incomplete(let reason): return "Claudeの応答が途中で終わりました（\(reason ?? "停止理由なし")）"
            }
        }
    }

    /// APIキー。Xcodeのスキームの環境変数 ANTHROPIC_API_KEY、Info.plist の ClaudeAPIKey
    /// （Config/ClaudeAPI.local.xcconfig の CLAUDE_API_KEY）の順に探す
    static var configuredAPIKey: String? {
        let candidates = [
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "ClaudeAPIKey") as? String,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }

    static var isConfigured: Bool { configuredAPIKey != nil }

    var apiKey: String

    init?() {
        guard let key = Self.configuredAPIKey else { return nil }
        apiKey = key
    }

    /// 1回分の応答を生成し、本文ができた部分から onText に渡す。戻り値は本文全体。
    /// schema を渡すと構造化出力（JSON）になる
    func stream(
        system: String,
        user: String,
        schema: [String: Any]? = nil,
        onText: (String) -> Void
    ) async throws -> String {
        // 短い会話なので考える量は少なめにして、返事までの時間を縮める
        var outputConfig: [String: Any] = ["effort": "low"]
        if let schema { outputConfig["format"] = ["type": "json_schema", "schema": schema] }
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": outputConfig,
            // 安全分類器に断られたとき、推奨モデルでサーバー側で再試行する
            "fallbacks": "default",
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw ClaudeError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        var text = ""
        var stopReason: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "content_block_delta":
                // 考えている途中（thinking）は表示せず、本文だけを使う。
                // 途中でフォールバックしたときも、続きの本文がそのまま後ろにつながる
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let piece = delta["text"] as? String else { continue }
                text += piece
                onText(text)
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? payload
                throw ClaudeError.http(status: status, body: message)
            default:
                continue
            }
        }
        switch stopReason {
        case "end_turn", "stop_sequence": return text
        case "refusal": throw ClaudeError.refusal
        default: throw ClaudeError.incomplete(stopReason: stopReason)
        }
    }
}

/// 生成途中のJSONから、文字列の値を読める部分まで取り出す（返答文を途中から表示するため）
enum PartialJSON {
    static func stringValue(forKey key: String, in json: String) -> String? {
        guard let keyRange = json.range(of: "\"\(key)\"") else { return nil }
        var rest = json[keyRange.upperBound...].drop { $0 == " " || $0 == "\n" }
        guard rest.first == ":" else { return nil }
        rest = rest.dropFirst().drop { $0 == " " || $0 == "\n" }
        guard rest.first == "\"" else { return nil }
        var value = ""
        var iterator = rest.dropFirst().makeIterator()
        while let ch = iterator.next() {
            switch ch {
            case "\"":
                return value
            case "\\":
                guard let escaped = iterator.next() else { return value }
                switch escaped {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": continue
                case "u":
                    var hex = ""
                    for _ in 0..<4 { if let h = iterator.next() { hex.append(h) } }
                    guard hex.count == 4, let code = UInt32(hex, radix: 16) else { return value }
                    if let scalar = Unicode.Scalar(code) { value.unicodeScalars.append(scalar) }
                default: value.append(escaped)
                }
            default:
                value.append(ch)
            }
        }
        return value
    }
}
