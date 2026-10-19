import Foundation
import Testing
@testable import todomeru_ios

@Suite("Issue #33 設定と表示の境界")
struct Issue33PolicyTests {
    @Test("3時間を超えて24時間まで増やせ、24時間で止まる")
    func dailyLimitSupportsWholeDay() {
        withTemporaryStore { store in
            #expect(SNSLimitStep.canIncrease(3 * 3600))
            #expect(SNSLimitStep.increased(24 * 3600 - 300) == 24 * 3600)
            #expect(!SNSLimitStep.canIncrease(24 * 3600))
            store.setDailyLimit(22 * 3600 + 25 * 60, for: "x")
            #expect(store.sns("x")?.dailyLimitSeconds == 22 * 3600 + 25 * 60)
            store.setDailyLimit(25 * 3600, for: "x")
            #expect(store.sns("x")?.dailyLimitSeconds == 24 * 3600)
        }
    }

    @Test("旧設定は相談3回へ移行し、変更した回数は保存できる")
    func settingsMigrationAndPersistence() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.persuasionDailyLimit == 3)
        let name = "issue33-\(UUID().uuidString).json"
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = AppStore(fileName: name)
        store.settings.persuasionDailyLimit = 7
        #expect(AppStore(fileName: name).settings.persuasionDailyLimit == 7)
    }

    @Test("相談回数の設定を開始時と解除直前の両方で検査する")
    func editableQuotaControlsPolicy() {
        guard PolicyConstants.limitsPersuasionPerDay else { return }
        withTemporaryStore { store in
            store.settings.persuasionDailyLimit = 1
            var first = store.beginAttempt(snsID: "x")
            first.countsTowardQuota = true
            first.userMessageCount = 1
            store.updateAttempt(first)
            #expect(!UnlockPolicy.canStartPersuasion(store: store))
            store.settings.persuasionDailyLimit = 2
            #expect(UnlockPolicy.canStartPersuasion(store: store))
            var second = store.beginAttempt(snsID: "x")
            second.countsTowardQuota = true
            second.userMessageCount = 1
            store.updateAttempt(second)
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: second, store: store) == .success(PolicyConstants.persuasionGrantMinSeconds))
            store.settings.persuasionDailyLimit = 1
            #expect(UnlockPolicy.validate(reply: makeReply(), attempt: second, store: store) == .failure(.quotaExceeded))
        }
    }

    @Test("上限0・追加のみ・追加なしの区切り位置が不正値にならない")
    func usageBoundary() {
        let zero = SNSUsageStatus(usedSeconds: 0, limitSeconds: 0, baseLimitSeconds: 0, state: .restricted)
        let extraOnly = SNSUsageStatus(usedSeconds: 0, limitSeconds: 60, baseLimitSeconds: 0, state: .normal)
        let baseOnly = SNSUsageStatus(usedSeconds: 0, limitSeconds: 1800, baseLimitSeconds: 1800, state: .normal)
        #expect(zero.baseLimitRatio == 0)
        #expect(extraOnly.baseLimitRatio == 0)
        #expect(baseOnly.baseLimitRatio == 1)
        #expect(zero.label == "0 / 0分")
    }
}
