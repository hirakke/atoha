import SwiftUI
import UIKit

/// atoha の色とタイポグラフィ。モノクロ中心、アクセントは1色だけ。
enum Theme {
    /// 背景（紙）
    static let paper = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1) })
    /// 文字とドット（インク）
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.91, green: 0.90, blue: 0.86, alpha: 1)
        : UIColor(red: 0.17, green: 0.17, blue: 0.16, alpha: 1) })
    /// 控えめな文字
    static let quiet = ink.opacity(0.45)
    /// 罫線や背景のドット
    static let faint = ink.opacity(0.15)
    /// 軸に近いもの（唯一のアクセント）
    static let accent = Color(red: 0.85, green: 0.35, blue: 0.19)

    static let accentUIColor = UIColor(red: 0.85, green: 0.35, blue: 0.19, alpha: 1)
    static let inkUIColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.91, green: 0.90, blue: 0.86, alpha: 1)
        : UIColor(red: 0.17, green: 0.17, blue: 0.16, alpha: 1) }

    /// 角の丸み。立方体なので、ほぼ直角。
    static let radius: CGFloat = 2

    /// 本文。ドットの雰囲気に合わせて等幅。
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
