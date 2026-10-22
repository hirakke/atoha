import SwiftUI

/// 小見出し。太字の墨と、その下の細い罫。
struct SectionLabel: View {
    let text: String
    var ruled = true
    @Environment(\.atypeInk) private var ink
    init(_ text: String, ruled: Bool = true) { self.text = text; self.ruled = ruled }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(ink ?? Theme.ink)
            if ruled { Rectangle().fill(Theme.faint).frame(height: 2) }
        }
        .frame(maxWidth: ruled ? .infinity : nil, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

enum CardStyle {
    /// 白い面に藍の太い枠
    case plain
    /// アクセントの面、藍の枠と藍のずらした影（次の1つ）
    case accent
}

/// 箱。角を丸め、太い藍の線で囲む。
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
        let shape = RoundedRectangle(cornerRadius: Theme.radius)
        switch style {
        case .plain:
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(Theme.surface))
                .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        case .accent:
            content
                .environment(\.atypeInk, Theme.onAccent)
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(Theme.accent))
                .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                .background(shape.fill(Theme.ink).offset(x: Theme.shadow + 1, y: Theme.shadow + 1))
                .padding(.trailing, Theme.shadow + 1)
                .padding(.bottom, Theme.shadow + 1)
        }
    }
}

/// 白い面に載せる（リストや設定のまとまり）。角を丸め、藍の太い線で囲む。
struct PaperSheet: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.stroke))
    }
}

extension View {
    /// 白い面に載せる（リストや設定のまとまり）
    func onPaper(padding: CGFloat = 16) -> some View { modifier(PaperSheet(padding: padding)) }

    /// 箱の上辺に貼るステッカー（「次」「おすすめ」など）
    func sticker(_ text: String, color: Color = Theme.accent) -> some View {
        overlay(alignment: .topLeading) {
            Text(text)
                .font(Theme.display(.subheadline))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Capsule().fill(color))
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                .offset(x: 14, y: -16)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
