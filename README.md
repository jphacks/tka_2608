# サンプル（プロダクト名）

[![IMAGE ALT TEXT HERE](https://jphacks.com/wp-content/uploads/2026/07/IMG_5316.png)](https://www.youtube.com/watch?v=piaNsc6ilBI)

## 製品概要
### 背景(製品開発のきっかけ、課題等）
### 製品説明（具体的な製品の説明）
### 特長
#### 1. 特長1
#### 2. 特長2
#### 3. 特長3

### 解決出来ること
### 今後の展望
### 注力したこと（こだわり等）
* 
* 

## 開発技術

### 活用した技術

#### API・データ

- 外部API・サーバーなし（データは端末内で完結）
- アプリのデータ：JSONファイルに保存
- やること：リマインダーと連携（EventKit）
- AIとの会話：端末内AI（Apple Foundation Models）。使えない端末ではキーワードによる簡易応答に切り替え
- 本体と拡張機能の間：App Group で制限の状態を共有

#### フレームワーク・ライブラリ・モジュール

- SwiftUI / Observation
- Foundation Models（端末内AI）
- Screen Time API（FamilyControls / ManagedSettings / DeviceActivity）
- EventKit（リマインダー連携）
- Swift Charts（利用時間のグラフ）
- Swift Testing（テスト）

#### デバイス

- iPhone（iOS 26以上）

### 独自技術

#### ハッカソンで開発した独自機能・技術

- AIとの相談の設計：端末内AIには、返答・納得度・次の行動を決まった型で出させる。やることの名前や会話はデータとして扱い、会話から判定を書き換えられるのを防ぐ。AIが「許可」を出しても、アプリのルールで再検査してから制限を解く
- アプリを閉じていても効く制限：上限への到達や一時利用の終了をスクリーンタイムの拡張機能で検知し、アプリが裏にいても制限をかけ直す
- 使用時間の扱い：SNSの使用時間はスクリーンタイムの拡張機能の中だけで扱い、アプリ本体には渡さない
- SNS時間の台帳：獲得と利用を取引として記録し、同じ報酬の二重付与を防ぐ
- 端末内AIがなくても動く相談：端末内AIを使えないiPhoneでは、キーワードから納得度を出す簡易応答で相談を続ける

#### 特に力を入れた部分

- UI・UX（[Figma](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=0-1) / [UI・UX設計](docs/UI_UX.md)）
  - モチーフ：寓話「アリとキリギリス」。SNSを使おうとするキリギリス（ユーザー）を、アリ（AI）がやることへ向かうよう促す。キリギリスが実際に手を動かすようになるまでの話
  - 操作性：制限画面のボタンは「やることを先に片付ける」「AIに相談する」の2つだけ。相談のあとは、画面を移らずにそのままやることを選べる
  - デザイン：アリとキリギリスの表情は、ユーザーの行動に合わせて変わる（アリは納得度に応じて5段階、キリギリスは取り組んだ時間に応じて4段階）
- [UnlockPolicy.swift](todomeru_ios/todomeru_ios/Core/UnlockPolicy.swift)（AIの判定の再検査）
- [FoundationModelsPersuasionAI.swift](todomeru_ios/todomeru_ios/Features/Persuasion/FoundationModelsPersuasionAI.swift)（端末内AIとの対話）
- [TodomeruMonitor.swift](todomeru_ios/TodomeruMonitor/TodomeruMonitor.swift)（制限のかけ直し）
- [AppStore.swift](todomeru_ios/todomeru_ios/Core/AppStore.swift)（SNS時間の台帳・データ保存）
