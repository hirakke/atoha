import SwiftUI

/// 文字のトークン。画面ごとにサイズを決めず、ここから選ぶ。
enum AType {
    case title   // 17 medium
    case body    // 15
    case small   // 13
    case label   // 11, quiet, 少し字間を空ける

    var font: Font {
        switch self {
        case .title: Theme.mono(17, weight: .medium)
        case .body: Theme.mono(15)
        case .small: Theme.mono(13)
        case .label: Theme.mono(11)
        }
    }

    var tracking: CGFloat { self == .label ? 0.6 : 0 }
    var color: Color { self == .label ? Theme.quiet : Theme.ink }

    var uiFont: UIFont {
        switch self {
        case .title: .monospacedSystemFont(ofSize: 17, weight: .medium)
        case .body: .monospacedSystemFont(ofSize: 15, weight: .regular)
        case .small: .monospacedSystemFont(ofSize: 13, weight: .regular)
        case .label: .monospacedSystemFont(ofSize: 11, weight: .regular)
        }
    }
}

extension View {
    /// 文字のトークンを当てる。色を渡さなければトークンの色。
    func atype(_ type: AType, color: Color? = nil) -> some View {
        font(type.font).tracking(type.tracking).foregroundStyle(color ?? type.color)
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
