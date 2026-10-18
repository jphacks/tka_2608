import Foundation

extension AIProvider {
    /// Claude API（APIキーの設定時）、端末内AI（Foundation Models）、固定の応答の順に、使えるものを設定したプロバイダ
    static func makeDefault() -> AIProvider {
        let p = AIProvider()
        p.useBestAvailable()
        return p
    }

    /// 現在の環境で使える説得AIに切り替える（説得画面の表示時に呼ぶ）
    func useBestAvailable() {
        if ClaudeClient.isConfigured {
            if !(persuasion is ClaudePersuasionAI), let claude = ClaudePersuasionAI() { persuasion = claude }
        } else if FoundationModelsPersuasionAI.isAvailable {
            if !(persuasion is FoundationModelsPersuasionAI) { persuasion = FoundationModelsPersuasionAI() }
        } else if !(persuasion is FallbackPersuasionAI) {
            persuasion = FallbackPersuasionAI()
        }
    }
}
