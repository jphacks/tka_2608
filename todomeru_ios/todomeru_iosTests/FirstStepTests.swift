import Foundation
import Testing
@testable import todomeru_ios

/// 返答を決めておくテスト用のAI
private struct StubFirstStepAI: FirstStepAI {
    var reply: String
    var fails = false
    func suggest(task: TaskItem, progress: String, onPartial: @escaping (String) -> Void) async throws -> String {
        if fails { throw FoundationModelsPersuasionAI.AIError.unavailable }
        onPartial(reply)
        return reply
    }
}

/// やることを選んだあとの「最初の一歩」
@Suite("最初の一歩の提案")
struct FirstStepTests {
    @Test("入力にはやることと答えをデータとして入れ、長い答えは切る")
    func promptCarriesData() {
        let task = makeTask(title: "レポートの序論")
        let prompt = FoundationModelsFirstStepAI.prompt(task: task, progress: String(repeating: "答", count: 300))
        #expect(prompt.contains("【やること（データ）】レポートの序論"))
        #expect(prompt.contains(String(repeating: "答", count: FoundationModelsFirstStepAI.maxProgressCharacters) + "…（以下省略）"))
        #expect(!prompt.contains(String(repeating: "答", count: FoundationModelsFirstStepAI.maxProgressCharacters + 1)))
        #expect(!FoundationModelsFirstStepAI.instructions.contains("レポートの序論"))
    }

    @MainActor
    private func pickingModel(store: AppStore, task: TaskItem) -> PersuasionViewModel {
        let model = PersuasionViewModel(snsID: "x")
        model.beginNewAttempt(store: store, reminders: ReminderService())
        model.beginTaskPicking()
        model.picker.select(task)
        return model
    }

    @Test("やることを選ぶと答えられ、答えると提案が出て、もう答えられない")
    @MainActor func answerProducesSuggestion() async {
        await withTemporaryStoreAsync { store in
            let task = makeTask(id: "t1", title: "レポート")
            let model = pickingModel(store: store, task: task)
            model.firstStepAI = StubFirstStepAI(reply: " まずキーワードを3つ書き出してみよう。 ")
            #expect(model.canAnswerFirstStep)
            #expect(model.canType(store: store))
            model.input = "1段落目は書けた"
            await model.sendInput(store: store, reminders: ReminderService())
            #expect(model.firstStepForSelected?.answer == "1段落目は書けた")
            #expect(model.firstStepForSelected?.suggestion == "まずキーワードを3つ書き出してみよう。")
            #expect(!model.canAnswerFirstStep)
            #expect(model.isPickingTask)
        }
    }

    @Test("AIが失敗したら決まった提案にする")
    @MainActor func fallbackOnFailure() async {
        await withTemporaryStoreAsync { store in
            let task = makeTask(id: "t1", title: "机の掃除")
            let model = pickingModel(store: store, task: task)
            model.firstStepAI = StubFirstStepAI(reply: "", fails: true)
            await model.answerFirstStep("まだ")
            #expect(model.firstStepForSelected?.suggestion == FallbackFirstStepAI.line(for: task))
        }
    }

    @Test("別のやることを選び直すと、もう一度答えられる")
    @MainActor func reselectResets() async {
        await withTemporaryStoreAsync { store in
            let model = pickingModel(store: store, task: makeTask(id: "t1"))
            model.firstStepAI = StubFirstStepAI(reply: "まず開いてみよう。")
            await model.answerFirstStep("まだ")
            model.picker.select(makeTask(id: "t2"))
            #expect(model.firstStepForSelected == nil)
            #expect(model.canAnswerFirstStep)
        }
    }
}

/// withTemporaryStore の非同期版
@MainActor
private func withTemporaryStoreAsync(_ body: (AppStore) async -> Void) async {
    let fileName = "todomeru-test-\(UUID().uuidString).json"
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    defer { try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName)) }
    await body(AppStore(fileName: fileName))
}
