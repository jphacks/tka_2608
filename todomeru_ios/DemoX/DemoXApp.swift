import SwiftUI

/// デモ用の「X」。本物のXではなく、Screen Timeの制限（Shield）の対象として端末に入れるだけのアプリ。
@main
struct DemoXApp: App {
    var body: some Scene {
        WindowGroup {
            TimelineView()
                .preferredColorScheme(.light)
        }
    }
}

private enum DemoXStyle {
    static let accent = Color(red: 0.11, green: 0.61, blue: 0.94)
    static let secondary = Color.gray
    static let avatarColors: [Color] = [.orange, .purple, .teal, .pink, .indigo, .green]
}

private struct Post: Identifiable {
    let id: Int
    let name: String
    let handle: String
    let text: String
    let minutesAgo: Int
}

private let samplePosts: [Post] = [
    Post(id: 0, name: "ゼミ連絡bot", handle: "seminar_info", text: "【連絡】来週のゼミは教室が変更になります。詳細はDMで確認してください。", minutesAgo: 3),
    Post(id: 1, name: "ねこ写真", handle: "cats_daily", text: "今日のねこ。日向ぼっこ中 ☀️", minutesAgo: 12),
    Post(id: 2, name: "ニュース速報", handle: "news_flash", text: "週末は全国的に晴れの予報。", minutesAgo: 25),
    Post(id: 3, name: "友だち", handle: "friend_a", text: "課題おわった人いる？", minutesAgo: 40),
    Post(id: 4, name: "ゲーム情報", handle: "game_news", text: "新イベント開催中！期間限定アイテムを手に入れよう。", minutesAgo: 58),
    Post(id: 5, name: "料理レシピ", handle: "recipe_jp", text: "5分でできる簡単パスタ 🍝", minutesAgo: 75),
]

private struct TimelineView: View {
    var body: some View {
        NavigationStack {
            List(samplePosts) { post in
                PostRow(post: post)
            }
            .listStyle(.plain)
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { DemoNotice() }
        }
    }
}

private struct DemoNotice: View {
    var body: some View {
        Text("デモ用アプリです。本物のXではありません。")
            .font(.caption)
            .foregroundStyle(DemoXStyle.secondary)
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(.bar)
    }
}

private struct PostRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(DemoXStyle.avatarColors[post.id % DemoXStyle.avatarColors.count])
                .frame(width: 40, height: 40)
                .overlay(Text(String(post.name.prefix(1))).foregroundStyle(.white).bold())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(post.name).bold()
                    Text("@\(post.handle) · \(post.minutesAgo)分").foregroundStyle(DemoXStyle.secondary)
                }
                .font(.subheadline)
                Text(post.text)
                HStack(spacing: 40) {
                    Image(systemName: "bubble.right")
                    Image(systemName: "arrow.2.squarepath")
                    Image(systemName: "heart")
                }
                .font(.footnote)
                .foregroundStyle(DemoXStyle.secondary)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
