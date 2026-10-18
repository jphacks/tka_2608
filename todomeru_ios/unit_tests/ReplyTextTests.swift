import Testing
@testable import todomeru_ios

/// 端末内AIの返答文の整形（同じ文の繰り返しで止まらなくなる対策）
@Suite("ReplyText")
struct ReplyTextTests {
    @Test("同じ文の繰り返しは1つにまとめる")
    func collapsesRepeats() {
        let looped = "いいね、確認してきて。" + String(repeating: "質問なし。", count: 50)
        #expect(ReplyText.tidy(looped) == "いいね、確認してきて。質問なし。")
        #expect(ReplyText.isRunaway(looped))
    }

    @Test("最大2文まで")
    func keepsTwoSentences() {
        #expect(ReplyText.tidy("一つ目。二つ目！三つ目？") == "一つ目。二つ目！")
    }

    @Test("文字数の上限を超える文は入れず、1文目だけで超えるなら切って印を付ける")
    func characterLimit() {
        let first = String(repeating: "あ", count: 100) + "。"
        #expect(ReplyText.tidy(first + String(repeating: "い", count: 30) + "。") == first)
        #expect(ReplyText.tidy(String(repeating: "う", count: 200)) == String(repeating: "う", count: 120) + "…")
    }

    @Test("短い返答はそのまま。終わりの記号がない部分も残す")
    func shortUnchanged() {
        #expect(ReplyText.tidy("わかった、2分だけね。") == "わかった、2分だけね。")
        #expect(ReplyText.tidy("まず開いてみよう") == "まず開いてみよう")
        #expect(!ReplyText.isRunaway("わかった、2分だけね。"))
    }
}
