import SwiftUI
import UIKit

enum CubeMetrics {
    /// 押し出し（ずらした影）の量
    static let depth: CGFloat = 3
}

enum CubeVariant {
    case accent     // 紅の面、藍の枠と藍の影
    case primary    // 藍の面、白い字、紅の影
    case secondary  // 白い面、藍の枠と藍の影
    case quiet      // 枠なし、静かな字
    case flat       // 選べないとき（薄い枠、影なし）
}

enum CubeSize {
    case large, small

    var type: AType { self == .large ? .title : .small }
    var horizontal: CGFloat { self == .large ? 22 : 16 }
    var vertical: CGFloat { self == .large ? 14 : 8 }
}

/// 丸いボタンの面と、ずらした影。ボタンにも静的なラベルにも使う。
/// 押せるものは高さ44pt以上（HIG）。
struct CubeFace: ViewModifier {
    var variant: CubeVariant = .secondary
    var size: CubeSize = .small
    var fill = false
    var pressed = false

    private var foreground: Color {
        switch variant {
        case .accent: Theme.onAccent
        case .primary: Theme.paper
        case .secondary, .flat: Theme.ink
        case .quiet: Theme.quiet
        }
    }

    private var extruded: Bool { variant != .quiet && variant != .flat }

    func body(content: Content) -> some View {
        let shape = Capsule()
        let d = CubeMetrics.depth
        let shift = pressed && extruded ? d : 0
        content
            .atype(size.type, color: foreground)
            .padding(.horizontal, variant == .quiet ? 8 : size.horizontal)
            .padding(.vertical, variant == .quiet ? 4 : size.vertical)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 44)
            .background {
                switch variant {
                case .accent: shape.fill(Theme.accent).overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                case .primary: shape.fill(Theme.ink)
                case .secondary: shape.fill(Theme.surface).overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                case .flat: shape.fill(Theme.surface).overlay(shape.strokeBorder(Theme.faint, lineWidth: 2))
                case .quiet: Color.clear
                }
            }
            .offset(x: shift, y: shift)
            .background {
                // ずらした影。藍の面には紅、ほかは藍
                if extruded { shape.fill(variant == .primary ? Theme.accent : Theme.ink).offset(x: d, y: d) }
            }
            .padding(.trailing, extruded ? d : 0)
            .padding(.bottom, extruded ? d : 0)
            .contentShape(Rectangle())
    }
}

extension View {
    func cubeFace(_ variant: CubeVariant = .secondary, size: CubeSize = .small, fill: Bool = false) -> some View {
        modifier(CubeFace(variant: variant, size: size, fill: fill))
    }
}

/// 立方体のボタン。押すと面が押し出しの中へ沈み、軽い触覚が返る。
struct CubeButtonStyle: ButtonStyle {
    var variant: CubeVariant = .secondary
    var size: CubeSize = .small
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        CubeButtonBody(configuration: configuration, variant: variant, size: size, fill: fill)
    }

    private struct CubeButtonBody: View {
        let configuration: Configuration
        let variant: CubeVariant
        let size: CubeSize
        let fill: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .modifier(CubeFace(variant: variant, size: size, fill: fill, pressed: configuration.isPressed))
                .opacity(isEnabled ? (variant == .quiet && configuration.isPressed ? 0.5 : 1) : 0.4)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
        }
    }
}

extension ButtonStyle where Self == CubeButtonStyle {
    static func cube(_ variant: CubeVariant = .secondary, size: CubeSize = .small, fill: Bool = false) -> CubeButtonStyle {
        CubeButtonStyle(variant: variant, size: size, fill: fill)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        Button("あとに回す") {}.buttonStyle(.cube(.primary, size: .large, fill: true))
        Button("今に入れる") {}.buttonStyle(.cube(.secondary))
        Button("やる") {}.buttonStyle(.cube(.primary))
        Button("閉じる") {}.buttonStyle(.cube(.quiet))
        CubeSegmented(options: ["今夜", "明日の朝", "手が空いたら"], label: { $0 }, selection: .constant("明日"))
    }
    .padding()
    .background(Theme.paper)
}
