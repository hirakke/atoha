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

    /// 池の四角。枠いっぱいに描き、極の札は池の中に置く
    private func pondRect(_ size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: Theme.stroke / 2, dy: Theme.stroke / 2)
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
        let inset = r.width * 0.076
        return (r.minX + inset, r.maxX - inset, r.minY + 42, r.maxY - 42)
    }

    private func drawPond(context: GraphicsContext, size: CGSize) {
        let ink = Theme.ink
        let rect = pondRect(size)
        let pond = Path(roundedRect: rect, cornerRadius: 22, style: .continuous)
        context.fill(pond, with: .color(Theme.water))
        // 網点の水（7pt ごとに、互い違いの青い点）
        var dots = Path()
        var y = rect.minY + 2
        var row = 0
        while y < rect.maxY + 4 {
            var x = rect.minX + (row.isMultiple(of: 2) ? 2 : 5.5)
            while x < rect.maxX + 4 { dots.addEllipse(in: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)); x += 7 }
            y += 3.5
            row += 1
        }
        var water = context
        water.clip(to: pond)
        water.fill(dots, with: .color(Theme.waterDot.opacity(0.3)))
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
                    // 区画の名前（ごくうすく）
                    let top = rect.minY + rect.height * 0.25, bottom = rect.minY + rect.height * 0.78
                    quadrant("\(axes[0].negativePole)・\(axes[1].positivePole)").position(x: size.width * 0.25, y: top)
                    quadrant("\(axes[0].positivePole)・\(axes[1].positivePole)").position(x: size.width * 0.75, y: top)
                    quadrant("\(axes[0].negativePole)・\(axes[1].negativePole)").position(x: size.width * 0.25, y: bottom)
                    quadrant("\(axes[0].positivePole)・\(axes[1].negativePole)").position(x: size.width * 0.75, y: bottom)

                    // 縦の軸の札：池の中の上端と下端に
                    poleLabel(axes[1].positivePole).position(x: c.x, y: rect.minY + 22)
                    poleLabel(axes[1].negativePole).position(x: c.x, y: rect.maxY - 22)
                }
                if axes.count >= 1 {
                    // 横の軸の札：軸の線のすぐ下、池の左右の端に
                    HStack {
                        poleLabel(axes[0].negativePole)
                        Spacer()
                        poleLabel(axes[0].positivePole)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: c.y + 26)
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
        Text(text).font(.system(.footnote, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.28))
            .opacity(selectedID == nil ? 1 : 0.4)
            .lineLimit(1).minimumScaleFactor(0.7)
            .fixedSize()
    }

    private func poleLabel(_ text: String) -> some View {
        Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
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

/// 地図：池を傾けて見る。tilt 0＝上から、1＝横から（断面）。そのあいだは池を手前に倒した立体で描く。
/// 横＝1本目、水面の縦＝2本目、深さ（水面からの下向き）＝3本目。浅い＝低い側の極（今）、深い＝高い側の極（将来）。
/// tilt は animatableData なので、上から↔横からを切り替えると、毎フレームこの形のまま描き直される。
struct PondTiltView: View, Animatable {
    let items: [Item]
    var takenHome: [Item] = []
    let axes: [Axis]
    let selectedID: UUID?
    /// 0＝上から、1＝横から
    var tilt: Double
    let onSelect: (Item?) -> Void

    @Environment(\.colorScheme) private var scheme

    var animatableData: Double {
        get { tilt }
        set { tilt = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let proj = TiltProjection(size: size, tilt: tilt)
            let fish = placements(proj)
            let dark = scheme == .dark
            ZStack {
                PaperBackground(fullScreen: false)
                // 池・壁・軸は傾きが変わったときだけ描く（止まっているあいだは描き直さない）
                Canvas { context, _ in drawPond(context: context, proj: proj, dark: dark) }
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, _ in drawFish(context: context, proj: proj, fish: fish, time: t) }
                }
                // 枠（上からのときは水面の縁と重なる）
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: Theme.stroke)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                tap(at: value.location, proj: proj, fish: fish)
            })
            .overlay { labels(proj: proj, fish: fish) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if tilt >= 0.5 {
            return "池を横から見たところ。浅いほど\(axes[2].negativePole)、深いほど\(axes[2].positivePole)。金魚 \(items.count) 匹"
        }
        var s = "池を上から見たところ。金魚 \(items.count) 匹。横の軸は\(axes[0].negativePole)から\(axes[0].positivePole)、縦の軸は\(axes[1].positivePole)から\(axes[1].negativePole)。大きいほど\(axes[2].negativePole)"
        if !takenHome.isEmpty { s += "。持ち帰った金魚 \(takenHome.count) 匹" }
        return s
    }

    // MARK: 位置

    /// 1匹分の置き場所（池の座標。x＝横、y＝水面の縦（上が +）、z＝水面からの深さ）
    struct Fish {
        let item: Item
        let x: CGFloat
        let y: CGFloat
        let z: CGFloat
        let step: Int
        let tint: GoldfishTint
        let phase: Double
        let done: Bool
    }

    private func placements(_ p: TiltProjection) -> [Fish] {
        let doneIDs = Set(takenHome.map(\.id))
        return (items + takenHome).map { item in
            let s2 = score(item, 2)
            let step = PondMapView.depthStep(s2)
            // 段の層の中に収める（境をまたがない）
            let lo: Double = [-1, -0.33, 0.33][step], hi: Double = [-0.33, 0.33, 1][step]
            let frac = max(0, min(1, (s2 - lo) / (hi - lo)))
            return Fish(item: item,
                        x: score(item, 0) * (2 * p.w + Theme.stroke) * 0.31,
                        y: score(item, 1) * (p.h - 26) * 0.86,
                        // いちばん深い層は、底の軸と重ならないよう少し浅めに
                        z: p.depth * CGFloat(Double(step) + 0.2 + (step == 2 ? 0.45 : 0.6) * frac) / 3,
                        step: step,
                        tint: GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust),
                        phase: Double(abs(item.id.hashValue % 6283)) / 1000,
                        done: doneIDs.contains(item.id))
        }
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    /// 泳いでいる今の位置（水面の上でゆっくり小さく回る）。選んだ金魚は止める
    private func swimming(_ f: Fish, time: Double) -> (x: CGFloat, y: CGFloat, facingRight: Bool) {
        if f.item.id == selectedID { return (f.x, f.y, false) }
        let dx = sin(time * 0.35 + f.phase) * 8
        let dy = sin(time * 0.27 + f.phase * 1.7) * 4
        return (f.x + dx, f.y + dy, cos(time * 0.35 + f.phase) > 0)
    }

    /// 金魚の画面の位置・水面の印の位置・大きさ
    private func projected(_ f: Fish, proj: TiltProjection, time: Double) -> (pos: CGPoint, spot: CGPoint, width: CGFloat, dep: CGFloat, right: Bool) {
        let s = swimming(f, time: time)
        // 横から近くでは、手前の面（断面）へ寄せる。層の帯と金魚の深さがずれないように
        let y = s.y + (-proj.h - s.y) * proj.section
        // 上からのときは水面に浮かせ、傾けるにつれて深さへ沈める
        let fish = proj(s.x, y, f.z * proj.sink)
        let spot = proj(s.x, y, 0)
        let w = fishWidth(f.step) * fish.k
        return (fish.point, spot.point, w, fish.dep, s.facingRight)
    }

    /// 金魚の幅（遠近をかける前）。地図の上からより少し大きく。深いほど小さい
    static let fishScale: CGFloat = 1.35
    private func fishWidth(_ step: Int) -> CGFloat {
        PondMapView.baseFishWidth * PondMapView.depthScales[max(0, min(2, step))] * Self.fishScale
    }

    // MARK: 描く（池・壁・軸）

    private func drawPond(context: GraphicsContext, proj p: TiltProjection, dark: Bool) {
        let ink = Theme.ink
        let deg = p.degrees
        let sc = p.unit
        let thirds = [0, p.depth / 3, p.depth * 2 / 3, p.depth]
        func line(_ pts: [CGPoint], close: Bool) -> Path {
            var path = Path()
            path.addLines(pts)
            if close { path.closeSubpath() }
            return path
        }

        if deg > 0.5 {
            // 奥の見えない辺（うすい点線）
            if deg < 89.5 {
                var hidden = Path()
                for (a, b) in [((-p.w, p.h, 0), (-p.w, p.h, p.depth)), ((p.w, p.h, 0), (p.w, p.h, p.depth)),
                               ((-p.w, p.h, p.depth), (p.w, p.h, p.depth)), ((-p.w, -p.h, p.depth), (-p.w, p.h, p.depth)),
                               ((p.w, -p.h, p.depth), (p.w, p.h, p.depth))] as [((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] {
                    hidden.move(to: p(a.0, a.1, a.2).point); hidden.addLine(to: p(b.0, b.1, b.2).point)
                }
                context.stroke(hidden, with: .color(ink.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
            }
            // 手前の壁。3つの層（深いほど網点が濃い）
            let outlines = thirds.map { z in p.frontOutline(z: z).map { p($0.0, $0.1, $0.2).point } }
            for i in 0..<3 {
                let band = line(outlines[i] + outlines[i + 1].reversed(), close: true)
                context.fill(band, with: WaterTile.shading(i, dark: dark))
            }
            for i in 1...2 {
                context.stroke(line(outlines[i], close: false), with: .color(ink.opacity(0.55)), lineWidth: 1.5)
                if p.section < 0.99 {
                    // 層の境の面（池の中の点線）。横から近くでは消していく
                    let plane = p.surfaceOutline(z: thirds[i]).map { p($0.0, $0.1, $0.2).point }
                    context.stroke(line(plane, close: true), with: .color(Theme.waterDot.opacity(0.45 * (1 - p.section))),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                }
            }
            let wall = line(outlines[0] + outlines[3].reversed(), close: true)
            context.stroke(wall, with: .color(ink), style: StrokeStyle(lineWidth: Theme.stroke, lineJoin: .round))

            // 横から近くでは、手前の面（断面）を上に重ねていく。池のほかの部分はすべてこの面の内側に入るので、
            // 90° では、3つの層・層の境の点線・波の水面だけのすっきりした断面になる
            if p.section > 0.01 {
                var face = context
                face.opacity = p.section
                let corners = thirds.map { z in (p(-p.w, -p.h, z).point, p(p.w, -p.h, z).point) }
                for i in 0..<3 {
                    let band = line([corners[i].0, corners[i].1, corners[i + 1].1, corners[i + 1].0], close: true)
                    face.fill(band, with: WaterTile.shading(i, dark: dark))
                }
                var seps = Path()
                for i in 1...2 { seps.move(to: corners[i].0); seps.addLine(to: corners[i].1) }
                face.stroke(seps, with: .color(ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                // 水面の、ゆるい波の線
                let wz = 14 * sc, amp = 3.5 * sc
                let n = 48
                var wave = Path()
                for j in 0...n {
                    let u = CGFloat(j) / CGFloat(n)
                    let x = -p.w + 2 * p.w * u
                    let pt = p(x, -p.h, wz).point
                    let q = CGPoint(x: pt.x, y: pt.y + amp * sin(u * .pi * 2 * 4.5))
                    if j == 0 { wave.move(to: q) } else { wave.addLine(to: q) }
                }
                face.stroke(wave, with: .color(ink.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        // 水面
        if deg < 89.5 {
            let surface = line(p.surfaceOutline(z: 0).map { p($0.0, $0.1, $0.2).point }, close: true)
            var water = context
            water.opacity = deg < 0.5 ? 1 : 0.92
            water.fill(surface, with: WaterTile.shading(0, dark: dark))
            if deg > 0.5 {
                context.stroke(surface, with: .color(ink), style: StrokeStyle(lineWidth: Theme.stroke, lineJoin: .round))
            }
        }

        // 水面の2本の軸。横から近くでは消し、かわりに底の横の軸を出す
        var lines = Path(), ticks = Path(), heads = Path()
        func axis(_ a: CGPoint, _ b: CGPoint) {
            lines.move(to: a); lines.addLine(to: b)
            if hypot(b.x - a.x, b.y - a.y) > 30 {
                heads.addPath(arrowHead(from: b, toward: a))
                heads.addPath(arrowHead(from: a, toward: b))
            }
        }
        let surfaceAxes = 1 - ramp(deg, 76, 88)
        if surfaceAxes > 0 {
            let xEnd = p.w * 0.848, yEnd = p.h - 42
            axis(p(-xEnd, 0, 0).point, p(xEnd, 0, 0).point)
            axis(p(0, -yEnd, 0).point, p(0, yEnd, 0).point)
            for t in [CGFloat(1) / 3, CGFloat(2) / 3] {
                for x in [-xEnd * t, xEnd * t] { ticks.move(to: p(x, 4, 0).point); ticks.addLine(to: p(x, -4, 0).point) }
                for y in [-yEnd * t, yEnd * t] { ticks.move(to: p(-4, y, 0).point); ticks.addLine(to: p(4, y, 0).point) }
            }
            var g = context
            g.opacity = surfaceAxes
            g.stroke(lines, with: .color(ink), lineWidth: 2.5)
            g.stroke(ticks, with: .color(ink.opacity(0.6)), lineWidth: 1.5)
            g.fill(heads, with: .color(ink))
        }
        let bottomAxis = ramp(deg, 78, 90)
        if bottomAxis > 0 {
            lines = Path(); heads = Path()
            let z = p.depth - 24 * sc
            axis(p(-p.w * 0.656, -p.h, z).point, p(p.w * 0.656, -p.h, z).point)
            var g = context
            g.opacity = bottomAxis
            g.stroke(lines, with: .color(ink), lineWidth: 2.5)
            g.fill(heads, with: .color(ink))
        }
    }

    // MARK: 描く（金魚）

    private func drawFish(context: GraphicsContext, proj p: TiltProjection, fish: [Fish], time: Double) {
        let ink = Theme.ink, accent = Theme.accent, surface = Theme.surface
        let shown = fish.map { ($0, projected($0, proj: p, time: time)) }

        // 水面の印から深さまでの、下げ糸（点線）と波紋。上からのときは金魚と重なるので出さない
        // 横から近くでは消していく（断面の絵には出さない）
        let sink = p.sink * (1 - p.section)
        if sink > 0.02 {
            var plumbs = Path(), rings = Path(), cores = Path(), flats = Path()
            let r1 = 15 * p.unit, r2 = 7 * p.unit
            for (f, s) in shown {
                if hypot(s.pos.x - s.spot.x, s.pos.y - s.spot.y) > 3 { plumbs.move(to: s.spot); plumbs.addLine(to: s.pos) }
                let sw = swimming(f, time: time)
                let ring1 = (0..<20).map { i -> CGPoint in
                    let a = Double(i) / 20 * 2 * .pi
                    return p(sw.x + r1 * cos(a), sw.y + r1 * sin(a), 0).point
                }
                let ys = ring1.map(\.y)
                if (ys.max()! - ys.min()!) < 1.2 {
                    // 真横からは、水面の短い線
                    let xs = ring1.map(\.x)
                    flats.move(to: CGPoint(x: xs.min()!, y: s.spot.y)); flats.addLine(to: CGPoint(x: xs.max()!, y: s.spot.y))
                } else {
                    rings.addLines(ring1); rings.closeSubpath()
                    let ring2 = (0..<20).map { i -> CGPoint in
                        let a = Double(i) / 20 * 2 * .pi
                        return p(sw.x + r2 * cos(a), sw.y + r2 * sin(a), 0).point
                    }
                    cores.addLines(ring2); cores.closeSubpath()
                }
            }
            var g = context
            g.opacity = sink
            g.stroke(plumbs, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
            g.stroke(rings, with: .color(ink.opacity(0.5)), lineWidth: 1.5)
            g.fill(cores, with: .color(ink.opacity(0.18)))
            g.stroke(flats, with: .color(ink.opacity(0.45)), lineWidth: 2.5)
        }

        // 遠いものから順に描く（手前の金魚が上）。持ち帰った金魚はいちばん下。選んだ金魚は最後
        let order = shown.sorted {
            ($0.0.item.id == selectedID ? 0 : 1, $0.0.done ? 1 : 0, $0.1.dep) > ($1.0.item.id == selectedID ? 0 : 1, $1.0.done ? 1 : 0, $1.1.dep)
        }
        let flat = max(0, 1 - tilt * 8)  // 上からのときだけの印（選んだ金魚から軸への点線）
        let center = p(0, 0, 0).point
        for (f, s) in order {
            let pos = s.pos, right = s.right, w = s.width
            let selected = f.item.id == selectedID
            let dim = selectedID != nil && !selected
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
            if selected, flat > 0 {
                // 選んだ金魚から軸へ、紅い点線
                var cross = Path()
                cross.move(to: pos); cross.addLine(to: CGPoint(x: center.x, y: pos.y))
                cross.move(to: pos); cross.addLine(to: CGPoint(x: pos.x, y: center.y))
                var c = g
                c.opacity *= flat
                c.stroke(cross, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, dash: [5.5, 4]))
                for q in [CGPoint(x: center.x, y: pos.y), CGPoint(x: pos.x, y: center.y)] {
                    c.fill(Path(ellipseIn: CGRect(x: q.x - 4.5, y: q.y - 4.5, width: 9, height: 9)), with: .color(accent))
                }
            }
            if selected {
                let k = w / fishWidth(f.step)
                let d = max(w * 1.8, 50 * min(1, k))
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

    /// 矢印の先（tip が先端、from の側から向かう）
    private func arrowHead(from: CGPoint, toward tip: CGPoint) -> Path {
        let l: CGFloat = 13, w: CGFloat = 7.5
        let len = max(hypot(tip.x - from.x, tip.y - from.y), 0.001)
        let ux = (tip.x - from.x) / len, uy = (tip.y - from.y) / len
        let back = CGPoint(x: tip.x - ux * l, y: tip.y - uy * l)
        var a = Path()
        a.move(to: tip)
        a.addLine(to: CGPoint(x: back.x - uy * w, y: back.y + ux * w))
        a.addLine(to: CGPoint(x: back.x + uy * w, y: back.y - ux * w))
        a.closeSubpath()
        return a
    }

    /// a 度から b 度のあいだで 0→1
    private func ramp(_ deg: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (deg - a) / (b - a))) }

    // MARK: ラベル

    @ViewBuilder private func labels(proj p: TiltProjection, fish: [Fish]) -> some View {
        let deg = p.degrees
        let flat = max(0, 1 - tilt * 5)
        let size = p.size
        let c = p(0, 0, 0).point
        ZStack {
            if flat > 0 {
                // 区画の名前（ごくうすく）。上からのときだけ
                let top = size.height * 0.25, bottom = size.height * 0.78
                Group {
                    quadrant("\(axes[0].negativePole)・\(axes[1].positivePole)").position(x: size.width * 0.25, y: top)
                    quadrant("\(axes[0].positivePole)・\(axes[1].positivePole)").position(x: size.width * 0.75, y: top)
                    quadrant("\(axes[0].negativePole)・\(axes[1].negativePole)").position(x: size.width * 0.25, y: bottom)
                    quadrant("\(axes[0].positivePole)・\(axes[1].negativePole)").position(x: size.width * 0.75, y: bottom)
                }
                .opacity(flat)
            }

            // 縦の軸の札：水面の上端と下端に。傾けると奥へ小さくなり、横から近くで消える
            let vertical = deg <= 50 ? 1 : deg <= 70 ? 1 - 0.25 * (deg - 50) / 20 : max(0, 0.75 * (1 - (deg - 70) / 15))
            if vertical > 0 {
                let t = p(0, p.h - 22, 0), b = p(0, -(p.h - 22), 0)
                poleLabel(axes[1].positivePole).scaleEffect(min(t.k, 1)).position(t.point).opacity(vertical)
                poleLabel(axes[1].negativePole).scaleEffect(min(b.k, 1)).position(b.point).opacity(vertical)
            }
            // 横の軸の札：水面の左右の端、軸のすぐ下
            let horizontal = 1 - ramp(deg, 75, 88)
            if horizontal > 0 {
                let l = p(-(p.w - 6.5), -26, 0), r = p(p.w - 6.5, -26, 0)
                poleLabel(axes[0].negativePole).scaleEffect(min(l.k, 1), anchor: .leading)
                    .frame(width: 200, alignment: .leading).position(x: l.point.x + 100, y: l.point.y)
                    .opacity(horizontal)
                poleLabel(axes[0].positivePole).scaleEffect(min(r.k, 1), anchor: .trailing)
                    .frame(width: 200, alignment: .trailing).position(x: r.point.x - 100, y: r.point.y)
                    .opacity(horizontal)
            }
            // 横からの横の軸の札：底の軸の上に
            let bottom = ramp(deg, 78, 90)
            if bottom > 0 {
                let z = p.depth - 24 * p.unit
                let l = p(-p.w * 0.81, -p.h, z).point, r = p(p.w * 0.81, -p.h, z).point
                poleLabel(axes[0].negativePole).position(x: l.x + 6, y: l.y - 22).opacity(bottom)
                poleLabel(axes[0].positivePole).position(x: r.x - 6, y: r.y - 22).opacity(bottom)
            }
            // 深さの3つの層の札：手前の壁の左に
            let layers = ramp(deg, 35, 50)
            if layers > 0 {
                let names = PondMapView.depthNames(axes)
                ForEach(0..<3, id: \.self) { i in
                    let q = p(-p.w + 40 * p.unit, -p.h, p.depth * (CGFloat(i) + 0.5) / 3)
                    layerLabel(names[i], filled: i != 1).scaleEffect(min(q.k, 1)).position(q.point).opacity(layers)
                }
            }
            // 選んだ金魚が、それぞれの軸のどちら寄りか（上からのときだけ）
            if flat > 0, let sel = fish.first(where: { $0.item.id == selectedID }) {
                let q = p(sel.x, sel.y, 0).point
                let ux = score(sel.item, 0), uy = score(sel.item, 1)
                Group {
                    if abs(ux) >= 0.15 {
                        leanTag(ux < 0 ? axes[0].negativePole : axes[0].positivePole)
                            .position(x: q.x, y: c.y + (q.y > c.y ? -21 : 21))
                    }
                    if abs(uy) >= 0.15 {
                        let right = q.x > c.x
                        leanTag(uy > 0 ? axes[1].positivePole : axes[1].negativePole)
                            .frame(width: 160, alignment: right ? .trailing : .leading)
                            .position(x: right ? c.x - 7 - 80 : c.x + 7 + 80, y: q.y)
                    }
                }
                .opacity(flat)
            }
        }
        .allowsHitTesting(false)
    }

    private func quadrant(_ text: String) -> some View {
        Text(text).font(.system(.footnote, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.28))
            .opacity(selectedID == nil ? 1 : 0.4)
            .lineLimit(1).minimumScaleFactor(0.7)
            .fixedSize()
    }

    private func poleLabel(_ text: String) -> some View {
        Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
            .fixedSize()
    }

    /// 層の札。いちばん浅い層（今）といちばん深い層（将来）は紺で塗り、まんなかは白に紺の縁
    private func layerLabel(_ text: String, filled: Bool) -> some View {
        Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(filled ? Color.white : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(filled ? Theme.band : Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
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

    private func tap(at point: CGPoint, proj: TiltProjection, fish: [Fish]) {
        let time = Date.now.timeIntervalSinceReferenceDate
        var best: (Item, CGFloat)?
        for f in fish {
            let s = projected(f, proj: proj, time: time)
            let d = hypot(s.pos.x - point.x, s.pos.y - point.y)
            if d <= s.width / 2 + 16, d < (best?.1 ?? .infinity) { best = (f.item, d) }
        }
        if best != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.easeOut(duration: 0.2)) { onSelect(best?.0) }
    }
}

/// 池を手前に倒して見るための投影。水面の中心を原点に、x＝右、y＝奥（上から見たときの上）、z＝下（深さ）。
/// x 軸のまわりに θ 回して、カメラから見た高さ up と奥行き dep にし、遠近（k＝f / (d + dep)）をかける。
/// カメラの距離 d は、池（水面と底の8つの角）がちょうど収まるように θ ごとに決める。
struct TiltProjection {
    let size: CGSize
    /// 水面の半分の幅・高さと、深さ（上から見たとき枠いっぱい）
    let w: CGFloat, h: CGFloat, depth: CGFloat
    /// デザイン（高さ470）の 1px にあたる長さ
    let unit: CGFloat
    let degrees: Double
    /// 金魚が深さへ沈む割合（上から 0 → 30° で 1）
    let sink: CGFloat
    /// 横からの断面へ寄せる割合（67.5° で 0 → 90° で 1）。下げ糸や層の境の面を消し、手前の面だけの絵にする
    let section: CGFloat
    private let f: CGFloat, d: CGFloat, ox: CGFloat, oy: CGFloat, cosT: CGFloat, sinT: CGFloat

    init(size: CGSize, tilt: Double) {
        self.size = size
        let inset = Theme.stroke / 2
        let vw = max(size.width - 2 * inset, 10), vh = max(size.height - 2 * inset, 10)
        w = vw / 2; h = vh / 2; depth = vh
        unit = vh / 470
        f = 600 * unit
        let t = max(0, min(1, tilt))
        degrees = t * 90
        let th = t * .pi / 2
        cosT = cos(th); sinT = sin(th)
        let s = max(0, min(1, degrees / 30))
        sink = s * s * (3 - 2 * s)
        let e = max(0, min(1, (t - 0.75) / 0.25))
        section = e * e * (3 - 2 * e)
        // 途中は余白をとる（上から・横からはぴったり）
        let m = min(1, sin(2 * th) * 1.6)
        let mx = 22 * unit * m, mt = 34 * unit * m, mb = 22 * unit * m
        let (w, h, depth, f, c, sn) = (w, h, depth, f, cosT, sinT)
        func bounds(_ d: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
            for x in [-w, w] { for y in [-h, h] { for z in [0, depth] {
                let k = f / max(d + y * sn + z * c, 1)
                let sx = x * k, sy = -(y * c - z * sn) * k
                x0 = min(x0, sx); x1 = max(x1, sx); y0 = min(y0, sy); y1 = max(y1, sy)
            } } }
            return (x0, x1, y0, y1)
        }
        var lo = f * 0.5, hi = f * 12
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let b = bounds(mid)
            if b.1 - b.0 <= vw - 2 * mx + 0.01 && b.3 - b.2 <= vh - mt - mb + 0.01 { hi = mid } else { lo = mid }
        }
        d = hi
        let b = bounds(hi)
        ox = inset + mx + (vw - 2 * mx - (b.1 - b.0)) / 2 - b.0
        oy = inset + mt + (vh - mt - mb - (b.3 - b.2)) / 2 - b.2
    }

    /// 池の点 → 画面の点と、遠近の倍率 k、奥行き dep
    func callAsFunction(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> (point: CGPoint, k: CGFloat, dep: CGFloat) {
        let up = y * cosT - z * sinT
        let dep = y * sinT + z * cosT
        let k = f / max(d + dep, 1)
        return (CGPoint(x: ox + x * k, y: oy - up * k), k, dep)
    }

    /// 深さ z の角の丸い四角（水面・層の境の面）
    func surfaceOutline(z: CGFloat, r: CGFloat = 22, n: Int = 6) -> [(CGFloat, CGFloat, CGFloat)] {
        var pts: [(CGFloat, CGFloat, CGFloat)] = []
        for (cx, cy, a0) in [(w - r, h - r, 0.0), (-(w - r), h - r, 90.0), (-(w - r), -(h - r), 180.0), (w - r, -(h - r), 270.0)] {
            for i in 0...n {
                let a = (a0 + 90 * Double(i) / Double(n)) * .pi / 180
                pts.append((cx + r * cos(a), cy + r * sin(a), z))
            }
        }
        return pts
    }

    /// 深さ z の手前半分の縁（右の辺の中ほど → 手前の辺 → 左の辺の中ほど）。手前の壁の上下の線
    func frontOutline(z: CGFloat, r: CGFloat = 22, n: Int = 6) -> [(CGFloat, CGFloat, CGFloat)] {
        var pts: [(CGFloat, CGFloat, CGFloat)] = [(w, 0, z)]
        for i in 0...n {
            let a = -90 * Double(i) / Double(n) * .pi / 180
            pts.append((w - r + r * cos(a), -(h - r) + r * sin(a), z))
        }
        for i in 0...n {
            let a = (270 - 90 * Double(i) / Double(n)) * .pi / 180
            pts.append((-(w - r) + r * cos(a), -(h - r) + r * sin(a), z))
        }
        pts.append((-w, 0, z))
        return pts
    }
}

/// 水の網点の1枚（0＝水面・今、1＝近いうち、2＝将来。深いほど点が大きく濃い）。一度だけ作って敷き詰める
@MainActor
enum WaterTile {
    private static var cache: [Int: Image] = [:]

    static func shading(_ level: Int, dark: Bool) -> GraphicsContext.Shading {
        let key = level * 2 + (dark ? 1 : 0)
        let image = cache[key] ?? make(level, dark: dark)
        cache[key] = image
        // 上から見たときの網点（7pt ごとの互い違い）と目をそろえる
        return .tiledImage(image, origin: CGPoint(x: Theme.stroke / 2, y: Theme.stroke / 2))
    }

    private static func make(_ level: Int, dark: Bool) -> Image {
        let period: [CGFloat] = [7, 6, 5], radius: [CGFloat] = [1.3, 1.6, 1.6], alpha: [CGFloat] = [0.3, 0.42, 0.58]
        let bg: [UInt32] = dark ? [0x1C2440, 0x222C4E, 0x29355D] : [0xEEF4FF, 0xE3ECFD, 0xD6E2FB]
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let dot = Theme.waterDotUIColor.resolvedColor(with: traits).withAlphaComponent(alpha[level])
        let p = period[level], r = radius[level]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let ui = UIGraphicsImageRenderer(size: CGSize(width: p, height: p), format: format).image { ctx in
            UIColor(hex: bg[level]).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: p, height: p))
            dot.setFill()
            let a: CGFloat = level == 0 ? 2 / 7 : 0.25, b: CGFloat = level == 0 ? 5.5 / 7 : 0.75
            for c in [CGPoint(x: p * a, y: p * a), CGPoint(x: p * b, y: p * b)] {
                ctx.cgContext.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
        }
        return Image(uiImage: ui)
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
