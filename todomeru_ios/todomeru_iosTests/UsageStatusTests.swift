import Testing
@testable import todomeru_ios

/// SNSの「使用 / 上限」の表記とバー（使用時間タブ・ふりかえりの候補）
@Suite("SNSUsageStatus")
struct UsageStatusTests {
    @Test("追加がなければ「使用 / 上限分」")
    func labelWithoutExtra() {
        #expect(SNSUsageStatus.label(usedSeconds: 12 * 60, limitSeconds: 15 * 60, extraSeconds: 0) == "12 / 15分")
    }

    @Test("追加があれば元の上限と追加分を足し算で分け、括弧で囲む")
    func labelWithExtra() {
        #expect(SNSUsageStatus.label(usedSeconds: 12 * 60, limitSeconds: 15 * 60, extraSeconds: 6 * 60) == "12 / (15+6)分")
    }

    @Test("使うほど分子が増え、分母（元の上限＋追加分）は変わらない")
    func usageIncreasesNumeratorOnly() {
        withTemporaryStore { store in
            let base = store.sns("x")!.dailyLimitSeconds
            let before = SNSUsageStatus.make("x", store: store)
            store.consumeUsage("x", seconds: 5 * 60)
            let after = SNSUsageStatus.make("x", store: store)
            #expect(before.limitSeconds == base && after.limitSeconds == base)
            #expect(after.usedSeconds == before.usedSeconds + 5 * 60)
            #expect(after.label == "5 / \(base / 60)分")
        }
    }

    @Test("上限到達後にやることの時間を追加しても、分母の上乗せ分に足して表示する")
    func rewardAfterLimitShowsInDenominator() {
        withTemporaryStore { store in
            let base = store.sns("x")!.dailyLimitSeconds
            let reward = PolicyConstants.focusRewardSeconds
            store.setDemoUsage(base, for: "x")
            let s = store.runFocus(seconds: PolicyConstants.focusRewardIntervalSeconds)
            #expect(isSuccess(store.applyReward(to: "x", sessionID: s.id)))
            // 制限の仕組みは一時利用枠のまま（上限そのものは増やさない）
            #expect(store.effectiveLimit("x") == base)
            #expect(store.activeGrant("x")?.source == .reward)
            let status = SNSUsageStatus.make("x", store: store)
            #expect(status.limitSeconds == base + reward)
            #expect(status.label == "\(base / 60) / (\(base / 60)+\(reward / 60))分")
            #expect(!status.isOverLimit)
        }
    }

    @Test("相談の一時利用枠も、やることで増やした分とまとめて上乗せ分に数える")
    func persuasionGrantIsAddedTogether() {
        withTemporaryStore { store in
            let base = store.sns("x")!.dailyLimitSeconds
            let reward = PolicyConstants.focusRewardSeconds
            let persuasion = PolicyConstants.persuasionGrantMinSeconds
            let s = store.runFocus(seconds: PolicyConstants.focusRewardIntervalSeconds)
            #expect(isSuccess(store.applyReward(to: "x", sessionID: s.id)))
            store.setDemoUsage(base + reward, for: "x")
            store.issueGrant(snsID: "x", seconds: persuasion, source: .persuasion)
            let status = SNSUsageStatus.make("x", store: store)
            #expect(status.extraSeconds == reward + persuasion)
            #expect(status.label == "\((base + reward) / 60) / (\(base / 60)+\((reward + persuasion) / 60))分")
        }
    }

    @Test("バーは元の上限と追加分の和を100%とする")
    func ratioUsesSumOfLimits() {
        let s = SNSUsageStatus(usedSeconds: 7 * 60, limitSeconds: 21 * 60, baseLimitSeconds: 15 * 60, state: .normal)
        #expect(s.extraSeconds == 6 * 60)
        #expect(s.ratio == 1.0 / 3)
        #expect(s.label == "7 / (15+6)分")
    }

    @Test("バーの色相は0%で緑、100%以上で赤")
    func barHue() {
        #expect(SNSUsageStatus.barHue(ratio: 0) == Theme.barHueGreen)
        #expect(SNSUsageStatus.barHue(ratio: 0.5) == Theme.barHueGreen / 2)
        #expect(SNSUsageStatus.barHue(ratio: 1) == 0)
        #expect(SNSUsageStatus.barHue(ratio: 1.5) == 0)
    }
}
