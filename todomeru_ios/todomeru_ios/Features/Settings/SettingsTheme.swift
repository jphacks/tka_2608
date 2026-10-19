import SwiftUI

/// 初回設定・設定画面で使う追加の色（Figma 64:115 / 67:2 / 150:96 など）。
/// Theme にない色だけをここで名前を付けて定義する。
extension Theme {
    /// 権限画面のアイコン背景
    static let permissionScreenTime = Color(hex: 0x5E6AD2)
    static let permissionReminder = Color(hex: 0xF59E0B)
    static let permissionNotification = Color(hex: 0xEF4444)
    /// リスト選択・チェックの塗り（黄色）
    static let checkFill = Color(hex: 0xF4B400)
    /// 進捗ドットの未到達色
    static let progressInactive = Color(hex: 0xE6DCC4)
    /// ようこそ画面のキャラクター背景
    static let welcomeHalo = Color(hex: 0xFFEAB0)
}

/// 初回設定・設定画面の寸法と文字サイズ
enum SettingsMetrics {
    static let gutter: CGFloat = 16
    static let rowMinHeight: CGFloat = 50
    static let rowIconSize: CGFloat = 30
    static let heroSize: CGFloat = 130
    static let introCharacterSize: CGFloat = 76
    static let stepperValueWidth: CGFloat = 94
    static let sectionSpacing: CGFloat = 20

    static let largeTitle = Font.system(size: 30, weight: .heavy)
    static let stepTitle = Font.system(size: 24, weight: .heavy)
    static let sectionTitle = Font.system(size: 13, weight: .bold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let rowValue = Font.system(size: 14, weight: .bold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
}

