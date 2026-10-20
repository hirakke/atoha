import SwiftUI

/// 小さな等角の立方体。3D の地図のボクセルと同じ形。
struct CubeGlyph: View {
    enum Style {
        case outline(alpha: Double = 1, dashed: Bool = false)
        case ink(Double = 1)
        case accent(Double = 1)
        /// 墨の上にアクセントを重ねる（やらなきゃ × やりたい）
        case layered(ink: Double, accent: Double)
    }

    let style: Style
    var size: CGFloat = 10

    init(_ style: Style, size: CGFloat = 10) {
        self.style = style
        self.size = size
    }

    var body: some View {
        Canvas { context, canvas in
            let lw = max(1, min(canvas.width, canvas.height) * 0.1)
            let inset = lw / 2
            let w = canvas.width - lw, h = canvas.height - lw
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: inset + w * x, y: inset + h * y) }
            func poly(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                return path
            }
            let top = poly([p(0.5, 0), p(1, 0.25), p(0.5, 0.5), p(0, 0.25)])
            let left = poly([p(0, 0.25), p(0.5, 0.5), p(0.5, 1), p(0, 0.75)])
            let right = poly([p(0.5, 0.5), p(1, 0.25), p(1, 0.75), p(0.5, 1)])

            func fill(_ color: Color, _ alpha: Double) {
                guard alpha > 0 else { return }
                for (face, shade) in [(top, 0.5), (left, 0.8), (right, 1.0)] {
                    let c = color.opacity(alpha * shade)
                    context.fill(face, with: .color(c))
                    context.stroke(face, with: .color(c), lineWidth: 0.5)
                }
            }

            switch style {
            case let .outline(alpha, dashed):
                var edges = Path()
                edges.addLines([p(0.5, 0), p(1, 0.25), p(1, 0.75), p(0.5, 1), p(0, 0.75), p(0, 0.25)])
                edges.closeSubpath()
                edges.move(to: p(0, 0.25)); edges.addLine(to: p(0.5, 0.5))
                edges.move(to: p(1, 0.25)); edges.addLine(to: p(0.5, 0.5))
                edges.move(to: p(0.5, 0.5)); edges.addLine(to: p(0.5, 1))
                let stroke = dashed
                    ? StrokeStyle(lineWidth: lw, lineJoin: .miter, dash: [lw * 1.2, lw * 1.6])
                    : StrokeStyle(lineWidth: lw, lineJoin: .miter)
                context.stroke(edges, with: .color(Theme.ink.opacity(alpha)), style: stroke)
            case let .ink(alpha):
                fill(Theme.ink, alpha)
            case let .accent(alpha):
                fill(Theme.accent, alpha)
            case let .layered(ink, accent):
                fill(Theme.ink, ink)
                fill(Theme.accent, accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 10) {
        CubeGlyph(.outline())
        CubeGlyph(.outline(dashed: true))
        CubeGlyph(.ink())
        CubeGlyph(.ink(0.4))
        CubeGlyph(.accent())
        CubeGlyph(.layered(ink: 0.6, accent: 0.5), size: 24)
    }
    .padding()
    .background(Theme.paper)
}
