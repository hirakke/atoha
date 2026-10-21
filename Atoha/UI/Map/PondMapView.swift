import SwiftUI

/// 地図：上から見た池。金魚がどのあたりを泳いでいるかで、自分の軸が見える。
/// 軸のときは横＝1本目、縦＝2本目、3本目は深さ（浅い＝低い側の極、深い＝高い側の極）。
/// 深いところの金魚は小さく薄く、浅いところの金魚は大きくくっきり描く。
/// つながりのときは、意味の近いもの同士を寄せて点線で結ぶ。
struct PondMapView: View {
    let items: [Item]
    let axes: [Axis]
    let selectedID: UUID?
    var mode: MapMode = .axis
    let onSelect: (Item?) -> Void

    @State private var graph = PondGraph()

    var body: some View {
        GeometryReader { geo in
            // 深さの凡例を出すときは、そのぶん池を下げる
            let top: CGFloat = mode == .axis && axes.count >= 3 ? 40 : 0
            let size = CGSize(width: geo.size.width, height: max(1, geo.size.height - top))
            let fish = placements()
            VStack(spacing: 0) {
                if top > 0 {
                    HStack { Spacer(); depthLegend(axes[2]) }.frame(height: top, alignment: .top)
                }
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, canvas in
                        draw(context: context, size: canvas, fish: fish, time: t)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    tap(at: value.location, size: size, fish: fish)
                })
                .overlay { labels(size: size) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("池に \(items.count) 匹")
    }

    // MARK: 位置

    /// 1匹分の置き場所。u は池の中の位置（-1...1、上が +）、depth は 0（浅い）...1（深い）。
    struct Placement {
        let item: Item
        let u: CGPoint
        let depth: Double
        let tint: GoldfishTint
        let phase: Double
    }

    private func placements() -> [Placement] {
        let positions: [UUID: CGPoint]
        if mode == .graph {
            positions = graph.layout(items)
        } else {
            positions = Dictionary(uniqueKeysWithValues: items.map { item in
                (item.id, CGPoint(x: score(item, 0), y: score(item, 1)))
            })
        }
        return items.map { item in
            let depth = axes.count >= 3 ? (score(item, 2) + 1) / 2 : 0.25
            return Placement(item: item, u: positions[item.id] ?? .zero, depth: depth,
                             tint: GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust),
                             phase: Double(abs(item.id.hashValue % 6283)) / 1000)
        }
    }

    private func score(_ item: Item, _ i: Int) -> Double {
        guard i < axes.count, i < item.axisScores.count else { return 0 }
        return max(-1, min(1, item.axisScores[i]))
    }

    // MARK: 描く

    /// 池の形（正規化した座標をビューの大きさに合わせる）
    private func pondPath(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var path = Path()
        path.move(to: p(0.16, 0.21))
        path.addCurve(to: p(0.61, 0.09), control1: p(0.11, 0.11), control2: p(0.43, 0.05))
        path.addCurve(to: p(0.90, 0.46), control1: p(0.88, 0.12), control2: p(0.96, 0.29))
        path.addCurve(to: p(0.72, 0.89), control1: p(0.88, 0.64), control2: p(0.96, 0.80))
        path.addCurve(to: p(0.12, 0.77), control1: p(0.48, 0.97), control2: p(0.19, 0.93))
        path.addCurve(to: p(0.13, 0.43), control1: p(0.07, 0.64), control2: p(0.19, 0.54))
        path.addCurve(to: p(0.16, 0.21), control1: p(0.09, 0.34), control2: p(0.19, 0.29))
        path.closeSubpath()
        return path
    }

    /// 池の中の位置 → 画面の点
    private func screen(_ u: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + u.x * size.width * 0.33,
                y: size.height / 2 - u.y * size.height * 0.33)
    }

    /// 泳いでいる今の位置（もとの場所のまわりを、ゆっくり小さく回る）
    private func swimming(_ f: Placement, size: CGSize, time: Double) -> (CGPoint, facingRight: Bool) {
        let base = screen(f.u, size: size)
        let dx = sin(time * 0.35 + f.phase) * 9
        let dy = sin(time * 0.27 + f.phase * 1.7) * 5
        let vx = cos(time * 0.35 + f.phase)
        return (CGPoint(x: base.x + dx, y: base.y + dy), vx > 0)
    }

    private func fishWidth(_ depth: Double) -> CGFloat { CGFloat(30 - 16 * depth) }

    private func draw(context: GraphicsContext, size: CGSize, fish: [Placement], time: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let pond = pondPath(in: rect)
        context.fill(pond, with: .color(Theme.water))
        context.stroke(pond, with: .color(Theme.ink), lineWidth: 2)

        // 波紋
        var ripples = Path()
        for (fx, fy, w) in [(0.30, 0.18, 24.0), (0.66, 0.36, 28.0), (0.40, 0.78, 22.0)] {
            let x = size.width * fx, y = size.height * fy
            ripples.move(to: CGPoint(x: x, y: y))
            ripples.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - 6))
        }
        context.stroke(ripples, with: .color(Color(Theme.rippleUIColor).opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let now = Dictionary(uniqueKeysWithValues: fish.map { ($0.item.id, swimming($0, size: size, time: time)) })

        if mode == .axis {
            // 軸の点線（十字）
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var cross = Path()
            if axes.count >= 2 {
                cross.move(to: CGPoint(x: c.x, y: size.height * 0.1))
                cross.addLine(to: CGPoint(x: c.x, y: size.height * 0.9))
            }
            if axes.count >= 1 {
                cross.move(to: CGPoint(x: size.width * 0.1, y: c.y))
                cross.addLine(to: CGPoint(x: size.width * 0.9, y: c.y))
            }
            context.stroke(cross, with: .color(Theme.quiet), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
        } else {
            // つながり：近いもの同士の点線。選んだものの線は濃く
            for e in graph.edges {
                guard let a = now[e.a]?.0, let b = now[e.b]?.0 else { continue }
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                let lit = e.a == selectedID || e.b == selectedID
                context.stroke(line, with: .color(Theme.ink.opacity(lit ? 0.7 : 0.22)),
                               style: StrokeStyle(lineWidth: lit ? 1.5 : 1, dash: [3, 4]))
            }
        }

        // 深いものから順に描く（浅い金魚が手前）
        for f in fish.sorted(by: { $0.depth > $1.depth }) {
            guard let (pos, right) = now[f.item.id] else { continue }
            let selected = f.item.id == selectedID
            let w = fishWidth(f.depth) * (selected ? 1.25 : 1)
            let cell = w / CGFloat(GoldfishShape.width)
            let h = cell * CGFloat(GoldfishShape.height)
            let origin = CGPoint(x: pos.x - w / 2, y: pos.y - h / 2)
            var body = Path()
            for c in GoldfishShape.cells {
                // 絵は左向き。右へ泳ぐときは左右を反転する
                let x = right ? CGFloat(GoldfishShape.width - 1 - c.x) : CGFloat(c.x)
                body.addRect(CGRect(x: origin.x + x * cell, y: origin.y + CGFloat(c.y) * cell, width: cell, height: cell))
            }
            let opacity = selected ? 1 : 1 - 0.6 * f.depth
            context.fill(body, with: .color(f.tint.color.opacity(opacity)))
            if selected {
                let ring = CGRect(x: origin.x - 5, y: origin.y - 5, width: w + 10, height: h + 10)
                context.stroke(Path(ring), with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
    }

    // MARK: ラベル

    @ViewBuilder private func labels(size: CGSize) -> some View {
        if mode == .axis {
            ZStack {
                if axes.count >= 2 {
                    poleLabel(axes[1].positivePole).position(x: size.width / 2, y: size.height * 0.05)
                    poleLabel(axes[1].negativePole).position(x: size.width / 2, y: size.height * 0.95)
                }
                if axes.count >= 1 {
                    poleLabel(axes[0].negativePole).position(x: size.width * 0.07, y: size.height / 2 - 14)
                    poleLabel(axes[0].positivePole).position(x: size.width * 0.93, y: size.height / 2 - 14)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func poleLabel(_ text: String) -> some View {
        Text(text).font(Theme.sans(13, weight: .bold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 4)
            .background(Theme.paper.opacity(0.85))
    }

    /// 深さの凡例：浅い（低い側の極）→ 深い（高い側の極）
    private func depthLegend(_ axis: Axis) -> some View {
        HStack(spacing: 6) {
            Text("浅い（\(axis.negativePole)）")
            HStack(spacing: 3) {
                GoldfishMark(color: Theme.accent, width: 18)
                GoldfishMark(color: Theme.accent.opacity(0.6), width: 13)
                GoldfishMark(color: Theme.accent.opacity(0.3), width: 9)
            }
            Text("深い（\(axis.positivePole)）")
        }
        .font(Theme.sans(10, weight: .bold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
        .fixedSize()
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
        if let best { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.easeOut(duration: 0.2)) { onSelect(best?.0) }
    }

    /// 地図のカードに出す一言：どのあたりを泳いでいるか
    static func whereText(_ item: Item, axes: [Axis]) -> String? {
        var parts: [String] = []
        for (i, axis) in axes.prefix(2).enumerated() where i < item.axisScores.count {
            let s = item.axisScores[i]
            if abs(s) >= 0.2 { parts.append(s < 0 ? axis.negativePole : axis.positivePole) }
        }
        if axes.count >= 3, item.axisScores.count >= 3 {
            let s = item.axisScores[2]
            if s <= -0.2 { parts.append("浅いところ（\(axes[2].negativePole)）") }
            else if s >= 0.2 { parts.append("深いところ（\(axes[2].positivePole)）") }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "・") + " のあたりを泳いでいる"
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
