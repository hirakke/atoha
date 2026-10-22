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
        /// 深さの3段（0＝浅い・今、1＝あいだ、2＝深い・将来）
        let step: Int
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
            let depth = axes.count >= 3 ? (score(item, 2) + 1) / 2 : 0.5
            return Placement(item: item, u: positions[item.id] ?? .zero, depth: depth,
                             step: axes.count >= 3 ? Self.depthStep(score(item, 2)) : 1,
                             tint: GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust),
                             phase: Double(abs(item.id.hashValue % 6283)) / 1000,
                             done: doneIDs.contains(item.id))
        }
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    // MARK: 深さの3段

    /// 3本目の軸の値を3段に分ける（0＝浅い、1＝あいだ、2＝深い）
    static func depthStep(_ s: Double) -> Int { s <= -0.33 ? 0 : s >= 0.33 ? 2 : 1 }
    /// 段ごとの金魚の大きさ（浅いほど大きい）
    static let depthScales: [CGFloat] = [1.3, 1.0, 0.7]
    /// 金魚のふつうの横幅
    static let baseFishWidth: CGFloat = 30
    /// 段の名前。3本目の極と、そのあいだ（今↔将来なら「近いうち」）
    static func depthNames(_ axes: [Axis]) -> [String] {
        guard axes.count >= 3 else { return ["浅い", "あいだ", "深い"] }
        let near = axes[2].negativePole, far = axes[2].positivePole
        return [near, near == "今" ? "近いうち" : "あいだ", far]
    }

    // MARK: 描く

    /// 池の四角（極の札のぶん、上下を空ける）。デザインの 100×104 の枠に合わせた割合
    private func pondRect(_ size: CGSize) -> CGRect {
        let pad = min(size.height * 10 / 104, 32)
        return CGRect(x: size.width * 0.04, y: pad, width: size.width * 0.92, height: size.height - pad * 2)
    }

    /// 池の中の位置 → 画面の点
    private func screen(_ u: CGPoint, size: CGSize) -> CGPoint {
        let r = pondRect(size)
        return CGPoint(x: r.midX + u.x * size.width * 0.31,
                       y: r.midY - u.y * (r.height / 2 - 26) * 0.86)
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

    /// 浅い（今）ほど大きく、深い（将来）ほど小さい。3段
    private func fishWidth(_ step: Int) -> CGFloat { Self.baseFishWidth * Self.depthScales[max(0, min(2, step))] }

    /// 軸の端（矢印の先）
    private func axisEnds(_ size: CGSize) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let r = pondRect(size)
        return (size.width * 0.18, size.width * 0.82, r.minY + 7, r.maxY - 7)
    }

    private func drawPond(context: GraphicsContext, size: CGSize) {
        let ink = Theme.ink
        let rect = pondRect(size)
        let pond = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.15, style: .continuous)
        context.fill(pond, with: .color(Theme.water))
        // 網点の水（方眼にそろえた点）
        var dots = Path()
        var y = rect.minY + 3
        while y < rect.maxY {
            var x = rect.minX + 3
            while x < rect.maxX { dots.addRect(CGRect(x: x, y: y, width: 2.4, height: 2.4)); x += 7 }
            y += 7
        }
        var water = context
        water.clip(to: pond)
        water.fill(dots, with: .color(ink.opacity(0.13)))
        context.stroke(pond, with: .color(ink), lineWidth: Theme.stroke)

        let c = CGPoint(x: rect.midX, y: rect.midY)
        let e = axisEnds(size)

        if mode == .axis {
            // 2本の軸。両端に矢印、目盛り付き
            var lines = Path()
            var ticks = Path()
            var heads = Path()
            if axes.count >= 1 {
                lines.move(to: CGPoint(x: e.left + 6, y: c.y)); lines.addLine(to: CGPoint(x: e.right - 6, y: c.y))
                heads.addPath(arrowHead(at: CGPoint(x: e.left, y: c.y), dir: .left))
                heads.addPath(arrowHead(at: CGPoint(x: e.right, y: c.y), dir: .right))
                for t in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    for x in [c.x - (c.x - e.left) * t, c.x + (e.right - c.x) * t] {
                        ticks.move(to: CGPoint(x: x, y: c.y - 4)); ticks.addLine(to: CGPoint(x: x, y: c.y + 4))
                    }
                }
            }
            if axes.count >= 2 {
                lines.move(to: CGPoint(x: c.x, y: e.top + 6)); lines.addLine(to: CGPoint(x: c.x, y: e.bottom - 6))
                heads.addPath(arrowHead(at: CGPoint(x: c.x, y: e.top), dir: .up))
                heads.addPath(arrowHead(at: CGPoint(x: c.x, y: e.bottom), dir: .down))
                for t in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    for yy in [c.y - (c.y - e.top) * t, c.y + (e.bottom - c.y) * t] {
                        ticks.move(to: CGPoint(x: c.x - 4, y: yy)); ticks.addLine(to: CGPoint(x: c.x + 4, y: yy))
                    }
                }
            }
            context.stroke(lines, with: .color(ink), lineWidth: 2.5)
            context.stroke(ticks, with: .color(ink.opacity(0.6)), lineWidth: 1.5)
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

        // 深いものから順に描く（浅い金魚が手前）。持ち帰った金魚はいちばん下。選んだ金魚は最後
        let order = fish.sorted {
            ($0.item.id == selectedID ? 0 : 1, $0.done ? 1 : 0, $0.depth) > ($1.item.id == selectedID ? 0 : 1, $1.done ? 1 : 0, $1.depth)
        }
        for f in order {
            guard let (pos, right) = now[f.item.id] else { continue }
            let selected = f.item.id == selectedID
            let dim = selectedID != nil && !selected
            let w = fishWidth(f.step)
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
            if selected, mode == .axis, axes.count >= 2 {
                // 選んだ金魚から軸へ、紅い点線
                var cross = Path()
                cross.move(to: pos); cross.addLine(to: CGPoint(x: c.x, y: pos.y))
                cross.move(to: pos); cross.addLine(to: CGPoint(x: pos.x, y: c.y))
                g.stroke(cross, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, dash: [5.5, 4]))
                for q in [CGPoint(x: c.x, y: pos.y), CGPoint(x: pos.x, y: c.y)] {
                    g.fill(Path(ellipseIn: CGRect(x: q.x - 4.5, y: q.y - 4.5, width: 9, height: 9)), with: .color(accent))
                }
            }
            if selected {
                let d = max(w * 1.8, 50)
                let ring = Path(ellipseIn: CGRect(x: pos.x - d / 2, y: pos.y - d / 2, width: d, height: d))
                g.fill(ring, with: .color(surface))
                g.stroke(ring, with: .color(accent), lineWidth: 3)
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

    /// 矢印の先（p が先端）
    private func arrowHead(at p: CGPoint, dir: Dir) -> Path {
        let l: CGFloat = 13, w: CGFloat = 7.5
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
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ZStack {
                if axes.count >= 2 {
                    // 区画の名前（うすく、区画の真ん中に）
                    let top = rect.minY + rect.height * 0.14, bottom = rect.maxY - rect.height * 0.08
                    quadrant("\(axes[0].negativePole)・\(axes[1].positivePole)").position(x: size.width * 0.27, y: top)
                    quadrant("\(axes[0].positivePole)・\(axes[1].positivePole)").position(x: size.width * 0.73, y: top)
                    quadrant("\(axes[0].negativePole)・\(axes[1].negativePole)").position(x: size.width * 0.27, y: bottom)
                    quadrant("\(axes[0].positivePole)・\(axes[1].negativePole)").position(x: size.width * 0.73, y: bottom)

                    // 縦の軸の札：池の縁の外側に、縁に接して
                    poleLabel(axes[1].positivePole)
                        .frame(height: rect.minY, alignment: .bottom)
                        .position(x: c.x, y: rect.minY / 2)
                    poleLabel(axes[1].negativePole)
                        .frame(height: size.height - rect.maxY, alignment: .top)
                        .position(x: c.x, y: (rect.maxY + size.height) / 2)
                }
                if axes.count >= 1 {
                    HStack {
                        poleLabel(axes[0].negativePole)
                        Spacer()
                        poleLabel(axes[0].positivePole)
                    }
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: c.y)
                }
                // 選んだ金魚が、それぞれの軸のどちら寄りか
                if axes.count >= 2, let sel = fish.first(where: { $0.item.id == selectedID }) {
                    let p = screen(sel.u, size: size)
                    if abs(sel.u.x) >= 0.15 {
                        leanTag(sel.u.x < 0 ? axes[0].negativePole : axes[0].positivePole)
                            .position(x: p.x, y: c.y + (p.y > c.y ? -21 : 21))
                    }
                    if abs(sel.u.y) >= 0.15 {
                        let right = p.x > c.x
                        leanTag(sel.u.y > 0 ? axes[1].positivePole : axes[1].negativePole)
                            .frame(width: 160, alignment: right ? .trailing : .leading)
                            .position(x: right ? c.x - 7 - 80 : c.x + 7 + 80, y: p.y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func quadrant(_ text: String) -> some View {
        Text(text).font(.system(.caption, weight: .bold)).foregroundStyle(Theme.quiet)
            .opacity(selectedID == nil ? 1 : 0.4)
            .lineLimit(1).minimumScaleFactor(0.7)
            .fixedSize()
    }

    private func poleLabel(_ text: String) -> some View {
        Text(text).font(.system(.subheadline, weight: .black)).foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Capsule().fill(Theme.band))
            .fixedSize()
    }

    private func leanTag(_ pole: String) -> some View {
        Text("\(pole)寄り").font(.system(.footnote, weight: .black)).foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent))
            .fixedSize()
    }

    // MARK: 選ぶ

    private func tap(at point: CGPoint, size: CGSize, fish: [Placement]) {
        let time = Date.now.timeIntervalSinceReferenceDate
        var best: (Item, CGFloat)?
        for f in fish {
            let (pos, _) = swimming(f, size: size, time: time)
            let d = hypot(pos.x - point.x, pos.y - point.y)
            if d <= fishWidth(f.step) / 2 + 16, d < (best?.1 ?? .infinity) { best = (f.item, d) }
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
        .accessibilityLabel(axes.count >= 3 ? "池を横から見たところ。浅いほど\(axes[2].negativePole)、深いほど\(axes[2].positivePole)。金魚 \(items.count) 匹" : "池を横から見たところ")
    }

    /// 水の四角（上は水面）。左は深さの札、下は横の軸のぶん空ける
    private func waterRect(_ size: CGSize) -> CGRect {
        let top = max(22, size.height * 0.07)
        return CGRect(x: size.width * 0.22, y: top, width: size.width * 0.74, height: size.height - 38 - top)
    }

    /// 3つの層の境（水面、境1、境2、底）
    private func layerEdges(_ r: CGRect) -> [CGFloat] {
        [r.minY, r.minY + r.height * 0.325, r.minY + r.height * 0.65, r.maxY]
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    /// 水の形。上が波打つ水面、下の角は丸い
    private func waterShape(_ r: CGRect) -> Path {
        var p = Path()
        let period = r.width / 7.4, amp: CGFloat = r.height * 0.035
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        var x = r.minX, up = true
        while x + period <= r.maxX + 0.5 {
            p.addQuadCurve(to: CGPoint(x: x + period, y: r.minY), control: CGPoint(x: x + period / 2, y: r.minY + (up ? -amp : amp)))
            x += period; up.toggle()
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        let rad: CGFloat = 14
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let ink = Theme.ink, accent = Theme.accent
        let r = waterRect(size)
        let shape = waterShape(r)
        let edges = layerEdges(r)
        context.fill(shape, with: .color(Theme.water))
        // 3つの層。深いほど網点が大きく濃い
        var layered = context
        layered.clip(to: shape)
        let dot: [(CGFloat, Double)] = [(2.4, 0.14), (3.2, 0.24), (4, 0.38)]
        for i in 0..<3 {
            var dots = Path()
            var y = r.minY - 8 + 2
            while y < r.maxY {
                if y >= edges[i] - (i == 0 ? 10 : 0) && y < edges[i + 1] {
                    var x = r.minX + 2
                    while x < r.maxX { dots.addRect(CGRect(x: x, y: y, width: dot[i].0, height: dot[i].0)); x += 7 }
                }
                y += 7
            }
            layered.fill(dots, with: .color(ink.opacity(dot[i].1)))
        }
        var seams = Path()
        for y in edges[1...2] { seams.move(to: CGPoint(x: r.minX, y: y)); seams.addLine(to: CGPoint(x: r.maxX, y: y)) }
        layered.stroke(seams, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        context.stroke(shape, with: .color(ink), lineWidth: Theme.stroke)

        // 左の深さの矢印（下向き）
        let ax = size.width * 0.12
        var depthLine = Path()
        depthLine.move(to: CGPoint(x: ax, y: r.minY + 6)); depthLine.addLine(to: CGPoint(x: ax, y: r.maxY - 8))
        context.stroke(depthLine, with: .color(ink), lineWidth: 2.5)
        context.fill(arrow(CGPoint(x: ax, y: r.maxY + 2), dx: 0, dy: 1), with: .color(ink))

        // 下の横の軸（両端に矢印）
        let y = size.height - 26
        let x0 = size.width * 0.24, x1 = size.width * 0.94
        var axis = Path()
        axis.move(to: CGPoint(x: x0 + 6, y: y)); axis.addLine(to: CGPoint(x: x1 - 6, y: y))
        context.stroke(axis, with: .color(ink), lineWidth: 2.5)
        context.fill(arrow(CGPoint(x: x0, y: y), dx: -1, dy: 0), with: .color(ink))
        context.fill(arrow(CGPoint(x: x1, y: y), dx: 1, dy: 0), with: .color(ink))

        // 金魚。深さの段の層に、段の大きさで
        let sorted = items.sorted { score($0, 2) > score($1, 2) }
        for item in sorted {
            let s2 = score(item, 2)
            let step = PondMapView.depthStep(s2)
            let lo: Double = [-1, -0.33, 0.33][step], hi: Double = [-0.33, 0.33, 1][step]
            let frac = max(0, min(1, (s2 - lo) / (hi - lo)))
            let x = r.midX + score(item, 0) * (r.width / 2 - 28) * 0.9
            let py = edges[step] + (edges[step + 1] - edges[step]) * CGFloat(0.3 + 0.4 * frac)
            let w = PondMapView.baseFishWidth * PondMapView.depthScales[step]
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

    /// 矢印の先（p が先端、dx/dy が向き）
    private func arrow(_ p: CGPoint, dx: CGFloat, dy: CGFloat) -> Path {
        let l: CGFloat = 13, w: CGFloat = 7.5
        let back = CGPoint(x: p.x - dx * l, y: p.y - dy * l)
        var a = Path()
        a.move(to: p)
        a.addLine(to: CGPoint(x: back.x - dy * w, y: back.y - dx * w))
        a.addLine(to: CGPoint(x: back.x + dy * w, y: back.y + dx * w))
        a.closeSubpath()
        return a
    }

    @ViewBuilder private func labels(size: CGSize) -> some View {
        let r = waterRect(size)
        let edges = layerEdges(r)
        let pillWidth = size.width * 0.19
        ZStack {
            if axes.count >= 3 {
                let names = PondMapView.depthNames(axes)
                ForEach(0..<3, id: \.self) { i in
                    Text(names[i]).font(.system(.footnote, weight: .black))
                        .foregroundStyle(i == 1 ? Theme.ink : Color.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 4).padding(.vertical, 4)
                        .frame(width: pillWidth)
                        .background(Capsule().fill(i == 1 ? Theme.surface : Theme.band))
                        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: i == 1 ? 2 : 0))
                        .position(x: size.width * 0.10, y: (edges[i] + edges[i + 1]) / 2 - (i == 0 ? 4 : 0))
                }
            }
            if axes.count >= 1 {
                Group {
                    Text(axes[0].negativePole).position(x: size.width * 0.31, y: size.height - 8)
                    Text(axes[0].positivePole).position(x: size.width * 0.87, y: size.height - 8)
                }
                .font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
                .lineLimit(1)
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
