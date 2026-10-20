import SwiftUI
import SwiftData

/// 集中の画面。選んだ1つだけを出す。
struct FocusView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var session = FocusSession.shared
    @Query private var items: [Item]

    private var item: Item? { items.first { $0.id == session.itemID } }
    private let step = 5 // 目安の1ドット = 5分

    var body: some View {
        @Bindable var router = router
        ZStack {
            PaperBackground()
            DotGridBackground().ignoresSafeArea().opacity(0.5)

            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Text(item?.text ?? "")
                    .atype(.title)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 32)
                clock
                if session.endedAt == nil { planned }
                Spacer(minLength: 0)
                if session.endedAt == nil { controls } else { choices }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .fullScreenCover(isPresented: $router.showCapture) { CaptureView() }
        .onAppear {
            if item == nil && !items.isEmpty { session.clear() } else { session.scheduleNotification() }
        }
    }

    // MARK: 経過

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = session.elapsed(at: timeline.date)
            VStack(spacing: 16) {
                DotMatrixText(Self.format(elapsed), size: elapsed >= 3600 ? .medium : .large,
                              color: session.endedAt == nil ? Theme.ink : Theme.quiet)
                if let m = session.plannedMinutes {
                    plannedDots(minutes: m, elapsed: elapsed)
                }
                if let item, item.focusSeconds > 0 {
                    HStack(spacing: 8) {
                        SectionLabel("合計", ruled: false)
                        TimeText(seconds: item.focusSeconds)
                    }
                }
            }
            .onChange(of: reached(elapsed)) { _, now in
                if now && session.endedAt == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
    }

    private func reached(_ elapsed: TimeInterval) -> Bool {
        guard let m = session.plannedMinutes else { return false }
        return elapsed >= Double(m) * 60
    }

    private func plannedDots(minutes: Int, elapsed: TimeInterval) -> some View {
        let total = minutes / step
        let filled = min(total, Int(elapsed / 60) / step)
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                SquareMark(i < filled ? .accent() : .ink(0.15), size: 9)
            }
        }
        .accessibilityHidden(true)
    }

    private var planned: some View {
        CubeSegmented(options: [25, 50, nil] as [Int?], label: { $0.map(String.init) ?? "—" },
                      selection: Binding(get: { session.plannedMinutes }, set: { session.setPlanned($0) }))
    }

    // MARK: 操作

    private var controls: some View {
        HStack(spacing: 12) {
            Button { router.showCapture = true } label: { Label("あとで", systemImage: "plus") }
                .accessibilityLabel("あとでに回す")
                .buttonStyle(.cube(.secondary, size: .large))
            Button(action: finish) { Text("終わる") }
                .buttonStyle(.cube(.primary, size: .large, fill: true))
        }
    }

    private var choices: some View {
        HStack(spacing: 12) {
            Button { conclude(done: false) } label: { Text("まだ") }
                .buttonStyle(.cube(.secondary, size: .large, fill: true))
            Button { conclude(done: true) } label: { Text("できた") }
                .buttonStyle(.cube(.primary, size: .large, fill: true))
        }
    }

    private func finish() {
        guard let seconds = session.stop() else { return }
        item?.focusSeconds += seconds
        withAnimation { ReturnService.returnAtBreak(in: context) }
        try? context.save()
    }

    private func conclude(done: Bool) {
        if done, let item {
            item.state = .done
            item.resolvedAt = .now
        }
        try? context.save()
        ReturnService.refill(in: context)
        session.clear()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
