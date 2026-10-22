import SwiftUI
import SwiftData

/// 地図：気になることを池に泳がせる。2本の軸をはっきり見せ、横から見ると3本目（深さ）が見える。
/// 持ち帰った金魚は白抜きで重ねられ、金魚鉢から一覧・カレンダーでも見られる。
struct MapScreen: View {
    @Environment(AppRouter.self) private var router
    @Query private var items: [Item]
    @Query(sort: \Axis.order) private var axes: [Axis]
    @State private var selectedID: UUID?
    @State private var showAxes = DebugLaunch.showAxesSheet
    @AppStorage("mapPeriod") private var periodRaw: String = MapPeriod.month.rawValue
    @AppStorage("mapMode") private var modeRaw: String = ""
    @AppStorage("mapSide") private var side = false
    @AppStorage("mapShowTakenHome") private var showTakenHome = false
    @State private var path: [MapRoute] = []

    enum MapRoute: Hashable { case collection }

    private var period: MapPeriod { MapPeriod(rawValue: periodRaw) ?? .month }
    private var mode: MapMode {
        if let m = MapMode(rawValue: modeRaw) { return m }
        return axes.isEmpty ? .graph : .axis
    }

    private var cutoff: Date {
        guard let days = period.days else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -Int(days), to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
    }

    private var allConcerns: [Item] { items.filter(\.showsOnMap) }
    private var concerns: [Item] { allConcerns.filter { $0.createdAt >= cutoff } }
    /// 持ち帰った金魚（期間内に持ち帰ったもの）
    private var takenHome: [Item] {
        items.filter { $0.state == .done && ($0.resolvedAt ?? $0.createdAt) >= cutoff }
    }
    private var takenHomeThisMonth: Int {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return items.filter { $0.state == .done && ($0.resolvedAt ?? .distantPast) >= start }.count
    }

    private var selected: Item? {
        guard let selectedID else { return nil }
        return (concerns + takenHome).first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PaperBackground()
                VStack(alignment: .leading, spacing: 12) {
                    header
                    axisCard
                    if !(allConcerns.isEmpty && takenHome.isEmpty) && !showsSide { controls }
                    if allConcerns.isEmpty && takenHome.isEmpty {
                        Text("気になることが増えると、ここに金魚が泳ぎます。")
                            .atype(.small, color: Theme.quiet)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if showsSide {
                        PondSideView(items: concerns, axes: axes)
                    } else {
                        PondMapView(items: concerns, takenHome: showTakenHome ? takenHome : [], axes: axes,
                                    selectedID: selectedID, mode: side ? .axis : mode) { item in
                            selectedID = item?.id
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if let item = selected {
                            MapSelectionCard(item: item, leanings: PondMapView.leanings(item, axes: axes))
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .id(item.id)
                        } else {
                            if showsSide { sideNote } else if axes.count >= 3 { legend }
                            collectionEntry
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .awning()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MapRoute.self) { _ in CollectionView() }
            .sheet(isPresented: $showAxes) { AxesView() }
        }
        // 「持ち帰りました」の知らせから開く
        .onChange(of: router.showCollection, initial: true) { _, show in
            guard show else { return }
            router.showCollection = false
            if path.last != .collection { path.append(.collection) }
        }
        #if DEBUG
        .onAppear {
            if let v = DebugLaunch.mapSide { side = v }
            if DebugLaunch.mapSelect, selectedID == nil {
                selectedID = concerns.first { $0.isRated && GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust) != .faint && $0.axisScores.count >= 2 && abs($0.axisScores[0]) > 0.3 && abs($0.axisScores[1]) > 0.3 }?.id ?? concerns.first?.id
            }
        }
        #endif
    }

    private var showsSide: Bool { side && axes.count >= 3 }

    private var header: some View {
        HStack(spacing: 8) {
            Text("地図").font(Theme.display(.title)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
            Spacer(minLength: 0)
            CubeSegmented(options: [false, true], label: { $0 ? "横から" : "上から" },
                          selection: Binding(get: { side }, set: { side = $0; selectedID = nil }))
                .fixedSize()
            Menu {
                Picker("期間", selection: Binding(get: { period }, set: { periodRaw = $0.rawValue })) {
                    ForEach(MapPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("並べ方", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                    ForEach(MapMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                Text(period.label).font(.system(.subheadline, weight: .black)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                    .fixedSize()
            }
            .accessibilityLabel("期間 \(period.label)")
        }
    }

    /// どの軸で見ているか。押すと軸の画面へ
    private var axisCard: some View {
        Button { showAxes = true } label: {
            HStack(spacing: 10) {
                if axes.count >= 2 && !(side && axes.count < 3) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                        GridRow {
                            Text("横の軸").font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.quiet)
                            Text("\(axes[0].negativePole) ↔ \(axes[0].positivePole)").font(.system(.subheadline, weight: .black))
                        }
                        GridRow {
                            Text(side ? "深さ" : "縦の軸").font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.quiet)
                            Text(side ? "\(axes[2].negativePole) ↔ \(axes[2].positivePole)" : "\(axes[1].positivePole) ↔ \(axes[1].negativePole)")
                                .font(.system(.subheadline, weight: .black))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                } else {
                    Text(axes.isEmpty ? "軸はまだありません" : "横から見るには、軸が3本いります").atype(.small).fontWeight(.bold)
                }
                Spacer(minLength: 0)
                Text(axes.isEmpty ? "軸をつくる ›" : "軸を変える ›").font(.system(.subheadline, weight: .black)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.faint.opacity(0.7)))
                    .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink).offset(x: 3, y: 3))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 3)
    }

    /// 池の上の操作：持ち帰った金魚を出すかどうか（スイッチの札）と、泳いでいる数
    private var controls: some View {
        HStack(spacing: 8) {
            if !showsSide {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showTakenHome.toggle() }
                    if !showTakenHome, let id = selectedID, takenHome.contains(where: { $0.id == id }) { selectedID = nil }
                } label: {
                    HStack(spacing: 8) {
                        TakenHomeGlyph(inverted: showTakenHome, width: 22)
                        Text("持ち帰った").font(.system(.subheadline, weight: .black)).lineLimit(1)
                        ChipSwitch(isOn: showTakenHome)
                    }
                    .foregroundStyle(showTakenHome ? Color.white : Theme.ink)
                    .padding(.leading, 12).padding(.trailing, 8)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(showTakenHome ? Theme.ink : Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                    .background(Capsule().fill(showTakenHome ? Theme.accent : .clear).offset(x: 3, y: 3))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("持ち帰った金魚を出す")
                .accessibilityValue(showTakenHome ? "オン" : "オフ")
                .accessibilityAddTraits(.isToggle)
            }
            Spacer(minLength: 0)
            Text(countText).font(Theme.dot(.footnote)).foregroundStyle(Theme.quiet)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
    }

    private var countText: String {
        var s = "泳いでいる \(concerns.count)匹"
        if showTakenHome && !showsSide { s += "・持ち帰った \(takenHome.count)匹" }
        return s
    }

    /// 深さ（大きさ）の見方。浅い＝今ほど大きく、深い＝将来ほど小さい
    private var legend: some View {
        let names = PondMapView.depthNames(axes)
        let widths: [CGFloat] = [30, 22, 15]
        let row = ForEach(0..<3, id: \.self) { i in
            HStack(spacing: 6) {
                GoldfishMark(color: Theme.ink, width: widths[i])
                Text(names[i]).lineLimit(1)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("深さ").fontWeight(.black)
                row
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("深さ").fontWeight(.black)
                row
            }
        }
        .font(.system(.footnote, weight: .bold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("深さ。大きい金魚ほど\(names[0])、小さいほど\(names[2])")
    }

    /// 横から見たときの説明
    private var sideNote: some View {
        let near = axes[2].negativePole, far = axes[2].positivePole
        let text = (near == "今" && far == "将来")
            ? "浅いところほど今の気持ち、深いところほど将来のこと。"
            : "浅いところほど\(near)、深いところほど\(far)。"
        return Text(text)
            .font(.system(.footnote, weight: .bold))
            .foregroundStyle(Theme.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
    }

    /// この月に持ち帰った金魚が、どのあたりに多いか（「人と・作るが多め」）
    private var collectionLeaning: String? {
        guard axes.count >= 2 else { return nil }
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        let done = items.filter { $0.state == .done && ($0.resolvedAt ?? .distantPast) >= start && $0.axisScores.count >= 2 }
        guard !done.isEmpty else { return nil }
        var parts: [String] = []
        for i in 0..<2 {
            let mean = done.map { $0.axisScores[i] }.reduce(0, +) / Double(done.count)
            if abs(mean) >= 0.15 { parts.append(mean < 0 ? axes[i].negativePole : axes[i].positivePole) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "・") + "が多め"
    }

    /// 金魚鉢へ
    private var collectionEntry: some View {
        Button { path.append(.collection) } label: {
            HStack(spacing: 12) {
                FishbowlIcon(count: min(3, takenHomeThisMonth), width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("金魚鉢　この月 \(takenHomeThisMonth)匹").font(.system(.subheadline, weight: .black)).foregroundStyle(Theme.ink)
                    Text(collectionLeaning ?? "持ち帰った金魚を、一覧・カレンダーで")
                        .font(.system(.footnote, weight: .bold)).foregroundStyle(Theme.quiet)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .black)).foregroundStyle(Theme.quiet)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.ink).offset(x: Theme.shadow, y: Theme.shadow))
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.shadow)
        .padding(.bottom, Theme.shadow)
    }
}

/// 持ち帰った金魚の絵（白抜き）。inverted は藍の札の上（白い金魚に藍の中）
private struct TakenHomeGlyph: View {
    var inverted: Bool
    var width: CGFloat

    var body: some View {
        let body = inverted ? Color.white : Theme.ink
        let hole = inverted ? Theme.ink : Color.white
        Canvas { context, size in
            let cell = size.width / CGFloat(GoldfishShape.width)
            func path(_ cells: [(x: Int, y: Int)]) -> Path {
                var p = Path()
                for c in cells { p.addRect(CGRect(x: CGFloat(c.x) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell)) }
                return p
            }
            context.fill(path(GoldfishShape.cells), with: .color(body))
            context.fill(path(GoldfishShape.holeCells), with: .color(hole))
        }
        .frame(width: width, height: width * CGFloat(GoldfishShape.height) / CGFloat(GoldfishShape.width))
        .accessibilityHidden(true)
    }
}

/// 札の中の小さなスイッチ（見た目だけ。押すのは札全体）
private struct ChipSwitch: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.accent : Theme.faint.opacity(0.7))
            Capsule().strokeBorder(isOn ? Color.white : Theme.ink, lineWidth: 2)
            Circle().fill(Color.white)
                .overlay(Circle().strokeBorder(isOn ? Color.clear : Theme.ink, lineWidth: 2))
                .frame(width: 18, height: 18)
                .padding(.horizontal, 4)
        }
        .frame(width: 44, height: 26)
        .accessibilityHidden(true)
    }
}

private struct MapSelectionCard: View {
    let item: Item
    let leanings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if item.state == .done {
                    GoldfishMark(color: Theme.ink, style: .takenHome, width: 30)
                } else if item.isRated {
                    GoldfishMark(tint: GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust), width: 30)
                } else {
                    GoldfishMark(color: Theme.ink, style: .fry, width: 30)
                }
                Text(item.text).atype(.body).fontWeight(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowRow(spacing: 6) {
                ForEach(leanings + [placeLabel], id: \.self) { text in
                    Text(text).atype(.small).fontWeight(.bold)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.faint.opacity(0.7)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent, lineWidth: Theme.stroke))
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent).offset(x: Theme.shadow, y: Theme.shadow))
        .padding(.trailing, Theme.shadow)
    }

    private var placeLabel: String {
        switch item.state {
        case .returned: "今のお椀"
        case .waiting: "あとでの水槽"
        case .done: "持ち帰った"
        default: "池"
        }
    }
}

// MARK: - Preview

private enum MapScreenPreviewData {
    struct Rng: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @MainActor
    static func container() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Item.self, Axis.self, configurations: config)
        let context = container.mainContext

        let poles = [("一人で", "人と"), ("作る", "整える"), ("今", "将来")]
        for (i, p) in poles.enumerated() {
            context.insert(Axis(negativePole: p.0, positivePole: p.1, order: i))
        }

        let texts = [
            "陶芸教室に行ってみたい", "部屋の本棚を整理したい", "昔の友だちに連絡する",
            "朝の散歩を習慣にしたい", "小さな畑を借りる", "写真をまとめて一冊にする",
            "英語をもう一度やり直す", "週末にパンを焼く", "引っ越しを考えている",
            "古いノートを読み返す", "誰かと一緒に山に登る", "家計の見直し",
            "短い文章を書き続ける", "知らない街を歩く", "楽器をまた始めたい",
        ]
        let themes: [String?] = ["手を動かす", "暮らし", "人", nil]
        var rng = Rng(state: 42)
        let now = Date()
        for (i, text) in texts.enumerated() {
            let item = Item(text: text, timing: .atBreak, now: now.addingTimeInterval(-Double(i) * 86_400 * 1.7))
            item.kind = .concern
            item.state = .grown
            item.axisScores = (0..<3).map { _ in Double.random(in: -1...1, using: &rng) }
            item.axisAffinity = Double.random(in: 0...1, using: &rng)
            item.theme = themes[i % themes.count]
            context.insert(item)
        }
        return container
    }
}

#Preview {
    MapScreen()
        .modelContainer(MapScreenPreviewData.container())
}
