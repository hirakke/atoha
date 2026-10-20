import SwiftUI

/// 文字のトークン。画面ごとにサイズを決めず、ここから選ぶ。
/// 見出しと本文は太めのゴシック、補足（ラベル）は等幅。
enum AType {
    case display // 24 black：画面の名前
    case title   // 17 heavy
    case body    // 15 semibold
    case small   // 13 medium
    case label   // 11 等幅、控えめ、少し字間を空ける

    var font: Font {
        switch self {
        case .display: Theme.sans(24, weight: .black)
        case .title: Theme.sans(17, weight: .heavy)
        case .body: Theme.sans(15, weight: .semibold)
        case .small: Theme.sans(13, weight: .medium)
        case .label: Theme.mono(11, weight: .medium)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .label: 0.6
        case .display: -0.4
        default: 0
        }
    }

    var color: Color { self == .label ? Theme.quiet : Theme.ink }

    var uiFont: UIFont {
        switch self {
        case .display: .systemFont(ofSize: 24, weight: .black)
        case .title: .systemFont(ofSize: 17, weight: .heavy)
        case .body: .systemFont(ofSize: 15, weight: .semibold)
        case .small: .systemFont(ofSize: 13, weight: .medium)
        case .label: .monospacedSystemFont(ofSize: 11, weight: .medium)
        }
    }
}

/// アクセントの面の上など、文字の色をまとめて変えたいときに使う。
private struct ATypeInkKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var atypeInk: Color? {
        get { self[ATypeInkKey.self] }
        set { self[ATypeInkKey.self] = newValue }
    }
}

private struct ATypeModifier: ViewModifier {
    let type: AType
    let color: Color?
    @Environment(\.atypeInk) private var ink

    func body(content: Content) -> some View {
        let resolved = color ?? ink.map { type == .label ? $0.opacity(0.8) : $0 } ?? type.color
        content.font(type.font).tracking(type.tracking).foregroundStyle(resolved)
    }
}

extension View {
    /// 文字のトークンを当てる。色を渡さなければトークンの色（atypeInk があればそれ）。
    func atype(_ type: AType, color: Color? = nil) -> some View {
        modifier(ATypeModifier(type: type, color: color))
    }
}

/// 数字（ドットマトリクス）の大きさ。
enum DotSize {
    case large   // 7pt
    case medium  // 4pt
    case small   // 2.5pt
    case tiny    // 1.4pt：文字（13pt前後）と並べる補足の数字

    var dot: CGFloat {
        switch self {
        case .large: 7
        case .medium: 4
        case .small: 2.5
        case .tiny: 1.4
        }
    }

    var spacing: CGFloat {
        switch self {
        case .large: 1.5
        case .medium: 1.2
        case .small: 0.8
        case .tiny: 0.5
        }
    }
}

extension DotMatrixText {
    init(_ text: String, size: DotSize, color: Color = Theme.ink) {
        self.init(text, dotSize: size.dot, spacing: size.spacing, color: color)
    }
}
