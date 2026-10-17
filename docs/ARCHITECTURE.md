# 実装設計：DBエンティティ・画面ロジック・共通処理

更新日: 2026-10-17。対象: iPhone向けのSwiftアプリ。アプリ実装・ビルド・実機検証は行っていない。

本書は、**どのデータをどこに置き、各画面の操作で何を処理するか**を実装者が追えるようにした設計案である。文言・キャラクター表現・対話プロンプトは[UI_UX.md](UI_UX.md)、採用判断は[DECISIONS.md](DECISIONS.md)、環境・実機確認結果は[STATUS.md](STATUS.md)を参照する。

第1〜3章に実装内容、第4章に検証と完了条件、第5章に未決事項・実装引き継ぎ、第6章に参照資料をまとめる。検証計画と、実装する機能・処理を分けて読む。

### スコープと情報の状態

| 区分             | 内容                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| ユーザー指定     | DBエンティティ一覧、画面一覧と各画面ロジック、画面外の共通処理を中心に構成する                                                                   |
| ユーザー指定     | SNS上限による制限とAIへの相談を実装対象にする。夜間機能・完全ブロックモード・音声入力は対象外とし、関連設定や採否の未決事項を設けない            |
| ユーザー指定     | アリ度（%）＝取り組み時間÷目標時間×100。キリギリス度（%）＝100−アリ度。計算元と残る表示ルールは2.3節                                             |
| ユーザー指定     | ホームの「今週のありとキリギリス」を実装対象とし、使用時間はReport拡張内で週次集計・表示する。休日別設定は引き続きスコープ外                     |
| ユーザー指定     | 報酬係数は「どれだけ取り組むと、SNS利用時間をどれだけ追加するか」を表す。取り組み時間：SNS追加時間＝5：1で固定する                               |
| Figmaで確認      | 初回設定、今日／すべてのToDo、使用時間、アプリ別上限、Shield、タスク選択、説得、取り組み、完了／未完了ふりかえり                                 |
| Figma上の例      | 25分取り組みで+5分、完了で+1分、説得で1分、1日3回、目標2時間。取り組み報酬の比率5：1はユーザー指定で採用。付与単位やその他の具体値は別途確定する |
| 本書の設計提案   | SwiftUI、本体の永続化にSwiftData、共有設定・実行状態にApp Group。下記のモデル・型・処理順                                                        |
| 採用・検証待ち   | 最低OS、SDK、署名、解除条件、時間の意味、回数の数え方、報酬の繰越                                                                                |
| 今回必須にしない | 「通知だけ」モード、会話からのタスク追加、朝の自動チェックイン、Android実装。採用する場合は範囲を別途確定                                        |

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

以下は本書で提案する論理モデル。SwiftDataの実装はまだ作成しない。Relationshipで示す関連を、同じ意味のUUID属性と二重に正本化しない。`?`はNULL許容、時刻はDate、時間量は秒単位のInt、Enumは列挙値を保存する想定。

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

初回設定・報酬ルール・目標。端末内で1レコード。

取り組み報酬の付与単位、ToDo完了報酬、説得の回数上限・納得度のしきい値・説得成功時の利用枠の範囲はDBに保存せず、3.7.6節の定数にまとめる（D026・D028）。

| 項目                    | 型    | 制約・用途                                                           |
| ----------------------- | ----- | -------------------------------------------------------------------- |
| `id`                    | UUID  | PK。singletonをアプリで保証                                          |
| `onboardingCompletedAt` | Date? | 必要な設定を確認できた日時                                           |
| `autoIncludeNewLists`   | Bool  | 初回設定後に新しく検出したリストを対象に加えるか                     |
| `dailyFocusGoalSeconds` | Int   | 1日の取り組み目標。日次アリ度の分母。Figma例7200                     |
| `policyVersion`         | Int   | ルールの版。3.7.6節の定数の版（`PolicyConstants.version`）を記録する |
| `updatedAt`             | Date  | 更新日時                                                             |

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

選択したアプリ単位の上限・選択世代。

| 項目                   | 型   | 制約・用途                                                    |
| ---------------------- | ---- | ------------------------------------------------------------- |
| `id`                   | UUID | PK。アプリ内部の対象参照                                      |
| `applicationTokenData` | Data | エンコードしたApplicationToken                                |
| `tokenFormatVersion`   | Int  | アプリ側の保存形式の版                                        |
| `dailyLimitSeconds`    | Int  | 曜日にかかわらず適用する日次上限。FigmaのXは1800              |
| `isEnabled`            | Bool | 制限対象の設定値。発行済み利用枠の失効フラグではない（3.4節） |
| `selectionRevision`    | Int  | 選び直し・再登録前の古い要求を検出                            |
| `updatedAt`            | Date | 更新日時                                                      |

### 1.7 FocusSession

1つのToDoに取り組む1回分。取り組み中・ふりかえりを結ぶ。

| 項目                                 | 型                   | 制約・用途                                                                           |
| ------------------------------------ | -------------------- | ------------------------------------------------------------------------------------ |
| `id`                                 | UUID                 | PK                                                                                   |
| `reminder`                           | ReminderReference?   | 対象ToDo。参照不能でも履歴は保持                                                     |
| `originConversation`                 | Conversation?        | 開始元の会話。ホームからならNULL可                                                   |
| `titleSnapshot`                      | String?              | 取り組み時のタスク名。表示用履歴の削除後はNULL（3.7節）                              |
| `startedAt / workEndedAt / closedAt` | Date / Date? / Date? | 開始／作業終了／ふりかえり確定                                                       |
| `status`                             | Enum                 | running / reflecting / finished / interrupted                                        |
| `historyDeletionRequestedAt`         | Date?                | 表示用履歴の削除要求日時。進行中でも要求を保存し、終了・照合後に区間等を削除する     |
| `rewardIntervalSnapshot`             | Int                  | 開始時の内部付与単位。後のルール変更で再計算しない。追加時間は固定比率5：1から求める |
| `policyVersion`                      | Int                  | 開始時のルール版                                                                     |

### 1.8 FocusSegment

実際に計測する区間。日跨ぎ・中断・復旧を扱い、日次・週次の取り組み時間を集計する。集計した取り組み時間をアリ度の分子に使う（2.3節）。

| 項目                  | 型           | 制約・用途                                   |
| --------------------- | ------------ | -------------------------------------------- |
| `id`                  | UUID         | PK                                           |
| `session`             | FocusSession | 所属する取り組み                             |
| `startedAt / endedAt` | Date / Date? | 区間開始／終了。NULLなら計測中               |
| `elapsedSeconds`      | Int          | 確定値または直近チェックポイントまでの計測秒 |
| `checkpointAt`        | Date         | 最後に計測値を保存した時刻                   |

### 1.9 Conversation

タスク選択・説得・ふりかえりの会話単位。閉じるときの戻り先も保持する。

| 項目                    | 型                 | 制約・用途                                                               |
| ----------------------- | ------------------ | ------------------------------------------------------------------------ |
| `id`                    | UUID               | PK                                                                       |
| `purpose`               | Enum               | taskSelection / persuasion / reflection                                  |
| `origin`                | Enum               | home / shield / task。遷移元の文脈                                       |
| `targetApp`             | AppRestriction?    | 相談の対象アプリ                                                         |
| `selectedReminder`      | ReminderReference? | 選択・おすすめ・復帰対象のToDo                                           |
| `focusSession`          | FocusSession?      | ふりかえり対象                                                           |
| `status`                | Enum               | active / completed / cancelled                                           |
| `promptVersion`         | String             | 使用したプロンプト版                                                     |
| `messagesPurgedAt`      | Date?              | 本文・カードを削除した日時。削除後も必要な処理参照は保持                 |
| `createdAt / updatedAt` | Date / Date        | 開始／最後のメッセージ確定日時。閲覧・照合・清掃では保持期限を延長しない |

### 1.10 ChatMessage

会話を再表示する本文とカード。モデル内部状態の丸ごと保存を要求しない。本文・カード・進捗の自由記述は最終更新から30日で削除する。詳細は3.7節。

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

| 項目                                    | 型                            | 制約・用途                                                                   |
| --------------------------------------- | ----------------------------- | ---------------------------------------------------------------------------- |
| `id`                                    | UUID                          | PK。通信再試行では同じID                                                     |
| `conversation / targetApp`              | Conversation / AppRestriction | 所属会話／対象アプリ                                                         |
| `quotaDayKey / quotaTimeZoneIdentifier` | String / String               | 開始時の「アプリの1日」（朝4時区切り）の日付YYYY-MM-DD／タイムゾーン（D024） |
| `countsTowardQuota`                     | Bool                          | 日次回数への算入。条件は3.7.4節                                              |
| `status`                                | Enum                          | evaluating / approved / rejected / failed / cancelled                        |
| `convictionScore`                       | Int?                          | 最新の納得度0〜100。試行ごとに0から始める（D025）                            |
| `decisionReason`                        | String?                       | 判定理由                                                                     |
| `attemptedAt / decidedAt`               | Date / Date?                  | 試行開始／最終判定日時                                                       |

### 1.12 TaskCompletionEvent

ユーザー確認後のEventKit完了書込みと完了報酬を結ぶ処理記録。

| 項目                                    | 型                                | 制約・用途                                                            |
| --------------------------------------- | --------------------------------- | --------------------------------------------------------------------- |
| `id`                                    | UUID                              | PK。処理の再開・再試行でも同じID                                      |
| `reminder / focusSession`               | ReminderReference / FocusSession? | 対象ToDo／取り組み                                                    |
| `occurrenceKey`                         | String                            | 報酬対象回のアプリ内識別子。非繰返しは固定値onceを提案                |
| `titleSnapshot / dueComponentsSnapshot` | String / Data                     | 完了前の名前／DateComponents相当の照合補助。確定後90日で削除（3.7節） |
| `rewardSecondsSnapshot / policyVersion` | Int / Int                         | 完了処理受付時の報酬量／ルール版                                      |
| `requestedAt / appliedAt`               | Date / Date?                      | ユーザー確認／EventKit書込み確認日時                                  |
| `status`                                | Enum                              | pending / applied / needsReview                                       |

### 1.13 RewardTransaction

獲得あそび時間の増減台帳。残高を別カラムに重複保持しない。

| 項目                        | 型                   | 制約・用途                                                                                               |
| --------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------- |
| `id`                        | UUID                 | PK                                                                                                       |
| `deltaSeconds`              | Int                  | 獲得は正、利用枠との交換は負。0を許容しない                                                              |
| `rewardDayKey`              | String               | 計上した「アプリの1日」（朝4時区切り）の日付YYYY-MM-DD。残高はこの日付が今日の取引だけで計算する（D028） |
| `kind`                      | Enum                 | focusReward / completionReward / redeem / refund                                                         |
| `focusSession`              | FocusSession?        | 取り組み報酬の原因                                                                                       |
| `completionEvent`           | TaskCompletionEvent? | 完了報酬の原因                                                                                           |
| `unlockGrant`               | UnlockGrant?         | 利用枠との交換・返金の対象                                                                               |
| `reversesTransaction`       | RewardTransaction?   | 返金で打ち消す元の引落し                                                                                 |
| `idempotencyKey`            | String               | 一意。同じ原因の二重計上を防ぐ                                                                           |
| `policyVersion / createdAt` | Int / Date           | 計算時のルール版／確定日時                                                                               |

### 1.14 UnlockGrant

対象アプリへ発行する一時利用枠。許可の記録とOSへの適用処理を追跡する。

**利用枠とは:** 報酬との交換やAIへの相談で発行する「対象アプリを一定時間使える」という一時許可。たとえば「Xを5分使える」という許可1件をUnlockGrantで表す。報酬残高やアプリの日次上限とは別の記録である。「有効利用枠」は、OSへの登録が完了し、終了条件に達しておらず、取り消されていない許可を指す。DBのregisteredだけでOS上の有効性を断定せず、監視・復帰時の照合で確認する。

発行済みの枠は、後から上限や対象選択を変更しても発行時の終了条件まで維持する。変更後の設定は次の発行判定と枠終了後の制限再計算から使用する。設定変更を理由に取り消し・返金・時間の再付与を行わない。詳細は3.4節。

| 項目                                                    | 型                 | 制約・用途                                             |
| ------------------------------------------------------- | ------------------ | ------------------------------------------------------ |
| `id`                                                    | UUID               | PK                                                     |
| `targetApp`                                             | AppRestriction     | 対象アプリ                                             |
| `source`                                                | Enum               | reward / persuasion                                    |
| `persuasionAttempt`                                     | PersuasionAttempt? | 説得由来の場合の成功試行。1試行から最大1件             |
| `timeBasis`                                             | Enum               | appUsageTime（D023で実利用時間に決定）                 |
| `allowanceSeconds`                                      | Int                | 発行した利用枠。正の整数                               |
| `requestedAt / registeredAt`                            | Date / Date?       | 要求日時／OS適用処理の成功日時                         |
| `plannedExpiresAt / endedAt`                            | Date? / Date?      | 失効予定（次の朝4時）／終了処理の観測日時              |
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
- ToDoの改名・削除後も、3.7節の保持期間内は取り組み・完了時のsnapshotで履歴を表示する。表示用の名前等を削除しても、台帳と二重実行防止に必要な発生元・状態・一意キー・必須参照は維持する。
- 会話本文・取り組み詳細と処理記録の削除は3.7節に従う。必須の関連をcascadeで失わせず、本文を削除したConversationは必要なヘッダーを残す。任意の表示用参照だけnullifyできる。
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

### 2.2 初回設定（オンボーディング画面）

Figmaの統合変更（D029）では、下表のO04・O05を1つの「アプリと時間」画面64:225にまとめている。下表のIDは処理の区分として維持し、選択と上限設定の間に独立画面への遷移が必要とは解釈しない。リスト選択→統合画面→準備完了と進む。完了報酬の編集UIとD028の固定値の照合事項はUI_UX.mdの2節を参照する。

| 画面           | 表示するデータ                            | 操作→処理→遷移                                            | 保存・異常系                                                                                                    |
| -------------- | ----------------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| O01 ようこそ   | アプリの目的、初回設定の有無              | はじめる→O02。設定済みの起動は復帰時照合後H01へ           | この画面だけで初回設定完了にしない                                                                              |
| O02 権限       | Family Controls・EventKit・通知の現在状態 | 個別の許可操作→OSの認可→状態を再取得。次へ→O03            | 権限をDBの正本にしない。必須権限と拒否時の扱いは3.7.1節                                                         |
| O03 リスト選択 | EKCalendarのリスト、既存の選択、件数      | 選択・自動追加設定→保存→O04                               | 検出済み全リストのisSelectedを保持。0件・取得失敗・書込み不可を区別。ID変更を新規作成と即断しない               |
| O04 アプリ選択 | 現在のApplicationToken集合                | OSのFamilyActivityPickerで選択→アプリ別設定へ対応付け→O05 | トークンを保存し選択revisionを更新。標準認可で名称・bundle ID文字列を取得できる前提にせずLabel(token)で表示     |
| O05 上限設定   | 選択アプリと各上限                        | 秒数・対象を検査→設定保存→O06                             | 初期値は一律30分、5分刻み、0分は最初から制限（3.7.2節）。Figmaの30/20/45/10分は例。対象なし・不正値は修正を案内 |
| O06 準備完了   | 対象件数・リスト件数・上限合計            | ホームへ→必要設定・監視準備を再確認→H01                   | 条件成立後にonboardingCompletedAtを保存。欠落時は該当設定に戻る。朝チェックインは自動追加しない                 |

### 2.3 ホーム・使用時間・設定

| 画面             | 表示するデータ                                                                  | 操作→処理→遷移                                                                                         | 保存・異常系                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| H01 ホーム       | EventKitの最新ToDo、当日の取り組み合計・指標、報酬残高。SNS利用表示部分はReport | 今日／すべて切替→対象を再計算。取り組む→origin=homeでT01。使用時間→H02                                 | 表示だけで報酬を発行しない。「今日」・期限なし・期限切れの分類と並び順は3.7.7節。取得失敗と本当に0件を分ける  |
| H02 使用時間     | アプリ別使用時間、上限、週次グラフ、取り組み、目標・ルール                      | Reportを日次／週次フィルターで表示。対象アプリの設定操作→S01。アプリ追加・削除→OSピッカーとO04共通処理 | 使用時間はReport内で集計。上限・取り組み・残高は本体データ。無許可・準備中・データなし・遅延を0分と混同しない |
| S01 アプリ別上限 | 対象アプリ、使用時間Report、毎日共通の日次上限                                  | 編集→値の検査→版を更新→共有設定・監視を更新→起点画面へ                                                 | 「通知だけ」も採用済みにしない。設定変更時の有効利用枠の扱いはAQ12                                            |

**週次表示と設定の範囲:** H01の「今週のありとキリギリス」とH02の週次グラフを実装する。SNS実利用時間はReport拡張内で集計・表示し、本体DBへ書き出さない。独自の取り組み時間はFocusSegmentから集計し、比較表示に必要な値をReportへ渡す方式をV08で検証する。休日別設定は引き続き対象外で、S01の日次上限を毎日共通で適用する。

**H01・H02のReport構成**

1. 本体アプリが`DeviceActivityReport(context, filter:)`をSwiftUIの画面に配置する。日付範囲・選択対象・日次／週次などの条件を渡す。
2. Report拡張の`makeConfiguration(representing:)`がOSから渡された利用データを集計し、独自の表示用Configurationを作る。
3. Report拡張が、そのConfigurationを使ってH01の週次欄やH02のアプリ別の数字、合計、日次・週次グラフをSwiftUIで描画する。表示用の集計処理は可能。
4. 本体が持つ取り組み時間・目標・上限を、読取り用スナップショットとしてReport側に渡す案を検証する。Report内で使用時間と比較してグラフ・指標を計算することまで不可能とは扱わない。
5. Report内の操作を本体のS01へ渡せるかは未確認。経路が成立する場合も、対象のアプリ内参照など最小限の操作情報だけを扱い、利用時間の数値を本体へ返す方法として使わない。本体側に設定操作を置く案を含め、Reportの行との対応と遷移をV08で検証する。

Appleは、Report拡張内で利用データを集計して独自のSwiftUIレポートを表示し、本体画面に埋め込む方法を説明している。[WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)、[makeConfiguration](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene/makeconfiguration%28representing%3A%29)

Report拡張はsandboxで動き、機微な情報を拡張の外へ移動すること等に制約がある。そのため、**Reportが受け取ったSNS利用時間を本体のSwiftDataへ書き出し、本体・AIが自由に再利用する構成は標準構成にしない**。これはReport内の集計・表示を禁止する意味ではない。独自の取り組みデータをReportへ読ませる共有方式、更新、比較グラフはSDK・実機で検証する。[DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)

専用entitlement・認可・地域等の条件を伴う直接データアクセスAPIは別経路として存在する。「あらゆるiOS環境で取得不可能」と断定しない。本書は通常のReport APIを使う構成を基本とし、日本向け配布でその例外へ依存しない。[activityData](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata%28filteredby%3Ausing%3A%29)、[approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess)

**アリ度・キリギリス度（ユーザー指定）**

| 指標              | 計算式・計算元                                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| アリ度（%）       | 取り組み時間÷目標時間×100。取り組み時間はFocusSegmentの計測値から集計する。日次の目標時間はAppSettings.dailyFocusGoalSecondsを使う |
| キリギリス度（%） | 100−アリ度                                                                                                                         |

例: 取り組み72分・目標120分なら、アリ度は60%、キリギリス度は40%。両指標は本体の取り組み・目標データから算出でき、SNS実利用時間は計算に使わない。画面の使用分数・アプリ別使用時間・使用時間グラフは、引き続きReportが扱う実利用データを表示する。

目標超過時に100%で打ち止めにするか、目標0・未設定時、端数の丸め方、日付境界、キャラクターの段階切替はAQ11に残す。ホーム週次欄の集計期間・目標時間・「アリの日」の判定・途中日や欠測時の表示と、SNS使用時間Reportの集計対象アプリ・週の開始日もAQ11で確定する。アリ度・キリギリス度の確定した計算式は維持する。指標は都度計算する派生値とし、指標専用のDBカラムは追加しない設計案とする。

### 2.4 Shield・タスク選択・説得

| 画面           | 表示するデータ                                   | 操作→処理→遷移                                                                                                 | 保存・異常系                                                                                                                                |
| -------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| R01 通常Shield | 対象アプリ、案内、再取得可能な範囲のタスク情報   | 本体への導線を使い、origin=shieldでT01またはC01へ。対象アプリ等の起動要求を共有する                            | Shield内で自由なチャットを描かない。最新タスク数を常時保証しない。対応API・対象OS・失敗時の手動導線をV04で確認                              |
| T01 タスク選択 | 最新の未完了候補、選択状態、起点                 | 候補選択→開始直前に再取得→FocusSession・最初のFocusSegment作成→F01。理由相談→C01                               | 閉じる→保存したoriginに対応する戻り先。ホーム起点をShieldへ戻さない。削除・完了済みなら再選択。会話からの新規作成は今回必須にしない追加候補 |
| C01 説得       | 対象アプリ、タスク、会話、利用可能な条件・試行枠 | 文字で理由を入力・送信→試行枠を検査・確保→AI応答→アプリが提案を検査。着手→T01。不許可→C02。利用枠の発行は3.4節 | 生成中の重複送信防止、古い結果・カードの無効化、取消しを扱う。納得度だけで解除しない。1回の数え方は3.7.4節、納得度は3.7.5節                 |
| C02 説得不許可 | 判定理由、最新の試行枠、次のタスク候補           | タスクへ→T01。再挑戦→条件成立時に新しい試行IDでC01                                                             | 生成エラーは技術エラーとして区別。失敗・中断・エラー時の回数消費は3.7.4節                                                                   |
| R02 利用枠終了 | 終了した利用枠、最新タスク、制限状態             | 着手→T01または既存の取り組みへ。相談→C01                                                                       | Monitorが再制限・終了を記録。本体を自動的に前面へ出せる前提にしない。次にShield／本体を表示するときに状態を反映                             |

Figmaの「Xを開く」は、利用枠の発行要求とSNSの起動を分けて実装する。具体的なSNSを自動起動できるかは別途確認し、一般のApplicationTokenから任意アプリを必ず起動できるとは約束しない。利用枠を発行したあと、手動で対象アプリを開く導線も用意する案とする。

### 2.5 取り組み・ふりかえり

| 画面                 | 表示するデータ                                                 | 操作→処理→遷移                                                                                                               | 保存・異常系                                                                                                                           |
| -------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| F01 取り組み中       | 選択ToDo、計測時間、見込み／付与済みの報酬、次の単位までの時間 | 「終わってふりかえる」→区間を閉じworkEndedAtを記録→ふりかえり会話を開始。ユーザーの回答・確認によりF02またはF03の状態へ      | 画面のTimer値だけを正本にしない。復帰時に区間・チェックポイントから再構成。途中終了でも自動完了させない                                |
| F02 完了ふりかえり   | 計測結果、実ToDo、完了確認、今回の付与内訳                     | 進捗回答→AIが確認を提案→ユーザーが「完了にする」→TaskCompletionEvent作成→EventKit保存→報酬を確定。ホーム→H01、他のタスク→T01 | EventKit更新成功前に「チェックした」と表示しない。AIの発言だけで完了にしない。再押下・再開でも二重付与しない                           |
| F03 未完了ふりかえり | 計測結果、未完了ToDo、進捗回答、今回の時間報酬                 | 本人の未完了回答を確認→ToDoは未完了のまま、今回の計測終了と報酬を確定→H01またはT01                                           | 完了報酬を付けない。Figmaの「まだ続ける」はToDoの継続を指し、タイマー再開と混同しない。時間報酬は3.7.8節。25分未満の端数は繰り越さない |

F02・F03は同じふりかえり画面の結果状態として扱える。Figmaの取り組み終了ボタンが直接完了済みの画面へ進む設定を、そのまま完了操作として実装しない。まず進捗と本人確認を受け取り、未完了の結果にも到達できるようにする。

取り組み報酬は5：1で換算する。25分の取り組みに対してSNS5分、50分に対して10分となる。付与の単位・時点・端数処理と完了時の追加時間は3.7.8節に従う。途中ですでに報酬を記録した場合は、終了時に同じ取り組みの未計上分だけを追加する。未完了なら完了報酬を追加しない。

## 3. 画面に属さない共通処理

### 3.1 責務とターゲット構成

| 処理・ターゲット               | 責務                                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| 本体アプリ                     | 初回設定、EventKit取得・確認済み更新、タスク選択、対話、取り組み、台帳、ポリシー検査、Reportビューの配置 |
| Shield Configuration拡張       | OSのShieldに表示するアイコン・文言・ボタンの設定                                                         |
| Shield Action拡張              | Shieldの操作に応答し、対象と起点の要求を共有。本体への導線を実装                                         |
| Device Activity Monitor拡張    | 日次上限・利用枠の監視に応じて制限を更新し、実行結果を記録                                               |
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
- completionDateだけを完了回の一意キーにしない。完了解除・再完了・外部クライアントで値が変わる場合がある。外部完了・取消し・繰返しへの報酬の扱いは3.7.8節。
- 個人向けFamily Controls認可は本人が取り消せる。選択トークンの無効化を扱い、必要なら再選択を案内する。[A03](https://developer.apple.com/videos/play/wwdc2022/110336/)、[A04](https://developer.apple.com/documentation/familycontrols/familyactivityselection)
- アプリの表示にはLabel(applicationToken)を用いる。名称・bundle IDを標準認可で必ず取得できる前提にしない。モデルには独自の対象参照を渡し、トークンをプロンプトへ直接渡さない。[Displaying Activity Labels](https://developer.apple.com/documentation/familycontrols/displayingactivitylabels)

### 3.4 制限・解除・再制限

**設定変更中の一時利用許可（確定）**

維持する対象はOSへの適用が完了したregisteredの枠とする。requested等の準備中の要求・カードは最新設定で再検査し、その段階では旧設定による許可を確約しない。

| 状況                                                                 | 採用する動作                                                                                                             |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Xを5分使える許可が残り3分ある間に、Xの日次上限を30分から10分へ下げる | 発行済みの3分は維持する。新上限は枠終了後の制限再計算と次の利用枠の発行判定から適用する                                  |
| 一時許可が残っているXを制限対象から外す                              | 発行済みの枠は元の終了条件まで保持する。終了時の最新設定が対象外なら再制限しない。設定変更を理由に返金しない             |
| Xを対象から外した後で、もう一度Xを選ぶ                               | 同じ対象として照合でき、元の枠が有効なら残り時間だけを引き継ぐ。終了済みの枠は復活させず、照合できない対象へ枠を移さない |

保存した新設定と、発行済みの枠へ適用する条件を分ける。発行済みのgrantID・対象参照・終了時刻／残り利用量・監視設定を保持し、policyVersionやselectionRevisionの更新だけでは失効させない。再登録しても時間を起算し直さず、返金・再引落し・追加付与を行わない。利用枠の長さ・経過時間／実使用時間の意味はAQ03に従う。OS認可取消し・全データ初期化・復旧処理は別の異常系として扱う。

未発行の要求・カードは最新の設定世代で検査する。一方、発行済み枠の終了通知はgrantIDとその枠のmonitorGenerationで照合し、全体の設定が新しくなっただけで破棄しない。日次上限の通知も有効な発行済み枠を短縮せず、枠終了時に最新設定からShieldを再計算する。対象解除でAppRestrictionを物理削除せず、参照を残して選択状態を更新する。

利用枠の発行処理案:

1. AIは返答とUnlockProposalを返す。提案だけでは制限を変更しない。
2. 本体は提案カードを表示し、ユーザーの利用操作を受け付ける。カードに対象・量・時間の意味を示す。
3. UnlockPolicyが権限、対象、タスク、ルール版、試行上限、既存の利用枠、量を検査する。古い対象・会話・要求を拒否する。
4. UnlockGrantをrequestedとして一意に記録する。残高との交換なら、残高検査と引落しも同じDBトランザクションで行う。説得由来の利用枠と残高への加算を同一視しない。
5. 先に終了条件の監視を準備し、その後、対象だけの制限を変更する。成功後にregistered・結果表示へ進む。時間は対象アプリの実利用時間で数える（3.7.3節）。カードの表示時刻を利用開始とみなさない。
6. 失敗時は解除成功を表示せず、必要な再制限・一意な返金を行う。別アプリの制限をまとめて解除しない。
7. MonitorがgrantIDと枠固有の監視世代を照合し、終了条件を検知したら最新設定で制限を再計算してイベントを記録する。本体は復帰時にも照合する。他の枠や更新前の監視登録の通知で、現在の枠を終了しない。

| 状態               | 意味・遷移                                             |
| ------------------ | ------------------------------------------------------ |
| permissionRequired | 必要な権限なし。認可状態と選択を再取得                 |
| ready              | 設定・対象を利用できる。採用した開始条件でrestrictedへ |
| restricted         | アプリが制限を適用した状態。相談開始でnegotiatingへ    |
| negotiating        | 対話中。現在の制限を維持                               |
| grantPending       | 検査、利用枠記録、終了監視の準備中                     |
| temporarilyAllowed | 条件付きの解除処理を行った状態。終了条件で再制限       |
| recoveryRequired   | DB・共有状態・OS設定の不一致や処理失敗。再評価・復旧   |

状態はアプリの処理記録であり、DBの値だけでデバイス上の実効制限を保証しない。日次上限・一時利用枠の基本関係はAQ02、設定変更時は本節の発行済み枠を維持する規則に従う。複数ManagedSettingsStoreでは厳しい設定が優先されることを踏まえ、発行済み枠の条件と最新の通常設定を区別して対象ごとの制限を再計算する。[A03](https://developer.apple.com/videos/play/wwdc2022/110336/)

「解除から1分経過」と「対象アプリを1分使用」は別仕様。監視scheduleには最小15分のinterval制約があるが、すべての利用しきい値が15分以上という意味ではない。長い監視窓と短い利用しきい値の候補は実機検証する。[A11](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)

**Screen Time APIの制約（2026-10-17調査）**

表記は【公式】Appleのドキュメント、【WWDC】セッションでの説明、【非公式】Developer Forums等の報告、【推測】調査者の推論、【不明】確認できなかったこと。出典は6.1節。

| 項目                 | 内容                                                                                                                                                                   | 設計への反映                                                                                                                        |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 監視期間             | 最小15分、最大1週間【公式】。15分が区間全体の長さか残り時間かの定義はない【不明】                                                                                      | 3.7.3節の朝4時直前の発行で問題になる                                                                                                |
| しきい値             | 最小値の記載はない【公式】。1つのイベントに複数アプリを入れると合算で判定される【公式】                                                                                | 一時利用は対象アプリ1つだけのイベントにする                                                                                         |
| しきい値の数え始め   | 既定では監視を始めた時点から。iOS 17.4以降の`includesPastActivity: true`で区間の開始から数える【公式】                                                                 | 日次上限には`true`、一時利用には`false`を使う案                                                                                     |
| 短いしきい値の不具合 | すぐ発火する、発火しない、30〜60分遅れる、二重に発火する、という報告がiOS 26.5.2まである【非公式】                                                                     | 「解除が一瞬で終わる」「解除が終わらない」の両方への保険が必要。例えば、時計の時刻で上限を設けた監視を重ねる【提案】。V06で確認する |
| 監視の数             | アプリと拡張を合わせて同時に20個まで（`excessiveActivities`）【公式】。1つの監視に入れられるイベント数の上限は記載なし【不明】                                         | アプリごとに監視を分けず、日次上限は1つの監視に複数イベントをまとめる【推測】                                                       |
| コールバック         | `intervalDidStart` / `intervalDidEnd`は、端末が使われたときにしか呼ばれない【公式】                                                                                    | 本体の復帰時の照合（3.4節7）を省かない                                                                                              |
| 即時の制限           | `ManagedSettingsStore.shield.applications`に代入すれば、監視を待たずに制限がかかる。1ストアで50トークンまで【公式】                                                    | 0分のアプリの制限（3.7.2節）に使う                                                                                                  |
| 複数ストア           | 名前付きストアは1プロセス50個まで。設定が衝突したら最も厳しい設定が勝つ【WWDC】。iOS 26.5でストアを計算から外す`isActive`、削除、トークン更新のAPIが追加された【公式】 | 一時利用では、対象アプリを入れている全ストアから外す必要がある                                                                      |

本体はバックグラウンドでsuspendされ得るため、画面内Timerだけで再制限しない。経過時間方式／実利用時間方式の意味、既使用分、再登録、再起動・時計変更をV06で確認する。[A12](https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence)

### 3.5 AI・UI・ポリシー間の入出力

以下は実装時の型契約案。モデルの生の文章から制限操作を推測せず、構造化された候補を検査する。

| 契約                   | 項目・意味                                                                                                                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI入力                 | 最新のTaskSnapshot、選択タスク、対象アプリの独自参照、必要な会話、許可アクション、量の上限・単位、時間の意味、直前の処理結果                                                                 |
| AI出力候補             | 説得時はcontent（String）とconvictionScore（Int）を持つJSON形式を想定。action、taskID?、proposedSeconds?、reason等を付ける案。actionはask / suggestFocus / proposeUnlock / confirmCompletion |
| 本体が保持する要求情報 | requestID、conversationID、対象参照、selectionRevision、policyVersion。戻った応答を元の要求と照合する                                                                                        |
| UIからの操作           | startFocus、sendMessage、acceptUnlock、finishFocus、confirmCompletion、saveLimit。各操作に必要な対象IDと一意な要求IDを付ける                                                                 |
| 処理結果               | 成功時は新しい状態と確定ID。失敗時はpermissionRequired / taskUnavailable / modelUnavailable / modelFailed / invalidProposal / staleRequest / storageFailed / monitoringFailed等の区別        |

新規の提案・未発行カードは、タスク参照の実在、対象選択、正の秒数、上限、重複、現行版をアプリが検査する。発行済みの利用枠は3.4節の発行時条件で維持する。タスク名・メモ・会話をポリシー変更の命令として扱わない。取消した要求の遅延応答でカードを復活させず、古い未発行カードを再利用しない。Tool Callingでも同じ検査を通す。

納得度の3要素は「事情がやむを得ない度」「タスクの必要性」「利用後に取り組む行動の具体性」で確定した（D023）。各要素の評価基準の詳細・必要性の対象と加減方向・配点・更新方法・表示段階・許可判断との関係はAQ06に残す。UI_UX.mdの計算式等は未採用であり、JSONで整数が返ることだけで採点の妥当性や解除許可を確定しない。

Foundation Modelsは構造化生成・Tool Callingの候補。利用前にSystemLanguageModel.default.availabilityを確認する。形式が正しくても判断内容の正しさは保証されない。端末、OS、言語・地域、モデル準備と実応答をV05で確認する。[A09](https://developer.apple.com/videos/play/wwdc2025/286/)、[A10](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

### 3.6 Shield・署名・実行環境

Shieldはシステムの制限画面であり、自由なチャットは本体で表示する。背景のblurやラベル等の設定APIを、SNSの任意画像の取得・自由なオーバーレイ機能として扱わない。[A07](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/primarybuttonlabel)

ShieldActionResponse.openParentalControlsAppは最新資料に存在する。使用SDKのavailability、個人認可、対象端末、渡せる文脈をV04で確認し、任意deep linkが使えると仮定しない。非対応時は本人が本体を開く導線を用意する。[A08](https://developer.apple.com/documentation/managedsettings/shieldactionresponse)

2026-10-17の調査で分かったこと（表記と出典は3.4節・6.1節）:

- `openParentalControlsApp`はiOS / iPadOS 26.5以降【公式】。説明は「シールドを掛けているアプリを開くようシステムに指示する」の一文だけで、個人向け認可（`.individual`）で使えるか、どの画面が開くか、状態を渡せるかは記載がない【不明】。
- iOS 26.4以前には、Shieldから本体を開く公式の方法がない。Appleのエンジニアが2022年11月と2025年1月に「サポートされた方法はない」と回答しており、ローカル通知を経由する回避策が一般的だった【非公式】。
- iOS 26.4から、Shieldのセカンダリボタンに最大3項目のサブメニュー（例:「あと1分」）を付けられる。押すと`ShieldAction`に通知が届く【公式】。
- 最低OSを26.5以上にするかは、デモの導線（V04）に直結する。STATUS.mdのQ02・Q07で決める。

開発時のFamily Controls capability、ターゲットごとのApp ID・署名、配布時のentitlement申請を区別する。配布では関連extensionの申請も確認する。[A05](https://developer.apple.com/documentation/xcode/configuring-family-controls)、[A06](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

プロダクト名、project／scheme、Bundle ID、App Group ID、最低OS、使用Xcode／SDK、実機担当は未確定。存在しないビルドコマンドや実機結果を作らず、成立した設定をSTATUS.mdへ記録する。プロジェクト・ターゲット設定の編集責任者を決め、並行実装では上記の型契約を共有する。

### 3.7 権限・上限・一時利用・説得のルール

5章の未決事項（旧AQ01・AQ02・AQ03・AQ05・AQ06・AQ07・AQ08）について、2026-10-17にユーザーが決めた内容。判断の履歴はDECISIONS.mdのD021〜D028。

#### 3.7.1 対応機種・権限・初回設定の完了条件（D021）

2026-10-17にユーザーが決定。完了条件の4〜7は、2.2節の既存設計を完了条件として並べたもので、この決定で新たに選んだ内容ではない。

**対応機種と権限**

| 項目                                             | 扱い                                                                | 拒否・不可のとき                                                                                                     |
| ------------------------------------------------ | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 対応機種                                         | Apple Intelligence対応機種に限定する（Foundation Modelsが動く機種） | `SystemLanguageModel.default.availability` が端末非対応なら、O01で「この端末では使えません」と伝えて初回設定を止める |
| Family Controls（個人認可）                      | 必須                                                                | O02から先へ進めない。理由と再試行の操作を表示する                                                                    |
| リマインダー（full access）                      | 必須                                                                | O02から先へ進めない。理由と設定アプリへの導線を表示する                                                              |
| 通知                                             | 任意                                                                | 拒否しても初回設定を完了できる。再制限はMonitor拡張が行うため、通知の有無に依存させない                              |
| AIの準備（Apple Intelligenceオフ、モデル準備中） | 初回設定の完了条件にしない                                          | 下記「AIが使えないとき」の扱いにする                                                                                 |

**AIが使えないとき（対応機種でApple Intelligenceがオフ、またはモデル準備中）**

- 制限・タスクルート（R01→T01→F01→F02）は通常どおり使える。
- R01の「AIを説得する」とC01は使えない状態にし、理由を表示する。オフなら設定アプリへの案内、準備中なら時間をおいて再試行する案内を出す。
- 固定文言の返答でAI対話の代わりにしない。
- 利用可否は会話を始める直前に毎回確認する。会話の途中で使えなくなったら、modelUnavailableとして扱う（3.5節）。

**初回設定のあとで権限が取り消されたとき**

| 取り消された権限 | 扱い                                                                                                                                                                                                     |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Family Controls  | OSが制限を外すので、アプリの状態をpermissionRequiredにする。H01に「制限が止まっています」と再認可の操作を表示する。選択済みのアプリ・上限の設定は残し、再認可後に選択トークンの有効性を確かめる（3.3節） |
| リマインダー     | 制限は維持する。T01とC01で再許可を案内し、タスクを取得できない状態を「タスク0件」として扱わない（3.3節）                                                                                                 |
| 通知             | 何もしない。必要なら設定画面で状態を表示する                                                                                                                                                             |

初回設定へ自動で戻すことはしない。

**初回設定の完了条件（O06で `onboardingCompletedAt` を保存する条件）**

1. 端末が対応機種である。
2. Family Controlsが承認されている。
3. リマインダーのfull accessが承認されている。
4. 対象リストが1つ以上選ばれている（O03）。
5. 対象アプリが1つ以上選ばれている（O04）。
6. 選んだアプリごとに、検査を通った上限が設定されている（O05）。
7. 上限の監視の登録に成功している。

通知の許可とAIの準備状態は完了条件に含めない。

#### 3.7.2 上限とToDoの関係・上限の値（D022）

2026-10-17にユーザーが決定。最初の依頼（U01）には「リマインダーにタスクがある場合、SNS等のアプリ利用に制限をかける」とあるが、「未完了があるときだけ上限を有効にする」案と比べたうえで、上限を常に有効にする案が選ばれた。

**未完了ToDoと上限の関係**

- 上限は、未完了ToDoの有無に関係なく常に有効にする。対象アプリの当日の利用が上限に達したらShield（R01）を出す。
- ToDoは、Shieldのあとのタスクルート（T01）とAIとの会話の材料に使う。監視拡張（Device Activity Monitor）はタスクの状態を読まずに制限を判断する。
- 上限に達する前は制限しない。対象アプリは自由に使える。本体からのタスク開始（H01→T01）はいつでもできる。

**未完了タスクが0件のとき**

- 上限に達したら、通常どおりShieldを出す。
- T01では「未完了のタスクがない」ことを表示し、説得ルート（C01）へ案内する。
- 取得失敗・権限なし・同期中を「0件」として扱わない（3.3節）。この場合は3.7.1節の取消し時の扱いに従う。

**上限の値**

| 項目   | 決定                                                                                                                                                                                    |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 初期値 | 選んだアプリすべてに一律30分（1800秒）。O05で変更できる                                                                                                                                 |
| 刻み   | 5分                                                                                                                                                                                     |
| 0分    | 許可する。0分のアプリは、使用時間の監視を待たずに最初から制限し、開くたびにShieldを出す。説得とタスクルートは通常どおり使える。解除相談を受け付けない「完全ブロック」（対象外）とは別物 |
| 最大値 | 未決定（O05の選択肢の上端。例: 3時間）                                                                                                                                                  |

0分のアプリへの制限は、監視のしきい値ではなく、上限設定の保存時と日付の切替時（朝4時、D024）に`ManagedSettingsStore.shield.applications`へ直接設定する。監視を待たずに制限できることは公式ドキュメントで確認した（3.4節）。実機での動作は未確認（V03・V06）。設定変更の適用点はAQ12で決める。

#### 3.7.3 一時利用の時間（D023）

2026-10-17にユーザーが決定。

**時間の数え方: 実利用時間**

- 一時利用の時間は、対象アプリを実際に使っている時間だけで数える。ほかのアプリに移っている間は減らない。
- 利用時間を数え始めるのは、ユーザーが提案カードの操作（acceptUnlock）で利用枠を受け取り、制限が外れたあとに対象アプリを使った時点。カードの表示時刻ではない。
- 実装案: 利用枠を登録するときに、その時刻から次の朝4時（D024）までのDeviceActivityの監視を新しく登録し、対象アプリだけのイベントのしきい値を利用枠の秒数にする。`includesPastActivity`は`false`にして、受け取る前の利用を数えない（既定でも監視開始時点から数える【公式】）。しきい値に達したらMonitor拡張が制限を戻す。
- 朝4時まで15分以上あれば、最小間隔の制約（A11）にかからない。朝4時の直前（残り15分未満）に発行する場合の扱いは未決定。開始時刻が過去の区間も登録はできる【公式】が、15分の判定が区間全体か残り時間かは記載がない【不明】。監視の開始時刻を過去にずらすか、その時間帯は発行しないかを、V06の結果で決める。
- 短いしきい値には、すぐ発火する・発火しない等の不具合報告がある【非公式】（3.4節）。そのため、しきい値の通知だけに頼らない保険を用意する【提案】。例えば、受け取った時刻から一定時間後に必ず終わる、時計の時刻での上限を重ねる。保険の時間は未決定。
- 一時利用で制限を外すときは、対象アプリを入れている全ストアから外す（3.4節）。
- 報酬の残高と交換して発行する利用枠も、同じ数え方にする想定。報酬係数は取り組み時間：SNS追加時間＝5：1の固定値（D015・D018）。付与単位・タイミングは3.7.8節。

**説得が通ったときの1回の量: AIが1〜5分で提案**

- AIが事情に応じて分数を提案し（AI出力の`proposedSeconds`）、UnlockPolicyが60〜300秒（`PolicyConstants.persuasionGrantMinSeconds`〜`persuasionGrantMaxSeconds`、3.7.6節）の範囲かを検査する。範囲外の提案は採用せず、invalidProposalとして扱う。上限に丸めて許可することはしない。
- 提案の単位を1分刻みにするかは実装時に決める。
- 1日の合計は、説得の回数上限（全アプリ合計3回、3.7.4節）×1回の上限5分で最大15分。合計時間の上限は別に設けない。
- 同じ対象アプリに有効な利用枠が残っているあいだは、新しい利用枠を発行しない（3.4節）。

**終了条件**

次のどれかで利用枠を終了し、対象アプリを再び制限する。

1. 実利用時間が利用枠に達した。
2. 「アプリの1日」が切り替わった（朝4時、D024）。使い切らなかった分は失効し、翌日に持ち越さない。
3. 対象アプリの選び直しやFamily Controlsの取消しで、選択トークンが無効になった（3.3節）。
4. 上限設定の変更で利用枠を終了すると決めた場合（AQ12）。

日付の切替時刻とタイムゾーンは3.7.4節。

#### 3.7.4 説得の回数と「アプリの1日」（D024）

2026-10-17にユーザーが決定。

**説得1回の区切り**

- 「AIを説得する」で説得を始めてから、AIが許可または不許可を判定するまでを1回（PersuasionAttempt 1件）とする。
- 1回の中で複数往復してよい。ユーザーの発言が5通目になった応答で、AIは必ず許可か不許可を判定する。5往復目にAIが判定を返さなかった場合は、アプリが不許可として扱う。
- 不許可（C02）のあとに再挑戦すると、新しい1回になる。

**回数に数える終わり方**

| 終わり方                                             | 回数に数えるか                                   |
| ---------------------------------------------------- | ------------------------------------------------ |
| 許可（approved）                                     | 数える                                           |
| 不許可（rejected）                                   | 数える                                           |
| ユーザーが1通以上送ってから途中で閉じた（cancelled） | 数える。断られそうなときに閉じてやり直すのを防ぐ |
| 1通も送らずに閉じた                                  | 数えない                                         |
| AIのエラー・モデル利用不可で終わった（failed）       | 数えない                                         |
| AIの提案を受けてタスクに着手した（C01→T01）          | 数えない                                         |

回数は試行を始めた時点（最初の1通を送った時点）で確保し、数えない終わり方になったら確保を戻す（`countsTowardQuota`をfalseにする）。アプリが途中で終了した場合は、復帰時にcancelledとして数える。

**1日の上限**

- 全アプリ合計で1日3回。アプリを乗り換えても回数は増えない。
- 3回は初期値。定数`PolicyConstants.persuasionDailyLimit`（3.7.6節）として1か所にまとめ、処理の中に数値を直接書かない。値は開発側が後から調整する。利用者が変える設定画面は今回作らない。
- 説得による一時利用は、1日最大で3回×5分＝15分になる。合計時間の上限は別に設けない。

**「アプリの1日」の切替: 朝4時**

- 回数・上限・一時利用の失効は、端末の現地時刻で朝4時に切り替える。0時〜3時59分の利用は前日分として数える。
- タイムゾーンは端末の現在の設定を使う。試行には開始時のタイムゾーンと日付を記録し（`quotaDayKey`、`quotaTimeZoneIdentifier`）、途中でタイムゾーンが変わっても、その試行の日付は変えない。
- アプリ別上限の監視（DeviceActivityの日次スケジュール）も朝4時開始にする。0分のアプリへの制限のかけ直しも朝4時に行う。
- 日次上限の監視は、4:00〜翌3:59のスケジュールを繰り返し（`repeats`）で登録し、`includesPastActivity: true`で区間の開始から数える案。開始時刻が過去の区間も登録でき、登録時点でその区間の監視が始まる【公式】。`includesPastActivity`はiOS 17.4以降【公式】。日をまたぐ区間として解決されることは推測で、4:00〜4:00のように開始と終了が同じ指定の扱いは不明。V06で確認する。
- 利用時間は、スケジュールの開始日のタイムゾーンで数えられる。区間の途中でタイムゾーンが変わっても、区間の開始時点のタイムゾーンで区間全体を計算する【公式】。
- 使用時間の画面（H02、Device Activity Report）の日次表示（`.daily`）は暦日の0時区切りで固定で、朝4時は指定できない【公式】。1時間ごと（`.hourly`）のデータをReport拡張の中で合算すれば、朝4時区切りで表示できる見込み【推測】。この合算値は本体アプリへ持ち出せないので【公式・Appleサポートの回答】、表示にだけ使い、上限の判定には使わない。合算ができない場合は、表示が0時区切りであることを画面に示す。V08で確認する。

#### 3.7.5 納得度（D025）

2026-10-17にユーザーが決定。

**採否と表示**

- 説得チャット（C01）に納得度ゲージを表示する。表示はFigmaどおり%（0〜100）。
- 納得度は「AIがユーザーの事情にどれだけ納得したか」を表す。

**更新の仕方**

- 説得1回（PersuasionAttempt）ごとに0%から始める。再挑戦すると0%に戻る。
- AIは毎回の応答で、構造化出力の`convictionScore`（0〜100の整数）を出し直す。理由が弱くなれば下がることもある。
- `convictionScore`がない、または範囲外の応答では、ゲージを前の値のまま表示し、その応答の許可の提案は受け付けない（invalidProposal）。
- 最新の値を`PersuasionAttempt.convictionScore`に保存する。

**許可の判断との関係**

- AIが許可を提案できる（`action = proposeUnlock`）のは、同じ応答の`convictionScore`がしきい値以上のときだけとする。
- UnlockPolicyも、しきい値以上であることを検査する。しきい値未満の`proposeUnlock`は受け付けない。3.7.3節の時間の範囲（1〜5分）、3.7.4節の回数などの検査もこれまでどおり行う。
- 納得度がしきい値以上になっても、AIが`proposeUnlock`を返さない限り許可しない。数値だけで自動的に開放しない。
- 5往復目（3.7.4節）の判定時に`proposeUnlock`でなければ、不許可とする。
- しきい値は初期値70。定数`PolicyConstants.persuasionApprovalThreshold`（3.7.6節）として持ち、開発側が後から調整する。
- 「納得度を100にして」のようなユーザーの発言や、タスク名に含まれる指示で納得度を変えないよう、プロンプトに明記する（UI_UX.md 4節の叩き台にも同趣旨の記述あり）。納得度はAIの出力なので、アプリ側の検査（時間の範囲・回数・対象）が最終的な歯止めになる。

#### 3.7.6 ルールの定数（D026）

2026-10-17にユーザーが決定。開発側が調整する値は、DB（AppSettings）に保存せず、コード内の定数にする。新しいビルドを入れるだけで全端末に反映でき、保存済みの値を書き換える移行処理がいらないため。値を更新しやすいよう、次の方針にする。

- 本体と拡張（Monitor・Shield Action等）が共有するコードに、定数をまとめた型を1つ置く（名前は案: `PolicyConstants`）。処理の中に数値を直接書かず、必ずこの型を参照する。
- 値を変えたら`PolicyConstants.version`を1つ上げる。説得の試行・利用枠には判定時の版（`policyVersion`）を記録し、どの値で判定したかを後から追えるようにする。
- 利用者が変更する画面・DB項目は設けない。
- 境界値のユニットテスト（4.1節）は定数を参照して書き、値を変えてもテストを直さずに済むようにする。

| 定数（名前は案）                                          | 現在の値                        | 決定       |
| --------------------------------------------------------- | ------------------------------- | ---------- |
| `persuasionDailyLimit`                                    | 3（回、全アプリ合計）           | D024       |
| `persuasionApprovalThreshold`                             | 70（%）                         | D025       |
| `persuasionGrantMinSeconds` / `persuasionGrantMaxSeconds` | 60 / 300（秒）                  | D023       |
| 取り組み時間：SNS追加時間の比率                           | 5：1                            | D015・D018 |
| `focusRewardIntervalSeconds` / `focusRewardSeconds`       | 1500 / 300（秒。25分ごとに5分） | D028       |
| `completionRewardSeconds`                                 | 60（秒、ToDo完了1件につき）     | D028       |
| `dayBoundaryHour`                                         | 4（時、端末の現地時刻）         | D024       |
| `defaultDailyLimitSeconds` / `dailyLimitStepSeconds`      | 1800 / 300（秒）                | D022       |

報酬係数・日付の切替時刻・上限の初期値と刻みも、同じ型に置く案とする。報酬係数をコード内の定数にすることはD018で決定済み。それ以外を同じ型にまとめるのは、この節で整理した実装方針である。

#### 3.7.7 ホームの「今日」と「すべて」（D027）

2026-10-17にユーザーが決定。対象リストと日付の区切りの扱いは、決定時に前提として示し、異論がなかったもの。

**対象リスト**

- ホーム（H01）、タスク選択（T01）、AIに渡すタスクは、初回設定（O03）で選んだリストのタスクだけにする。

**「今日」タブに出すもの**

| 種類                   | 「今日」                         | 「すべて」 |
| ---------------------- | -------------------------------- | ---------- |
| 期限が今日の未完了     | 出す                             | 出す       |
| 期限切れの未完了       | 出す                             | 出す       |
| 期限が明日以降の未完了 | 出さない                         | 出す       |
| 期限なしの未完了       | 出さない                         | 出す       |
| その日に完了したもの   | 未完了の下に、完了済みとして出す | 出さない   |

- 「今日」は「アプリの1日」（朝4時区切り、3.7.4節）で判定する。深夜1時なら、前日が期限のタスクも「今日」に含める。
- 期限が時刻付きなら、その時刻が今日の「アプリの1日」に入るものを「今日」とする。日付だけの期限なら、日付が「アプリの1日」の日付と同じものを「今日」とする。今日より前のものは期限切れとする。今日の期限の時刻を過ぎていても、その日のうちは「今日」として扱う（実装方針）。
- 「その日に完了したもの」は、EventKitの完了日時が今日の「アプリの1日」に入るものとする。表示の判定にだけ使い、完了回の一意キー（3.3節）には使わない。

**並び順**

1. 期限の早い順（期限切れが先頭）。
2. 期限が同じなら、リマインダーの優先度が高い順（高・中・低・なしの順）。
3. さらに同じなら、作成日時が古い順。
4. 期限なしは末尾。

- 時刻付きと日付だけの期限が同じ日にあるときは、日付だけのものをその日の最後として並べる（実装方針）。
- 「すべて」タブの未完了も同じ順にする（実装方針）。

#### 3.7.8 あそび時間（報酬）の付与と失効（D028）

2026-10-17にユーザーが決定。比率5：1（D015・D018）を前提にする。

**取り組み報酬: 25分ごとに+5分、端数は切り捨て**

- 1回の取り組み（FocusSession）の計測時間が25分に達するごとに、あそび時間を5分付与する。付与量＝⌊計測秒÷1500⌋×300秒。
- 25分に満たない端数は切り捨て、次の取り組みに繰り越さない。24分でやめると0分。
- 数えるのは1回の取り組みの中だけ（中断・再開を含むFocusSegmentの合計）。別の取り組みの端数とは合算しない（実装方針）。
- F01には「次の+5分まであと○分」を表示する。
- 25分に達した単位は、画面で確認した時点か取り組みの終了時のどちらか早いときに台帳へ記録する。同じ取り組み・同じ単位番号の記録は一意にし（`idempotencyKey`）、復帰や再押下で二重に付与しない（実装方針）。

**完了報酬: 1件につき+1分**

- ふりかえり（F02）で「完了にする」を押し、EventKitへの書き込みを確認できたときに60秒を付与する（3.3節の手順）。
- 取り組み報酬とは別に付与する。

**完了報酬の対象**

- アプリ内の完了だけを対象にする。リマインダーアプリなど、アプリ外で完了にしたタスクには付与しない。
- 完了を取り消しても、付与した分は取り消さない。
- 繰り返しタスクは、回（`occurrenceKey`）ごとに1回まで付与する。
- 取り組み報酬は、タスクを完了したかどうかに関係なく付与する（F03の未完了でも付与する）。

**残高と失効**

- 残高は台帳（RewardTransaction）の合計で計算し、別のカラムに持たない。
- その日（朝4時区切り、3.7.4節）に計上した取引だけを残高に数える。朝4時になると前日の残りは使えなくなる。失効のための取引は作らず、`rewardDayKey`で区切る（実装方針）。
- 残高はShieldから本体を開いたときに、対象アプリの一時利用（UnlockGrant、source = reward）と交換する（3.4節）。交換した利用枠は、実利用時間で数え、朝4時に失効する（3.7.3節）。交換の画面と操作は未設計（AQ14）。

## 4. 検証と完了条件

以下は実装後の検証計画であり、現時点ではテストの実装・実行や実機検証は行っていない。未決仕様に関する期待値は、該当AQの解消後に追加する。

### 4.1 ユニットテスト

OSや実モデルを呼ばずに確認できる計算・ポリシー・台帳を対象とする。

| 対象               | 確認すること                                                                                                                                                   |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 取り組み報酬       | 1回の取り組みで1499秒→0秒、1500秒→300秒、2999秒→300秒、3000秒→600秒となる（3.7.8節）。完了報酬は1件60秒で、同じ回に二重付与しない。値は3.7.6節の定数を参照する |
| 日次指標・計測     | 取り組み72分・目標120分ならアリ度60%、キリギリス度40%。区間・チェックポイントの復元で同じ取り組みを二重集計しない。目標0・超過・丸め等はAQ11の確定後に追加する |
| 解除ポリシー       | 対象外アプリ、上限を超える提案、古い設定世代・要求・カードからの実行を拒否する。具体的な許可条件は採用したポリシーに合わせる                                   |
| 報酬・利用枠の台帳 | 同じ発生元の再試行で報酬を二重付与しない。二重引落し・二重返金を防ぎ、保存途中の復旧でも残高と利用枠の整合を保つ                                               |

### 4.2 実機・統合検証

OS権限・拡張・モデルの実動作は、ユニットテストとは別に以下の条件で確認する。

| ID               | 確認すること                                                                       | 記録する結果                                           |
| ---------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------ |
| V01 環境         | Xcode／SDK、OS、モデル対応端末、署名、capability、App Group                        | バージョン・ターゲット設定・成功したビルド手順         |
| V02 リマインダー | 許可、取得、0件、拒否、外部変更、確認済み完了保存                                  | 実データの再現手順と結果                               |
| V03 Shield       | 選択した実アプリだけへの制限、解除、選び直し                                       | 画面と対象外アプリへの影響                             |
| V04 導線         | Shield→本体、対象・起点の受け渡し、戻る                                            | 使用APIとOS条件、成功／代替手順                        |
| V05 モデル       | availability、日本語、構造化提案、生成取消し・失敗                                 | 端末、プロンプト版、応答、ポリシー検査結果             |
| V06 再制限       | 時間の意味、既使用分、背景動作、設定変更中の枠維持、枠固有の終了通知、復帰・再起動 | 本体が前面にない状態での結果                           |
| V07 統合         | 実タスク→対話／取り組み→検査→利用枠→再制限                                         | デモ動画、commit、実接続／模擬の区別                   |
| V08 Report       | H01の「今週のありとキリギリス」とH02の使用時間、独自データ読込み、操作・更新       | Report内の週次表示、設定導線、拒否・データなし時の結果 |
| V09 台帳・復旧   | 報酬重複、再押下、保存途中終了、二重引落し・返金                                   | 一意性と残高、再開結果                                 |

### 4.3 完了条件

- 実装対象に関係する未決事項を解消し、採用した仕様とDB・画面・共通処理の記述が一致している。
- 対象ロジックのユニットテストと、実装対象に必要なV01〜V09・C01〜C09の検証を行い、結果を記録している。
- デモ対象の実タスク→対話／取り組み→利用枠→再制限を通して確認し、バックグラウンドでの再制限や復帰も記録している。
- 実接続・モック・未検証の範囲を区別し、端末・OS・SDK・手順・結果・証拠をSTATUS.mdへ残している。

## 5. 未決事項・実装引き継ぎ

以下のAQ番号は本書内の未決事項であり、STATUS.mdのQ番号とは別である。製品上の判断は、AIが空欄を埋めて採用済みにせず、[UI_UX.mdの6・7節](UI_UX.md#6-両班で合わせる仕様)と決定ログへ採用内容を残す。

**AQ一覧の更新ルール（ユーザー指定）:** 一覧には未解決の問いだけを置く。決定・修正・スコープ除外で解決した部分は、その都度削除する。行の全項目が解決したら行ごと削除し、一部が残る場合は残った問いだけに書き直す。採用仕様は本文、判断の履歴はDECISIONS.mdへ残す。AQ番号は振り直さず、削除した行への参照も採用仕様の記載先へ置き換える。

| ID   | 実装前に決めること                                                                                                                         |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| AQ01 | 必須権限、部分的な拒否・モデル非対応時に使える画面、初回設定の完了条件                                                                     |
| AQ02 | 未完了ToDoとSNS上限の関係、タスク0件時、上限未到達時、上限の初期値・0分の扱い                                                              |
| AQ03 | 一時利用は経過時間か実利用時間か、起算点、1回・合計の上限、終了条件                                                                        |
| AQ05 | 説得1回の区切り、成功・拒否・中断・エラーの算入、日次上限、日付・タイムゾーンの切替                                                        |
| AQ06 | 3要素の評価基準の詳細、「タスクの必要性」の対象と加減方向、配点・初期表示・更新規則・表示段階、許可判断との関係                            |
| AQ07 | 「今日」に含める期限・期限切れ・完了・期限なし、並び順、対象リスト                                                                         |
| AQ08 | 取り組み報酬を付与する単位・タイミング・端数処理、ToDo完了時の追加時間、残高の失効、外部完了・取消し・繰返しへの付与                       |
| AQ11 | 指標の目標超過・目標0／未設定・丸め・日付境界・キャラ段階、週次の集計期間・目標時間・「アリの日」の判定・途中日／欠測時の表示、SNS集計対象 |

技術上の採用方式・保存形式・UI操作の型は本書へ、文言・プロンプトはUI_UX.mdへ、採用判断はDECISIONS.mdへ、実機結果はSTATUS.mdへ記録する。現時点ではアプリの実装・実機検証は未実施。

<a id="39-技術資料の参照"></a>

## 6. 技術資料の参照

前版で確認した資料A01〜A12を各該当箇所に保持した。今回の再確認では、DeviceActivityReport／ReportScene／makeConfigurationとWWDC22のレポート説明から、**Report内での集計・SwiftUI表示が可能**であることと、利用情報を外へ持ち出す制約を区別した。

- [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)
- [DeviceActivityReportScene](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene)
- [makeConfiguration(representing:)](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportscene/makeconfiguration%28representing%3A%29)
- [WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)
- その他の出典状態・ユーザー提供の原文は[sources/README.md](sources/README.md)を参照する。

### 6.1 Screen Time APIの再調査（2026-10-17）

AIのサブエージェントが、Apple公式リファレンス、WWDC21・22、Developer Forumsの個別スレッドを読んで整理した。実機では確認していない。フォーラムの報告は非公式情報であり、Appleが認めた不具合とは限らない。

公式ドキュメント:

- [DeviceActivityFilter.SegmentInterval.daily(during:)](<https://developer.apple.com/documentation/deviceactivity/deviceactivityfilter/segmentinterval-swift.enum/daily(during:)>)、[hourly(during:)](<https://developer.apple.com/documentation/deviceactivity/deviceactivityfilter/segmentinterval-swift.enum/hourly(during:)>)、[DeviceActivityData.activitySegments](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitysegments)
- [DeviceActivitySchedule init](<https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/init(intervalstart:intervalend:repeats:warningtime:)>)、[nextInterval](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval)、[warningTime](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/warningtime)、[intervalTooLong](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltoolong)、[excessiveActivities](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/excessiveactivities)、[startMonitoring](<https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)>)
- [DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent)、[threshold](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/threshold)、[includesPastActivity](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/includespastactivity)
- [ShieldSettings.applications](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property)、[ManagedSettingsStore](https://developer.apple.com/documentation/managedsettings/managedsettingsstore)、[isActive](https://developer.apple.com/documentation/managedsettings/managedsettingsstore/isactive)
- [openParentalControlsApp](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/openparentalcontrolsapp)、[secondaryButtonSubmenuItems](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/secondarybuttonsubmenuitems)
- [activityData(filteredBy:using:)](<https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata(filteredby:using:)>)（iOS 26.4。EU所在のアカウント等の条件があり、日本向けには使わない）

非公式（Developer Forums）:

- Report拡張のサンドボックス: [thread 818174](https://developer.apple.com/forums/thread/818174)、[818297](https://developer.apple.com/forums/thread/818297)
- しきい値の即時発火・未発火・遅延: [728277](https://developer.apple.com/forums/thread/728277)、[819997](https://developer.apple.com/forums/thread/819997)、[838510](https://developer.apple.com/forums/thread/838510)、[786854](https://developer.apple.com/forums/thread/786854)、[696072](https://developer.apple.com/forums/thread/696072)、[741133](https://developer.apple.com/forums/thread/741133)
- 15分未満の区切りの回避策: [747557](https://developer.apple.com/forums/thread/747557)
- Shieldから本体を開く方法: [719905](https://developer.apple.com/forums/thread/719905)、[820790](https://developer.apple.com/forums/thread/820790)
