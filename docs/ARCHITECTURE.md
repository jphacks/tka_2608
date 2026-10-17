# 実装設計：DBエンティティ・画面ロジック・共通処理

更新日: 2026-10-17。対象: iPhone向けのSwiftアプリ。アプリ実装・ビルド・実機検証は行っていない。

本書は、**どのデータをどこに置き、各画面の操作で何を処理するか**を実装者が追えるようにした設計案である。文言・キャラクター表現・対話プロンプトは[UI_UX.md](UI_UX.md)、採用判断は[DECISIONS.md](DECISIONS.md)、環境・実機確認結果は[STATUS.md](STATUS.md)を参照する。

### スコープと情報の状態

| 区分             | 内容                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| ユーザー指定     | DBエンティティ一覧、画面一覧と各画面ロジック、画面外の共通処理を中心に構成する                                      |
| ユーザー指定     | **解除相談を受け付けない「完全ブロック」モードはスコープ外**。SNS上限到達時の通常のShield画面は引き続き対象         |
| Figmaで確認      | 初回設定、今日／すべてのToDo、使用時間、アプリ別上限、Shield、タスク選択、説得、取り組み、完了／未完了ふりかえり    |
| Figma上の例      | 25分取り組みで+5分、完了で+1分、説得で1分、1日3回、目標2時間、夜22:00〜7:00。具体値の採用は別途記録する             |
| 本書の設計提案   | SwiftUI、本体の永続化にSwiftData、共有設定・実行状態にApp Group。下記のモデル・型・処理順                           |
| 採用・検証待ち   | 最低OS、SDK、署名、解除条件、時間の意味、回数の数え方、報酬の繰越、夜間・休日設定、会話保持期間                     |
| 今回必須にしない | 「通知だけ」モード、音声入力、会話からのタスク追加、朝の自動チェックイン、Android実装。採用する場合は範囲を別途確定 |

Figmaの基準は[採用ページ0:1](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=0-1)。画面とプロトタイプ設定の確認であり、実際のSNS利用・時間経過・iOS動作を実証したものではない。プロトタイプの「Xを開く→時間切れ」は、実装では解除処理と利用時間の監視に置き換える。

**使用時間はDeviceActivityReport拡張で集計・表示できる。** 本体はそのレポートをSwiftUIのビューとして画面に配置する。「使用時間の表示ができない」という制約ではない。本体DBへの利用データの持ち出しとは分けて設計する。詳しくは2.3節。

## 1. DBエンティティ一覧

### 1.1 データの正本と保存先

| データ                                                       | 正本・保存先                                   | 本体と拡張の扱い                                                     |
| ------------------------------------------------------------ | ---------------------------------------------- | -------------------------------------------------------------------- |
| ToDoのタイトル・メモ・期限・完了・繰返し・所属リスト         | EventKitのEKReminder / EKCalendar              | 本体で必要時に取得。独自DBに本体の複製を作らない                     |
| リスト選択、アプリ別上限、取り組み、会話、試行、報酬、利用枠 | 本体の永続ストア。SwiftDataを提案              | 本体を主な更新主体にする                                             |
| 選択トークン、適用するルール、利用枠の実行に必要な情報       | App Groupの版付き設定・実行状態                | 本体とMonitor / Shield拡張で共有する。方式は3.2節                    |
| SNSの実使用時間とその集計結果                                | OSからReport拡張へ渡される利用情報             | Report拡張内で集計・表示。本体DBへの書出しを前提にしない             |
| Reportで比較表示する独自の取り組み時間・目標・上限           | 本体データから生成した読取り用スナップショット | Report側へ渡す方式を実機検証する。利用情報を外へ持ち出す向きではない |
| 権限状態・モデル利用可否                                     | OS / Foundation Models                         | その都度取得。DBのBooleanを認可の正本にしない                        |
| 入力途中・選択中・生成中・スクロール位置                     | 原則メモリ上の画面状態                         | 復元が必要なものだけ保存方針を追加する                               |

URLCacheはHTTPレスポンス用で、報酬・取り組み・制限設定の永続ストアには用いない。[SwiftData](https://developer.apple.com/documentation/swiftdata/)、[URLCache](https://developer.apple.com/documentation/foundation/urlcache)

EventKitから取得するTaskSnapshotは一時的な表示・AI入力用の値であり、DBエンティティではない。ID、リスト、タイトル、メモ、完了、期限のDateComponents、取得日時を持つ。期限なし・日付のみ・時刻付き・タイムゾーンの意味を保持する。

### 1.2 エンティティと関連の一覧

以下は本書で提案する論理モデル。SwiftDataの実装はまだ作成しない。Relationshipで示す関連を、同じ意味のUUID属性と二重に正本化しない。`?`はNULL許容、時刻はDate、時間量は秒単位のInt、時刻設定は午前0時からの分、Enumは列挙値を保存する想定。

| エンティティ          | 役割                         | 主な関連                                       |
| --------------------- | ---------------------------- | ---------------------------------------------- |
| AppSettings           | 初回設定と共通ルール         | 端末ごとに1件                                  |
| ReminderListSelection | 検出済みリストの選択状態     | 1対多でReminderReference                       |
| ReminderReference     | EventKitのToDoへの独自参照   | 1対多で取り組み・完了イベント                  |
| AppRestriction        | 対象アプリと上限             | 1対多で説得試行・利用枠                        |
| FocusSession          | 取り組み1回                  | 1対多でFocusSegment                            |
| FocusSegment          | 計測する区間                 | FocusSessionに所属                             |
| Conversation          | タスク選択・説得・ふりかえり | 1対多でメッセージ・説得試行                    |
| ChatMessage           | 会話本文とカード             | Conversation、任意でPersuasionAttemptに所属    |
| PersuasionAttempt     | 説得1回の判定と回数枠        | 成功時に最大1つのUnlockGrant                   |
| TaskCompletionEvent   | ユーザー確認後の完了処理     | EventKit書込みと完了報酬を対応付ける           |
| RewardTransaction     | 獲得あそび時間の増減台帳     | 取り組み・完了・利用枠を発生元に持つ           |
| UnlockGrant           | 対象アプリへの一時利用枠     | AppRestrictionと、任意で成功した説得試行に関連 |

### 1.3 AppSettings

初回設定・報酬ルール・目標・共通の夜間設定。端末内で1レコード。

| 項目                                | 型          | 制約・用途                                       |
| ----------------------------------- | ----------- | ------------------------------------------------ |
| `id`                                | UUID        | PK。singletonをアプリで保証                      |
| `onboardingCompletedAt`             | Date?       | 必要な設定を確認できた日時                       |
| `autoIncludeNewLists`               | Bool        | 初回設定後に新しく検出したリストを対象に加えるか |
| `dailyFocusGoalSeconds`             | Int         | 1日の取り組み目標。Figma例7200                   |
| `focusRewardIntervalSeconds`        | Int         | 報酬計算の単位時間。Figma例1500                  |
| `focusRewardSeconds`                | Int         | 単位時間ごとの報酬。Figma例300                   |
| `completionRewardSeconds`           | Int         | ToDo完了報酬。Figma例60                          |
| `persuasionDailyLimit`              | Int         | 日次試行上限。Figma例3                           |
| `persuasionGrantSeconds`            | Int         | 説得成功時の利用枠。Figma例60                    |
| `nightEnabled`                      | Bool?       | 夜間機能が未採用ならNULL。具体的動作はQ04        |
| `nightStartMinute / nightEndMinute` | Int? / Int? | 現地0時からの分。Figma例1320 / 420               |
| `policyVersion`                     | Int         | ルールの版                                       |
| `updatedAt`                         | Date        | 更新日時                                         |

### 1.4 ReminderListSelection

EventKitで検出した全リストと、その対象／対象外の選択。未選択も保持し新規検出と区別する。

| 項目                       | 型          | 制約・用途                                             |
| -------------------------- | ----------- | ------------------------------------------------------ |
| `id`                       | UUID        | PK。アプリ内リスト参照                                 |
| `calendarIdentifier`       | String?     | EKCalendarの直近のID。外部照合用                       |
| `sourceIdentifier`         | String?     | 保存先ソースの照合補助                                 |
| `lastKnownTitle`           | String      | 照合・参照不能時の表示用。通常はEventKitの値を表示     |
| `isSelected`               | Bool        | このリストを対象にするか                               |
| `linkState`                | Enum        | available / unresolved                                 |
| `firstSeenAt / lastSeenAt` | Date / Date | アプリでの初回検出／最終確認。リストの作成日時ではない |

### 1.5 ReminderReference

ToDoを取り組み・会話・完了イベントに結ぶアプリ内参照。ToDo本体を複製しない。

| 項目                     | 型                     | 制約・用途                               |
| ------------------------ | ---------------------- | ---------------------------------------- |
| `id`                     | UUID                   | PK。アプリ内で維持する参照               |
| `list`                   | ReminderListSelection? | 直近の所属リストへの関連                 |
| `calendarItemIdentifier` | String?                | EventKit内の直近のID。恒久的なPKではない |
| `externalIdentifier`     | String?                | 再照合補助。一意性を前提にしない         |
| `linkState`              | Enum                   | linked / unresolved                      |
| `createdAt / updatedAt`  | Date / Date            | 作成／更新日時                           |

### 1.6 AppRestriction

選択したアプリ単位の上限・選択世代。解除不能の完全ブロックモードのカラムは作らない。

| 項目                                                | 型          | 制約・用途                                       |
| --------------------------------------------------- | ----------- | ------------------------------------------------ |
| `id`                                                | UUID        | PK。アプリ内部の対象参照                         |
| `applicationTokenData`                              | Data        | エンコードしたApplicationToken                   |
| `tokenFormatVersion`                                | Int         | アプリ側の保存形式の版                           |
| `weekdayLimitSeconds`                               | Int         | 通常の日次上限。FigmaのXは1800                   |
| `weekendLimitSeconds`                               | Int?        | 休日別設定を採用する場合のみ。NULLは通常値と同じ |
| `nightEnabledOverride`                              | Bool?       | NULLは共通設定を継承                             |
| `nightStartMinuteOverride / nightEndMinuteOverride` | Int? / Int? | NULLは共通時刻を継承                             |
| `isEnabled`                                         | Bool        | 制限対象として使うか。実効制限状態ではない       |
| `selectionRevision`                                 | Int         | 選び直し・再登録前の古い要求を検出               |
| `updatedAt`                                         | Date        | 更新日時                                         |

### 1.7 FocusSession

1つのToDoに取り組む1回分。取り組み中・ふりかえりを結ぶ。

| 項目                                             | 型                   | 制約・用途                                    |
| ------------------------------------------------ | -------------------- | --------------------------------------------- |
| `id`                                             | UUID                 | PK                                            |
| `reminder`                                       | ReminderReference?   | 対象ToDo。参照不能でも履歴は保持              |
| `originConversation`                             | Conversation?        | 開始元の会話。ホームからならNULL可            |
| `titleSnapshot`                                  | String               | 取り組み時のタスク名                          |
| `startedAt / workEndedAt / closedAt`             | Date / Date? / Date? | 開始／作業終了／ふりかえり確定                |
| `status`                                         | Enum                 | running / reflecting / finished / interrupted |
| `rewardIntervalSnapshot / rewardSecondsSnapshot` | Int / Int            | 開始時の報酬係数。後の設定変更で再計算しない  |
| `policyVersion`                                  | Int                  | 開始時のルール版                              |

### 1.8 FocusSegment

実際に計測する区間。日跨ぎ・中断・復旧を扱い、日次・週次の取り組み時間を集計する。

| 項目                  | 型           | 制約・用途                                   |
| --------------------- | ------------ | -------------------------------------------- |
| `id`                  | UUID         | PK                                           |
| `session`             | FocusSession | 所属する取り組み                             |
| `startedAt / endedAt` | Date / Date? | 区間開始／終了。NULLなら計測中               |
| `elapsedSeconds`      | Int          | 確定値または直近チェックポイントまでの計測秒 |
| `checkpointAt`        | Date         | 最後に計測値を保存した時刻                   |

### 1.9 Conversation

タスク選択・説得・ふりかえりの会話単位。閉じるときの戻り先も保持する。

| 項目                    | 型                 | 制約・用途                              |
| ----------------------- | ------------------ | --------------------------------------- |
| `id`                    | UUID               | PK                                      |
| `purpose`               | Enum               | taskSelection / persuasion / reflection |
| `origin`                | Enum               | home / shield / task。遷移元の文脈      |
| `targetApp`             | AppRestriction?    | 相談の対象アプリ                        |
| `selectedReminder`      | ReminderReference? | 選択・おすすめ・復帰対象のToDo          |
| `focusSession`          | FocusSession?      | ふりかえり対象                          |
| `status`                | Enum               | active / completed / cancelled          |
| `promptVersion`         | String             | 使用したプロンプト版                    |
| `createdAt / updatedAt` | Date / Date        | 開始／更新日時                          |

### 1.10 ChatMessage

会話を再表示する本文とカード。モデル内部状態の丸ごと保存を要求しない。保持期間はQ10。

| 項目                | 型                 | 制約・用途                                                  |
| ------------------- | ------------------ | ----------------------------------------------------------- |
| `id`                | UUID               | PK                                                          |
| `conversation`      | Conversation       | 所属会話                                                    |
| `persuasionAttempt` | PersuasionAttempt? | 説得のどの試行に属する発言か                                |
| `sequenceNo`        | Int                | 会話内で一意の表示順                                        |
| `role`              | Enum               | user / assistant                                            |
| `text`              | String             | 表示本文                                                    |
| `contentKind`       | Enum               | text / taskCandidates / completionConfirmation / unlockCard |
| `actionPayload`     | Data?              | 版付きの表示用構造化データ。実行状態の正本ではない          |
| `createdAt`         | Date               | 発言確定日時                                                |

### 1.11 PersuasionAttempt

説得1回の評価と回数枠。1試行に複数ターンを含められ、同じ会話で再挑戦できる。

| 項目                                    | 型                            | 制約・用途                                            |
| --------------------------------------- | ----------------------------- | ----------------------------------------------------- |
| `id`                                    | UUID                          | PK。通信再試行では同じID                              |
| `conversation / targetApp`              | Conversation / AppRestriction | 所属会話／対象アプリ                                  |
| `quotaDayKey / quotaTimeZoneIdentifier` | String / String               | 開始時の現地日付YYYY-MM-DD／タイムゾーン              |
| `countsTowardQuota`                     | Bool                          | 日次回数への算入。算入・取消し条件はQ05               |
| `status`                                | Enum                          | evaluating / approved / rejected / failed / cancelled |
| `convictionScore`                       | Int?                          | 納得度0〜100。意味・更新元はQ06                       |
| `decisionReason`                        | String?                       | 判定理由                                              |
| `attemptedAt / decidedAt`               | Date / Date?                  | 試行開始／最終判定日時                                |

### 1.12 TaskCompletionEvent

ユーザー確認後のEventKit完了書込みと完了報酬を結ぶ処理記録。

| 項目                                    | 型                                | 制約・用途                                             |
| --------------------------------------- | --------------------------------- | ------------------------------------------------------ |
| `id`                                    | UUID                              | PK。処理の再開・再試行でも同じID                       |
| `reminder / focusSession`               | ReminderReference / FocusSession? | 対象ToDo／取り組み                                     |
| `occurrenceKey`                         | String                            | 報酬対象回のアプリ内識別子。非繰返しは固定値onceを提案 |
| `titleSnapshot / dueComponentsSnapshot` | String / Data?                    | 完了前の名前／DateComponents相当の照合補助             |
| `rewardSecondsSnapshot / policyVersion` | Int / Int                         | 完了処理受付時の報酬量／ルール版                       |
| `requestedAt / appliedAt`               | Date / Date?                      | ユーザー確認／EventKit書込み確認日時                   |
| `status`                                | Enum                              | pending / applied / needsReview                        |

### 1.13 RewardTransaction

獲得あそび時間の増減台帳。残高を別カラムに重複保持しない。

| 項目                        | 型                   | 制約・用途                                       |
| --------------------------- | -------------------- | ------------------------------------------------ |
| `id`                        | UUID                 | PK                                               |
| `deltaSeconds`              | Int                  | 獲得は正、利用枠との交換は負。0を許容しない      |
| `kind`                      | Enum                 | focusReward / completionReward / redeem / refund |
| `focusSession`              | FocusSession?        | 取り組み報酬の原因                               |
| `completionEvent`           | TaskCompletionEvent? | 完了報酬の原因                                   |
| `unlockGrant`               | UnlockGrant?         | 利用枠との交換・返金の対象                       |
| `reversesTransaction`       | RewardTransaction?   | 返金で打ち消す元の引落し                         |
| `idempotencyKey`            | String               | 一意。同じ原因の二重計上を防ぐ                   |
| `policyVersion / createdAt` | Int / Date           | 計算時のルール版／確定日時                       |

### 1.14 UnlockGrant

対象アプリへ発行する一時利用枠。許可の記録とOSへの適用処理を追跡する。

| 項目                                                    | 型                 | 制約・用途                                             |
| ------------------------------------------------------- | ------------------ | ------------------------------------------------------ |
| `id`                                                    | UUID               | PK                                                     |
| `targetApp`                                             | AppRestriction     | 対象アプリ                                             |
| `source`                                                | Enum               | reward / persuasion                                    |
| `persuasionAttempt`                                     | PersuasionAttempt? | 説得由来の場合の成功試行。1試行から最大1件             |
| `timeBasis`                                             | Enum               | elapsedTime / appUsageTime。採用方式はQ03              |
| `allowanceSeconds`                                      | Int                | 発行した利用枠。正の整数                               |
| `requestedAt / registeredAt`                            | Date / Date?       | 要求日時／OS適用処理の成功日時                         |
| `plannedExpiresAt / endedAt`                            | Date? / Date?      | 経過時間方式の予定終了／終了処理の観測日時             |
| `status`                                                | Enum               | requested / registered / finished / failed / cancelled |
| `selectionRevision / policyVersion / monitorGeneration` | Int / Int / Int    | 選択／ルール／監視の世代                               |
| `idempotencyKey`                                        | String             | 一意。二重発行を防ぐ                                   |

### 1.15 一意制約・更新・削除

- 各idは独自UUID。同じlinked状態のcalendarItemIdentifierに複数のReminderReferenceを作らない。EventKitのローカルID・リストIDはフル同期で変わり得るため、恒久的な主キーにはしない。externalIdentifierも常に一意とは限らない。[calendarItemIdentifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier)、[externalIdentifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier)
- ChatMessageの`(conversation, sequenceNo)`、TaskCompletionEventの`(reminder, occurrenceKey)`、台帳・利用枠のidempotencyKeyはそれぞれ一意。
- 取り組み報酬のキー例は`focus:{sessionID}:interval:{n}`。完了報酬は`completion:{eventID}`。通信・表示・保存の再試行ではIDを作り直さない。
- 残高はRewardTransaction.deltaSecondsの合計。利用枠との交換は残高確認・利用枠作成・引落しを同じDBトランザクションで行う。OS操作とは別のため、失敗時は元の引落しを参照する返金行を追記する。
- 引落しは`redeem:{grantID}`、全額返金は`refund:{debitID}`を一意キーにする。返金は元の引落額と一致させ、1引落しへ最大1回。
- 台帳のkindに応じ、取り組み・完了イベント・利用枠のいずれか適切な発生元を必須にする。説得由来の利用枠はapprovedの試行のみ参照できる。
- 同じ端末で同時に計測中にする取り組み・区間は最大1件とする設計を提案する。日次の説得枠の確認と試行作成もトランザクションで行う。
- ToDoの改名・削除後も、取り組み・完了時のsnapshotで履歴を表示する。台帳に関連するReminderReference、完了イベント、利用枠、試行は削除せず、参照不能・無効・終了状態として保持する。任意の関連だけnullifyでき、必須の関連は維持する。
- 会話の削除は保持方針Q10に従う。メッセージは会話と一緒に削除できるが、試行・報酬・利用枠に必要な参照を失わせる削除は先に設計する。
- 正確なSNS利用時間を保存するDailyAppUsage等のテーブルは標準構成に設けない。取り組み時間の週次値はFocusSegmentから再計算でき、初期構成で集計専用テーブルを必要としない。

## 2. アプリに必要な画面一覧と各画面のロジック

### 2.1 画面の識別と共通の受け渡し

画面名は実装用の識別案。Figmaの状態違いは同じViewの状態として実装できる。文言・色・キャラクター・プロンプト本文は[UI_UX.md](UI_UX.md)を正とする。

画面間では、必要に応じて`origin`（戻り先）、`targetAppID`、`reminderID`、`focusSessionID`、`conversationID`を渡す。ホーム起点のタスク選択を閉じてShieldへ戻すような起点の混同を防ぐ。取得中・失敗・0件は共通の別状態とし、失敗を0件で表さない。

| ID  | 画面・状態               | Figmaノード                                                                                                                                                          |
| --- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O01 | ようこそ                 | [64:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=64-2)                                                                                      |
| O02 | 権限説明・許可           | [64:115](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=64-115)                                                                                  |
| O03 | リマインダーのリスト選択 | [67:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=67-2)                                                                                      |
| O04 | 制限するアプリの選択     | [64:225](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=64-225)                                                                                  |
| O05 | 初期上限時間の設定       | [64:317](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=64-317)                                                                                  |
| O06 | 準備完了                 | [64:395](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=64-395)                                                                                  |
| H01 | ホーム：今日／すべて     | [65:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=65-2)、[66:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=66-2)     |
| H02 | 使用時間                 | [79:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=79-2)                                                                                      |
| S01 | アプリ別上限設定         | [31:131](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=31-131)                                                                                  |
| R01 | 上限到達時の通常Shield   | [27:203](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=27-203)                                                                                  |
| T01 | タスク選択・選択済み     | [72:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=72-2)、[72:286](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=72-286) |
| C01 | 説得チャット             | [30:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=30-2)                                                                                      |
| C02 | 説得が通らなかった状態   | [32:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=32-2)                                                                                      |
| R02 | 一時利用枠の終了案内     | [32:309](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=32-309)                                                                                  |
| F01 | 取り組み中               | [37:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=37-2)                                                                                      |
| F02 | ふりかえり：完了         | [90:2](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=90-2)                                                                                      |
| F03 | ふりかえり：未完了       | [37:125](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=37-125)                                                                                  |

### 2.2 初回設定

| 画面           | 表示するデータ                            | 操作→処理→遷移                                            | 保存・異常系                                                                                                |
| -------------- | ----------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| O01 ようこそ   | アプリの目的、初回設定の有無              | はじめる→O02。設定済みの起動は復帰時照合後H01へ           | この画面だけで初回設定完了にしない                                                                          |
| O02 権限       | Family Controls・EventKit・通知の現在状態 | 個別の許可操作→OSの認可→状態を再取得。次へ→O03            | 権限をDBの正本にしない。必須権限と拒否時の継続条件はQ01。通知は音声権限と別                                 |
| O03 リスト選択 | EKCalendarのリスト、既存の選択、件数      | 選択・自動追加設定→保存→O04                               | 検出済み全リストのisSelectedを保持。0件・取得失敗・書込み不可を区別。ID変更を新規作成と即断しない           |
| O04 アプリ選択 | 現在のApplicationToken集合                | OSのFamilyActivityPickerで選択→アプリ別設定へ対応付け→O05 | トークンを保存し選択revisionを更新。標準認可で名称・bundle ID文字列を取得できる前提にせずLabel(token)で表示 |
| O05 上限設定   | 選択アプリと各上限                        | 秒数・対象を検査→設定保存→O06                             | Figmaの30/20/45/10分は例。初期値・刻み・0分の扱いはQ02。対象なし・不正値は修正を案内                        |
| O06 準備完了   | 対象件数・リスト件数・上限合計            | ホームへ→必要設定・監視準備を再確認→H01                   | 条件成立後にonboardingCompletedAtを保存。欠落時は該当設定に戻る。朝チェックインは自動追加しない             |

### 2.3 ホーム・使用時間・設定

| 画面             | 表示するデータ                                                      | 操作→処理→遷移                                                                                         | 保存・異常系                                                                                                  |
| ---------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| H01 ホーム       | EventKitの最新ToDo、取り組み合計、報酬残高。SNS利用表示部分はReport | 今日／すべて切替→対象を再計算。取り組む→origin=homeでT01。使用時間→H02                                 | 表示だけで報酬を発行しない。「今日」・期限なし・期限切れの分類はQ07。取得失敗と本当に0件を分ける              |
| H02 使用時間     | アプリ別使用時間、上限、週次グラフ、取り組み、目標・ルール          | Reportを日次／週次フィルターで表示。対象アプリの設定操作→S01。アプリ追加・削除→OSピッカーとO04共通処理 | 使用時間はReport内で集計。上限・取り組み・残高は本体データ。無許可・準備中・データなし・遅延を0分と混同しない |
| S01 アプリ別上限 | 対象アプリ、使用時間Report、現在の上限・任意の夜間／休日設定        | 編集→値の検査→版を更新→共有設定・監視を更新→起点画面へ                                                 | 完全ブロックモードは実装しない。「通知だけ」も採用済みにしない。設定変更時の有効利用枠の扱いはQ12             |

**H02のReport構成**

1. 本体アプリが`DeviceActivityReport(context, filter:)`をSwiftUIの画面に配置する。日付範囲・選択対象・日次／週次などの条件を渡す。
2. Report拡張の`makeConfiguration(representing:)`がOSから渡された利用データを集計し、独自の表示用Configurationを作る。
3. Report拡張が、そのConfigurationを使ってアプリ別の数字、合計、日次・週次グラフをSwiftUIで描画する。表示用の集計処理は可能。
4. 本体が持つ取り組み時間・目標・上限を、読取り用スナップショットとしてReport側に渡す案を検証する。Report内で使用時間と比較してグラフ・指標を計算することまで不可能とは扱わない。
5. Report内の操作を本体のS01へ渡せるかは未確認。経路が成立する場合も、対象のアプリ内参照など最小限の操作情報だけを扱い、利用時間の数値を本体へ返す方法として使わない。本体側に設定操作を置く案を含め、Reportの行との対応と遷移をV08で検証する。

Appleは、Report拡張内で利用データを集計して独自のSwiftUIレポートを表示し、本体画面に埋め込む方法を説明している。[WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)、[makeConfiguration](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene/makeconfiguration%28representing%3A%29)

Report拡張はsandboxで動き、機微な情報を拡張の外へ移動すること等に制約がある。そのため、**Reportが受け取ったSNS利用時間を本体のSwiftDataへ書き出し、本体・AIが自由に再利用する構成は標準構成にしない**。これはReport内の集計・表示を禁止する意味ではない。独自の取り組みデータをReportへ読ませる共有方式、更新、比較グラフはSDK・実機で検証する。[DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)

専用entitlement・認可・地域等の条件を伴う直接データアクセスAPIは別経路として存在する。「あらゆるiOS環境で取得不可能」と断定しない。本書は通常のReport APIを使う構成を基本とし、日本向け配布でその例外へ依存しない。[activityData](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata%28filteredby%3Ausing%3A%29)、[approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess)

アリ度／キリギリス度、キャラクターの段階切替、「アリの日」、週の開始日、日付境界、集計対象アプリはQ11で定義する。本体で必要な判定にReport内の利用数値が返ってくる前提を置かず、表示内で完結する計算と制限用のしきい値監視を分ける。

### 2.4 Shield・タスク選択・説得

| 画面           | 表示するデータ                                   | 操作→処理→遷移                                                                                   | 保存・異常系                                                                                                            |
| -------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| R01 通常Shield | 対象アプリ、案内、再取得可能な範囲のタスク情報   | 本体への導線を使い、origin=shieldでT01またはC01へ。対象アプリ等の起動要求を共有する              | Shield内で自由なチャットを描かない。最新タスク数を常時保証しない。対応API・対象OS・失敗時の手動導線をV04で確認          |
| T01 タスク選択 | 最新の未完了候補、選択状態、起点                 | 候補選択→開始直前に再取得→FocusSession・最初のFocusSegment作成→F01。理由相談→C01                 | 閉じる→保存したoriginに対応する戻り先。ホーム起点をShieldへ戻さない。削除・完了済みなら再選択。会話からの新規作成はQ09  |
| C01 説得       | 対象アプリ、タスク、会話、利用可能な条件・試行枠 | 理由送信→試行枠を検査・確保→AI応答→アプリが提案を検査。着手→T01。不許可→C02。利用枠の発行は3.4節 | 生成中の重複送信防止、古い結果・カードの無効化、取消しを扱う。納得度だけで解除しない。複数ターンと1回の数え方はQ05・AQ06 |
| C02 説得不許可 | 判定理由、最新の試行枠、次のタスク候補           | タスクへ→T01。再挑戦→条件成立時に新しい試行IDでC01                                               | 生成エラーは技術エラーとして区別。失敗・中断・エラー時の回数消費はQ05                                                   |
| R02 利用枠終了 | 終了した利用枠、最新タスク、制限状態             | 着手→T01または既存の取り組みへ。相談→C01                                                         | Monitorが再制限・終了を記録。本体を自動的に前面へ出せる前提にしない。次にShield／本体を表示するときに状態を反映         |

Figmaの「Xを開く」は、利用枠の発行要求とSNSの起動を分けて実装する。具体的なSNSを自動起動できるかは別途確認し、一般のApplicationTokenから任意アプリを必ず起動できるとは約束しない。利用枠を発行したあと、手動で対象アプリを開く導線も用意する案とする。

### 2.5 取り組み・ふりかえり

| 画面                 | 表示するデータ                                                 | 操作→処理→遷移                                                                                                               | 保存・異常系                                                                                                 |
| -------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| F01 取り組み中       | 選択ToDo、計測時間、見込み／付与済みの報酬、次の単位までの時間 | 「終わってふりかえる」→区間を閉じworkEndedAtを記録→ふりかえり会話を開始。ユーザーの回答・確認によりF02またはF03の状態へ      | 画面のTimer値だけを正本にしない。復帰時に区間・チェックポイントから再構成。途中終了でも自動完了させない      |
| F02 完了ふりかえり   | 計測結果、実ToDo、完了確認、今回の付与内訳                     | 進捗回答→AIが確認を提案→ユーザーが「完了にする」→TaskCompletionEvent作成→EventKit保存→報酬を確定。ホーム→H01、他のタスク→T01 | EventKit更新成功前に「チェックした」と表示しない。AIの発言だけで完了にしない。再押下・再開でも二重付与しない |
| F03 未完了ふりかえり | 計測結果、未完了ToDo、進捗回答、今回の時間報酬                 | 本人の未完了回答を確認→ToDoは未完了のまま、今回の計測終了と報酬を確定→H01またはT01                                                         | 完了報酬を付けない。Figmaの「まだ続ける」はToDoの継続を指し、タイマー再開と混同しない。途中時間の繰越・時間報酬はQ08          |

F02・F03は同じふりかえり画面の結果状態として扱える。Figmaの取り組み終了ボタンが直接完了済みの画面へ進む設定を、そのまま完了操作として実装しない。まず進捗と本人確認を受け取り、未完了の結果にも到達できるようにする。

報酬の計算例（Figmaの値を採用する場合）: 32分の取り組みは`floor(1920 / 1500) × 300 = 300秒`、完了確認とEventKit保存が成功すればさらに60秒で合計6分。25分到達時にすでに5分を台帳へ記録した場合、最後に追加するのは未計上の1分だけ。未完了なら完了分を追加しない。

## 3. 画面に属さない共通処理

### 3.1 責務とターゲット構成

| 処理・ターゲット               | 責務                                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| 本体アプリ                     | 初回設定、EventKit取得・確認済み更新、タスク選択、対話、取り組み、台帳、ポリシー検査、Reportビューの配置 |
| Shield Configuration拡張       | OSのShieldに表示するアイコン・文言・ボタンの設定                                                         |
| Shield Action拡張              | Shieldの操作に応答し、対象と起点の要求を共有。本体への導線を実装                                         |
| Device Activity Monitor拡張    | 日次上限・時間帯・利用枠の監視に応じて制限を更新し、実行結果を記録                                       |
| **Device Activity Report拡張** | **OSから渡された利用データの集計と、数字・グラフのSwiftUI表示**                                          |
| 共通コード／App Group          | 対象参照、ルール版、世代付き設定、利用枠の実行状態の共有                                                 |

本体内の境界はTaskRepository、RestrictionService、AIConversationService、UnlockPolicy、ConversationCoordinator、StateStoreを提案する。UIからOSへ直接独自判定を重複実装せず、`操作→Coordinator→データ／AI→Policy→OSアダプター→結果`の順で扱う。extensionは別プロセスであり、本体のサービスインスタンスを直接呼ぶ前提にしない。Androidを今実装せず、業務上の参照・判定とApple固有トークンの境界を小さく分ける。

### 3.2 永続化・共有・実行結果

| 情報                                       | 更新主体            | 共有・復元方針                                                                                      |
| ------------------------------------------ | ------------------- | --------------------------------------------------------------------------------------------------- |
| 独自DBのモデル・報酬台帳                   | 原則本体            | SwiftDataを候補とする。保存エラーを成功表示にしない                                                 |
| 対象トークン・ルール・実行すべき利用枠     | 本体                | App Groupへ版・世代付きスナップショットを公開。複数ファイル更新時も同じ世代として読める方法を決める |
| 監視開始・枠終了・再制限・エラーの実行結果 | Monitor等の実行主体 | イベントIDと世代を持つ共有結果を保存。本体が復帰時に一意に取り込み、DB・台帳と照合                  |
| Reportで比較する取り組み・目標・上限       | 本体→Report         | 独自データだけを読取り用として渡す。共有コンテナの可用性・形式・更新をV08で確認                     |
| Reportに渡されたSNS利用データ              | Report内            | Reportの表示用集計に使用。本体側へ数値をエクスポートする共有設定とは分ける                          |

App Group内のファイル／共有ストアの選定、原子的な保存・世代切替、拡張からの書込み競合はV01・V06・V08で確定する。UserDefaultsの単純なread-modify-writeを、複数プロセスで原子的な残高・回数更新ができる仕組みとみなさない。Reportに本体のDB全体を読ませることも必須にせず、必要最小限の独自データを渡す。

### 3.3 EventKitと対象アプリの照合

- iOS 17以降のリマインダー取得は`NSRemindersFullAccessUsageDescription`と`requestFullAccessToReminders`を使用する。読み取りにもfull accessが必要。実装対象の更新・削除・新規作成は、採用した操作に限る。[A01](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- 起動・復帰・完了処理の前後・`EKEventStoreChanged`で必要な範囲を再取得する。この通知は常時バックグラウンド監視の保証ではない。[A02](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged)
- 権限取消し、同期中、参照不能を「タスク0件」「ToDo削除」と即断しない。照合が曖昧ならunresolvedとし、既存の参照・報酬枠を維持する。
- 完了書込みはTaskCompletionEventをpendingで保存→ユーザーが確認した対象をEventKitで更新→appliedを確認→一意な報酬を記録する。EventKitと独自DBは別トランザクションのため、途中終了は同じイベントIDで再評価し、成功を確定できなければneedsReviewにする。
- completionDateだけを完了回の一意キーにしない。完了解除・再完了・外部クライアントで値が変わる場合がある。繰返しの回の識別・外部完了への付与・取消し時の扱いはQ08で確定する。
- 個人向けFamily Controls認可は本人が取り消せる。選択トークンの無効化を扱い、必要なら再選択を案内する。[A03](https://developer.apple.com/videos/play/wwdc2022/110336/)、[A04](https://developer.apple.com/documentation/familycontrols/familyactivityselection)
- アプリの表示にはLabel(applicationToken)を用いる。名称・bundle IDを標準認可で必ず取得できる前提にしない。モデルには独自の対象参照を渡し、トークンをプロンプトへ直接渡さない。[Displaying Activity Labels](https://developer.apple.com/documentation/familycontrols/displayingactivitylabels)

### 3.4 制限・解除・再制限

利用枠の発行処理案:

1. AIは返答とUnlockProposalを返す。提案だけでは制限を変更しない。
2. 本体は提案カードを表示し、ユーザーの利用操作を受け付ける。カードに対象・量・時間の意味を示す。
3. UnlockPolicyが権限、対象、タスク、ルール版、試行上限、既存の利用枠、量を検査する。古い対象・会話・要求を拒否する。
4. UnlockGrantをrequestedとして一意に記録する。残高との交換なら、残高検査と引落しも同じDBトランザクションで行う。説得由来の利用枠と残高への加算を同一視しない。
5. 先に終了条件の監視を準備し、その後、対象だけの制限を変更する。成功後にregistered・結果表示へ進む。利用開始点はQ03に従い、単なるカード表示時刻と混同しない。
6. 失敗時は解除成功を表示せず、必要な再制限・一意な返金を行う。別アプリの制限をまとめて解除しない。
7. Monitorが終了条件を検知して制限を再計算し、イベントを記録する。本体は復帰時にも照合する。古い世代のコールバックで新しい枠を終了しない。

| 状態               | 意味・遷移                                             |
| ------------------ | ------------------------------------------------------ |
| permissionRequired | 必要な権限なし。認可状態と選択を再取得                 |
| ready              | 設定・対象を利用できる。採用した開始条件でrestrictedへ |
| restricted         | アプリが制限を適用した状態。相談開始でnegotiatingへ    |
| negotiating        | 対話中。現在の制限を維持                               |
| grantPending       | 検査、利用枠記録、終了監視の準備中                     |
| temporarilyAllowed | 条件付きの解除処理を行った状態。終了条件で再制限       |
| recoveryRequired   | DB・共有状態・OS設定の不一致や処理失敗。再評価・復旧   |

状態はアプリの処理記録であり、DBの値だけでデバイス上の実効制限を保証しない。夜間・日次上限・一時利用枠の優先順位と、有効中の設定変更はQ02・AQ04・AQ12。複数ManagedSettingsStoreでは厳しい設定が優先されることを踏まえ、現在の全ルールから対象ごとの制限を再計算する。[A03](https://developer.apple.com/videos/play/wwdc2022/110336/)

「解除から1分経過」と「対象アプリを1分使用」は別仕様。監視scheduleには最小15分のinterval制約があるが、すべての利用しきい値が15分以上という意味ではない。長い監視窓と短い利用しきい値の候補は実機検証する。[A11](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)

本体はバックグラウンドでsuspendされ得るため、画面内Timerだけで再制限しない。経過時間方式／実利用時間方式の意味、既使用分、再登録、再起動・時計変更をV06で確認する。[A12](https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence)

### 3.5 AI・UI・ポリシー間の入出力

以下は実装時の型契約案。モデルの生の文章から制限操作を推測せず、構造化された候補を検査する。

| 契約                   | 項目・意味                                                                                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI入力                 | 最新のTaskSnapshot、選択タスク、対象アプリの独自参照、必要な会話、許可アクション、量の上限・単位、時間の意味、直前の処理結果                                                          |
| AI出力候補             | text、action、taskID?、proposedSeconds?、reason、convictionScore?。actionはask / suggestFocus / proposeUnlock / confirmCompletion                                                     |
| 本体が保持する要求情報 | requestID、conversationID、対象参照、selectionRevision、policyVersion。戻った応答を元の要求と照合する                                                                                 |
| UIからの操作           | startFocus、sendMessage、acceptUnlock、finishFocus、confirmCompletion、saveLimit。各操作に必要な対象IDと一意な要求IDを付ける                                                          |
| 処理結果               | 成功時は新しい状態と確定ID。失敗時はpermissionRequired / taskUnavailable / modelUnavailable / modelFailed / invalidProposal / staleRequest / storageFailed / monitoringFailed等の区別 |

タスク参照の実在、対象選択、正の秒数、上限、重複、現行版をアプリが検査する。タスク名・メモ・会話をポリシー変更の命令として扱わない。取消した要求の遅延応答でカードを復活させず、古い利用カードを再利用しない。Tool Callingでも同じ検査を通す。

Foundation Modelsは構造化生成・Tool Callingの候補。利用前にSystemLanguageModel.default.availabilityを確認する。形式が正しくても判断内容の正しさは保証されない。端末、OS、言語・地域、モデル準備と実応答をV05で確認する。[A09](https://developer.apple.com/videos/play/wwdc2025/286/)、[A10](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

### 3.6 Shield・署名・実行環境

Shieldはシステムの制限画面であり、自由なチャットは本体で表示する。背景のblurやラベル等の設定APIを、SNSの任意画像の取得・自由なオーバーレイ機能として扱わない。[A07](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/primarybuttonlabel)

ShieldActionResponse.openParentalControlsAppは最新資料に存在する。使用SDKのavailability、個人認可、対象端末、渡せる文脈をV04で確認し、任意deep linkが使えると仮定しない。非対応時は本人が本体を開く導線を用意する。[A08](https://developer.apple.com/documentation/managedsettings/shieldactionresponse)

開発時のFamily Controls capability、ターゲットごとのApp ID・署名、配布時のentitlement申請を区別する。配布では関連extensionの申請も確認する。[A05](https://developer.apple.com/documentation/xcode/configuring-family-controls)、[A06](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

プロダクト名、project／scheme、Bundle ID、App Group ID、最低OS、使用Xcode／SDK、実機担当は未確定。存在しないビルドコマンドや実機結果を作らず、成立した設定をSTATUS.mdへ記録する。プロジェクト・ターゲット設定の編集責任者を決め、並行実装では上記の型契約を共有する。

### 3.7 検証と完了条件

| ID               | 確認すること                                                         | 記録する結果                                       |
| ---------------- | -------------------------------------------------------------------- | -------------------------------------------------- |
| V01 環境         | Xcode／SDK、OS、モデル対応端末、署名、capability、App Group          | バージョン・ターゲット設定・成功したビルド手順     |
| V02 リマインダー | 許可、取得、0件、拒否、外部変更、確認済み完了保存                    | 実データの再現手順と結果                           |
| V03 Shield       | 選択した実アプリだけへの制限、解除、選び直し                         | 画面と対象外アプリへの影響                         |
| V04 導線         | Shield→本体、対象・起点の受け渡し、戻る                              | 使用APIとOS条件、成功／代替手順                    |
| V05 モデル       | availability、日本語、構造化提案、生成取消し・失敗                   | 端末、プロンプト版、応答、ポリシー検査結果         |
| V06 再制限       | 時間の意味、既使用分、背景動作、古い世代、復帰・再起動               | 本体が前面にない状態での結果                       |
| V07 統合         | 実タスク→対話／取り組み→検査→利用枠→再制限                           | デモ動画、commit、実接続／模擬の区別               |
| V08 Report       | アプリ別・日次・週次の表示、独自データ読込み、比較グラフ、操作・更新 | Report内の表示、設定導線、拒否・データなし時の結果 |
| V09 台帳・復旧   | 報酬重複、再押下、保存途中終了、二重引落し・返金                     | 一意性と残高、再開結果                             |

純粋なポリシー・台帳には、上限・対象外・不正提案・重複・返金の検証を用意する。UI_UX.mdのC01〜C09も対応付ける。本体Timerの表示、固定会話、Figmaのクリックだけを、OS制限・AI対話・自動再制限の実証としない。

<a id="8-午後の検討実装引き継ぎ"></a>

### 3.8 午後の検討・実装引き継ぎ（旧8節）

既存資料の「ARCHITECTURE.mdの8節」へのリンクは本節へ接続する。本書はDB・画面・共通処理の3章へ再構成した。以下のAQ番号は本書内の未決事項であり、STATUS.mdのQ番号とは別である。製品上の判断は、AIが空欄を埋めて採用済みにせず、[UI_UX.mdの6・7節](UI_UX.md#6-両班で合わせる仕様)と決定ログへ採用内容を残す。

| ID  | 実装前に決めること                                                                   |
| --- | ------------------------------------------------------------------------------------ |
| AQ01 | 必須権限、部分的な拒否・モデル非対応時に使える画面、初回設定の完了条件               |
| AQ02 | 未完了ToDoとSNS上限の関係、タスク0件時、上限未到達時、上限の初期値・0分の扱い        |
| AQ03 | 一時利用は経過時間か実利用時間か、起算点、1回・合計の上限、終了条件                  |
| AQ04 | 夜間機能の採否、対象時間、通常上限との優先順位、報酬・説得で解除できるか             |
| AQ05 | 説得1回の区切り、成功・拒否・中断・エラーの算入、日次上限、日付・タイムゾーンの切替  |
| AQ06 | 納得度の採否・意味・更新元・表示段階、許可判断との関係                               |
| AQ07 | 「今日」に含める期限・期限切れ・完了・期限なし、並び順、対象リスト                   |
| AQ08 | 報酬係数の採用値、25分未満の端数の繰越、残高の失効、外部完了・取消し・繰返しへの付与 |
| AQ09 | 音声入力・会話からのToDo追加の採否、入力確認と書込み範囲                             |
| AQ10 | 会話・進捗・取り組み等の保持期間、削除、モデルに渡す履歴の上限                       |
| AQ11 | 日次・週次指標、アリ度／キリギリス度、キャラ段階、「アリの日」の計算と表示範囲       |
| AQ12 | 休日の定義、設定変更時の適用点、有効利用枠の失効・維持、対象解除・再選択時の処理     |
| AQ13 | 実装する画面・省略する画面、実接続／モック、デモの完了条件と担当                     |

技術上の採用方式・保存形式・UI操作の型は本書へ、文言・プロンプトはUI_UX.mdへ、採用判断はDECISIONS.mdへ、実機結果はSTATUS.mdへ記録する。現時点ではアプリの実装・実機検証は未実施。

### 3.9 技術資料の参照

前版で確認した資料A01〜A12を各該当箇所に保持した。今回の再確認では、DeviceActivityReport／ReportScene／makeConfigurationとWWDC22のレポート説明から、**Report内での集計・SwiftUI表示が可能**であることと、利用情報を外へ持ち出す制約を区別した。

- [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)
- [DeviceActivityReportScene](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene)
- [makeConfiguration(representing:)](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene/makeconfiguration%28representing%3A%29)
- [WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)
- その他の出典状態・ユーザー提供の原文は[sources/README.md](sources/README.md)を参照する。
