import SwiftUI

/// 地図：上から見た池。2本の軸をはっきり引き、金魚がどの区画を泳いでいるかで自分の傾向が見える。
/// 軸のときは横＝1本目、縦＝2本目、3本目は深さ（浅い＝低い側の極、深い＝高い側の極）で、金魚の大きさで見せる。
/// つながりのときは、意味の近いもの同士を寄せて点線で結ぶ。
struct PondMapView: View {
    let items: [Item]
    /// 持ち帰った金魚（白抜きで重ねる）
    var takenHome: [Item] = []
    let axes: [Axis]
    let selectedID: UUID?
    var mode: MapMode = .axis
    let onSelect: (Item?) -> Void

    @State private var graph = PondGraph()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let fish = placements()
            ZStack {
                // 池・網点・軸は動かないので、毎フレームは描かない
                Canvas { context, canvas in drawPond(context: context, size: canvas) }
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, canvas in
                        draw(context: context, size: canvas, fish: fish, time: t)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                tap(at: value.location, size: size, fish: fish)
            })
            .overlay { labels(size: size, fish: fish) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = "池に \(items.count) 匹"
        if axes.count >= 2 {
            s += "。横の軸は\(axes[0].negativePole)から\(axes[0].positivePole)、縦の軸は\(axes[1].positivePole)から\(axes[1].negativePole)"
        }
        if !takenHome.isEmpty { s += "。持ち帰った金魚 \(takenHome.count) 匹" }
        return s
    }

    // MARK: 位置

    /// 1匹分の置き場所。u は池の中の位置（-1...1、上が +）、depth は 0（浅い）...1（深い）。
    struct Placement {
        let item: Item
        let u: CGPoint
        let depth: Double
        let tint: GoldfishTint
        let phase: Double
        let done: Bool
    }

    private func placements() -> [Placement] {
        let all = items + takenHome
        let positions: [UUID: CGPoint]
        if mode == .graph {
            positions = graph.layout(all)
        } else {
            positions = Dictionary(uniqueKeysWithValues: all.map { item in
                (item.id, CGPoint(x: score(item, 0), y: score(item, 1)))
            })
        }
        let doneIDs = Set(takenHome.map(\.id))
        return all.map { item in
            let depth = axes.count >= 3 ? (score(item, 2) + 1) / 2 : 0.25
            return Placement(item: item, u: positions[item.id] ?? .zero, depth: depth,
                             tint: GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust),
                             phase: Double(abs(item.id.hashValue % 6283)) / 1000,
                             done: doneIDs.contains(item.id))
        }
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    // MARK: 描く

    /// 池の四角（極の札のぶん、上下を空ける）
    private func pondRect(_ size: CGSize) -> CGRect {
        CGRect(x: 4, y: 20, width: size.width - 8, height: size.height - 40)
    }

    /// 池の中の位置 → 画面の点
    private func screen(_ u: CGPoint, size: CGSize) -> CGPoint {
        let r = pondRect(size)
        return CGPoint(x: r.midX + u.x * (r.width / 2 - 40) * 0.9,
                       y: r.midY - u.y * (r.height / 2 - 34) * 0.9)
    }

    /// 泳いでいる今の位置（もとの場所のまわりを、ゆっくり小さく回る）。選んだ金魚は止める
    private func swimming(_ f: Placement, size: CGSize, time: Double) -> (CGPoint, facingRight: Bool) {
        let base = screen(f.u, size: size)
        if f.item.id == selectedID { return (base, false) }
        let dx = sin(time * 0.35 + f.phase) * 8
        let dy = sin(time * 0.27 + f.phase * 1.7) * 4
        let vx = cos(time * 0.35 + f.phase)
        return (CGPoint(x: base.x + dx, y: base.y + dy), vx > 0)
    }

    /// 浅い（今）ほど大きく、深い（将来）ほど小さい
    private func fishWidth(_ depth: Double) -> CGFloat { CGFloat(40 - 22 * depth) }

    private func drawPond(context: GraphicsContext, size: CGSize) {
        let ink = Theme.ink
        let rect = pondRect(size)
        let pond = Path(roundedRect: rect, cornerRadius: 26)
        context.fill(pond, with: .color(Theme.water))
        // 網点の水
        var dots = Path()
        var y = rect.minY + 6, row = 0
        while y < rect.maxY - 4 {
            var x = rect.minX + (row.isMultiple(of: 2) ? 6 : 10)
            while x < rect.maxX - 4 { dots.addRect(CGRect(x: x, y: y, width: 1.6, height: 1.6)); x += 8 }
            y += 4; row += 1
        }
        var water = context
        water.clip(to: pond)
        water.fill(dots, with: .color(ink.opacity(0.12)))
        context.stroke(pond, with: .color(ink), lineWidth: Theme.stroke)

        let c = CGPoint(x: rect.midX, y: rect.midY)

        if mode == .axis {
            // 2本の軸。両端に矢印、目盛り付き
            var lines = Path()
            var heads = Path()
            if axes.count >= 1 {
                let x0 = rect.minX + 62, x1 = rect.maxX - 62
                lines.move(to: CGPoint(x: x0, y: c.y)); lines.addLine(to: CGPoint(x: x1, y: c.y))
                heads.addPath(arrowHead(at: CGPoint(x: x0 - 2, y: c.y), dir: .left))
                heads.addPath(arrowHead(at: CGPoint(x: x1 + 2, y: c.y), dir: .right))
                for i in 1...4 {
                    let t = CGFloat(i) / 5
                    for x in [c.x - (c.x - x0) * t, c.x + (x1 - c.x) * t] {
                        lines.move(to: CGPoint(x: x, y: c.y - 3)); lines.addLine(to: CGPoint(x: x, y: c.y + 3))
                    }
                }
            }
            if axes.count >= 2 {
                let y0 = rect.minY + 10, y1 = rect.maxY - 10
                lines.move(to: CGPoint(x: c.x, y: y0)); lines.addLine(to: CGPoint(x: c.x, y: y1))
                heads.addPath(arrowHead(at: CGPoint(x: c.x, y: y0 - 2), dir: .up))
                heads.addPath(arrowHead(at: CGPoint(x: c.x, y: y1 + 2), dir: .down))
                for i in 1...4 {
                    let t = CGFloat(i) / 5
                    for yy in [c.y - (c.y - y0) * t, c.y + (y1 - c.y) * t] {
                        lines.move(to: CGPoint(x: c.x - 3, y: yy)); lines.addLine(to: CGPoint(x: c.x + 3, y: yy))
                    }
                }
            }
            context.stroke(lines, with: .color(ink), lineWidth: 2)
            context.fill(heads, with: .color(ink))
        }

    }

    private func draw(context: GraphicsContext, size: CGSize, fish: [Placement], time: Double) {
        let ink = Theme.ink, accent = Theme.accent, surface = Theme.surface
        let rect = pondRect(size)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let now = Dictionary(uniqueKeysWithValues: fish.map { ($0.item.id, swimming($0, size: size, time: time)) })

        if mode == .graph {
            // つながり：近いもの同士の点線。選んだものの線は濃く
            for e in graph.edges {
                guard let a = now[e.a]?.0, let b = now[e.b]?.0 else { continue }
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                let lit = e.a == selectedID || e.b == selectedID
                context.stroke(line, with: .color(ink.opacity(lit ? 0.7 : 0.22)),
                               style: StrokeStyle(lineWidth: lit ? 1.5 : 1, dash: [3, 4]))
            }
        }

        // 選んだ金魚から軸へ、紅い点線
        if mode == .axis, let sel = fish.first(where: { $0.item.id == selectedID }), axes.count >= 2 {
            let p = screen(sel.u, size: size)
            var cross = Path()
            cross.move(to: p); cross.addLine(to: CGPoint(x: c.x, y: p.y))
            cross.move(to: p); cross.addLine(to: CGPoint(x: p.x, y: c.y))
            context.stroke(cross, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            for q in [CGPoint(x: c.x, y: p.y), CGPoint(x: p.x, y: c.y)] {
                context.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(accent))
            }
        }

        // 深いものから順に描く（浅い金魚が手前）。持ち帰った金魚はいちばん下
        let order = fish.sorted { ($0.done ? 1 : 0, $0.depth) > ($1.done ? 1 : 0, $1.depth) }
        for f in order {
            guard let (pos, right) = now[f.item.id] else { continue }
            let selected = f.item.id == selectedID
            let dim = selectedID != nil && !selected
            let w = fishWidth(f.depth) * (selected ? 1.2 : 1)
            let cell = w / CGFloat(GoldfishShape.width)
            let h = cell * CGFloat(GoldfishShape.height)
            let origin = CGPoint(x: pos.x - w / 2, y: pos.y - h / 2)
            func path(_ cells: [(x: Int, y: Int)]) -> Path {
                var p = Path()
                for c in cells {
                    // 絵は左向き。右へ泳ぐときは左右を反転する
                    let x = right ? CGFloat(GoldfishShape.width - 1 - c.x) : CGFloat(c.x)
                    p.addRect(CGRect(x: origin.x + x * cell, y: origin.y + CGFloat(c.y) * cell, width: cell, height: cell))
                }
                return p
            }
            var g = context
            g.opacity = dim ? 0.3 : 1
            if selected {
                let ring = Path(ellipseIn: CGRect(x: pos.x - w * 0.75, y: pos.y - w * 0.75, width: w * 1.5, height: w * 1.5))
                g.fill(ring, with: .color(surface))
                g.stroke(ring, with: .color(accent), lineWidth: 2.5)
            }
            if f.done {
                g.fill(path(GoldfishShape.cells), with: .color(ink))
                g.fill(path(GoldfishShape.holeCells), with: .color(surface))
            } else if !f.item.isRated {
                g.fill(path(GoldfishShape.dottedCells), with: .color(ink))
            } else if f.tint == .both {
                g.fill(path(GoldfishShape.cells), with: .color(ink))
                g.fill(path(GoldfishShape.holeCells), with: .color(accent))
            } else {
                g.fill(path(GoldfishShape.cells), with: .color(f.tint.color))
            }
        }
    }

    private enum Dir { case left, right, up, down }

    private func arrowHead(at p: CGPoint, dir: Dir) -> Path {
        let l: CGFloat = 9, w: CGFloat = 6
        var a = Path()
        switch dir {
        case .left: a.move(to: p); a.addLine(to: CGPoint(x: p.x + l, y: p.y - w)); a.addLine(to: CGPoint(x: p.x + l, y: p.y + w))
        case .right: a.move(to: p); a.addLine(to: CGPoint(x: p.x - l, y: p.y - w)); a.addLine(to: CGPoint(x: p.x - l, y: p.y + w))
        case .up: a.move(to: p); a.addLine(to: CGPoint(x: p.x - w, y: p.y + l)); a.addLine(to: CGPoint(x: p.x + w, y: p.y + l))
        case .down: a.move(to: p); a.addLine(to: CGPoint(x: p.x - w, y: p.y - l)); a.addLine(to: CGPoint(x: p.x + w, y: p.y - l))
        }
        a.closeSubpath()
        return a
    }

    // MARK: ラベル

    @ViewBuilder private func labels(size: CGSize, fish: [Placement]) -> some View {
        if mode == .axis {
            let rect = pondRect(size)
            ZStack {
                if axes.count >= 2 {
                    // 区画の名前（うすく）
                    VStack {
                        HStack { quadrant("\(axes[0].negativePole)・\(axes[1].positivePole)"); Spacer(); quadrant("\(axes[0].positivePole)・\(axes[1].positivePole)") }
                        Spacer()
                        HStack { quadrant("\(axes[0].negativePole)・\(axes[1].negativePole)"); Spacer(); quadrant("\(axes[0].positivePole)・\(axes[1].negativePole)") }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                    poleLabel(axes[1].positivePole).position(x: rect.midX, y: rect.minY)
                    poleLabel(axes[1].negativePole).position(x: rect.midX, y: rect.maxY)
                }
                if axes.count >= 1 {
                    HStack {
                        poleLabel(axes[0].negativePole)
                        Spacer()
                        poleLabel(axes[0].positivePole)
                    }
                    .frame(width: rect.width)
                    .position(x: rect.midX, y: rect.midY)
                }
                // 選んだ金魚が、それぞれの軸のどちら寄りか
                if axes.count >= 2, let sel = fish.first(where: { $0.item.id == selectedID }) {
                    let p = screen(sel.u, size: size)
                    let c = CGPoint(x: rect.midX, y: rect.midY)
                    if abs(sel.u.x) >= 0.15 {
                        leanTag(sel.u.x < 0 ? axes[0].negativePole : axes[0].positivePole)
                            .position(x: p.x, y: c.y + (p.y > c.y ? -18 : 18))
                    }
                    if abs(sel.u.y) >= 0.15 {
                        leanTag(sel.u.y > 0 ? axes[1].positivePole : axes[1].negativePole)
                            .fixedSize()
                            .position(x: c.x + (p.x > c.x ? -46 : 46), y: p.y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func quadrant(_ text: String) -> some View {
        Text(text).font(.system(.caption2, weight: .bold)).foregroundStyle(Theme.quiet.opacity(0.85))
    }

    private func poleLabel(_ text: String) -> some View {
        Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(Color.white)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(Theme.band))
            .fixedSize()
    }

    private func leanTag(_ pole: String) -> some View {
        Text("\(pole)寄り").font(.system(.caption, weight: .black)).foregroundStyle(Color.white)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Theme.accent))
    }

    // MARK: 選ぶ

    private func tap(at point: CGPoint, size: CGSize, fish: [Placement]) {
        let time = Date.now.timeIntervalSinceReferenceDate
        var best: (Item, CGFloat)?
        for f in fish {
            let (pos, _) = swimming(f, size: size, time: time)
            let d = hypot(pos.x - point.x, pos.y - point.y)
            if d <= fishWidth(f.depth) / 2 + 16, d < (best?.1 ?? .infinity) { best = (f.item, d) }
        }
        if best != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.easeOut(duration: 0.2)) { onSelect(best?.0) }
    }

    /// どのあたりを泳いでいるか（札にして出す）
    static func leanings(_ item: Item, axes: [Axis]) -> [String] {
        var parts: [String] = []
        for (i, axis) in axes.prefix(2).enumerated() where i < item.axisScores.count {
            let s = item.axisScores[i]
            if abs(s) >= 0.15 { parts.append((s < 0 ? axis.negativePole : axis.positivePole) + "寄り") }
        }
        if axes.count >= 3, item.axisScores.count >= 3 {
            let s = item.axisScores[2]
            parts.append("深さ：" + (s <= -0.33 ? axes[2].negativePole : s >= 0.33 ? axes[2].positivePole : "あいだ"))
        }
        return parts
    }
}

/// 地図：横から見た池（断面）。3本目の軸＝深さを、水の層で見せる。浅いほど低い側の極、深いほど高い側の極。
struct PondSideView: View {
    let items: [Item]
    let axes: [Axis]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, canvas in draw(context: context, size: canvas) }
                .overlay { labels(size: size) }
        }
        .accessibilityElement()
        .accessibilityLabel(axes.count >= 3 ? "池を横から見たところ。浅いほど\(axes[2].negativePole)、深いほど\(axes[2].positivePole)" : "池を横から見たところ")
    }

    private func waterRect(_ size: CGSize) -> CGRect {
        CGRect(x: 64, y: 14, width: size.width - 68, height: size.height - 44)
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let ink = Theme.ink, accent = Theme.accent
        let r = waterRect(size)
        let shape = Path(roundedRect: r, cornerRadius: 18)
        context.fill(shape, with: .color(Theme.water))
        // 3つの層。深いほど網点が濃い
        var layered = context
        layered.clip(to: shape)
        for (i, alpha) in [0.10, 0.20, 0.34].enumerated() {
            let band = CGRect(x: r.minX, y: r.minY + r.height * CGFloat(i) / 3, width: r.width, height: r.height / 3)
            var dots = Path()
            var y = band.minY + 4, row = 0
            while y < band.maxY {
                var x = band.minX + (row.isMultiple(of: 2) ? 4 : 8)
                while x < band.maxX { dots.addRect(CGRect(x: x, y: y, width: 1.8, height: 1.8)); x += 8 }
                y += 4; row += 1
            }
            layered.fill(dots, with: .color(ink.opacity(alpha)))
            if i > 0 {
                var line = Path()
                line.move(to: CGPoint(x: band.minX, y: band.minY)); line.addLine(to: CGPoint(x: band.maxX, y: band.minY))
                layered.stroke(line, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        context.stroke(shape, with: .color(ink), lineWidth: Theme.stroke)
        // 下の横の軸
        var axis = Path()
        let y = size.height - 12
        axis.move(to: CGPoint(x: r.minX + 52, y: y)); axis.addLine(to: CGPoint(x: r.maxX - 52, y: y))
        context.stroke(axis, with: .color(ink), lineWidth: 2)
        // 金魚
        for item in items {
            let x = r.midX + score(item, 0) * (r.width / 2 - 26) * 0.9
            let d = (score(item, 2) + 1) / 2
            let py = r.minY + 16 + d * (r.height - 32)
            let w = CGFloat(40 - 22 * d)
            let cell = w / CGFloat(GoldfishShape.width)
            let origin = CGPoint(x: x - w / 2, y: py - cell * 2.5)
            func path(_ cells: [(x: Int, y: Int)]) -> Path {
                var p = Path()
                for c in cells { p.addRect(CGRect(x: origin.x + CGFloat(c.x) * cell, y: origin.y + CGFloat(c.y) * cell, width: cell, height: cell)) }
                return p
            }
            let tint = GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust)
            if !item.isRated {
                context.fill(path(GoldfishShape.dottedCells), with: .color(ink))
            } else if tint == .both {
                context.fill(path(GoldfishShape.cells), with: .color(ink))
                context.fill(path(GoldfishShape.holeCells), with: .color(accent))
            } else {
                context.fill(path(GoldfishShape.cells), with: .color(tint.color))
            }
        }
    }

    @ViewBuilder private func labels(size: CGSize) -> some View {
        let r = waterRect(size)
        ZStack {
            if axes.count >= 3 {
                VStack(spacing: 0) {
                    ForEach(Array([axes[2].negativePole, "あいだ", axes[2].positivePole].enumerated()), id: \.offset) { i, text in
                        Text(text).font(.system(.caption, weight: .black))
                            .foregroundStyle(i == 1 ? Theme.ink : Color.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .frame(width: 56)
                            .background(Capsule().fill(i == 1 ? Theme.surface : Theme.band))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: i == 1 ? 1.5 : 0))
                            .frame(height: r.height / 3)
                    }
                }
                .frame(width: 60, height: r.height)
                .position(x: 30, y: r.midY)
            }
            if axes.count >= 1 {
                HStack {
                    Text(axes[0].negativePole); Spacer(); Text(axes[0].positivePole)
                }
                .font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
                .frame(width: r.width)
                .position(x: r.midX, y: size.height - 12)
            }
        }
        .allowsHitTesting(false)
    }
}

/// つながりのときの配置。意味の近いもの同士を引き寄せる（力学的な配置を、項目が変わったときだけ計算する）。
@MainActor
final class PondGraph {
    struct Edge { let a: UUID; let b: UUID }
    private(set) var edges: [Edge] = []
    private var key = ""
    private var positions: [UUID: CGPoint] = [:]

    func layout(_ items: [Item]) -> [UUID: CGPoint] {
        let newKey = items.map(\.id.uuidString).sorted().joined(separator: ",")
        if newKey == key { return positions }
        key = newKey
        let n = items.count
        guard n > 0 else { edges = []; positions = [:]; return [:] }
        let vecs = items.map { item -> [Double] in
            let raw = (item.embedding?.isEmpty == false) ? item.embedding! : EmbeddingService.embed(item.text)
            return EmbeddingService.l2(raw)
        }
        func sim(_ i: Int, _ j: Int) -> Double {
            let a = vecs[i], b = vecs[j]
            guard a.count == b.count else { return 0 }
            return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        }
        // それぞれ一番近い1本は必ず結び、2本目は近いときだけ
        var found = Set<String>()
        var pairs: [(Int, Int)] = []
        for i in 0..<n {
            var b1 = (-1, -2.0), b2 = (-1, -2.0)
            for j in 0..<n where j != i {
                let s = sim(i, j)
                if s > b1.1 { b2 = b1; b1 = (j, s) } else if s > b2.1 { b2 = (j, s) }
            }
            for (j, s) in [b1, b2] where j >= 0 && (j == b1.0 || (s >= 0.15 && s >= b1.1 * 0.85)) {
                let k = i < j ? "\(i)-\(j)" : "\(j)-\(i)"
                if found.insert(k).inserted { pairs.append((min(i, j), max(i, j))) }
            }
        }
        edges = pairs.map { Edge(a: items[$0.0].id, b: items[$0.1].id) }

        // 力学的な配置（ID から決めた位置で始め、毎回同じ形になる）
        var pos: [CGPoint] = items.map { item in
            var h: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in item.id.uuidString.utf8 { h ^= UInt64(byte); h = h &* 0x100_0000_01B3 }
            return CGPoint(x: Double(h & 0xFFFF) / 65535 * 1.6 - 0.8, y: Double((h >> 16) & 0xFFFF) / 65535 * 1.6 - 0.8)
        }
        let rep = 0.6 / Double(n + 4)
        for step in 0..<220 {
            let alpha = max(0.05, 1 - Double(step) / 220)
            var force = [CGPoint](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    if abs(dx) + abs(dy) < 0.0001 { dx = 0.01; dy = 0.013 }
                    let r2 = max(dx * dx + dy * dy, 0.004)
                    let f = min(rep / r2, 2) / r2.squareRoot()
                    force[i].x += dx * f; force[i].y += dy * f
                    force[j].x -= dx * f; force[j].y -= dy * f
                }
                force[i].x -= pos[i].x * 0.3; force[i].y -= pos[i].y * 0.3
            }
            for (a, b) in pairs {
                let dx = pos[b].x - pos[a].x, dy = pos[b].y - pos[a].y
                let len = max((dx * dx + dy * dy).squareRoot(), 0.0001)
                let f = (len - 0.35) * 0.6 / len
                force[a].x += dx * f; force[a].y += dy * f
                force[b].x -= dx * f; force[b].y -= dy * f
            }
            for i in 0..<n {
                pos[i].x += max(-0.08, min(0.08, force[i].x * 0.1 * alpha))
                pos[i].y += max(-0.08, min(0.08, force[i].y * 0.1 * alpha))
            }
        }
        // 池の中に収める
        let extent = pos.reduce(0.001) { max($0, abs($1.x), abs($1.y)) }
        let scale = min(1, 0.95 / extent)
        positions = Dictionary(uniqueKeysWithValues: zip(items.map(\.id), pos.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }))
        return positions
    }
}
