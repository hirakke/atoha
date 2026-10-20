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
