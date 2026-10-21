import SwiftUI
import SwiftData

/// あとで：預かり中のもの。水槽と、返す時刻ごとの並び。
struct LaterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]

    private var waiting: [Item] { items.filter { $0.state == .waiting } }
    /// 今にあと何件入れられるか
    private var room: Int { max(0, SettingsStore.nowCapacity - items.filter { $0.state == .returned }.count) }
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
                        if waiting.isEmpty {
                            Text("「あとでに回す」で入れたものが、今に戻るまでここで待ちます。")
                                .atype(.small, color: Theme.quiet)
                                .onPaper()
                        }
                        if !ready.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("戻ってきた")
                                Text(room > 0 ? "おすすめ順。今に入れるものを選ぶ（あと\(room)件）" : "おすすめ順。今がいっぱいなので、今のものが片付いたら入れられます")
                                    .atype(.label).padding(.bottom, 6)
                                ForEach(Array(ready.enumerated()), id: \.element.id) { index, item in
                                    SuggestionRow(item: item, top: index == 0, room: room)
                                }
                            }
                            .onPaper(padding: 14)
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                if section.id == "break" {
                                    breakHeader
                                } else {
                                    SectionLabel("\(section.title) に戻ってくる").padding(.bottom, 6)
                                }
                                ForEach(section.rows.sorted { $0.createdAt < $1.createdAt }) { LaterRow(item: $0, room: room) }
                            }
                            .onPaper(padding: 14)
                        }
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .bottom) { CaptureButton() }
                // タブバーの下の白いぼかしを消して、方眼を最後まで見せる
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .paperStatusBar()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("あとで").atype(.display)
            Text("\(waiting.count)").atype(.label)
            Spacer()
        }
    }

    /// 「終わったら」の見出し。区切りがついたときに押すボタンを、その対象のすぐ横に置く。
    private var breakHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                Text("終わったら戻ってくる").font(Theme.sans(12, weight: .black)).foregroundStyle(Theme.ink)
                Spacer()
                Button("区切りがついた") {
                    withAnimation { ReturnService.returnAtBreak(in: context) }
                }
                .buttonStyle(.cube(.secondary))
            }
            Rectangle().fill(Theme.ink).frame(height: Theme.stroke)
            Text("押すと、ここにあるものが「戻ってきた」に移ります。集中を終えたときも同じ。")
                .atype(.label).padding(.bottom, 6)
        }
    }
}

private struct LaterRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    /// 今にあと何件入れられるか
    let room: Int
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
                    HStack(spacing: 10) {
                        Button("今に入れる") { receiveNow() }
                            .buttonStyle(.cube(.primary, size: .small))
                            .disabled(room == 0)
                        if room == 0 { Text("今がいっぱい").atype(.label) }
                    }
                    Text("戻る時を変える").atype(.label)
                    CubeSegmented(options: ReturnTiming.allCases, label: { $0.label() },
                                  selection: Binding(get: { item.timing }, set: { change(to: $0) }))
                }
                .padding(.leading, 34)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    /// 本人が選んで今に入れる（戻る時が来ていなくても入れられる）
    private func receiveNow() {
        withAnimation { _ = ReturnService.accept(item, in: context) }
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

/// 戻ってきたものの行。おすすめ順に並び、今に入れるかは本人が選ぶ。
private struct SuggestionRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    /// いちばんのおすすめ
    let top: Bool
    let room: Int

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isRated {
                    DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 10)
                } else {
                    DotMark(kind: .concern, size: 10)
                }
            }
            .padding(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).atype(.body)
                if top { Text("おすすめ").atype(.label, color: Theme.accent) }
            }
            Spacer(minLength: 8)
            Button("今に入れる") {
                withAnimation { _ = ReturnService.accept(item, in: context) }
            }
            .buttonStyle(.cube(top ? .accent : .secondary))
            .disabled(room == 0)
        }
        .padding(.vertical, 4)
    }
}
