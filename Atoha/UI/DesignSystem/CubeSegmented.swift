import SwiftUI

/// 丸い切り替え。選ばれた側が藍の丸になる。
struct CubeSegmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    var detail: (T) -> String? = { _ in nil }
    @Binding var selection: T
    var fill = false

    init(options: [T], label: @escaping (T) -> String, detail: @escaping (T) -> String? = { _ in nil },
         selection: Binding<T>, fill: Bool = false) {
        self.options = options
        self.label = label
        self.detail = detail
        self._selection = selection
        self.fill = fill
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    VStack(spacing: 2) {
                        Text(label(option)).lineLimit(1)
                            .atype(.small, color: on ? Theme.paper : Theme.ink)
                            .fontWeight(on ? .black : .bold)
                        if let detail = detail(option) {
                            Text(detail).atype(.label, color: on ? Theme.paper.opacity(0.7) : Theme.quiet)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: fill ? .infinity : nil, minHeight: 38)
                    .background(Capsule().fill(on ? Theme.ink : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.faint.opacity(0.7)))
        .fixedSize(horizontal: !fill, vertical: false)
    }
}
