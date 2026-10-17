import SwiftUI

/// デモ用の疑似SNS画面。表示中は1秒ごとに使用時間を進め、
/// 一時利用枠の終了・上限到達ですぐ利用終了画面／制限画面へ切り替える。
/// 注意: 本番ではSNSを使っている間アプリ本体は背景にあり、この計測は動かない。
/// 再制限はDeviceActivity Monitor拡張で行う必要がある（未実装）。
struct DemoSNSView: View {
    var snsID: String

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: DemoSNSModel

    init(snsID: String) {
        self.snsID = snsID
        _model = State(initialValue: DemoSNSModel(snsID: snsID))
    }

    var body: some View {
        if let sns = store.sns(snsID), sns.tokenData != nil {
            PickedAppNotice(sns: sns, onClose: { router.pop() })
        } else {
            demoScreen
        }
    }

    /// デモの候補だけで使う疑似SNS画面
    private var demoScreen: some View {
        VStack(spacing: 0) {
            DemoSNSHeader(sns: store.sns(snsID), onClose: { router.pop() })
            DemoSNSStatusBar(snsID: snsID, speed: $model.speed)
            Divider()
            DemoTimeline(tint: store.sns(snsID)?.tint ?? Theme.brown)
        }
        .background(Theme.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await runMeter() }
    }

    /// 1秒ごとに利用を進める。画面を離れるとタスクが取り消されて止まる
    private func runMeter() async {
        if let r = model.initialRedirect(store: store) { router.replaceTop(with: r); return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, scenePhase == .active else { continue }
            if let next = model.tick(store: store) {
                router.replaceTop(with: next)
                return
            }
        }
    }
}

// MARK: - 部品

private struct DemoSNSHeader: View {
    var sns: SNSApp?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("閉じる")
                if let sns { SNSIcon(sns: sns, size: 28) }
                Group {
                    if let sns { SNSNameLabel(sns: sns) } else { Text("SNS") }
                }
                .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            DemoBadge(text: "デモ：実際のSNSではありません")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// 標準機能で選んだアプリで開かれたとき。疑似画面は出さず、本物のアプリをホーム画面から開くよう案内する
private struct PickedAppNotice: View {
    var sns: SNSApp
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            SNSIcon(sns: sns, size: 56)
            SNSPhrase(sns: sns, suffix: "はホーム画面から開いてください")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("このアプリの制限はiOSのスクリーンタイムが行います。使用時間はデモの値で、使用時間画面の「上限まで進める」で上限に達すると、開いたときにiOSの制限画面が表示されます。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("閉じる", action: onClose)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Theme.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct DemoSNSStatusBar: View {
    var snsID: String
    @Binding var speed: DemoSNSModel.Speed
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("使用時間 \(TimeFormat.hm(store.usageToday(snsID))) / 上限 \(TimeFormat.hm(store.effectiveLimit(snsID)))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let g = store.activeGrant(snsID), store.isOverLimit(snsID) {
                    Text("残り \(TimeFormat.clock(g.remainingSeconds))")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.brown)
                }
            }
            HStack {
                Text("デモの倍速")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Picker("デモの倍速", selection: $speed) {
                    ForEach(DemoSNSModel.Speed.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
    }
}

private struct DemoTimeline: View {
    var tint: Color

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(DemoPost.samples) { post in
                    DemoPostRow(post: post, tint: tint)
                    Divider()
                }
            }
        }
    }
}

private struct DemoPostRow: View {
    var post: DemoPost
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay(Text(String(post.author.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(post.author).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("@\(post.handle)・\(post.minutesAgo)分").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Text(post.text).font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 18) {
                    Label("\(post.likes)", systemImage: "heart")
                    Image(systemName: "bubble.right")
                    Image(systemName: "arrow.2.squarepath")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private extension SNSApp {
    /// SNSごとの色（データとして持つ16進値から作る）
    var tint: Color { Color(hex: tintHex) }
}
