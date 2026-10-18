import Foundation

// MARK: - アプリ（制限対象）

/// 制限対象のアプリ。デモでは固定の候補から選ぶ（実機のScreen Time連携ではApplicationTokenに置き換える）。
struct SNSApp: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    /// SF Symbols名
    var symbol: String
    /// 0xRRGGBB
    var tintHex: UInt32
    var isSelected: Bool
    var dailyLimitSeconds: Int
    /// iOS標準のアプリ選択で選んだアプリのトークン（JSON）。nil ならデモの候補
    var tokenData: Data? = nil

    /// 文章（AIへの入力・メッセージ）で使う呼び名。標準機能で選んだアプリは名前が読めないので「このアプリ」
    var textName: String { name.isEmpty ? "このアプリ" : name }

    static let catalog: [SNSApp] = [
        SNSApp(id: "x", name: "X", symbol: "xmark", tintHex: 0x111111, isSelected: true, dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds),
        SNSApp(id: "instagram", name: "Instagram", symbol: "camera", tintHex: 0xD62976, isSelected: true, dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds),
        SNSApp(id: "youtube", name: "YouTube", symbol: "play.rectangle.fill", tintHex: 0xFF0000, isSelected: true, dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds),
        SNSApp(id: "puzzle", name: "パズルゲーム", symbol: "puzzlepiece.fill", tintHex: 0x8E6CEF, isSelected: true, dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds),
        SNSApp(id: "line", name: "LINE", symbol: "message.fill", tintHex: 0x06C755, isSelected: false, dailyLimitSeconds: PolicyConstants.defaultDailyLimitSeconds),
    ]
}

// MARK: - やること（リマインダー）

struct ReminderListInfo: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var openCount: Int
    var colorHex: UInt32
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var listID: String
    var listName: String
    var dueDate: Date?
    /// 期限に時刻が付いているか
    var dueHasTime: Bool
    /// EKReminderの優先度（0=なし, 1=高 … 9=低）
    var priority: Int
    var createdAt: Date?
    var isCompleted: Bool
    var completionDate: Date?
    /// リマインダーのメモ。最初の一歩の提案でAIへ渡す（アプリには保存しない）
    var notes: String? = nil
}

enum Origin: Codable, Hashable {
    case home
    case shield(snsID: String)

    var snsID: String? {
        if case .shield(let id) = self { return id }
        return nil
    }
}

// MARK: - 取り組み

struct FocusSession: Identifiable, Codable, Hashable {
    enum Outcome: String, Codable { case completed, incomplete }

    var id = UUID()
    var taskID: String
    var taskTitle: String
    var listName: String
    var origin: Origin
    var startedAt: Date
    var endedAt: Date?
    var outcome: Outcome?
    /// 獲得したアプリ時間を追加したアプリ（ホーム起点は選択、Shield起点は対象アプリ）
    var rewardTargetSNSID: String?

    func measuredSeconds(now: Date = .now) -> Int {
        Int((endedAt ?? now).timeIntervalSince(startedAt))
    }
}

// MARK: - 取り組みで獲得したアプリ時間

/// 取り組み1回ごとの獲得記録。残高として貯めず、ふりかえりでそのまま選んだアプリに追加する（issue #9）
struct RewardTransaction: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case focus, completion }

    var id = UUID()
    var kind: Kind
    var seconds: Int
    /// 二重付与を防ぐキー
    var idempotencyKey: String
    var createdAt = Date.now
}

// MARK: - 説得

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case ai, user, system }
    var id = UUID()
    var role: Role
    var text: String
    var createdAt = Date.now
}

struct PersuasionAttempt: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case active, approved, rejected, cancelled, failed, redirectedToTask
    }

    var id = UUID()
    var snsID: String
    var dayKey: String
    var startedAt = Date.now
    var status: Status = .active
    var userMessageCount = 0
    var convictionScore = 0
    /// 回数に数えるか（D024: 最初の1通で確保し、数えない終わり方で戻す）
    var countsTowardQuota = false
    var policyVersion = PolicyConstants.version
    var messages: [ChatMessage] = []
}

// MARK: - 一時利用枠

struct UnlockGrant: Identifiable, Codable, Hashable {
    enum Source: String, Codable { case persuasion, reward }
    enum Status: String, Codable { case active, ended }

    var id = UUID()
    var snsID: String
    var source: Source
    var grantedSeconds: Int
    /// 実利用で減る残り（デモでは疑似アプリ画面の利用時間で減らす）
    var remainingSeconds: Int
    var dayKey: String
    var status: Status = .active
    var createdAt = Date.now
    var policyVersion = PolicyConstants.version
}

// MARK: - 設定

struct AppSettings: Codable, Hashable {
    var onboardingCompleted = false
    var selectedListIDs: Set<String> = []
    /// 新しいリストを自動で追加（設定内だけ、初期OFF）
    var autoAddNewLists = false
    var dailyFocusGoalSeconds = PolicyConstants.defaultDailyFocusGoalSeconds
    /// リマインダーの代わりにデモ用のやることを使う
    var useDemoTasks = false

    init() {}

    /// 項目が欠けた保存データでも、欠けた項目だけ初期値で補う
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        selectedListIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedListIDs) ?? d.selectedListIDs
        autoAddNewLists = try c.decodeIfPresent(Bool.self, forKey: .autoAddNewLists) ?? d.autoAddNewLists
        dailyFocusGoalSeconds = try c.decodeIfPresent(Int.self, forKey: .dailyFocusGoalSeconds) ?? d.dailyFocusGoalSeconds
        useDemoTasks = try c.decodeIfPresent(Bool.self, forKey: .useDemoTasks) ?? d.useDemoTasks
    }
}
