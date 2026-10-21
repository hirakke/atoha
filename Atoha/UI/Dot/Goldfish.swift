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

    /// 輪郭のマス（上下左右のどれかが空いているマス）
    static let edgeCells: [(x: Int, y: Int)] = {
        let filled = Set(cells.map { $0.y * 100 + $0.x })
        return cells.filter { c in
            [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in !filled.contains((c.y + d.1) * 100 + c.x + d.0) }
        }
    }()
}

/// 金魚の色。やりたい寄りは朱、やらなきゃ寄りは墨（出目金）、どちらでもないものは橙。
enum GoldfishTint {
    case red, black, orange, faint

    var color: Color {
        switch self {
        case .red: Theme.accent
        case .black: Theme.ink
        case .orange: Theme.orange
        case .faint: Theme.quiet
        }
    }

    var uiColor: UIColor {
        switch self {
        case .red: Theme.accentUIColor
        case .black: Theme.inkUIColor
        case .orange: Theme.orangeUIColor
        case .faint: Theme.inkUIColor.withAlphaComponent(0.45)
        }
    }

    /// 本人の評価（未評価なら AI の仮の値）から色を決める。
    static func of(want: Double, must: Double) -> GoldfishTint {
        if want >= 0.5 { return .red }
        if must >= 0.5 { return .black }
        return .orange
    }
}

/// 画面の印としての金魚。outlined は未評価（輪郭だけ）。
struct GoldfishMark: View {
    var color: Color
    var outlined = false
    /// 横幅（縦は 5/9）
    var width: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let cell = size.width / CGFloat(GoldfishShape.width)
            var path = Path()
            for c in outlined ? GoldfishShape.edgeCells : GoldfishShape.cells {
                path.addRect(CGRect(x: CGFloat(c.x) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell))
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: width, height: width * CGFloat(GoldfishShape.height) / CGFloat(GoldfishShape.width))
        .accessibilityHidden(true)
    }
}

/// お椀。今に入っている数を見せる（filled なら金魚が1匹入っている）。
struct BowlIcon: View {
    var filled: Bool
    var width: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            BowlShape()
                .fill(Theme.paper)
                .overlay(BowlShape().stroke(Theme.ink, lineWidth: 1.5))
            if filled {
                GoldfishMark(color: Theme.accent, width: width * 0.42)
                    .padding(.top, width * 0.2)
            }
        }
        .frame(width: width, height: width * 0.62)
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
            GoldfishMark(color: Theme.orange)
            GoldfishMark(color: Theme.ink, outlined: true)
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
