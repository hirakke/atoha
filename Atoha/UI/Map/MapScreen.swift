import SwiftUI
import SwiftData

/// 地図：気になることを、上から見た池に泳がせる。
struct MapScreen: View {
    @Query private var items: [Item]
    @Query(sort: \Axis.order) private var axes: [Axis]
    @State private var selectedID: UUID?
    @State private var showAxes = DebugLaunch.showAxesSheet
    @AppStorage("mapPeriod") private var periodRaw: String = MapPeriod.month.rawValue
    @AppStorage("mapMode") private var modeRaw: String = ""

    private var period: MapPeriod { MapPeriod(rawValue: periodRaw) ?? .month }
    private var mode: MapMode {
        if let m = MapMode(rawValue: modeRaw) { return m }
        return axes.isEmpty ? .graph : .axis
    }

    private var allConcerns: [Item] {
        items.filter(\.showsOnMap)
    }

    private var concerns: [Item] {
        guard let days = period.days else { return allConcerns }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Int(days), to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return allConcerns.filter { $0.createdAt >= cutoff }
    }

    private var selected: Item? {
        guard let selectedID else { return nil }
        return concerns.first { $0.id == selectedID }
    }

    private var axesButton: some View {
        Button("軸") { showAxes = true }
            .buttonStyle(.cube(.secondary))
    }

    var body: some View {
        ZStack {
            PaperBackground()

            if allConcerns.isEmpty {
                SquareMark(.ink(0.15), size: 10)
                axesButton
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        axesButton
                        Text("\(concerns.count)匹")
                            .atype(.label)
                            .padding(.top, 10)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            CubeSegmented(options: MapPeriod.allCases, label: { $0.label },
                                          selection: Binding(get: { period }, set: { periodRaw = $0.rawValue }))
                            CubeSegmented(options: MapMode.allCases, label: { $0.label },
                                          selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue }))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // 上から見た池。縦横で軸2本、3本目は深さ
                    PondMapView(items: concerns, axes: axes, selectedID: selectedID, mode: mode) { item in
                        selectedID = item?.id
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .overlay(alignment: .bottom) {
                    if let item = selected {
                        MapSelectionCard(item: item, place: PondMapView.whereText(item, axes: axes))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(item.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showAxes) { AxesView() }
    }
}

private struct MapSelectionCard: View {
    let item: Item
    /// どのあたりを泳いでいるか
    var place: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd"
        return f
    }()

    var body: some View {
        Card(opaque: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.text)
                    .atype(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let place { Text(place).atype(.label) }
                HStack(spacing: 10) {
                    if let theme = item.theme, !theme.isEmpty {
                        Text(theme).atype(.label)
                    }
                    Spacer()
                    TimeText(seconds: item.focusSeconds)
                    Text(Self.dateFormatter.string(from: item.createdAt))
                        .atype(.label)
                }
            }
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
