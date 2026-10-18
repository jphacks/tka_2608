import Foundation

extension AIProvider {
    /// 端末内AI（Foundation Models）が使えればそれを、使えなければ固定の応答を設定したプロバイダ
    static func makeDefault() -> AIProvider {
        let p = AIProvider()
        p.useBestAvailable()
        return p
    }

    /// 現在の環境で使える説得AIに切り替える（説得画面の表示時に呼ぶ）
    func useBestAvailable() {
        if FoundationModelsPersuasionAI.isAvailable {
            if !(persuasion is FoundationModelsPersuasionAI) { persuasion = FoundationModelsPersuasionAI() }
        } else if !(persuasion is FallbackPersuasionAI) {
            persuasion = FallbackPersuasionAI()
        }
    }
}
