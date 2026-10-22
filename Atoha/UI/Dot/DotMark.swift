import SwiftUI

/// ひとつひとつを表す小さなドットの金魚。
/// やりたい＝紅、やらなきゃ＝藍、両方＝藍の縁で中が紅、どちらでもない＝薄い藍、まだ決めていない＝稚魚（点線）。
struct DotMark: View {
    let kind: ItemKind
    var highlighted: Bool = false
    var size: CGFloat = 8
    /// 以前の呼び出しとの互換のため残している。いつも正方形で描く
    var flat: Bool = true

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

    var body: some View {
        // size は以前の正方形の一辺。金魚は横長なので、横幅を少し広げて同じくらいの重さに見せる
        let width = size * 1.8
        if let rating {
            GoldfishMark(tint: GoldfishTint.of(want: rating.want, must: rating.must), width: width)
        } else {
            // まだ決めていないものは稚魚（点線の輪郭）。軸に近いものは紅
            GoldfishMark(color: highlighted ? Theme.accent : Theme.ink, style: .fry, width: width)
        }
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
