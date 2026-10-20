import SwiftUI
import SwiftData

/// あとで：預かり中のもの。水槽と、返す時刻ごとの並び。
struct LaterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]

    private var waiting: [Item] { items.filter { $0.state == .waiting } }
    /// 返す時が来ているが、今がいっぱいで待っているもの（優先順位の高い順）
    private var ready: [Item] {
        let now = Date.now
        return waiting.filter { $0.isReady(now: now) }.sorted { $0.priority(now: now) > $1.priority(now: now) }
    }
    private var notReady: [Item] {
        let now = Date.now
        return waiting.filter { !$0.isReady(now: now) }
    }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let date: Date
        let rows: [Item]
    }

    /// 「終わったら」を先頭に、返す時刻の早い順
    private var sections: [Section] {
        var result: [Section] = []
        let atBreak = notReady.filter { $0.timing == .atBreak || $0.returnAt == nil }
        if !atBreak.isEmpty {
            result.append(Section(id: "break", title: ReturnTiming.atBreak.label, date: .distantPast, rows: atBreak))
        }
        let timed = notReady.filter { $0.timing != .atBreak && $0.returnAt != nil }
        let grouped = Dictionary(grouping: timed) { Self.title(for: $0) }
        let later = grouped.map { title, rows in
            Section(id: title, title: title, date: rows.compactMap(\.returnAt).min() ?? .distantFuture, rows: rows)
        }
        result += later.sorted { $0.date < $1.date }
        return result
    }

    private static func title(for item: Item) -> String {
        guard let at = item.returnAt else { return ReturnTiming.atBreak.label }
        let hm = at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        // 選んだ返し方ではなく、実際に返ってくる日で見出しを付ける（21時過ぎの「今夜」は明日の21時になる）
        let cal = Calendar.current
        let hour = cal.component(.hour, from: at)
        if cal.isDateInToday(at) { return hour >= 17 ? "今夜 \(hm)" : "今日 \(hm)" }
        if cal.isDateInTomorrow(at) { return hour < 12 ? "明日の朝 \(hm)" : "明日 \(hm)" }
        return at.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) + " \(hm)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        TankView(cubes: waiting.map { TankCube(id: $0.id, accent: $0.isRated && $0.effectiveWant >= 0.5) })
                        if !ready.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("空いたら").padding(.bottom, 6)
                                ForEach(ready) { LaterRow(item: $0) }
                            }
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel(section.title).padding(.bottom, 6)
                                ForEach(section.rows.sorted { $0.createdAt < $1.createdAt }) { LaterRow(item: $0) }
                            }
                        }
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .bottom) { CaptureButton() }
            }
            .paperStatusBar()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            Text("あとで").atype(.display)
            Spacer()
            Button("受け取る") {
                withAnimation { ReturnService.returnAtBreak(in: context) }
            }
            .buttonStyle(.cube(.secondary))
            .disabled(waiting.isEmpty)
        }
    }
}

private struct LaterRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if item.isRated {
                        DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 10)
                    } else {
                        DotMark(kind: .concern, size: 10)
                    }
                }
                .padding(6)
                Text(item.text).atype(.body)
                Spacer(minLength: 0)
                TimeText(seconds: item.focusSeconds)
                    .frame(width: 60, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            .accessibilityAddTraits(.isButton)

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    Button("今受け取る") { receiveNow() }
                        .buttonStyle(.cube(.primary, size: .small))
                    CubeSegmented(options: ReturnTiming.allCases, label: { $0.label() },
                                  selection: Binding(get: { item.timing }, set: { change(to: $0) }))
                }
                .padding(.leading, 34)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    private func receiveNow() {
        withAnimation {
            let old = item.returnAt
            item.returnAt = .now
            try? context.save()
            if let old { NotificationScheduler.reschedule(for: old, in: context) }
            ReturnService.refill(in: context)
        }
    }

    private func change(to timing: ReturnTiming) {
        guard timing != item.timing else { return }
        withAnimation {
            let old = item.returnAt
            item.timing = timing
            try? context.save()
            if let old { NotificationScheduler.reschedule(for: old, in: context) }
            if let new = item.returnAt { NotificationScheduler.reschedule(for: new, in: context) }
            LiveActivityService.sync(in: context)
        }
    }
}
