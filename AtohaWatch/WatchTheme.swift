import SwiftUI

/// ウォッチ用の色。iPhone 側 Theme と同じ値（UIKit 非依存）。
enum Theme {
    static let paper = Color.black
    static let ink = Color(red: 0.91, green: 0.90, blue: 0.86)
    static let quiet = ink.opacity(0.45)
    static let faint = ink.opacity(0.15)
    static let accent = Color(red: 0.85, green: 0.35, blue: 0.19)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
