import SwiftUI
import SwiftData

/// 今の画面。預かり中の数と、返ってきたものだけを出す。
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showSettings = false
    @AppStorage(SettingsKey.nowCapacityKey) private var capacitySetting = 5

    private var capacity: Int { [3, 5, 7].contains(capacitySetting) ? capacitySetting : 5 }
    private var returned: [Item] { items.filter { $0.state == .returned } }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        if returned.isEmpty {
                            // 何もないときに、次に何をすればいいかだけを見せる
                            VStack(alignment: .leading, spacing: 6) {
                                Text("今やることはありません").atype(.body)
                                Text("気になったら「あとでに回す」。決めた時刻に、ここへ戻ってきます。")
                                    .atype(.small, color: Theme.quiet)
                            }
                        } else {
                            ReturnedList(items: returned)
                        }
                    }
                    .padding(24)
                }
                // ボタンの分だけスクロールの下端を空ける（最後の行がボタンに隠れないように）
                .safeAreaInset(edge: .bottom) { captureButton }
                // タブバーの下の白いぼかしを消して、方眼を最後まで見せる
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .paperStatusBar()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            // 返ってきたものがあるときに、まとめ処理（PCC が使えれば PCC）
            .task(id: returned.count) {
                guard !returned.isEmpty else { return }
                await BatchOrganizer.organizeIfNeeded(in: context)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("atoha").atype(.display)
            HStack(spacing: 3) {
                ForEach(0..<capacity, id: \.self) { index in
                    Rectangle()
                        .fill(index < returned.count ? Theme.accent : Theme.paper)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.leading, 8)
            .accessibilityHidden(true)
            Text("\(returned.count)/\(capacity)").atype(.label)
                .accessibilityLabel("今 \(returned.count) / \(capacity)")
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.cube(.quiet))
            .accessibilityLabel("設定")
        }
    }

    private var captureButton: some View { CaptureButton() }
}

/// 下に置く「あとで」ボタン（書き出し画面を開く）。
struct CaptureButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showCapture = true
        } label: {
            Label("あとでに回す", systemImage: "plus").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.cube(.primary, size: .large, fill: true))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // ボタンの下からタブバーの下まで方眼で埋める（スクロールした中身が透けないように）
        .background(PaperBackground(fullScreen: false).ignoresSafeArea(edges: .bottom))
    }
}

extension View {
    /// スクロールした中身がステータスバーの文字と重ならないよう、上端を紙の色で覆う
    func paperStatusBar() -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                PaperBackground(fullScreen: false)
                    .frame(height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
    }
}

/// 返ってきたもの。先頭に「次」、やりたい・やらなきゃの2つの値で4つに分けて並べる。
struct ReturnedList: View {
    let items: [Item]

    private static let threshold = 0.5

    /// 「次」に出す候補（優先順位の高い順、最大5つ）
    private var candidates: [Item] {
        Array(items.sorted { $0.priority() > $1.priority() }.prefix(5))
    }

    private func group(_ title: String, want: Bool, must: Bool) -> (String, [Item]) {
        let rows = items
            .filter { ($0.effectiveWant >= Self.threshold) == want && ($0.effectiveMust >= Self.threshold) == must }
            .sorted { $0.priority() > $1.priority() }
        return (title, rows)
    }

    private var sections: [(String, [Item])] {
        [group("やりたい・やらなきゃ", want: true, must: true),
         group("やらなきゃ", want: false, must: true),
         group("やりたい", want: true, must: false),
         group("そのほか", want: false, must: false)]
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !candidates.isEmpty { NextCard(items: candidates) }
            ForEach(sections, id: \.0) { title, rows in
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(title).padding(.bottom, 6)
                    ForEach(rows) { ReturnedRow(item: $0) }
                }
            }
        }
    }
}

/// 「次」：優先順位の高い順に、横にめくって選ぶ。
private struct NextCard: View {
    let items: [Item]
    @State private var page = 0

    var body: some View {
        Card(padding: 16, style: .accent) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("次", ruled: false)
                TabView(selection: $page) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NextPage(item: item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 64)
                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(items.indices, id: \.self) { index in
                            Rectangle()
                                .fill(Theme.onAccent.opacity(index == page ? 1 : 0.3))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if page >= ids.count { page = max(0, ids.count - 1) }
        }
    }
}

private struct NextPage: View {
    let item: Item

    var body: some View {
        // 左に中身（文字と、その下に時間・期限）、右に「やる」。余白を作らない
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text).atype(.title).lineLimit(2)
                HStack(spacing: 10) {
                    TimeText(seconds: item.focusSeconds)
                    if let deadline = item.deadline { DeadlineLabel(date: deadline) }
                }
            }
            Spacer(minLength: 0)
            Button("やる") { FocusSession.shared.start(item) }
                .buttonStyle(.cube(.secondary))
                .environment(\.atypeInk, nil)
        }
        .padding(.horizontal, 2)
    }
}

private struct ReturnedRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    @State private var open = false
    @State private var choosing = false
    @State private var confirmed: ReturnTiming?

    private var mustful: Bool { item.effectiveMust >= 0.5 }

    var body: some View {
        Group {
            if let confirmed {
                confirmation(for: confirmed)
            } else {
                rowBody
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        VStack(spacing: 8) {
            if let date = timing.returnDate() {
                DotMatrixText(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()), size: .medium)
            } else {
                DotMatrixText("--:--", size: .medium, color: Theme.quiet)
            }
            Text(timing.returnMessage()).atype(.small, color: Theme.quiet)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .transition(.opacity)
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if mustful {
                    // 小さなアイコンなので立方体ボタンにはせず、位置を他の行とそろえる
                    Button { resolve(.done) } label: { mark.padding(6).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("できた")
                } else {
                    mark.padding(6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text).atype(.body)
                    if let theme = item.theme {
                        Text(theme)
                            .atype(.label, color: item.isCloseToAxis ? Theme.accent : Theme.quiet)
                    }
                }
                Spacer(minLength: 0)
                // 右側は幅を決めた列にして、時間・期限・未評価の印を行をまたいで縦にそろえる
                TimeText(seconds: item.focusSeconds)
                    .frame(width: 60, alignment: .trailing)
                Group {
                    if let deadline = item.deadline { DeadlineLabel(date: deadline) } else { Color.clear }
                }
                .frame(width: 40, height: 12, alignment: .trailing)
                Group {
                    if !item.isRated {
                        SquareMark(.outline(alpha: 0.6, dashed: true), size: 10)
                            .accessibilityElement()
                            .accessibilityLabel("未評価")
                    } else { Color.clear }
                }
                .frame(width: 12, height: 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            .accessibilityAddTraits(.isButton)

            if open {
                WantMustPad(item: item)
                    .padding(.leading, 34)
                HStack(spacing: 8) {
                    action("やる") { FocusSession.shared.start(item) }
                    if mustful { action("できた") { resolve(.done) } }
                    action("あとでに回す") { withAnimation(.easeOut(duration: 0.15)) { choosing.toggle() } }
                    action("やめる", emphasized: item.isBothLow) { resolve(.released) }
                }
                .padding(.leading, 34)
                .transition(.opacity)
                if choosing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("いつ戻す？").atype(.label)
                        HStack(spacing: 8) {
                            ForEach(ReturnTiming.allCases) { timing in
                                Button(timing.label()) { postpone(timing) }
                                    .buttonStyle(.cube(timing == SettingsStore.defaultTiming ? .primary : .secondary, size: .small))
                            }
                        }
                    }
                    .padding(.leading, 34)
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private var mark: some View {
        if item.isRated {
            DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 10)
        } else {
            DotMark(kind: .concern, highlighted: item.isCloseToAxis, size: 10)
        }
    }

    private func action(_ title: String, emphasized: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(.cube(emphasized ? .primary : .secondary))
    }

    /// もう一度あとに回す。返す時刻を少し見せてから、預かり中へ戻す。
    private func postpone(_ timing: ReturnTiming) {
        guard confirmed == nil else { return }
        withAnimation(.easeOut(duration: 0.15)) { confirmed = timing }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation {
                item.state = .waiting
                item.timing = timing
                try? context.save()
                if let date = item.returnAt { NotificationScheduler.reschedule(for: date, in: context) }
                ReturnService.refill(in: context)
            }
        }
    }

    private func resolve(_ state: ItemState) {
        withAnimation {
            item.state = state
            item.resolvedAt = .now
            try? context.save()
            ReturnService.refill(in: context)
        }
    }
}

private struct DeadlineLabel: View {
    let date: Date

    var body: some View {
        Text(Calendar.current.isDateInToday(date) ? "今日"
             : Calendar.current.isDateInTomorrow(date) ? "明日"
             : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
            .atype(.label)
    }
}
