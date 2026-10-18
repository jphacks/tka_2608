import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 他アプリを覆うOSのShield。任意のSwiftUI画面をここへ載せることはできない。
final class TodomeruShieldConfiguration: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let canRoute = application.token.flatMap { SharedScreenTime.snsID(for: $0) } != nil
        return configuration(canRoute: canRoute)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    private func configuration(canRoute: Bool) -> ShieldConfiguration {
        let canOpenApp: Bool
        if #available(iOS 26.5, *) { canOpenApp = canRoute } else { canOpenApp = false }
        let brown = UIColor(red: 0.39, green: 0.23, blue: 0.12, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor(red: 1, green: 0.89, blue: 0.49, alpha: 1),
            icon: UIImage(systemName: "ant.fill"),
            title: .init(text: "やることやろう！", color: brown),
            subtitle: .init(text: canOpenApp
                ? "このアプリは制限中です。ToDo〆～るで次の行動を選ぼう。"
                : "このアプリは制限中です。閉じたあと、ホーム画面からToDo〆～るを開いてください。", color: brown),
            primaryButtonLabel: .init(text: canOpenApp ? "ToDo〆～るを開く" : "閉じる", color: .white),
            primaryButtonBackgroundColor: brown,
            secondaryButtonLabel: canOpenApp ? .init(text: "閉じる", color: brown) : nil
        )
    }
}
