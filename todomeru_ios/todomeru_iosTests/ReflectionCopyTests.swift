import Testing
@testable import todomeru_ios

/// ふりかえりの「どのSNSに使う？」の候補に出す表記
@Suite("ReflectionCopy")
struct ReflectionCopyTests {
    @Test("追加がなければ「使用 / 上限分」")
    func usageLabelWithoutExtra() {
        #expect(ReflectionViewModel.usageLabel(usageSeconds: 12 * 60, limitSeconds: 15 * 60, extraSeconds: 0) == "12 / 15分")
    }

    @Test("追加があれば元の上限と追加分を足し算で分け、括弧で囲む")
    func usageLabelWithExtra() {
        #expect(ReflectionViewModel.usageLabel(usageSeconds: 12 * 60, limitSeconds: 15 * 60, extraSeconds: 6 * 60) == "12 / (15+6)分")
    }
}
