import SwiftUI

/// 四角いドットの金魚の形（横9×縦5マス、頭が左）。画面の印と水槽の3Dで同じ形を使う。
enum GoldfishShape {
    static let width = 9
    static let height = 5
    /// 塗るマス（x, y）
    static let cells: [(x: Int, y: Int)] = {
        let rows: [String] = [
            "..XXX....",
            ".XXXXX.XX",
            "XXXXXXXX.",
            ".XXXXX.XX",
            "..XXX....",
        ]
        var out: [(x: Int, y: Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "X" { out.append((x, y)) }
        }
        return out
    }()

    /// 中のマス（両方・持ち帰ったで塗り分ける）
    static let holeCells: [(x: Int, y: Int)] = [(2, 1), (3, 1), (4, 1), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (2, 3), (3, 3), (4, 3)]

    /// 点線の輪郭（稚魚）
    static let dottedCells: [(x: Int, y: Int)] = [(2, 0), (4, 0), (1, 1), (5, 1), (8, 1), (0, 2), (7, 2), (1, 3), (5, 3), (8, 3), (2, 4), (4, 4)]

    /// 輪郭のマス（上下左右のどれかが空いているマス）
    static let edgeCells: [(x: Int, y: Int)] = {
        let filled = Set(cells.map { $0.y * 100 + $0.x })
        return cells.filter { c in
            [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in !filled.contains((c.y + d.1) * 100 + c.x + d.0) }
        }
    }()
}

/// 金魚の色。やりたい・やらなきゃの2つの強さから4通りに描き分ける。
/// やりたい＝紅、やらなきゃ＝藍、両方＝藍の縁で中が紅、どちらでもない＝薄い藍。
enum GoldfishTint {
    case red, black, both, faint

    var color: Color {
        switch self {
        case .red, .both: Theme.accent
        case .black: Theme.ink
        case .faint: Theme.ink.opacity(0.3)
        }
    }

    var uiColor: UIColor {
        switch self {
        case .red, .both: Theme.accentUIColor
        case .black: Theme.inkUIColor
        case .faint: Theme.inkUIColor.withAlphaComponent(0.3)
        }
    }

    /// 本人の評価（未評価なら AI の仮の値）から色を決める。
    static func of(want: Double, must: Double) -> GoldfishTint {
        switch (want >= 0.5, must >= 0.5) {
        case (true, true): .both
        case (true, false): .red
        case (false, true): .black
        case (false, false): .faint
        }
    }

    var label: String {
        switch self {
        case .red: "やりたい"
        case .black: "やらなきゃ"
        case .both: "両方"
        case .faint: "どちらでもない"
        }
    }
}

/// 画面の印としての金魚。
struct GoldfishMark: View {
    enum Style {
        /// 1色で塗る
        case solid
        /// 藍の縁で中が紅（やりたい・やらなきゃの両方）
        case both
        /// 線の輪郭で中が白（持ち帰った）
        case takenHome
        /// 点線の輪郭（稚魚：まだやりたい・やらなきゃを決めていない）
        case fry
    }

    var color: Color
    var style: Style = .solid
    /// 横幅（縦は 5/9）
    var width: CGFloat = 18

    init(color: Color, style: Style = .solid, width: CGFloat = 18) {
        self.color = color
        self.style = style
        self.width = width
    }

    /// 評価の色から描く
    init(tint: GoldfishTint, width: CGFloat = 18) {
        self.init(color: tint == .both ? Theme.ink : tint.color, style: tint == .both ? .both : .solid, width: width)
    }

    var body: some View {
        let style = style, color = color
        let accent = Theme.accent, surface = Theme.surface
        Canvas { context, size in
            let cell = size.width / CGFloat(GoldfishShape.width)
            func path(_ cells: [(x: Int, y: Int)]) -> Path {
                var p = Path()
                for c in cells { p.addRect(CGRect(x: CGFloat(c.x) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell)) }
                return p
            }
            switch style {
            case .solid:
                context.fill(path(GoldfishShape.cells), with: .color(color))
            case .both:
                context.fill(path(GoldfishShape.cells), with: .color(color))
                context.fill(path(GoldfishShape.holeCells), with: .color(accent))
            case .takenHome:
                context.fill(path(GoldfishShape.cells), with: .color(color))
                context.fill(path(GoldfishShape.holeCells), with: .color(surface))
            case .fry:
                context.fill(path(GoldfishShape.dottedCells), with: .color(color))
            }
        }
        .frame(width: width, height: width * CGFloat(GoldfishShape.height) / CGFloat(GoldfishShape.width))
        .accessibilityHidden(true)
    }
}

/// お椀。今に入っている数を見せる（filled なら金魚が1匹入っている）。
struct BowlIcon: View {
    var filled: Bool
    var width: CGFloat = 24
    /// 藍の札の上に置く（白い線、入っていれば紅い水）
    var onDark = false
    /// 空のときに中を塗らない（紙の上に縁だけ）
    var hollow = false

    /// ドットのお椀（横12×縦6マス）。縁と、金魚が入っているときの紅い水
    static let rim: [(x: Int, y: Int, w: Int)] = [(0, 0, 12), (0, 1, 1), (11, 1, 1), (1, 2, 1), (10, 2, 1), (1, 3, 1), (10, 3, 1), (2, 4, 1), (9, 4, 1), (3, 5, 6)]
    static let water: [(x: Int, y: Int, w: Int)] = [(1, 1, 10), (2, 2, 8), (2, 3, 8), (3, 4, 6)]

    var body: some View {
        let line = onDark ? Color.white : Theme.ink
        let fill = filled ? Theme.accent : (onDark || hollow ? Color.clear : Theme.surface)
        Canvas { context, size in
            let cell = size.width / 12
            func path(_ runs: [(x: Int, y: Int, w: Int)]) -> Path {
                var p = Path()
                for r in runs { p.addRect(CGRect(x: CGFloat(r.x) * cell, y: CGFloat(r.y) * cell, width: CGFloat(r.w) * cell, height: cell)) }
                return p
            }
            context.fill(path(Self.water), with: .color(fill))
            context.fill(path(Self.rim), with: .color(line))
        }
        .frame(width: width, height: width / 2)
        .accessibilityHidden(true)
    }
}

/// 水だけが入った大きなお椀（今がからっぽのとき）。薄い水色に青の網点、上に水面の線。
struct WaterBowl: View {
    var width: CGFloat = 168

    var body: some View {
        let ink = Theme.ink, dot = Theme.waterDot
        Canvas { context, size in
            let cell = size.width / 12
            func path(_ runs: [(x: Int, y: Int, w: Int)]) -> Path {
                var p = Path()
                for r in runs { p.addRect(CGRect(x: CGFloat(r.x) * cell, y: CGFloat(r.y) * cell, width: CGFloat(r.w) * cell, height: cell)) }
                return p
            }
            let water = path(BowlIcon.water)
            context.fill(water, with: .color(Theme.water))
            // 網点（6pt おきに互い違い）。水の形で切り抜く
            context.drawLayer { layer in
                layer.clip(to: water)
                var dots = Path()
                let step = size.width / 28
                var y = step / 4, row = 0
                while y < size.height {
                    var x = row.isMultiple(of: 2) ? step / 4 : step * 0.75
                    while x < size.width {
                        dots.addEllipse(in: CGRect(x: x - step / 6, y: y - step / 6, width: step / 3, height: step / 3))
                        x += step
                    }
                    y += step / 2
                    row += 1
                }
                layer.fill(dots, with: .color(dot.opacity(0.3)))
            }
            // 水面の線
            context.fill(Path(CGRect(x: 2 * cell, y: cell, width: 8 * cell, height: cell * 0.34)), with: .color(dot.opacity(0.55)))
            context.fill(path(BowlIcon.rim), with: .color(ink))
        }
        .frame(width: width, height: width / 2)
        .accessibilityElement()
        .accessibilityLabel("水だけが入ったお椀")
    }
}

/// 持ち帰りの袋。結び目のあるビニール袋に水と金魚。
struct BagIcon: View {
    var tint: GoldfishTint = .red
    var width: CGFloat = 28

    private static let outline: [(x: Int, y: Int, w: Int, h: Int)] = [
        (5, 0, 1, 1), (8, 0, 1, 1), (6, 1, 2, 2), (5, 3, 1, 1), (8, 3, 1, 1), (4, 4, 1, 1), (9, 4, 1, 1),
        (3, 5, 1, 1), (10, 5, 1, 1), (2, 6, 1, 9), (11, 6, 1, 9), (3, 15, 1, 1), (10, 15, 1, 1), (4, 16, 6, 1),
    ]

    var body: some View {
        let ink = Theme.ink
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let cell = size.width / 14
                var water = Path(CGRect(x: 3 * cell, y: 8 * cell, width: 8 * cell, height: 7 * cell))
                water.addRect(CGRect(x: 4 * cell, y: 15 * cell, width: 6 * cell, height: cell))
                context.fill(water, with: .color(ink.opacity(0.14)))
                var p = Path()
                for r in Self.outline {
                    p.addRect(CGRect(x: CGFloat(r.x) * cell, y: CGFloat(r.y) * cell, width: CGFloat(r.w) * cell, height: CGFloat(r.h) * cell))
                }
                context.fill(p, with: .color(ink))
            }
            GoldfishMark(tint: tint, width: width * 0.52)
                .offset(x: width * 0.24, y: width * 0.68)
        }
        .frame(width: width, height: width * 17 / 14)
        .accessibilityHidden(true)
    }
}

/// お椀の形（上が平らで、下が丸い）。
struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.minY + rect.height * 0.15
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            GoldfishMark(color: Theme.accent)
            GoldfishMark(color: Theme.ink)
            GoldfishMark(tint: .both)
            GoldfishMark(tint: .faint)
            GoldfishMark(color: Theme.ink, style: .takenHome)
            GoldfishMark(color: Theme.ink, style: .fry)
            GoldfishMark(color: Theme.accent, width: 48)
        }
        HStack(spacing: 4) {
            BowlIcon(filled: true)
            BowlIcon(filled: true)
            BowlIcon(filled: false)
        }
    }
    .padding()
    .background(Theme.paper)
}
