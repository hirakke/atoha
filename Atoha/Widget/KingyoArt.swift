import SwiftUI
import UIKit

/// ウィジェット・ライブアクティビティの色と書体。デザインボード（金魚すくいのウィジェット）の値をそのまま使う。
/// アプリの色の組（設定）には合わせず、ウィジェットはいつも藍と紅の2色刷り。
enum K {
    static let navy = Color(hex: 0x1F2A44)
    static let navy2 = Color(hex: 0x24324F)
    static let red = Color(hex: 0xD7263D)
    static let quiet = Color(hex: 0x56617A)
    static let water = Color(hex: 0xEEF4FF)
    static let waterDot = Color(hex: 0x3F6FD8)

    /// 見出しの1文字（今）。Dela Gothic One
    static func disp(_ size: CGFloat) -> Font { .custom("DelaGothicOne-Regular", fixedSize: size) }
    /// 時刻・期限。DotGothic16
    static func dot(_ size: CGFloat) -> Font { .custom("DotGothic16-Regular", fixedSize: size) }
    /// 名前（太いゴシック）
    static func item(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }

    /// 期限の書き方（18:00 まで／明日まで／10/31 まで）
    static func deadline(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) {
            let c = cal.dateComponents([.hour, .minute], from: date)
            if c.hour == 0 && c.minute == 0 { return "今日まで" }
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) + " まで"
        }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: t) { return "明日まで" }
        return date.formatted(.dateTime.month(.defaultDigits).day()) + " まで"
    }

    /// 止まった経過時間（12:34 / 1:02:03）
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// ドット絵の形（マス単位の四角の集まり）。デザインの <defs> の kBowl などを写したもの。
struct PixelArt {
    let rects: [CGRect]

    init(_ r: [(CGFloat, CGFloat, CGFloat, CGFloat)]) { rects = r.map { CGRect(x: $0.0, y: $0.1, width: $0.2, height: $0.3) } }

    func path(unit: CGFloat, at origin: CGPoint = .zero, scale: CGFloat = 1, mirrorWidth: CGFloat? = nil) -> Path {
        var p = Path()
        for r in rects {
            var x = r.minX
            if let w = mirrorWidth { x = w - r.maxX }
            p.addRect(CGRect(x: origin.x + x * scale * unit, y: origin.y + r.minY * scale * unit,
                             width: r.width * scale * unit, height: r.height * scale * unit))
        }
        return p
    }

    /// 9×5 の金魚
    static let fish = PixelArt([(2, 0, 3, 1), (1, 1, 5, 1), (7, 1, 2, 1), (0, 2, 8, 1), (1, 3, 5, 1), (7, 3, 2, 1), (2, 4, 3, 1)])
    /// 9×5 の稚魚（点の輪郭）
    static let fry = PixelArt([(2, 0, 1, 1), (4, 0, 1, 1), (1, 1, 1, 1), (5, 1, 1, 1), (8, 1, 1, 1), (0, 2, 1, 1), (7, 2, 1, 1),
                               (1, 3, 1, 1), (5, 3, 1, 1), (8, 3, 1, 1), (2, 4, 1, 1), (4, 4, 1, 1)])
    /// 24×9 のお椀（縁・胴・高台）
    static let bowl = PixelArt([(0, 0, 24, 1), (0, 1, 1, 2), (23, 1, 1, 2), (1, 3, 1, 2), (22, 3, 1, 2), (2, 5, 1, 1), (21, 5, 1, 1),
                                (3, 6, 18, 1), (8, 7, 8, 1), (7, 8, 10, 1)])
    static let bowlWater = PixelArt([(1, 1, 22, 2), (2, 3, 20, 2), (3, 5, 18, 1)])
    static let bowlSurf = PixelArt([(1, 1, 22, 1)])
    /// 12×14 の袋
    static let bag = PixelArt([(5, 0, 2, 1), (4, 1, 4, 1), (5, 2, 2, 1), (3, 3, 1, 1), (8, 3, 1, 1), (2, 4, 1, 2), (9, 4, 1, 2),
                               (1, 6, 1, 5), (10, 6, 1, 5), (2, 11, 1, 1), (9, 11, 1, 1), (3, 12, 6, 1)])
    static let bagWater = PixelArt([(2, 7, 8, 4), (3, 11, 6, 1)])
    /// 3×3 の泡
    static let bubble = PixelArt([(1, 0, 1, 1), (0, 1, 1, 1), (2, 1, 1, 1), (1, 2, 1, 1)])
}

/// お椀の描き分け
enum BowlLook {
    /// 白い面の上（網点の水・白い水面・紅の金魚・藍の縁）
    case color
    /// 色を抜いたとき／ロック画面（白の線と塗り、水は薄い白）
    case white(water: Double)
    /// ダイナミックアイランドの黒の上（白の縁・青い水・紅の金魚）
    case island(surface: Bool)
}

/// ドットのお椀。fish なら今の1匹が入っている。bubbles なら泡が立つ（集中中）。
struct PixelBowl: View {
    var fish = true
    var bubbles = false
    var look: BowlLook = .color
    var width: CGFloat = 104

    var body: some View {
        let fish = fish, bubbles = bubbles, look = look
        // 泡のあるときは上に2マスぶん足す（viewBox 0 -2 24 11）
        let rows: CGFloat = bubbles ? 11 : 9
        Canvas { ctx, size in
            let u = size.width / 24
            let top: CGFloat = bubbles ? 2 * u : 0
            let o = CGPoint(x: 0, y: top)
            let water = PixelArt.bowlWater.path(unit: u, at: o)
            switch look {
            case .color:
                PixelBowl.fillWaterDots(ctx, water, unit: u)
                ctx.fill(PixelArt.bowlSurf.path(unit: u, at: o), with: .color(.white.opacity(0.85)))
            case .white(let a):
                ctx.fill(water, with: .color(.white.opacity(a)))
            case .island(let surface):
                ctx.fill(water, with: .color(K.waterDot.opacity(0.6)))
                if surface { ctx.fill(PixelArt.bowlSurf.path(unit: u, at: o), with: .color(.white.opacity(0.6))) }
            }
            if fish {
                let fishColor: Color = { if case .white = look { return .white } else { return K.red } }()
                ctx.fill(PixelArt.fish.path(unit: u, at: CGPoint(x: 7.5 * u, y: top + 1.6 * u)), with: .color(fishColor))
            }
            let rim: Color = { if case .color = look { return K.navy } else { return .white } }()
            ctx.fill(PixelArt.bowl.path(unit: u, at: o), with: .color(rim))
            if bubbles {
                let bub: Color = { if case .white = look { return .white } else { return K.waterDot } }()
                ctx.fill(PixelArt.bubble.path(unit: u, at: CGPoint(x: 15 * u, y: 0), scale: 0.7), with: .color(bub))
                ctx.fill(PixelArt.bubble.path(unit: u, at: CGPoint(x: 18 * u, y: 1 * u), scale: 0.5), with: .color(bub))
            }
        }
        .frame(width: width, height: width * rows / 24)
        .accessibilityHidden(true)
    }

    /// 網点の水（kWaterU：2マスに2つの点を互い違いに）
    static func fillWaterDots(_ ctx: GraphicsContext, _ water: Path, unit u: CGFloat) {
        ctx.fill(water, with: .color(K.water))
        var dots = Path()
        let b = water.boundingRect
        var y: CGFloat = 0
        while y < b.maxY {
            var x: CGFloat = 0
            while x < b.maxX {
                dots.addRect(CGRect(x: x + 0.3 * u, y: y + 0.3 * u, width: 0.45 * u, height: 0.45 * u))
                dots.addRect(CGRect(x: x + 1.3 * u, y: y + 1.3 * u, width: 0.45 * u, height: 0.45 * u))
                x += 2 * u
            }
            y += 2 * u
        }
        var c = ctx
        c.clip(to: water)
        c.fill(dots, with: .color(K.waterDot.opacity(0.35)))
    }
}

/// ドットの金魚（1色）
struct PixelFish: View {
    var color: Color = K.red
    var width: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(PixelArt.fish.path(unit: size.width / 9), with: .color(color))
        }
        .frame(width: width, height: width * 5 / 9)
        .accessibilityHidden(true)
    }

    /// 1行のウィジェット用（Image しか置けないので、テンプレート画像にする）
    static func templateImage(height: CGFloat = 10) -> UIImage {
        let u = height / 5
        let size = CGSize(width: 9 * u, height: 5 * u)
        let img = UIGraphicsImageRenderer(size: size).image { c in
            UIColor.black.setFill()
            for r in PixelArt.fish.rects {
                c.fill(CGRect(x: r.minX * u, y: r.minY * u, width: r.width * u, height: r.height * u))
            }
        }
        return img.withRenderingMode(.alwaysTemplate)
    }
}

/// 持ち帰りの袋（水と金魚入り）。onDark なら白い線と青い水（アイランド）。lineOnly なら袋の線だけ。
struct PixelBag: View {
    var onDark = false
    var lineOnly = false
    var line: Color? = nil
    var width: CGFloat = 40

    var body: some View {
        let onDark = onDark, lineOnly = lineOnly, line = line
        Canvas { ctx, size in
            let u = size.width / 12
            if !lineOnly {
                let water = PixelArt.bagWater.path(unit: u)
                if onDark {
                    ctx.fill(water, with: .color(K.waterDot.opacity(0.7)))
                } else {
                    PixelBowl.fillWaterDots(ctx, water, unit: u)
                }
                ctx.fill(PixelArt.fish.path(unit: u, at: CGPoint(x: 1.6 * u, y: 6.6 * u), scale: 0.95), with: .color(K.red))
            }
            ctx.fill(PixelArt.bag.path(unit: u), with: .color(line ?? (onDark ? .white : K.navy)))
        }
        .frame(width: width, height: width * 14 / 12)
        .accessibilityHidden(true)
    }
}

/// 青海波（48×24 の点線の重ね円）。上から下へ薄れていく。
struct SeigaihaFade: View {
    var navy = false

    var body: some View {
        let navy = navy
        Canvas { ctx, size in
            let w: CGFloat = 48, h: CGFloat = 24
            let bg: Color = navy ? K.navy : .white
            let line: Color = navy ? Color.white.opacity(0.1) : K.navy.opacity(0.08)
            let style = StrokeStyle(lineWidth: 1.6, dash: [1.6, 3.2])
            let centers: [CGPoint] = [.init(x: 0, y: 0), .init(x: 48, y: 0), .init(x: 24, y: 12), .init(x: 0, y: 24), .init(x: 48, y: 24)]
            func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    var t = ctx
                    t.clip(to: Path(CGRect(x: x, y: y, width: w, height: h)))
                    t.translateBy(x: x, y: y)
                    for c in centers {
                        t.fill(circle(c, 22), with: .color(bg))
                        for r: CGFloat in [22, 15, 8] { t.stroke(circle(c, r), with: .color(line), style: style) }
                    }
                    x += w
                }
                y += h
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.75)],
                             startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}

/// 水面（kWater：薄い水色に青の丸い網点、6pt おき）
struct WaterDots: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(K.water))
            var dots = Path()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x + 0.5, y: y + 0.5, width: 2, height: 2))
                    dots.addEllipse(in: CGRect(x: x + 3.5, y: y + 3.5, width: 2, height: 2))
                    x += 6
                }
                y += 6
            }
            ctx.fill(dots, with: .color(K.waterDot.opacity(0.3)))
        }
        .accessibilityHidden(true)
    }
}

/// ＋のまわりの波紋（点線の楕円2つ）
struct Ripple: View {
    var color: Color = K.waterDot
    var inner = CGSize(width: 76, height: 26)
    var outer = CGSize(width: 116, height: 40)
    var opacities: (Double, Double) = (0.5, 0.28)
    var lineWidth: CGFloat = 1.6
    var dash: [CGFloat] = [2, 3]

    var body: some View {
        ZStack {
            Ellipse().stroke(color.opacity(opacities.1), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
                .frame(width: outer.width, height: outer.height)
            Ellipse().stroke(color.opacity(opacities.0), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
                .frame(width: inner.width, height: inner.height)
        }
        .accessibilityHidden(true)
    }
}

/// 稚魚（点の輪郭）。mirrored で右向き
struct PixelFry: View {
    var color: Color = K.navy
    var unit: CGFloat = 2.4
    var mirrored = false

    var body: some View {
        let unit = unit, mirrored = mirrored
        Canvas { ctx, _ in
            ctx.fill(PixelArt.fry.path(unit: unit, mirrorWidth: mirrored ? 9 : nil), with: .color(color))
        }
        .frame(width: 9 * unit, height: 5 * unit)
        .accessibilityHidden(true)
    }
}
