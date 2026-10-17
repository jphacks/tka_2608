import FamilyControls
import SwiftUI

/// SNSの名前。標準機能で選んだアプリはiOSが描く名前（Label(token)）、デモの候補は登録した名前を出す。
/// アプリからは名前を文字列として読めないので、文と組み合わせるときは SNSPhrase を使う。
struct SNSNameLabel: View {
    var sns: SNSApp

    var body: some View {
        if let token = sns.applicationToken {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(sns.name)
        }
    }
}

/// 「Xを開く」「Xの1日の上限」のように、SNS名の前後に文をつなげて表示する
struct SNSPhrase: View {
    var prefix: String = ""
    var sns: SNSApp
    var suffix: String = ""

    var body: some View {
        HStack(spacing: 0) {
            if !prefix.isEmpty { Text(prefix) }
            SNSNameLabel(sns: sns)
            if !suffix.isEmpty { Text(suffix) }
        }
        .lineLimit(1)
    }
}
