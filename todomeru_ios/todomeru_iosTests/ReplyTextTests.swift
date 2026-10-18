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

    @Test("「」}」が出たら崩れとみなし、その前の返答だけを使う（シミュレータで実際に出た形）")
    func cutsAtBrokenEnd() {
        let samples = [
            "なんとなく見たくなったんだね。先にやることに5分だけ進めてみない？」} 相談ではやることを優先する方が良いと思うよ。」}<<5>>",
            "集合場所の確認は大事だね。2分で確認したら、レポートの序論に進もうか。？」} 相談の次はこの提案で",
            "連絡が来るかもしれないって感じだね。まずは、どんな連絡が来るか確認してみない？」} 相談の進行は",
        ]
        #expect(samples.allSatisfy(ReplyText.isBroken))
        #expect(ReplyText.tidy(samples[0]) == "なんとなく見たくなったんだね。先にやることに5分だけ進めてみない？")
        #expect(ReplyText.tidy(samples[1]) == "集合場所の確認は大事だね。2分で確認したら、レポートの序論に進もうか。")
        #expect(ReplyText.tidy(samples[2]) == "連絡が来るかもしれないって感じだね。まずは、どんな連絡が来るか確認してみない？")
        #expect(!ReplyText.isBroken("「レポート」を5分だけ進めてみない？"))
        #expect(ReplyText.tidy("「レポート」を5分だけ進めてみない？") == "「レポート」を5分だけ進めてみない？")
        #expect(ReplyText.tidy("まず「レポート」") == "まず「レポート」")
    }
}
