import SwiftUI
import SwiftData

/// 池：気になることを池に泳がせる。2本の軸をはっきり見せ、横から見ると3本目（深さ）が見える。
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.tankGlassKey) private var glassRaw = TankGlass.drawn.rawValue
    /// 池の傾きの向き。保存した side は変更がトランザクションに乗らないので、動かす値は別に持つ
    @State private var tiltSide = UserDefaults.standard.bool(forKey: "mapSide")
    /// 「つながり」の並べ方から横からへ倒すあいだ（と起こすあいだ）、傾ける池のままにしておく
    @State private var tiltHold = false
    @State private var path: [MapRoute] = []

    enum MapRoute: Hashable { case collection }

    private var glass: TankGlass { TankGlass(rawValue: glassRaw) ?? .drawn }
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
                PaperBackground(fadeTop: true)
                VStack(alignment: .leading, spacing: 10) {
                    header
                        .padding(.horizontal, -20)
                    if allConcerns.isEmpty && takenHome.isEmpty {
                        Text("気になることが増えると、ここに金魚が泳ぎます。")
                            .atype(.small, color: Theme.quiet)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .bottomTrailing) { collectionEntry.padding(.bottom, 12) }
                    } else {
                        // 池はガラスの入れ物に入れる（見え方は設定で切り替える）
                        pond
                        .glassFrame(glass, radius: 22)
                        // 金魚鉢の札は池の右下に。金魚を選んでいるあいだは、金魚を隠さないよう引っ込める。横からは下の行に
                        .overlay(alignment: .bottomTrailing) {
                            if selected == nil && !showsSide { collectionEntry.padding(.trailing, 24).padding(.bottom, 60).transition(.opacity) }
                        }
                        .padding(.top, 8)
                    }
                    if let item = selected {
                        MapSelectionCard(item: item, leanings: PondMapView.leanings(item, axes: axes))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(item.id)
                    } else if showsSide {
                        HStack(spacing: 8) {
                            if let note = hint { hintText(note) }
                            Spacer(minLength: 0)
                            collectionEntry
                        }
                    } else if let note = hint {
                        hintText(note).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
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
        .onChange(of: side) { _, value in if tiltSide != value { tiltSide = value } }
        #if DEBUG
        .onAppear {
            if let v = DebugLaunch.mapSide { side = v }
            if let t = DebugLaunch.mapTilt { side = t >= 45 }
            if DebugLaunch.mapToggle {
                // 開いて少ししたら、上から↔横からを切り替える（動きの確認用）
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { setSide(!side) }
            }
            if DebugLaunch.mapSelect, selectedID == nil {
                selectedID = concerns.first { $0.isRated && GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust) != .faint && $0.axisScores.count >= 2 && abs($0.axisScores[0]) > 0.3 && abs($0.axisScores[1]) > 0.3 }?.id ?? concerns.first?.id
            }
        }
        #endif
    }

    private var showsSide: Bool { side && axes.count >= 3 }

    /// 軸が3本あるときは、上からと横からを1つの池で描き、切り替えると池が手前に倒れる（深さが見える）。
    /// 視差効果を減らす設定のときは、倒さずに入れ替える（ふわっと重ねる）。
    @ViewBuilder private var pond: some View {
        if axes.count >= 3 && (side || mode == .axis || tiltHold) {
            let tilt = DebugLaunch.mapTilt.map { $0 / 90 } ?? (tiltSide ? 1 : 0)
            ZStack {
                if reduceMotion {
                    tiltPond(tilt).id(tiltSide).transition(.opacity)
                } else {
                    tiltPond(tilt)
                }
            }
        } else {
            PondMapView(items: concerns, takenHome: showTakenHome ? takenHome : [], axes: axes,
                        selectedID: selectedID, mode: side ? .axis : mode) { item in
                selectedID = item?.id
            }
        }
    }

    private func tiltPond(_ tilt: Double) -> some View {
        PondTiltView(items: concerns, takenHome: showTakenHome ? takenHome : [], axes: axes,
                     selectedID: selectedID, tilt: tilt) { item in
            selectedID = item?.id
        }
    }

    /// 上から↔横からを切り替える。池がゆっくり倒れる（約0.9秒、なめらかに出入り）
    /// 並べ方が「つながり」のときは、いったん上からの池に入れ替えてから倒し、戻るときは起こし終えてから「つながり」に戻す
    private func setSide(_ value: Bool) {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.35) : .smooth(duration: 0.9)
        if value && axes.count >= 3 && mode != .axis && !tiltHold {
            tiltHold = true
            tiltSide = false
            selectedID = nil
            DispatchQueue.main.async { setSide(true) }
            return
        }
        if !value && mode != .axis { tiltHold = true }
        withAnimation(animation) {
            side = value
            tiltSide = value
            selectedID = nil
        } completion: {
            if !side { tiltHold = false }
        }
    }

    private var header: some View {
        ScreenHeader(title: "池") {
            EmptyView()
        } trailing: {
            HStack(spacing: 8) {
                CubeSegmented(options: [false, true], label: { $0 ? "横から" : "上から" },
                              selection: Binding(get: { side }, set: { setSide($0) }))
                    .fixedSize()
                viewMenu
            }
        }
    }

    /// 表示の設定をまとめた「…」：期間、並べ方、持ち帰った金魚、軸を変える
    private var viewMenu: some View {
        Menu {
            Picker("期間", selection: Binding(get: { period }, set: { periodRaw = $0.rawValue })) {
                ForEach(MapPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            if !side {
                Picker("並べ方", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                    ForEach(MapMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("持ち帰った金魚を出す", isOn: Binding(get: { showTakenHome }, set: { on in
                    withAnimation(.easeOut(duration: 0.2)) { showTakenHome = on }
                    if !on, let id = selectedID, takenHome.contains(where: { $0.id == id }) { selectedID = nil }
                }))
            }
            Divider()
            Button { showAxes = true } label: {
                Label(axes.isEmpty ? "軸をつくる" : "軸を変える", systemImage: "arrow.left.and.right")
            }
        } label: {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Theme.ink).frame(width: 5, height: 5) }
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
            .contentShape(Circle())
        }
        .accessibilityLabel("表示（期間・持ち帰った・軸を変える）")
        .accessibilityValue("期間 \(period.label)")
    }

    /// 池の下の一行の説明。上からは大きさ（深さ）の見方、横からは層の見方
    private var hint: String? {
        if side {
            guard axes.count >= 3 else { return "横から見るには、軸が3本いります" }
            return "浅い＝\(axes[2].negativePole)　深い＝\(axes[2].positivePole)"
        }
        if axes.isEmpty { return "「…」から軸をつくると、傾向が見えます" }
        guard axes.count >= 3 else { return nil }
        let names = PondMapView.depthNames(axes)
        return "大きい＝\(names[0])　小さい＝\(names[2])"
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(Theme.quiet)
            .lineLimit(2)
            .multilineTextAlignment(.center)
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

    /// 金魚鉢へ（池の右下の小さな札）
    private var collectionEntry: some View {
        Button { path.append(.collection) } label: {
            HStack(spacing: 8) {
                FishbowlIcon(count: min(1, takenHomeThisMonth), width: 22)
                Text("金魚鉢").font(.system(.subheadline, weight: .black))
                Text("\(takenHomeThisMonth)").font(Theme.dot(.body))
            }
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.leading, 12).padding(.trailing, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(Capsule().fill(Theme.ink).offset(x: 3, y: 3))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("金魚鉢。この月に持ち帰った金魚 \(takenHomeThisMonth)匹")
        .accessibilityHint(collectionLeaning ?? "持ち帰った金魚を、一覧・カレンダーで見る")
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
