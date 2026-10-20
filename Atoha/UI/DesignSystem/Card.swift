import SwiftUI

/// 小見出し。
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).atype(.label)
    }
}

/// 1ptの薄い枠の箱。角は立方体のまま。
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var opaque = false
    @ViewBuilder var content: Content

    init(padding: CGFloat = 14, opaque: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.opaque = opaque
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(opaque ? Theme.paper : Color.clear, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.faint, lineWidth: 1))
    }
}
