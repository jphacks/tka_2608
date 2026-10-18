import Foundation
import Observation
import Testing
@testable import todomeru_ios

/// 相談チャットの入力欄が使えるか（#5）
@Suite("PersuasionViewModel の入力可否")
struct PersuasionViewModelTests {
    @Test("始める前は入力できない")
    func cannotTypeBeforeStart() {
        withTemporaryStore { store in
            let model = PersuasionViewModel(snsID: "x")
            #expect(!model.canSend)
            #expect(!model.canType(store: store))
        }
    }

    @Test("相談を始めると入力できるようになり、画面にその変化が通知される")
    func startingAttemptNotifiesCanSend() {
        withTemporaryStore { store in
            let model = PersuasionViewModel(snsID: "x")
            var changed = false
            withObservationTracking {
                _ = model.canSend
            } onChange: {
                changed = true
            }
            model.beginNewAttempt(store: store, reminders: ReminderService())
            #expect(changed)
            #expect(model.canSend)
            #expect(model.canType(store: store))
            #expect(!model.canRetryBySending(store: store))
        }
    }
}
