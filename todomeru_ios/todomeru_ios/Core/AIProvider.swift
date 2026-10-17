import Foundation
import Observation

/// 説得AIの選択。エージェントがFoundation Models版と固定ルール版を実装して差し替える。
@Observable
final class AIProvider {
    var persuasion: any PersuasionAI = FallbackPersuasionAI()
}
