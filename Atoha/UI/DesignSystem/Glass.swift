import SwiftUI

/// 水槽・池・金魚鉢のガラスの見え方。設定で切り替える。
enum TankGlass: String, CaseIterable {
    /// 厚い縁、水面のきらめき、底の光の模様を自前で描く
    case drawn
    /// システムの Liquid Glass を枠にする
    case system

    var label: String {
        switch self {
        case .drawn: "描いたガラス"
        case .system: "Liquid Glass"
        }
    }
}

extension View {
    /// 水の入れ物をガラスで囲む。radius は内側（水）の角の丸み。tilt があればハイライトが傾きでずれる
    func glassFrame(_ look: TankGlass, radius: CGFloat, tilt: TankTilt? = nil) -> some View {
        modifier(GlassFrame(look: look, radius: radius, tilt: tilt))
    }
}

private struct GlassFrame: ViewModifier {
    let look: TankGlass
    let radius: CGFloat
    let tilt: TankTilt?

    func body(content: Content) -> some View {
        let drawn = look == .drawn
        let inner = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .overlay {
                if drawn {
                    GlassFront(tilt: tilt)
                } else {
                    // Liquid Glass の向こうの水は、少しだけ曇らせる
                    Color.white.opacity(0.12).allowsHitTesting(false)
                }
            }
            .clipShape(inner)
            .overlay(inner.strokeBorder(drawn ? Theme.ink.opacity(0.35) : Color.white.opacity(0.9), lineWidth: 1.5))
            .padding(drawn ? 10 : 14)
            .background {
                if drawn {
                    GlassRim(tilt: tilt, radius: radius + 9)
                } else {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: radius + 12))
                        .shadow(color: Theme.ink.opacity(0.12), radius: 9, y: 8)
                }
            }
    }
}

/// ガラスの色。明るいときは白から淡い青、暗いときは藍の濃淡
enum GlassTone {
    static func rim(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [Color(UIColor(hex: 0x4A5578)), Color(UIColor(hex: 0x2E3756)), Color(UIColor(hex: 0x1E2540))]
            : [.white, Color(UIColor(hex: 0xE6EDFA)), Color(UIColor(hex: 0xC7D5EF))]
    }
    static func air(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [Color(UIColor(hex: 0x2A3352)), Color(UIColor(hex: 0x222A47))]
            : [.white, Color(UIColor(hex: 0xF3F7FF))]
    }
    static func light(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(UIColor(hex: 0xC9D6FF)) : .white
    }
}

/// 描いたガラスの厚い縁。白から淡い青のグラデーション、藍の外枠、やわらかい影。上の縁に光の線。
private struct GlassRim: View {
    let tilt: TankTilt?
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(LinearGradient(colors: GlassTone.rim(scheme), startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2.5))
            .shadow(color: Theme.ink.opacity(0.16), radius: 9, y: 8)
            .overlay(alignment: .top) { RimLight(tilt: tilt, inset: radius * 0.7) }
    }
}

/// 上の縁の光の線。傾きで少しだけ横にすべる
private struct RimLight: View {
    let tilt: TankTilt?
    let inset: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(GlassTone.light(scheme).opacity(scheme == .dark ? 0.5 : 1))
            .frame(height: 3)
            .padding(.horizontal, inset)
            .padding(.top, 4)
            .offset(x: reduceMotion ? 0 : (tilt?.offset.width ?? 0) * 0.4)
    }
}

/// ガラスの手前。上から薄れる映り込み（動かない）と、傾きですべるハイライト。
private struct GlassFront: View {
    let tilt: TankTilt?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = GlassTone.light(scheme)
        GeometryReader { geo in
            // 映り込みは上から 90pt ほどまで（背の高い池でも、中の札を白く覆わない）
            let fade = min(0.5, 90 / max(geo.size.height, 1))
            ZStack {
                LinearGradient(stops: [.init(color: light.opacity(scheme == .dark ? 0.12 : 0.32), location: 0),
                                       .init(color: light.opacity(0), location: fade)],
                               startPoint: .top, endPoint: .bottom)
                GlassHighlights(tilt: tilt)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 左上の斜めの光の帯と、右の縁の細い光の筋。傾けると少しずれる（視差を減らす設定では止める）
private struct GlassHighlights: View {
    let tilt: TankTilt?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let light = GlassTone.light(scheme)
        let o = reduceMotion ? .zero : (tilt?.offset ?? .zero)
        ZStack(alignment: .topTrailing) {
            GlassBand()
                .fill(light.opacity(scheme == .dark ? 0.14 : 0.45))
                .offset(x: o.width, y: o.height)
            GeometryReader { geo in
                // 背の高い入れ物でも、筋は上のほうに水槽と同じくらいの長さで
                let length = min(geo.size.height * 0.62, 110)
                Capsule()
                    .fill(light.opacity(scheme == .dark ? 0.4 : 0.85))
                    .frame(width: 4, height: length)
                    .position(x: geo.size.width - 12, y: min(geo.size.height * 0.45, length / 2 + 24))
                    .offset(x: o.width * 0.3, y: o.height * 0.6)
            }
        }
    }
}

/// 左上の斜めの光の帯（台形）
private struct GlassBand: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.height / 164, 1.1)  // 水槽の高さで止める
        var p = Path()
        p.move(to: CGPoint(x: 14, y: 4 * k))
        p.addLine(to: CGPoint(x: 66, y: 4 * k))
        p.addLine(to: CGPoint(x: 28, y: 112 * k))
        p.addLine(to: CGPoint(x: 8, y: 112 * k))
        p.addLine(to: CGPoint(x: 8, y: 14 * k))
        p.closeSubpath()
        return p
    }
}
