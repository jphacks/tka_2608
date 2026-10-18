import ManagedSettings

/// Shieldから本体を開く操作。ボタンを押しても制限は解除しない。
final class TodomeruShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed,
              let snsID = SharedScreenTime.snsID(for: application),
              SharedScreenTime.shieldPresentation.request(snsID: snsID) else {
            completionHandler(.close)
            return
        }
        if #available(iOS 26.5, *) {
            completionHandler(.openParentalControlsApp)
        } else {
            // 旧OSでは本体の自動起動APIがない。手動で開いたときに同じ要求を受け取る。
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
