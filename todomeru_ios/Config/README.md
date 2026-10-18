# ローカル署名設定

## Personal Teamでデモを起動する場合

Scheme **`todomeru_ios_PersonalDemo`** を選んでRunします。このターゲットは本体と共有ソースを使いますが、Family Controls／App GroupsのentitlementsとReport／Monitor拡張を組み込みません。`TODOMERU_PERSONAL_DEMO` の条件で実際のScreen Time認可・アプリ選択・使用時間Reportを止め、既存の疑似SNS画面とデモ候補を使います。実際の他アプリの制限・使用時間取得は行いません。リマインダーとAIの実装はそのままです。

## ローカル設定の作成

`Signing.local.xcconfig.example` を同じフォルダーの `Signing.local.xcconfig` へコピーし、使用するTeam IDと一意な開発用Bundle IDを記入します。実値を含むローカルファイルはGit除外対象です。共有する `project.pbxproj` へ個人の値を直接保存しないでください。

プロジェクトのDebug／Releaseは共有の `Signing.xcconfig` を読み、末尾の任意includeでローカル設定を上書きします。本体・Report拡張・Monitor拡張は同じTeamを使い、拡張のBundle IDには本体のIDと拡張名を使います。テストとDemoXにも別の接尾辞を使います。

通常の **`todomeru_ios`** Schemeでは、Family ControlsとApp Groupsの有効な開発用プロファイルが必要です。**無料のPersonal Teamでは、実際のScreen Time機能を維持した実機ビルドはできません。** Apple Developer Program登録済みで、App ID・App Group・端末を登録できる権限のあるTeamを使ってください。TestFlight／App Store配布向けのFamily Controls申請は開発時の設定とは別です。PersonalDemoとは別のターゲットとして、本来のentitlements・拡張・実装は残しています。

App Groupは本体・Report・Monitorのentitlementsと `Shared/SharedScreenTime.swift` の値を一致させ、そのTeamで登録・利用できる必要があります。署名エラーを隠すためにFamily Controlsのentitlementや拡張を削除しないでください。

署名設定の変更にはローカルxcconfigを使います。XcodeのSigning画面でTeamやBundle IDを直接編集すると、個人の値が `project.pbxproj` に再保存される場合があるため、コミット前に差分を確認してください。

参考: [Apple: Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
