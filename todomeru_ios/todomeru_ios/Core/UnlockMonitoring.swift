import Foundation

/// 本体の割当を確定する前にOSの監視を準備する。テストでは失敗する登録先へ差し替える。
@MainActor
protocol UnlockMonitoring: AnyObject {
    func prepare(_ grant: UnlockGrant, limits: [ScreenTimeMonitorState.Limit]) throws
    func commit(_ grant: UnlockGrant, temporary: Bool) throws
    func rollback(_ grant: UnlockGrant)
}
