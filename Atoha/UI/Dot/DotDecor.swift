import SwiftUI

/// 全面に敷く薄いドットグリッド。
struct DotGridBackground: View {
    var spacing: CGFloat = 12
    var color: Color = Theme.faint

    init(spacing: CGFloat = 12, color: Color = Theme.faint) {
        self.spacing = spacing
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 0.9
            var path = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(color))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 数を丸ドットの列で示す。上限を超えたら「+」。
struct DotCountRow: View {
    let count: Int
    var max: Int = 12
    var dotSize: CGFloat = 6

    init(count: Int, max: Int = 12, dotSize: CGFloat = 6) {
        self.count = count
        self.max = max
        self.dotSize = dotSize
    }

    var body: some View {
        HStack(spacing: dotSize * 0.5) {
            ForEach(0..<Swift.max(0, Swift.min(count, max)), id: \.self) { _ in
                Circle().fill(Theme.ink).frame(width: dotSize, height: dotSize)
            }
            if count > max {
                DotMatrixText("+", dotSize: dotSize * 0.16, spacing: dotSize * 0.06)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(count)"))
    }
}

#Preview {
    ZStack {
        Theme.paper.ignoresSafeArea()
        DotGridBackground()
        VStack(alignment: .leading, spacing: 12) {
            DotCountRow(count: 3)
            DotCountRow(count: 12)
            DotCountRow(count: 20)
            DotCountRow(count: 5, max: 4, dotSize: 10)
        }
    }
}
