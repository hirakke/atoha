import SwiftUI
import SwiftData

/// やりたい（縦）× やらなきゃ（横）を、指で置いて決めるパッド。値は 0...1。
struct WantMustPicker: View {
    @Binding var want: Double?
    @Binding var must: Double?
    var kind: ItemKind = .concern
    var side: CGFloat = 180
    /// 触れた瞬間に呼ぶ（書き出し画面で変換中の文字を確定させる）
    var onTouch: () -> Void = {}
    var onDone: () -> Void = {}

    @State private var point: CGPoint?
    @State private var touching = false
    private let pitch: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let n = Int(size.width / pitch)
                let step = size.width / CGFloat(n)
                for i in 0...n {
                    for j in 0...n {
                        let center = (i == n / 2 || j == n / 2)
                        let r: CGFloat = center ? 1.4 : 0.8
                        let p = CGPoint(x: CGFloat(i) * step, y: CGFloat(j) * step)
                        ctx.fill(Path(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(center ? Theme.ink.opacity(0.35) : Theme.faint))
                    }
                }
            }
            if let point {
                DotMark(kind: kind, want: 1 - Double(point.y / side), must: Double(point.x / side), size: 12, flat: true)
                    .position(point)
            }
            Text("やりたい").atype(.label)
                .frame(width: side).offset(y: -14)
            Text("やらなきゃ").atype(.label)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .position(x: side + 10, y: side / 2)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged {
                    if !touching { touching = true; onTouch() }
                    point = clamp($0.location)
                }
                .onEnded { value in
                    touching = false
                    let p = clamp(value.location)
                    point = p
                    want = 1 - Double(p.y / side)
                    must = Double(p.x / side)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDone()
                }
        )
        .onAppear {
            if let w = want, let m = must { point = CGPoint(x: m * side, y: (1 - w) * side) }
        }
        .padding(.top, 14).padding(.trailing, 20)
        .accessibilityLabel("やりたい やらなきゃ")
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(side, max(0, p.x)), y: min(side, max(0, p.y)))
    }
}

/// 返ってきたものに付けるパッド。置いたらその場で保存する。
struct WantMustPad: View {
    @Bindable var item: Item
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context

    var body: some View {
        WantMustPicker(want: $item.want, must: $item.must, kind: item.kind) {
            try? context.save()
            onDone()
        }
    }
}

/// 書き出し画面の「気持ちを付ける」パッド。横長の板に指で置く（上ほどやりたい、右ほどやらなきゃ）。
/// 薄い網点と点線の十字、四隅の言葉。置いたところは白い丸と紅い輪、中に色の付いた金魚。
struct WantMustBoard: View {
    @Binding var want: Double?
    @Binding var must: Double?
    var height: CGFloat = 264

    /// 丸が板からはみ出さないよう、端から少し内側までにする
    private let inset: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                grid
                if let want, let must {
                    marker(want: want, must: must).position(point(want: want, must: must, in: size))
                }
                captions
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { place($0.location, in: size) }
                    .onEnded { value in
                        place(value.location, in: size)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
        }
        .frame(height: height)
        // 読み上げでは、上下のスワイプで4つの置き場所を順にたどる
        .accessibilityElement()
        .accessibilityLabel("やりたい・やらなきゃ")
        .accessibilityValue(valueText)
        .accessibilityHint("上下にスワイプして置く場所を選ぶ")
        .accessibilityAdjustableAction { direction in
            let order = Self.presets
            let current = order.firstIndex { want != nil && GoldfishTint.of(want: want!, must: must ?? 0) == $0.tint }
            let next: Int = switch direction {
            case .increment: current.map { ($0 + 1) % order.count } ?? 0
            case .decrement: current.map { ($0 + order.count - 1) % order.count } ?? order.count - 1
            @unknown default: current ?? 0
            }
            want = order[next].want
            must = order[next].must
        }
    }

    /// 読み上げで選ぶ4つの置き場所
    private static let presets: [(tint: GoldfishTint, want: Double, must: Double)] = [
        (.red, 0.8, 0.2), (.both, 0.8, 0.8), (.black, 0.2, 0.8), (.faint, 0.2, 0.2),
    ]

    private var valueText: String {
        guard let want, let must else { return "まだ置いていない" }
        let tint = GoldfishTint.of(want: want, must: must)
        return "\(tint.label)、\(Self.qualifier(tint))"
    }

    /// 色の名前の横に添える一言
    static func qualifier(_ tint: GoldfishTint) -> String {
        switch tint {
        case .red: "やらなきゃは弱め"
        case .black: "やりたいは弱め"
        case .both: "どちらも強め"
        case .faint: "どちらも弱め"
        }
    }

    /// 網点と点線の十字
    private var grid: some View {
        let ink = Theme.ink
        return Canvas { context, size in
            let pitch: CGFloat = 16
            var dots = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                    x += pitch
                }
                y += pitch
            }
            context.fill(dots, with: .color(ink.opacity(0.18)))
            var cross = Path()
            cross.move(to: CGPoint(x: size.width / 2, y: 10))
            cross.addLine(to: CGPoint(x: size.width / 2, y: size.height - 10))
            cross.move(to: CGPoint(x: 10, y: size.height / 2))
            cross.addLine(to: CGPoint(x: size.width - 10, y: size.height / 2))
            context.stroke(cross, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1.6, dash: [3, 5]))
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.paper.opacity(0.7)))
    }

    /// 四隅の言葉（やりたい・やらなきゃは太く、両方・どちらでもないは控えめに）
    private var captions: some View {
        ZStack {
            Text("↑ やりたい").font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
            Text("両方").font(.system(.caption, weight: .bold)).foregroundStyle(Theme.quiet)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(14)
            Text("どちらでもない").font(.system(.caption, weight: .bold)).foregroundStyle(Theme.quiet)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 14)
            Text("やらなきゃ →").font(.system(.footnote, weight: .black)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
        }
        .allowsHitTesting(false)
    }

    private func marker(want: Double, must: Double) -> some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.1)).frame(width: 60, height: 60)
            Circle().fill(Theme.surface).frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
            GoldfishMark(tint: GoldfishTint.of(want: want, must: must), width: 22.5)
        }
        .allowsHitTesting(false)
    }

    private func point(want: Double, must: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: inset + must * (size.width - inset * 2),
                y: inset + (1 - want) * (size.height - inset * 2))
    }

    private func place(_ location: CGPoint, in size: CGSize) {
        let w = max(1, size.width - inset * 2), h = max(1, size.height - inset * 2)
        must = min(1, max(0, Double((location.x - inset) / w)))
        want = min(1, max(0, Double(1 - (location.y - inset) / h)))
    }
}
