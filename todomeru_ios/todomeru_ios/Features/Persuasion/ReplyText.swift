import Foundation

/// 端末内AIの返答文を画面に出せる形に整える。
/// 構造化生成で判断項目を先に作らせると、返答を書き終えたところで出力全体を閉じるつもりの「」}」を
/// 文字列の中に書き、そのまま同じ文を繰り返して止まらなくなることがある（シミュレータで判断を先にした条件の約3〜7割）。
/// その合図か長さで生成を打ち切り、合図より前の部分だけを繰り返しを除いて短くする
enum ReplyText {
    /// これを超えたら生成を打ち切る（文字）
    static let streamCutoff = 160

    static func isRunaway(_ text: String) -> Bool { text.count > streamCutoff }

    /// 返答文の中に出力を閉じる記号が出た（ここから先は崩れている）
    static func isBroken(_ text: String) -> Bool { text.contains("}") }

    /// 続けて同じ文が出た分を除き、最大 maxSentences 文・maxCharacters 文字に収める
    static func tidy(_ text: String, maxSentences: Int = 2, maxCharacters: Int = 120) -> String {
        let usable = text.firstIndex(of: "}").map { String(text[..<$0]) } ?? text
        var kept: [String] = []
        for sentence in sentences(in: usable) where sentence != kept.last {
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
                if let s = cleaned(current) { result.append(s) }
                current = ""
            }
        }
        if let s = cleaned(current) { result.append(s) }
        return result
    }

    /// 前後の空白、対になる「のない」、引用符を除く。何も残らない切れ端は捨てる
    private static func cleaned(_ fragment: String) -> String? {
        var s = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"”"))
        while s.hasSuffix("」"), s.filter({ $0 == "」" }).count > s.filter({ $0 == "「" }).count {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
