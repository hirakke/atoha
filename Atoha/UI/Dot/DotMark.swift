import SwiftUI

/// 種類を表す小さな立方体。用事＝塗り、気になること・未分類＝枠。
struct DotMark: View {
    let kind: ItemKind
    var highlighted: Bool = false
    var size: CGFloat = 8
    /// true なら 2D の図用に、平らな正方形で描く（意味は立方体と同じ）
    var flat: Bool = false

    /// 本人の評価。must → 塗りの濃さ、want → アクセントの強さ。
    var rating: (want: Double, must: Double)?

    init(kind: ItemKind, want: Double?, must: Double?, highlighted: Bool = false, size: CGFloat = 8, flat: Bool = false) {
        self.init(kind: kind, highlighted: highlighted, size: size, flat: flat)
        if let want, let must { rating = (min(1, max(0, want)), min(1, max(0, must))) }
    }

    init(kind: ItemKind, highlighted: Bool = false, size: CGFloat = 8, flat: Bool = false) {
        self.kind = kind
        self.flat = flat
        self.highlighted = highlighted
        self.size = size
    }

    private var style: CubeGlyph.Style {
        if let rating {
            if rating.want < 0.25 && rating.must < 0.25 { return .outline(alpha: 0.6) }
            return .layered(ink: 0.15 + 0.85 * rating.must, accent: rating.want)
        }
        if highlighted { return .accent() }
        if kind == .errand { return .ink() }
        return .outline(alpha: kind == .unsorted ? 0.45 : 1)
    }

    var body: some View {
        if flat { SquareMark(style, size: size) } else { CubeGlyph(style, size: size) }
    }
}

/// 2D の図用の平らな正方形。CubeGlyph と同じ Style で、塗り・重ね・枠を描く。
struct SquareMark: View {
    let style: CubeGlyph.Style
    var size: CGFloat = 10

    init(_ style: CubeGlyph.Style, size: CGFloat = 10) {
        self.style = style
        self.size = size
    }

    var body: some View {
        Canvas { context, canvas in
            let lw = max(1, min(canvas.width, canvas.height) * 0.12)
            let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: lw / 2, dy: lw / 2)
            let path = Path(rect)
            switch style {
            case let .outline(alpha, dashed):
                let stroke = dashed
                    ? StrokeStyle(lineWidth: lw, dash: [lw * 1.2, lw * 1.6])
                    : StrokeStyle(lineWidth: lw)
                context.stroke(path, with: .color(Theme.ink.opacity(alpha)), style: stroke)
            case let .ink(alpha):
                context.fill(path, with: .color(Theme.ink.opacity(alpha)))
            case let .accent(alpha):
                context.fill(path, with: .color(Theme.accent.opacity(alpha)))
            case let .layered(ink, accent):
                context.fill(path, with: .color(Theme.ink.opacity(ink)))
                context.fill(path, with: .color(Theme.accent.opacity(accent)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 8) {
        DotMark(kind: .errand)
        DotMark(kind: .concern)
        DotMark(kind: .unsorted)
        DotMark(kind: .concern, highlighted: true)
        DotMark(kind: .errand, size: 16)
    }
    .padding()
    .background(Theme.paper)
}
