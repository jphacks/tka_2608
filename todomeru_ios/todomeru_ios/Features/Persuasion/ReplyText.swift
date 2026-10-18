import Foundation

/// 端末内AIの返答文を画面に出せる形に整える。
/// 同じ文を繰り返して止まらなくなることがあるため、長くなりすぎたら生成を打ち切り、繰り返しを除いて短くする
enum ReplyText {
    /// これを超えたら生成を打ち切る（文字）
    static let streamCutoff = 160

    static func isRunaway(_ text: String) -> Bool { text.count > streamCutoff }

    /// 続けて同じ文が出た分を除き、最大 maxSentences 文・maxCharacters 文字に収める
    static func tidy(_ text: String, maxSentences: Int = 2, maxCharacters: Int = 120) -> String {
        var kept: [String] = []
        for sentence in sentences(in: text) where sentence != kept.last {
            guard kept.count < maxSentences else { break }
            guard (kept + [sentence]).joined().count <= maxCharacters else {
                if kept.isEmpty { kept.append(String(sentence.prefix(maxCharacters)) + "…") }
                break
            }
            kept.append(sentence)
        }
        return kept.joined()
    }

    /// 「。」「！」「？」で区切る。終わりの記号がない最後の部分も1文として扱う
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if "。！？!?".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { result.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result
    }
}
