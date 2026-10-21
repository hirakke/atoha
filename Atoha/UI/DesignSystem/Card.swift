import SwiftUI

/// 小見出し。太字の墨と、その下の2ptの罫。
struct SectionLabel: View {
    let text: String
    var ruled = true
    @Environment(\.atypeInk) private var ink
    init(_ text: String, ruled: Bool = true) { self.text = text; self.ruled = ruled }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(Theme.sans(12, weight: .black)).foregroundStyle(ink ?? Theme.ink)
            if ruled { Rectangle().fill(ink ?? Theme.ink).frame(height: Theme.stroke) }
        }
        .frame(maxWidth: ruled ? .infinity : nil, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

enum CardStyle {
    /// 紙の面に薄い罫の枠
    case plain
    /// アクセントの面、2ptの墨の枠と墨の押し出し（次の1つ）
    case accent
}

/// 箱。角は立方体のまま。
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var opaque = false
    var style: CardStyle = .plain
    @ViewBuilder var content: Content

    init(padding: CGFloat = 14, opaque: Bool = false, style: CardStyle = .plain, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.opaque = opaque
        self.style = style
        self.content = content()
    }

    var body: some View {
        switch style {
        case .plain:
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paper)
                .overlay(Rectangle().strokeBorder(Theme.faint, lineWidth: 1))
        case .accent:
            content
                .environment(\.atypeInk, Theme.onAccent)
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                .background(Rectangle().fill(Theme.ink).offset(x: 6, y: 6))
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
    }
}

/// 方眼の上で文字を読みやすくするための紙の面。方眼は余白にだけ見せる。
struct PaperSheet: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
    }
}

extension View {
    /// 紙の面に載せる（リストや設定のまとまり）
    func onPaper(padding: CGFloat = 16) -> some View { modifier(PaperSheet(padding: padding)) }
}
