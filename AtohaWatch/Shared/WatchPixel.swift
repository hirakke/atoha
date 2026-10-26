import SwiftUI
import CoreText

/// 時計の色（デザインボード KingyoWatch の値）。アプリとコンプリケーションで同じものを使う。
enum KColor {
    /// 「今」などの紅（黒地で読める明るさ）
    static let now = Color(red: 1.0, green: 0.302, blue: 0.384)          // #FF4D62
    /// 金魚の紅
    static let fish = Color(red: 0.843, green: 0.149, blue: 0.239)       // #D7263D
    /// 補足の字
    static let quiet = Color(red: 0.655, green: 0.686, blue: 0.761)      // #A7AFC2
    /// お椀の水
    static let bowlWater = Color(red: 0.933, green: 0.957, blue: 1.0)    // #EEF4FF
    /// 夜の水
    static let waterDark = Color(red: 0.086, green: 0.129, blue: 0.239)  // #16213D
    static let waterDot = Color(red: 0.247, green: 0.435, blue: 0.847)   // #3F6FD8
    static let waterLine = Color(red: 0.435, green: 0.576, blue: 0.902)  // #6F93E6
    /// 藍の札（スマートスタック）
    static let cardTop = Color(red: 0.141, green: 0.188, blue: 0.310)    // #24304F
    static let cardBottom = Color(red: 0.102, green: 0.137, blue: 0.239) // #1A233D
}

/// 同梱の書体。Dela Gothic One（見出し）と DotGothic16（数・期限）。
enum KFont {
    static func registerFonts() {
        for name in ["DelaGothicOne-Regular", "DotGothic16-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat) -> Font { .custom("DelaGothicOne-Regular", fixedSize: size) }
    static func dot(_ size: CGFloat) -> Font { .custom("DotGothic16-Regular", fixedSize: size) }
}

/// ドット絵の形。行の文字列で書く（X＝塗る）。
enum KPixel {
    static let fish = [
        "..XXX....",
        ".XXXXX.XX",
        "XXXXXXXX.",
        ".XXXXX.XX",
        "..XXX....",
    ]
    /// 稚魚（点線の輪郭）
    static let fry = [
        "..X.X....",
        ".X...X..X",
        "X......X.",
        ".X...X..X",
        "..X.X....",
    ]
    /// お椀（12×6）
    static let bowl = [
        "XXXXXXXXXXXX",
        "X..........X",
        ".X........X.",
        ".X........X.",
        "..XXXXXXXX..",
        "....XXXX....",
    ]
    static let bowlWater = [
        "............",
        ".XXXXXXXXXX.",
        "..XXXXXXXX..",
        "..XXXXXXXX..",
        "............",
        "............",
    ]
    /// 持ち帰りの袋（10×10）
    static let bag = [
        "...XXXX...",
        "..X....X..",
        "XXXXXXXXXX",
        "X........X",
        "X........X",
        "X........X",
        "X........X",
        "X........X",
        ".X......X.",
        "..XXXXXX..",
    ]

    static func cells(_ rows: [String]) -> [(x: Int, y: Int)] {
        var out: [(x: Int, y: Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "X" { out.append((x, y)) }
        }
        return out
    }
}

/// ドット絵1つ。1マス = cell ポイント。
struct PixelArt: View {
    let rows: [String]
    var cell: CGFloat = 2
    var color: Color = .white

    var body: some View {
        let w = rows.map(\.count).max() ?? 0
        Canvas { ctx, _ in
            // 1つのパスにまとめて塗る（マスの継ぎ目が出ないように）
            var path = Path()
            for c in KPixel.cells(rows) {
                path.addRect(CGRect(x: CGFloat(c.x) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell))
            }
            ctx.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(w) * cell, height: CGFloat(rows.count) * cell)
        .accessibilityHidden(true)
    }
}

/// 金魚が1匹入ったお椀（24×12 を 4倍＝96×48）。fish = false で水だけ。
struct BowlArt: View {
    var fish: Bool = true
    var scale: CGFloat = 4

    var body: some View {
        Canvas { ctx, _ in
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1) -> Path {
                Path(CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale))
            }
            for c in KPixel.cells(KPixel.bowlWater) {
                ctx.fill(rect(CGFloat(c.x) * 2, CGFloat(c.y) * 2, 2, 2), with: .color(KColor.bowlWater))
            }
            let bubbles: [(CGFloat, CGFloat)] = fish
                ? [(4, 3), (8, 5), (15, 3), (18, 5), (11, 7)]
                : [(4, 3), (9, 5), (14, 3), (18, 5), (11, 7)]
            for b in bubbles { ctx.fill(rect(b.0, b.1), with: .color(KColor.waterDot.opacity(0.35))) }
            if fish {
                for c in KPixel.cells(KPixel.fish) {
                    ctx.fill(rect(7.5 + CGFloat(c.x), 2.5 + CGFloat(c.y)), with: .color(KColor.fish))
                }
            }
            for c in KPixel.cells(KPixel.bowl) {
                ctx.fill(rect(CGFloat(c.x) * 2, CGFloat(c.y) * 2, 2, 2), with: .color(.white))
            }
        }
        .frame(width: 24 * scale, height: 12 * scale)
        .accessibilityLabel(fish ? "金魚が1匹入ったお椀" : "水だけのお椀")
    }
}

/// 夜の水（紺に青い点の格子）。
struct DarkWater: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(KColor.waterDark))
            let step: CGFloat = 5
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    for (dx, dy) in [(1.25, 1.25), (3.75, 3.75)] as [(CGFloat, CGFloat)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: x + dx - 0.8, y: y + dy - 0.8, width: 1.6, height: 1.6)),
                                 with: .color(KColor.waterDot.opacity(0.75)))
                    }
                    x += step
                }
                y += step
            }
        }
    }
}

/// 黒地の青海波（白い点線、ごく薄く、下に向かって濃く）。
struct Seigaiha: View {
    var opacity: Double = 0.1

    var body: some View {
        Canvas { ctx, size in
            let w: CGFloat = 48, h: CGFloat = 24
            var centers: [CGPoint] = []
            var row = 0
            var y: CGFloat = 0
            while y <= size.height + h {
                var x: CGFloat = row % 2 == 0 ? 0 : w / 2
                while x <= size.width + w {
                    centers.append(CGPoint(x: x, y: y))
                    x += w
                }
                y += h / 2
                row += 1
            }
            let style = StrokeStyle(lineWidth: 1.6, dash: [1.6, 3.2])
            for c in centers {
                for r in [22.0, 15.0, 8.0] as [CGFloat] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(opacity)), style: style)
                }
            }
        }
        .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}
