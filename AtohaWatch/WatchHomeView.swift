import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var text = ""
    /// 時間は決めない（iPhone の「あとで」から選んで今に入れる）
    private let timing: ReturnTiming = .atBreak
    @State private var confirmed: ReturnTiming?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let confirmed {
                confirmation(for: confirmed).transition(.opacity)
            } else {
                main
            }
        }
    }

    private var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                DotMatrixText("\(store.count)", dotSize: 6, spacing: 2,
                              color: store.count > 0 ? Theme.accent : Theme.quiet)

                if store.isFull {
                    // 水槽がいっぱいのときは回せない（iPhone で減らすと、また回せる）
                    VStack(spacing: 4) {
                        Text("水槽がいっぱい").font(Theme.mono(15, weight: .bold)).foregroundStyle(Theme.accent)
                        Text("iPhone の「あとで」で減らすと回せます").font(Theme.mono(12)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                } else {
                // タップすると、すぐにシステムの入力（音声・手書き）が開く。
                TextField("あとでに回す", text: $text, prompt: Text("あとでに回す").foregroundStyle(Theme.paper))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.ink, in: .rect(cornerRadius: 24))
                    .onSubmit(submit)
                    .padding(.top, 4)
                }

            }
            .padding(.horizontal, 4)
        }
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        VStack(spacing: 8) {
            Rectangle().fill(Theme.accent).frame(width: 18, height: 18)
            Text("水槽に放しました").font(Theme.mono(12)).foregroundStyle(Theme.ink)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        guard !trimmed.isEmpty, confirmed == nil else { return }
        let chosen = timing
        store.capture(text: trimmed, timing: chosen)
        WKInterfaceDevice.current().play(.success)
        withAnimation(.easeOut(duration: 0.2)) { confirmed = chosen }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.2)) { confirmed = nil }
        }
    }
}
