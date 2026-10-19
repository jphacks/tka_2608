# 実アプリの上限到達とShieldの導線

2026-10-19 / 対象: `todomeru_ios`。MonitorとReportの不整合を調査・修正。今回の修正のビルド・テスト実行・実機動作は未検証。Issue #33等の過去のビルド成功は、その時点の記録。

## Reportが上限未満なのに制限される問題の調査・修正（2026-10-19）

Reportは使用時間の表示、Monitorは上限到達と利用枠終了の通知を担当する。両者を分ける構成自体ではなく、Monitorの古い状態の扱いと利用枠の終了条件に、次の不整合があった。以下はコードから確認した経路であり、報告された端末の原因を実機で特定したものではない。

| 問題・起きる例 | 原因 | 今回の修正 |
| --- | --- | --- |
| 30分に到達してから上限を60分に増やしても、30 / 60分で制限が残る | 到達済みを日付とアプリIDだけで保存し、どの上限への到達か区別していなかった | 監視条件（対象・トークン・上限）にイベント名をひも付ける。条件を変更した対象だけ新しいイベント名にし、現在の上限と一致する到達記録だけ取り込む。変更前の遅延通知も無視する |
| 30分使用後に5分の利用枠を得て、対象を使わず20分後に戻ると30 / 35分で制限される | 利用枠を実使用に関係なく「付与秒数＋15分」の経過で終了していた。Reportの表示上限には付与分が残る | 時計だけで終了する処理を撤去。既存D023どおり、Monitorの実利用到達・朝4時の日付切替で終了する |
| 利用枠が残っているのに日次通知で再制限される。朝4時をまたいだ古い枠の通知でも制限される | Monitorが有効な利用枠や日付を確認せず、通知対象を無条件にShieldへ追加していた | 本体から有効な枠のID・対象・日付を共有し、全通知で現在の到達記録と有効枠からShieldを再計算する。終了済み・旧日の枠通知を無視し、不要になった監視も停止する |
| 30分＋相談5分を使用後に基本上限を60分へ増やすと、表示65分に対して60分で制限される | 表示は今日の全付与分を足すが、日次監視は一時利用枠を除いた上限だった | 表示と日次監視が同じ`totalLimitToday`（基本上限＋今日の全付与分）を使う。枠終了だけでは新しい総上限への到達とみなさず、有効な枠は引き続き元の終了条件まで維持する |

共有状態は`Shared/ScreenTimeMonitorState.swift`へまとめ、実使用量は共有しない。同じ日の同じ条件での再登録では到達済みを維持し、別アプリの上限変更で制限が消えないようにする。朝4時にはMonitorが基本上限へ戻し、日次監視も登録し直す。通知名も日ごとに変え、前日の通知を当日の到達として使わない。0分は引き続き即制限し、有効な利用枠がある間はその枠を優先する。本体も設定変更時・復帰時・定期照合で現在の制限を反映する。本体の再起動時もOS上の登録済み利用枠の監視は再利用し、開始時刻を現在へ変更して使用時間を起算し直さない。[Apple: activities](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/activities)、[startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring%28_%3Aduring%3Aevents%3A%29)

旧形式の`limitReached`は上限を特定できないため新判定には使わず、更新後の監視で判定し直す。日次イベントの`includesPastActivity: true`は維持し、当日朝4時以降の既存使用分を再判定の対象にする。[Apple: DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent)

**残る表示差・未検証範囲**

- ReportはOSから受け取った集計値を表示し、Monitorの通知と同時に更新される保証はない。約60秒ごとの再生成でも、OS側のデータ更新を強制できない。数字が古い間の一時的な表示差は今回の修正だけでは解消しない。Reportの値を本体へ書き出して解除判定する方式には変更しない。[Apple: DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)
- Reportはアプリごとの秒数を合算してから分未満を切り捨てる。通常日の集計範囲はMonitorと同じ朝4時区切りで、今回この集計計算に明確な誤りは見つからなかった。
- **OSの集計対象による差:** Appleによると、一部アプリの日次イベントには関連Webドメインの使用が暗黙に含まれる。今回のReportはアプリの使用時間を集計しているため、Web利用がある場合にMonitorが先に上限へ達する可能性がある。これは資料と実装からの推論で、報告端末の原因としては未確認。無関係なWeb使用をアプリ時間へ加算する変更は行わない。[Apple: DeviceActivityEvent initializer](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/init%28applications%3Acategories%3Awebdomains%3Athreshold%3Aincludespastactivity%3A%29)
- 日次監視の日付切替での再登録、OSの閾値通知の精度、別プロセス間の反映順序は実機確認が必要。朝4時の監視再登録に失敗した場合のエラーはMonitorへ出力し、本体の復帰時に再登録を試みる。実機での確実な再制限を確認できたとは扱わない。
- 文書に残るXcode実行禁止の指示を引き継ぎ、今回Xcode・ビルド・単体テスト・実機操作は実施していない。回帰テストの追加と静的な参照・差分検査までを実施範囲とする。

実機では、(1)上限到達後に上限を増やす、(2)利用枠を得た後、別アプリで20分以上過ごしてから戻る、(3)利用枠中の監視再登録・本体の再起動、(4)朝4時直前の枠発行と日付切替、(5)使用済み追加時間がある状態での上限変更、を確認する。各ケースで対象アプリのShieldと本体の制限状態を確認し、Reportの更新遅延と関連Web利用の有無は分けて記録する。

## 実装した流れ

1. 本体でFamily Controlsを認可し、対象アプリと日次上限を設定する。
2. 本体がDevice Activityの監視を登録する。初回許可・再許可・復帰時にも登録状態を照合する。
3. 対象の実使用時間が上限に達すると、OSが`TodomeruMonitor`を呼ぶ。拡張は現在の上限・有効な利用枠を検査してManaged SettingsのShieldを反映する。本体がバックグラウンドでも、この処理をMonitorが担当する。
4. 対象アプリはOSのShieldで覆われる。`TodomeruShieldConfiguration`が黄色の背景・本体と同じアリの画像（`shield_ant`）・案内・ボタンを設定する。
5. iOS 26.5以降で「アリに相談する」を押すと、`TodomeruShieldAction`がApp Groupへ対象IDを記録し、`.openParentalControlsApp`を返す。本体は起動／復帰時にMonitorの状態を読み、対象の選択状態と制限を確認して対象の`PersuasionView`（相談チャット）へ直接遷移する。

Shieldボタンから渡すのは画面遷移の要求だけで、制限解除や利用枠の付与は行わない。要求は1回だけ受け取り、5分経過・未来時刻・朝4時の日付切替前のものを破棄する。データ初期化後の再選択で古い対象IDへ進まないよう、監視対象のトークン対応表を更新する。

## 0分設定がShieldへ反映される条件

0分はDevice Activityの閾値通知を待たない。本体で次の処理を行う。

1. `SNSLimitEditor`の増減操作が`AppStore.setDailyLimit`を呼び、基本上限を保存する。
2. 実アプリの当日の総上限は「基本上限＋今日の全付与分（一時利用枠も含む）」。`isOverLimit`は「総上限が0、または現在の上限へのMonitor到達記録あり」、`isRestricted`は「上限到達かつ有効な一時利用枠なし」で判定する。追加時間・一時利用枠があると、基本上限だけ0分にしても即制限にはならない。デモの使用記録は実アプリの判定には混ぜない。
3. `restrictedPickedTokens`は、選択中・制限中で、実アプリのトークンを復元できる対象を集める。
4. `RootView`の`onChange`が`ScreenTimeService.syncLimitShield`を呼ぶ。認可が`approved`の場合に`ManagedSettingsStore`（`todomeru.limits`）の`shield.applications`へ書き込む。未認可なら書き込まない。
5. OSが対象をShieldで覆い、Configuration拡張が表示を設定する。ボタンから本体へ進む処理は、その後の別の段階。

**2026-10-19の不具合修正:** 通常版も固定候補のX・Instagram等を選択済みとして表示し、0分へ変更できていた。しかし固定候補には実トークンがなく、上記3で除外されるため、実アプリは制限されない。この実装上の不整合を修正し、通常版の一覧・初回設定・追加画面では、OSピッカーから得た有効なトークンのアプリだけを選択済みとして扱う。固定候補の選択・認可失敗時の固定候補への迂回は通常版から外した。PersonalDemoの固定候補と既存の保存データは維持する。

加えて、Monitor再登録時の`intervalDidStart`は同じShieldストアを`alwaysShieldedTokens`で上書きするが、この共有値だけ読み書きの同期がなかった。他の共有値と同様にsetter後・getter前の同期を追加し、変更前の0分対象で上書きする競合の余地を減らした。拡張の呼出し順序・共有のタイミングが今回の実機症状の原因だったかは未検証。

報告された端末で固定候補を選んでいたかは未確認であり、この不整合を実機の唯一の原因と断定しない。OSピッカーで追加した実アプリでも出ない場合は、認可状態、追加時間・一時利用枠、実機に入っているターゲットと版を切り分ける必要がある。Xcode操作・実機テストは禁止のため実施していない。

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
2. 通常版のToDo〆～るで「使用時間 → アプリを追加・外す → アプリを選ぶ」を開き、スクリーンタイムへのアクセスを許可し、対象の**個別アプリ**を選ぶ。修正前にあった「候補から選ぶ」の固定項目は実アプリのトークンを持たないため、通常版の一覧と選択画面から外した。
3. 「使用時間」で選んだアプリの行をタップし、上限を設定する。まず0分にして対象アプリを開き、黄色の背景・アリのアイコン・「やることやろう！」の独自OS Shieldが出るか確認する。有効な一時利用枠がある間は制限されない。
4. iOS 26.5以降では「アリに相談する」を押し、本体の`ShieldView`へ進むか確認する。iOS 26.0〜26.4では「閉じる」を押した直後に本体を手動で開く。
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

同日の追加調査で`ScreenTimeStoreTests`へ、通常版で固定候補・読めないトークンを実アプリとして選択済み扱いしないこと、0分がMonitor通知なしで制限判定になることと有効な一時利用枠の優先を確認する3テストを追加した。これらも未実行で、OSへのShield適用を確認するテストではない。
