import SwiftUI
import UIKit

/// 色の組。方眼の紙に、墨と1色のアクセント。設定で選べる。
struct Palette: Identifiable, Equatable {
    struct Tone: Equatable {
        var paper: UInt32, ink: UInt32, grid: UInt32, line: UInt32, sub: UInt32
        var accent: UInt32, onAccent: UInt32
        /// 箱やボタンの面（なければ紙と同じ）
        var surface: UInt32? = nil
    }

    let id: String
    let name: String
    let light: Tone
    let dark: Tone

    static let all: [Palette] = [
        // 金魚すくい：藍と紅の2色刷り。方眼は引かず、白い面を藍の線で囲む
        Palette(id: "kingyo", name: "金魚",
                light: Tone(paper: 0xF3F5FA, ink: 0x1F2A44, grid: 0xF3F5FA, line: 0xD5DAE5, sub: 0x56617A, accent: 0xD7263D, onAccent: 0xFFFFFF, surface: 0xFFFFFF),
                dark: Tone(paper: 0x121829, ink: 0xEEF1F7, grid: 0x121829, line: 0x2C3756, sub: 0xA9B2C7, accent: 0xF0485B, onAccent: 0xFFFFFF, surface: 0x1C2440)),
        Palette(id: "blue", name: "青",
                light: Tone(paper: 0xFFFFFF, ink: 0x121A2E, grid: 0xE9EEF8, line: 0xC9D3E6, sub: 0x4A5878, accent: 0x2F5BEA, onAccent: 0xFFFFFF),
                dark: Tone(paper: 0x121A2E, ink: 0xE8ECF6, grid: 0x1B2540, line: 0x2C3A60, sub: 0xA3B1D4, accent: 0x7EA0FF, onAccent: 0x0A1022)),
        Palette(id: "vermilion", name: "朱",
                light: Tone(paper: 0xFFFDFA, ink: 0x1E1714, grid: 0xF3ECE6, line: 0xE0D4CA, sub: 0x6B5A50, accent: 0xE5482D, onAccent: 0xFFFFFF),
                dark: Tone(paper: 0x1C1513, ink: 0xF3ECE6, grid: 0x2A201C, line: 0x45362F, sub: 0xB8A79C, accent: 0xFF7A5C, onAccent: 0x1C1513)),
        Palette(id: "green", name: "緑",
                light: Tone(paper: 0xFFFFFF, ink: 0x10201A, grid: 0xE6F2EC, line: 0xC8DDD2, sub: 0x4B6358, accent: 0x0E8A5B, onAccent: 0xFFFFFF),
                dark: Tone(paper: 0x0F1D17, ink: 0xE4F1EA, grid: 0x1A2C24, line: 0x2C4639, sub: 0x9DB8AB, accent: 0x3FD39A, onAccent: 0x0F1D17)),
        Palette(id: "yellow", name: "黄",
                light: Tone(paper: 0xFFFFFF, ink: 0x121212, grid: 0xF1EFE6, line: 0xDAD6C8, sub: 0x55524A, accent: 0xFFC800, onAccent: 0x121212),
                dark: Tone(paper: 0x161512, ink: 0xF2F0E8, grid: 0x23211C, line: 0x3A372F, sub: 0xADA99D, accent: 0xFFC800, onAccent: 0x121212)),
        Palette(id: "purple", name: "紫",
                light: Tone(paper: 0xFFFFFF, ink: 0x1A1530, grid: 0xEEEAF9, line: 0xD4CCEE, sub: 0x57507A, accent: 0x6A3CE0, onAccent: 0xFFFFFF),
                dark: Tone(paper: 0x17132A, ink: 0xECE8FA, grid: 0x231D3D, line: 0x3A3263, sub: 0xABA3D1, accent: 0xA68BFF, onAccent: 0x17132A)),
        Palette(id: "night", name: "夜",
                light: Tone(paper: 0x121A2E, ink: 0xE8ECF6, grid: 0x1B2540, line: 0x2C3A60, sub: 0xA3B1D4, accent: 0xFFC800, onAccent: 0x121212),
                dark: Tone(paper: 0x121A2E, ink: 0xE8ECF6, grid: 0x1B2540, line: 0x2C3A60, sub: 0xA3B1D4, accent: 0xFFC800, onAccent: 0x121212)),
    ]

    static func find(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }

    /// 夜のように、明るい画面でも暗い色の組
    var alwaysDark: Bool { light == dark }

    func color(_ pick: @escaping (Tone) -> UInt32) -> UIColor {
        let light = light, dark = dark
        return UIColor { traits in
            UIColor(hex: pick(traits.userInterfaceStyle == .dark ? dark : light))
        }
    }
}

/// 選んでいる色の組。画面は Theme の色を読むたびにこれを読むので、変えるとすぐ塗り替わる。
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let key = "settings.palette"

    var palette: Palette {
        didSet { UserDefaults.standard.set(palette.id, forKey: Self.key) }
    }

    private init() {
        palette = Palette.find(UserDefaults.standard.string(forKey: Self.key) ?? "kingyo")
    }
}

/// atoha の色とタイポグラフィ。方眼の紙、墨、アクセントは1色だけ。
enum Theme {
    private static var palette: Palette { ThemeStore.shared.palette }

    /// 背景（紙）
    static var paper: Color { Color(paperUIColor) }
    /// 文字と線（墨）
    static var ink: Color { Color(inkUIColor) }
    /// 控えめな文字
    static var quiet: Color { Color(palette.color(\.sub)) }
    /// 罫線
    static var faint: Color { Color(palette.color(\.line)) }
    /// 方眼の線
    static var grid: Color { Color(palette.color(\.grid)) }
    /// アクセント（次の1つ、軸に近いもの）
    static var accent: Color { Color(accentUIColor) }
    /// アクセントの上の文字
    static var onAccent: Color { Color(palette.color(\.onAccent)) }
    /// 箱やボタンの面
    static var surface: Color { Color(palette.color { $0.surface ?? $0.paper }) }

    static var paperUIColor: UIColor { palette.color(\.paper) }
    static var inkUIColor: UIColor { palette.color(\.ink) }
    static var accentUIColor: UIColor { palette.color(\.accent) }

    /// 水（水槽・池）。白い面に藍の網点を打って水に見せる
    static let waterUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1C2440) : UIColor(hex: 0xFFFFFF) }
    static var water: Color { Color(waterUIColor) }
    /// 水面の波紋
    static let rippleUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x3D6670) : UIColor(hex: 0xFFFFFF) }
    /// 金魚の色違い（橙）
    static let orangeUIColor = UIColor(hex: 0xE88A3C)
    static var orange: Color { Color(orangeUIColor) }

    /// 色の組が変わったかを見分けるための印（3D の画面で塗り直すため）
    static var paletteID: String { palette.id }

    /// 箱の角
    static let radius: CGFloat = 18
    /// 枠の太さ
    static let stroke: CGFloat = 3
    /// 押し出し（ずらした影）の量
    static let shadow: CGFloat = 4

    /// 見出し（看板の文字）。丸みのある極太
    static func display(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .rounded, weight: .black)
    }

    /// 数字や補足の文字。等幅。
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 本文と見出し。太めのゴシック。
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 方眼の紙。画面の背景に敷く。
/// 線は画面の座標にそろえて引くので、上端の帯やボタンの下に部分的に敷いても目がずれない。
struct PaperBackground: View {
    var spacing: CGFloat = 16
    /// 安全領域の外まで広げる（画面全体の背景）
    var fullScreen = true

    var body: some View {
        let grid = Theme.grid
        let s = spacing
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            Canvas { context, size in
                var path = Path()
                var x = -origin.x.truncatingRemainder(dividingBy: s)
                while x <= size.width { path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += s }
                var y = -origin.y.truncatingRemainder(dividingBy: s)
                while y <= size.height { path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += s }
                context.fill(path, with: .color(grid))
            }
            .background(Theme.paper)
        }
        .ignoresSafeArea(edges: fullScreen ? .all : [])
        .accessibilityHidden(true)
    }
}
