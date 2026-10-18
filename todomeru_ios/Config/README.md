# ローカル署名設定

## Personal Team用ターゲットについて

既存の **`todomeru_ios_PersonalDemo`** ターゲットは本体と共有ソースを使いますが、Family Controls／App GroupsのentitlementsとScreen Time拡張を組み込まず、実際の他アプリの制限・使用時間取得は行いません。Settings内の固定候補選択と疑似SNS画面は削除済みです。実アプリの選択・制限を確認する場合は、対応する有料Teamで通常の **`todomeru_ios`** Schemeを使用します。

## ローカル設定の作成

App Groupは、そのTeamで登録・利用できる必要があります。本体・Report・Monitor・Shieldの各拡張のentitlementsは同じ `$(TODOMERU_APP_GROUP_IDENTIFIER)` を参照します。各Info.plistの `TodomeruAppGroupIdentifier` にも同じ値が展開され、`Shared/SharedScreenTime.swift` が実行中の本体／拡張のInfo.plistから読み取ります。今後IDを変更する際は、ローカル設定1か所だけを変更してください。署名エラーを隠すためにFamily Controlsのentitlementや拡張を削除しないでください。

手動署名を使う場合、プロファイルの名前も `Signing.local.xcconfig` に設定します。現在の通常版のDebug設定はこれらを参照します。署名方式（Manual／Automatic）は各ターゲットの設定に従い、この変数だけでは切り替わりません。

```xcconfig
TODOMERU_APP_PROFILE_SPECIFIER = 本体用プロファイル名
TODOMERU_REPORT_PROFILE_SPECIFIER = Report用プロファイル名
TODOMERU_MONITOR_PROFILE_SPECIFIER = Monitor用プロファイル名
TODOMERU_SHIELD_CONFIGURATION_PROFILE_SPECIFIER = Shield表示用プロファイル名
TODOMERU_SHIELD_ACTION_PROFILE_SPECIFIER = Shield操作用プロファイル名
```

通常版にはShieldの表示・ボタン操作を担当する `TodomeruShieldConfiguration` と `TodomeruShieldAction` も組み込みます。両拡張にもFamily Controlsと本体と同じApp Groupを設定した開発用プロファイルが必要です。[登録対象と実機確認手順](../../docs/SCREEN_TIME_SHIELD.md)を参照してください。

署名設定の変更にはローカルxcconfigを使います。XcodeのSigning画面でTeamやBundle IDを直接編集すると、個人の値が `project.pbxproj` に再保存される場合があるため、コミット前に差分を確認してください。

参考: [Apple: Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)

## Claude APIで相談する場合（`feature/claude-api`）

`ClaudeAPI.local.xcconfig.example` を同じフォルダーの `ClaudeAPI.local.xcconfig` へコピーし、`CLAUDE_API_KEY` にAnthropicのAPIキーを記入します。このファイルはGit除外対象です。シミュレータで試すだけなら、XcodeのScheme → Run → Arguments → Environment Variables に `ANTHROPIC_API_KEY` を設定しても使えます（Xcodeから起動したときだけ有効）。

キーがあれば相談と最初の一歩の提案に Claude API（`claude-opus-5-5`）を使い、なければ従来どおり端末内AI（Apple Intelligence）、それも使えなければ固定の応答になります。通信やAPIのエラーで返答が作れなかったときは、相談の途中から固定の応答に切り替わります。どちらの場合も、許可の可否はアプリの `UnlockPolicy` が検査します。

注意:

- やることの名前・期限と相談の会話がAnthropicのサーバーへ送られます。端末内AIと違い、通信が必要です。
- キーはアプリのInfo.plistに入るため、ビルドしたアプリから取り出せます。ハッカソンのデモ用の方法です。配布するアプリでは、キーを持つ中継サーバーを用意してください。
- 利用量に応じてAPI料金がかかります。
