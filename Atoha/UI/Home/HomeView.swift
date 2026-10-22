import SwiftUI
import SwiftData

/// 今の画面。お椀（今の上限）と、今にあるもの（すくった金魚）だけを出す。
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showSettings = DebugLaunch.openSettings
    @AppStorage(SettingsKey.nowCapacityKey) private var capacitySetting = 3

    private var capacity: Int { [3, 5, 7].contains(capacitySetting) ? capacitySetting : 3 }
    private var returned: [Item] { items.filter { $0.state == .returned } }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            ScreenTitle(title: "atoha")
                            Spacer(minLength: 0)
                            settingsButton
                        }
                        .padding(.trailing, -12)
                        VStack(alignment: .leading, spacing: 28) {
                            BowlLine(filled: returned.count, capacity: capacity)
                            if returned.isEmpty {
                                // 何もないときに、次に何をすればいいかだけを見せる
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("お椀はからっぽです").atype(.body)
                                    Text("気になることは「あとでに回す」で水槽へ。「あとで」から選んで、すくいます。")
                                        .atype(.small, color: Theme.quiet)
                                }
                            } else {
                                ReturnedList(items: returned)
                            }
                        }
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .padding(.bottom, 24)
                }
                // ボタンの分だけスクロールの下端を空ける（最後の行がボタンに隠れないように）
                .safeAreaInset(edge: .bottom) { CaptureButton() }
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .awning()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            // 今にあるものがあるときに、まとめ処理（PCC が使えれば PCC）
            .task(id: returned.count) {
                guard !returned.isEmpty else { return }
                await BatchOrganizer.organizeIfNeeded(in: context)
            }
        }
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.quiet)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("設定")
    }
}

/// 下に置く「あとでに回す」ボタン（書き出し画面を開く）。
struct CaptureButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showCapture = true
        } label: {
            Label("あとでに回す", systemImage: "plus").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.cube(.primary, size: .large, fill: true))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // ボタンの下からタブバーの下まで紙の色で埋める（スクロールした中身が透けないように）
        .background(PaperBackground(fullScreen: false).ignoresSafeArea(edges: .bottom))
    }
}

/// 今にあるもの。先頭に「次」、その下にすべてを罫で区切った行で（箱には入れない）。
/// やりたい・やらなきゃは見出しで分けず、金魚の描き分けで見せる。
struct ReturnedList: View {
    let items: [Item]

    /// 優先順位の高い順
    private var ordered: [Item] { items.sorted { $0.priority() > $1.priority() } }
    /// 「次」に出す候補（最大5つ）
    private var candidates: [Item] { Array(ordered.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !candidates.isEmpty { NextCard(items: candidates).padding(.top, 6) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Theme.faint.opacity(0.7)).frame(height: 2) }
                    ReturnedRow(item: item)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// 「次」：優先順位の高い順に、横にめくって選ぶ。
private struct NextCard: View {
    let items: [Item]
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NextPage(item: item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: 96)
            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.accent : Theme.faint)
                            .frame(width: index == page ? 18 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
        .padding(.top, 18)
        .padding([.horizontal, .bottom], 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.ink).offset(x: Theme.shadow + 1, y: Theme.shadow + 1))
        .sticker("次")
        .onChange(of: items.map(\.id)) { _, ids in
            if page >= ids.count { page = max(0, ids.count - 1) }
        }
    }
}

private struct NextPage: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.text).atype(.title).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if let deadline = item.deadline { DeadlineLabel(date: deadline) }
                Spacer(minLength: 0)
                Button("やる") { FocusSession.shared.start(item) }
                    .buttonStyle(.cube(.accent))
                    .environment(\.atypeInk, nil)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct ReturnedRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    @State private var open = false
    @State private var confirmed: ReturnTiming?
    /// あとでがいっぱいで回せなかったときの一言
    @State private var fullNotice = false

    var body: some View {
        Group {
            if let confirmed {
                confirmation(for: confirmed)
            } else {
                rowBody
            }
            if fullNotice {
                Text("水槽がいっぱいです（\(SettingsStore.laterCapacity)匹）。「あとで」で減らすと回せます")
                    .atype(.small, color: Theme.accent)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        Text("水槽に放しました").atype(.small, color: Theme.quiet)
        .frame(maxWidth: .infinity, minHeight: 56)
        .transition(.opacity)
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // 印は見せるだけ。触れても消えないよう、「できた」は開いたときのボタンだけにする
                mark
                Text(item.text).atype(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isBothLow { ReleaseHint() }
                if let deadline = item.deadline { DeadlineLabel(date: deadline) }
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(open ? "閉じる" : "やりたい・やらなきゃと、やることを出す")

            if open {
                WantMustPad(item: item)
                FlowRow {
                    action("やる", .accent) { FocusSession.shared.start(item) }
                    action("できた", .primary) { ReturnService.takeHome(item, in: context) }
                    action("あとでに回す", .secondary) { postpone(.atBreak) }
                    action("やめる", item.isBothLow ? .primary : .secondary) { resolve(.released) }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var mark: some View {
        if item.isRated {
            DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 15)
        } else {
            DotMark(kind: .concern, highlighted: item.isCloseToAxis, size: 15)
        }
    }

    private func action(_ title: String, _ variant: CubeVariant, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(.cube(variant))
    }

    /// もう一度あとに回す。一言見せてから「あとで」へ移す（時間は決めない）。
    private func postpone(_ timing: ReturnTiming) {
        guard confirmed == nil else { return }
        // あとでにも上限がある。いっぱいなら回さずに知らせる
        guard ReturnService.laterRoom(in: context) > 0 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.easeOut(duration: 0.15)) { fullNotice = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { fullNotice = false }
            }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { confirmed = timing }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation {
                item.state = .waiting
                item.timing = timing
                try? context.save()
                if let date = item.returnAt { NotificationScheduler.reschedule(for: date, in: context) }
                ReturnService.sync(in: context)
            }
        }
    }

    private func resolve(_ state: ItemState) {
        withAnimation {
            item.state = state
            item.resolvedAt = .now
            try? context.save()
            ReturnService.sync(in: context)
        }
    }
}

/// 横に並べ、入りきらなければ折り返す（文字が大きいときもボタンが切れないように）。
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct DeadlineLabel: View {
    let date: Date

    var body: some View {
        Text(Calendar.current.isDateInToday(date) ? "今日"
             : Calendar.current.isDateInTomorrow(date) ? "明日"
             : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
            .atype(.label)
    }
}
