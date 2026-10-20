import SwiftUI

/// 立方体の分節。選ばれた側が墨の立方体として浮く。
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
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    VStack(spacing: 2) {
                        Text(label(option)).lineLimit(1)
                        if let detail = detail(option) {
                            Text(detail).atype(.label, color: on ? Theme.paper.opacity(0.7) : Theme.quiet)
                        }
                    }
                }
                .buttonStyle(.cube(on ? .primary : .flat, size: .small, fill: fill))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: !fill, vertical: false)
    }
}
