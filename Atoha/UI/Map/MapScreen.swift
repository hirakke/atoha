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
        @Bindable var router = router
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(alignment: .leading, spacing: 12) {
                    header
                    axisCard
                    if allConcerns.isEmpty && takenHome.isEmpty {
                        Text("気になることが増えると、ここに金魚が泳ぎます。")
                            .atype(.small, color: Theme.quiet)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if side && axes.count >= 3 {
                        PondSideView(items: concerns, axes: axes)
                    } else {
                        PondMapView(items: concerns, takenHome: showTakenHome ? takenHome : [], axes: axes,
                                    selectedID: selectedID, mode: side ? .axis : mode) { item in
                            selectedID = item?.id
                        }
                    }
                    if let item = selected {
                        MapSelectionCard(item: item, leanings: PondMapView.leanings(item, axes: axes))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(item.id)
                    } else {
                        legend
                        collectionEntry
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .awning()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $router.showCollection) { CollectionView() }
            .sheet(isPresented: $showAxes) { AxesView() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("地図").font(Theme.display(.title)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CubeSegmented(options: [false, true], label: { $0 ? "横から" : "上から" },
                          selection: Binding(get: { side }, set: { side = $0; selectedID = nil }))
            Menu {
                Picker("期間", selection: Binding(get: { period }, set: { periodRaw = $0.rawValue })) {
                    ForEach(MapPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("並べ方", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                    ForEach(MapMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                Text(period.label).atype(.small).fontWeight(.black)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
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
                            Text("横の軸").atype(.small, color: Theme.quiet).fontWeight(.bold)
                            Text("\(axes[0].negativePole) ↔ \(axes[0].positivePole)").atype(.small).fontWeight(.black)
                        }
                        GridRow {
                            Text(side ? "深さ" : "縦の軸").atype(.small, color: Theme.quiet).fontWeight(.bold)
                            Text(side ? "\(axes[2].negativePole) ↔ \(axes[2].positivePole)" : "\(axes[1].positivePole) ↔ \(axes[1].negativePole)")
                                .atype(.small).fontWeight(.black)
                        }
                    }
                } else {
                    Text(axes.isEmpty ? "軸はまだありません" : "横から見るには、軸が3本いります").atype(.small).fontWeight(.bold)
                }
                Spacer(minLength: 0)
                Text(axes.isEmpty ? "軸をつくる ›" : "軸を変える ›").atype(.small).fontWeight(.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.faint.opacity(0.7)))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink).offset(x: 3, y: 3))
        }
        .buttonStyle(.plain)
    }

    /// 深さ（大きさ）と、持ち帰った金魚を出すかどうか
    private var legend: some View {
        HStack(spacing: 8) {
            if axes.count >= 3 && !side {
                Text("深さ").atype(.small).fontWeight(.black)
                GoldfishMark(color: Theme.ink, width: 24)
                Text(axes[2].negativePole).atype(.small)
                GoldfishMark(color: Theme.ink, width: 13)
                Text(axes[2].positivePole).atype(.small)
            }
            Spacer(minLength: 0)
            if !side {
                Toggle(isOn: $showTakenHome) {
                    HStack(spacing: 6) {
                        GoldfishMark(color: Theme.ink, style: .takenHome, width: 20)
                        Text("持ち帰った").atype(.small).fontWeight(.bold)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .fixedSize()
            }
        }
    }

    /// 金魚鉢へ
    private var collectionEntry: some View {
        Button { router.showCollection = true } label: {
            HStack(spacing: 12) {
                FishbowlIcon(count: min(3, takenHomeThisMonth), width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("金魚鉢　この月 \(takenHomeThisMonth)匹").atype(.body).fontWeight(.black)
                    Text("持ち帰った金魚を、一覧・カレンダーで").atype(.small, color: Theme.quiet)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .black)).foregroundStyle(Theme.quiet)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.ink).offset(x: Theme.shadow, y: Theme.shadow))
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.shadow)
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
