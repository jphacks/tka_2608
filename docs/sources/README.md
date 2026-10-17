# 出典と原文アーカイブ

受領・調査日: **2026-10-17（Asia/Tokyo）**。

公式資料を省略・言い換えずに残すという依頼に従い、ユーザーが貼り付けた内容をUTF-8のバイト列として保存しています。オンライン原本を取得して保存したものとは区別してください。原文中の誤字、重複、表記揺れ、古いリンク、表の改行も保持しています。

## 1. ユーザーが提供した原文

| ID | ファイル | 範囲・状態 |
| --- | --- | --- |
| U01 | [2026-10-17-user-input.txt](2026-10-17-user-input.txt) | 添付 `Pasted text.txt` の全文。依頼・議事録・公式資料として貼付された本文を含む。1–1363行 |
| T01 | [2026-10-17-team-notes.md](2026-10-17-team-notes.md) | U01の「自分たちチームの議事録」から公式資料の直前まで。元全文24–325行。原文のまま抜き出し |
| O01 | [2026-10-17-official-provided.md](2026-10-17-official-provided.md) | U01の「公式ドキュメント」以降。元全文326–1363行。ユーザーが公式資料として提供した本文。オンライン原本との一致・最新性は未確認 |
| O02 | [2026-10-17-judging-excerpt.md](2026-10-17-judging-excerpt.md) | O01の最初の審査説明をそのまま抜粋。元全文862–949行（O01の537–624行）。採点基準・制約事項を省略していない。後の重複掲載分はO01に保持 |

個人名・自己紹介・雑談も、原文保持という依頼のためT01/U01にそのまま含まれます。概要側の要約を、元の発言者の合意や正式な担当表として扱わないでください。

バイト数、SHA-256、元全文の行範囲は [manifest.json](manifest.json) に記録しています。`protected_readme_sha256` は今回変更しないルートREADMEの作業開始時の値です。

## 2. O01の読む場所

以下は **O01ファイル自身の行番号** です。U01の行番号に直す場合は325を加えます。見出しのないページが連結されているため、検索語と行範囲の両方を示しています。

| 内容 | O01の行範囲 | 検索語・補足 |
| --- | --- | --- |
| 開催概要・全体の流れ | 6–51 | 「イノベーターになろう」、Hack Day / Award Day |
| エントリー・参加者・Learning Day | 53–136 | Slack、ガイドライン配布 |
| Hack Day・会場・当日タイムライン | 137–183 | 東京A、Code Freeze |
| オンライン審査・Finalist・Kaizen Sprint | 185–204 | A日程10月19日AM8:00の本文 |
| Award Day・当日タイムライン | 206–243 | 8分ピッチ、年に2025という表記あり |
| ポリシー・問い合わせ・使用ツール | 245–324 | Slack、GitHub、Zoom。旧年リンクも保持 |
| メインテーマ全文 | 326–352 | “X-Tech 2026”  ～ Full Stack Hackers ～ |
| 成果物・事前開発・持込・権利・禁止事項 | 353–379 | 使用した技術と自分たちが作った技術の区別にも関係 |
| GitHub・README・フォーム提出 | 381–479 | チームID、ソース提出、動画、15:30 |
| Hack Day参加まで・当日の進め方 | 481–534 | 提出フォーム項目、録画、デモ |
| 審査方法・採点・制約・投票（1回目） | 536–624 | [O02](2026-10-17-judging-excerpt.md) は537行から同内容を抽出 |
| 審査方法・採点・制約・投票（2回目） | 625–712 | 重複もそのまま保持 |
| 各Awardの説明 | 714–731 | Finalist、Innovator、Audience、Hack、審査員特別賞 |
| スポンサーオリジナルテーマ | 733–753 | ULS、SoftBank等。ULSは751–753 |
| 提供API・デバイス・サービス | 755–761 | Infineon、Bluesky。Slack資料の本文は未取得 |
| Hack Day Block Sponsor Award | 763–912 | プラチナ・ゴールド、会場別の表 |
| Award Day Sponsor Award | 913–1002 | Hack Dayとは別の条件・賞品 |
| テクニカルパートナー | 1004–1015 | 学習支援、Slack、Zoom |
| 参加規約 | 1017–1037 | 第1条〜第7条 |

Mac/Linux等で特定範囲を読む例:

```sh
sed -n '537,624p' docs/sources/2026-10-17-official-provided.md
```

原文中のURLは当時貼られていた参照先です。リンク先をすべて読んだ、または最新の正しいリンクだという保証ではありません。

## 3. 元資料のURLと取得状態

| ID | 資料 | URL | 今回の確認状態 |
| --- | --- | --- | --- |
| N01 | JPHACKS2026参加者案内トップ | [Notion](https://jphacks-info.notion.site/JPHACKS2026-ed99bc2d28a783578aa4014e0c554005) | Webツールで本文を取得できず。O01の貼付本文を使用 |
| N02 | プロダクト開発・提出方法 | [Notion](https://app.notion.com/21b6931cc449812ba5f1ec3932cec917?pvs=21) | O01中に掲載。Webツールでは本文取得不可 |
| N03 | 審査基準 | [Notion](https://app.notion.com/21b6931cc44981078bf6f79e25853141?pvs=21) | O01中に掲載。Webツールでは本文取得不可 |
| N04 | チーム開発メモ | [Google Docs](https://docs.google.com/document/d/1E67aRGav7QTa4HBo2Re54lK4K1w2HhfleReBRRwcb50/edit?tab=t.3v0pahixhidv) | T01中に掲載。Webツールでは本文取得不可。貼付メモ以外の内容は未反映 |
| N05 | Infineon提供資料 | [Slack](https://jphacks2026.slack.com/docs/T0B4GU46HF1/F0C20BLCJ93) | URLのみ提供。本文未取得 |
| W01 | JPHACKS公式サイト | [JPHACKS 2026](https://jphacks.com/) | 公開スポンサー一覧にULS等の名前を確認。会場別条件・期限はこのトップページで照合したものではない |

「取得不可」はアクセスを試みてもこの環境で本文が返らなかったという意味です。公開／非公開の区別や権限不足の原因まで断定していません。読めたことにして補完しないでください。

O01の各ページの見出し・URLがすべて一対一で付いていたわけではありません。N02/N03のリンクがあるからといって、O01の各段落をオンラインで照合できたという意味ではありません。

## 4. 追加確認したApple一次資料

以下は設計の正確性を補うために参照した資料です。Apple資料の全文スナップショットは保存していません。本文・検索で取得できた公式記述の範囲をもとに、[ARCHITECTURE.md](../ARCHITECTURE.md) に必要事項だけを整理しています。使用SDKでの導入OS・利用条件と実機結果は別途確認してください。

| ID | 資料と直接リンク | 確認した範囲／残る確認 |
| --- | --- | --- |
| A01 | [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) | リマインダーのfull access、iOS 17以降のusage descriptionと要求API。読み取り専用認可がないこと |
| A02 | [EKEventStoreChanged](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged) | 取得済みイベント／リマインダーの再取得が必要な通知 |
| A03 | [What's new in Screen Time API — WWDC22](https://developer.apple.com/videos/play/wwdc2022/110336/) | individual認可、取消し、個人認可の削除防止に関する説明、3フレームワークの役割 |
| A04 | [FamilyActivitySelection](https://developer.apple.com/documentation/familycontrols/familyactivityselection) | 選択を不透明トークンで表すこと、認可取消し時の無効化 |
| A05 | [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls) | capability・App ID・provisioningの設定 |
| A06 | [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) | 配布前の申請とextensionの申請 |
| A07 | [primaryButtonLabel](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/primarybuttonlabel) | ShieldConfigurationのボタン表示プロパティ。任意チャット埋込みを示す資料ではない |
| A08 | [ShieldActionResponse](https://developer.apple.com/documentation/managedsettings/shieldactionresponse) / [openParentalControlsApp](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/openparentalcontrolsapp) | 公式の列挙型の記述に本体を開く応答がある。個別ページはJS表示のみで導入OS・詳細条件を読めず。利用条件は未確定 |
| A09 | [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/) | 端末上の言語モデル、構造化生成、Tool Callingの概要。T01にも同じ動画URLあり |
| A10 | [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) | availability確認と、利用不可時の代替体験の必要性 |
| A11 | [DeviceActivityCenter.MonitoringError.intervalTooShort](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort) | monitoring scheduleの最小intervalは15分。使用しきい値の一律制約とは解釈していない |
| A12 | [About the background execution sequence](https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence) | 背景移行後のsuspend。Timerだけで常時動作する前提を置けないことの根拠 |
| A13 | [Meet the Screen Time API — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10123/) | T01の参照先。初期の保護者向けAPIの概要。個人向け設計はA03以降も読む |

Appleのドキュメントには継続更新されるページがあります。2025年の紹介動画にないAPIが、現在のSDKに追加されている可能性があります。最低OSやAPIの有無を古い記憶だけで決めないでください。

## 5. 更新記録

| 日付 | 変更 | 根拠 |
| --- | --- | --- |
| 2026-10-17 | U01全文、T01/O01の区分、O02審査抜粋、manifestを作成 | ユーザー添付の受領内容 |
| 2026-10-17 | Notion/Google Docsの取得不可、Apple資料の確認範囲を記録 | この作業での取得・検索結果 |

次回更新は [WORKFLOW.md](../WORKFLOW.md) に従い、新しいスナップショットと確認状態を追加します。
