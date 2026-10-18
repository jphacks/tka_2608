# 実アプリの上限到達とShieldの導線

2026-10-19 / 対象: `todomeru_ios`。ソース実装と静的確認の記録。Xcodeによるビルド・実機検証は未実施。

## 実装した流れ

1. 本体でFamily Controlsを認可し、対象アプリと日次上限を設定する。
2. 本体がDevice Activityの監視を登録する。初回許可・再許可・復帰時にも登録状態を照合する。
3. 対象の実使用時間が上限に達すると、OSが`TodomeruMonitor`を呼ぶ。拡張は対象をManaged SettingsのShieldへ追加する。本体がバックグラウンドでも、この処理をMonitorが担当する。
4. 対象アプリはOSのShieldで覆われる。`TodomeruShieldConfiguration`が黄色の背景・アリのアイコン・案内・ボタンを設定する。
5. iOS 26.5以降で「ToDo〆～るを開く」を押すと、`TodomeruShieldAction`がApp Groupへ対象IDを記録し、`.openParentalControlsApp`を返す。本体は起動／復帰時にMonitorの状態を読み、対象の選択状態と制限を確認して既存の`ShieldView`へ遷移する。

Shieldボタンから渡すのは画面遷移の要求だけで、制限解除や利用枠の付与は行わない。要求は1回だけ受け取り、5分経過・未来時刻・朝4時の日付切替前のものを破棄する。データ初期化後の再選択で古い対象IDへ進まないよう、監視対象のトークン対応表を更新する。

## OSによる境界

- 他アプリを覆うShieldはOSの画面。本体の任意のSwiftUIビューを他アプリ上へ重ねたり、上限到達だけで本体を無操作で前面起動したりする実装ではない。
- 本体を開く公式APIはShieldのボタン操作への応答として使う。使用SDKの定義ではiOS 26.5以降。iOS 26.0〜26.4では「閉じる」と本体を手動で開く案内を表示する。「閉じる」の直後に本体を開けば対象IDの要求を受け取る。
- 対象は、このアプリで選び、このアプリの監視へ登録した上限。iPhoneの設定アプリで別途設定した標準スクリーンタイムの上限を検知して、そのShieldを差し替える機能ではない。
- `todomeru_ios_PersonalDemo`はこれらの拡張を組み込まない。

参考: [Meet the Screen Time API（WWDC21）](https://developer.apple.com/videos/play/wwdc2021/10123/)では、独自の表示はそのアプリ自身がShieldを適用した対象に使われると説明されている。[ShieldConfigurationDataSource](https://developer.apple.com/documentation/managedsettingsui/shieldconfigurationdatasource)、[ShieldAction](https://developer.apple.com/documentation/managedsettings/shieldaction)、[openParentalControlsApp](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/openparentalcontrolsapp)。SDKのSwift interfaceとApple提供テンプレートも、ファイルとして読み取ってAPI・拡張ポイントを確認した。

## Apple標準の制限画面が出る場合

2026-10-19、利用者から、上限はiPhoneの「設定 → スクリーンタイム」で設定していたと回答があった。この設定による制限は、本アプリのMonitor・Shield拡張を経由しない。標準の上限値を自動で取り込んだり、その画面を本アプリのShieldへ差し替えたりする機能はない。

独自Shieldを確認するときは、次のように本アプリ側へ設定する。

1. 同じ対象に設定したApple標準の上限を一時的に外し、標準の制限画面が先に出ない状態で確認する。
2. 通常版のToDo〆～るで「使用時間 → アプリを追加・外す → アプリを選ぶ」を開き、スクリーンタイムへのアクセスを許可し、対象の**個別アプリ**を選ぶ。「候補から選ぶ」の固定項目は実アプリのトークンを持たないため、実機の制限対象にはならない。
3. 「使用時間」で選んだアプリの行をタップし、上限を設定する。まず0分にして対象アプリを開き、黄色の背景・アリのアイコン・「やることやろう！」の独自OS Shieldが出るか確認する。有効な一時利用枠がある間は制限されない。
4. iOS 26.5以降では「ToDo〆～るを開く」を押し、本体の`ShieldView`へ進むか確認する。iOS 26.0〜26.4では「閉じる」を押した直後に本体を手動で開く。
5. 続いて正の上限で監視を確認する。当日の朝4時以降の既存使用分も閾値判定に含むため、設定後の使用時間だけを数えるわけではない。

この設定での実機結果は未確認。コード上の接続を静的に確認した範囲であり、独自Shieldが実機で表示できたとは扱わない。

## 実機ビルド前に必要な追加設定（利用者・Team管理者が行う）

既存の本体・Report・Monitorに加え、次の2拡張のApp IDと開発用プロファイルを用意する。Apple側の登録・変更は今回行っていない。

| ターゲット | Bundle ID | ローカル設定のプロファイル名 |
| --- | --- | --- |
| `TodomeruShieldConfiguration` | 本体ID + `.TodomeruShieldConfiguration` | `TODOMERU_SHIELD_CONFIGURATION_PROFILE_SPECIFIER` |
| `TodomeruShieldAction` | 本体ID + `.TodomeruShieldAction` | `TODOMERU_SHIELD_ACTION_PROFILE_SPECIFIER` |

両App IDでFamily Controls（Development）を有効にし、本体と同じApp Groupを割り当てる。同じTeam・開発証明書・テスト用iPhoneを使って作ったプロファイルをMacへ入れ、その名前をGit除外済みの`todomeru_ios/Config/Signing.local.xcconfig`へ記入する。Debugは既存通常版と同じ手動署名、Releaseは自動署名の設定。Team・Bundle ID・App Groupの実値を共有ファイルへ書かない。[AppleのFamily Controls設定](https://developer.apple.com/documentation/xcode/configuring-family-controls)

## 実機で確認すること

1. 通常版をビルド・起動し、スクリーンタイムを認可してアプリを選ぶ。まず0分設定でShieldとボタンの経路を確認する。
2. 正の上限（例: 5分）を設定し、本体をバックグラウンドへ移す。対象アプリを使い、上限到達でOSのShieldが表示されることを確認する。
3. Shieldのボタンから本体が開き、正しい対象の`ShieldView`が表示されることを確認する。本体の終了状態／バックグラウンド状態の両方で試す。
4. ボタンを押すだけでは制限が外れないこと、許可された利用枠を使い切ると再制限されることを確認する。
5. 認可の取消し・再許可、対象の削除・再選択、日付切替、古い要求では意図しない対象へ遷移しないことを確認する。

`todomeru_ios/unit_tests/ShieldPresentationTests.swift`に要求の消費・期限・日付切替・遷移時の対象検査を確認する6テストを追加した。テスト群はSwift Testingによるユニットテストで、旧ディレクトリ名`todomeru_iosTests`から`unit_tests`へ移した。Xcodeのターゲット名・生成物名は既存の`todomeru_iosTests`を維持する。Xcode実行禁止の指定により、これらのテストも今回は未実行。
