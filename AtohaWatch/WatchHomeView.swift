import SwiftUI

private func hhmm(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
}

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var text = ""
    @State private var timing: ReturnTiming = .tonight
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
                if let next = store.nextReturn, next > .now {
                    DotMatrixText(hhmm(next), dotSize: 2.5, spacing: 1, color: Theme.quiet)
                } else {
                    DotMatrixText("--:--", dotSize: 2.5, spacing: 1, color: Theme.faint)
                }

                // タップすると、すぐにシステムの入力（音声・手書き）が開く。
                TextField("あとで", text: $text, prompt: Text("あとで").foregroundStyle(Theme.paper))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.ink, in: .rect(cornerRadius: 24))
                    .onSubmit(submit)
                    .padding(.top, 4)

                HStack(spacing: 4) {
                    ForEach(ReturnTiming.allCases) { option in
                        timingChip(option)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func timingChip(_ option: ReturnTiming) -> some View {
        let selected = option == timing
        return Button { timing = option } label: {
            Text(option.label)
                .font(Theme.mono(11))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(selected ? Theme.paper : Theme.ink)
                .background(selected ? Theme.ink : .clear, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.faint, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        VStack(spacing: 8) {
            if let date = timing.returnDate() {
                DotMatrixText(hhmm(date), dotSize: 5, spacing: 1.5, color: Theme.accent)
            } else {
                DotMatrixText("--:--", dotSize: 5, spacing: 1.5, color: Theme.quiet)
                Text(timing.label).font(Theme.mono(12)).foregroundStyle(Theme.quiet)
            }
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
