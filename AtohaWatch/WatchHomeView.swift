import SwiftUI
import WatchKit

/// 時計の画面の切り替え。今（または集中・からっぽ）を土台に、あとに回す → 放したあと → 今 と流れる。
enum WatchScreen: String {
    case home, capture, released, full, taken
}

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore
    @Binding var screen: WatchScreen

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch screen {
            case .home:
                if store.snapshot.isFocusing {
                    FocusScreen(onCapture: openCapture, onDone: { screen = .taken })
                } else if store.snapshot.nowText != nil {
                    NowScreen(onCapture: openCapture)
                } else {
                    EmptyBowlScreen(onCapture: openCapture)
                }
            case .capture:
                CaptureScreen(screen: $screen)
            case .released:
                ReleasedScreen(screen: $screen)
            case .full:
                FullTankScreen(screen: $screen)
            case .taken:
                TakenHomeScreen(screen: $screen)
            }
        }
        .animation(.easeOut(duration: 0.25), value: screen)
    }

    /// 水槽がいっぱいなら、話す画面の代わりに知らせる。
    private func openCapture() {
        screen = store.isFull ? .full : .capture
    }
}

// MARK: - 部品

/// 画面の枠。上に小さな見出し（時刻は OS が右上に出す）、下にボタン。
private struct KScreen<Header: View, Content: View, Footer: View>: View {
    var seigaiha = false
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if seigaiha {
                    Seigaiha()
                        .frame(height: proxy.size.height * 0.45)
                }
                VStack(spacing: 0) {
                    HStack { header; Spacer(minLength: 0) }
                        .frame(height: 20)
                    content
                    Spacer(minLength: 0)
                    footer
                }
                .padding(EdgeInsets(top: 10, leading: 13, bottom: 11, trailing: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

/// 「今」の札（紅のドットの金魚＋字）
private struct NowLabel: View {
    var text = "今"
    var color = KColor.now
    var fish = true

    var body: some View {
        HStack(spacing: 5) {
            if fish { PixelArt(rows: KPixel.fish, cell: 16.0 / 9.0, color: color) }
            Text(text).font(KFont.display(15)).foregroundStyle(color)
        }
    }
}

/// Liquid Glass のボタン。決める1つだけ紅。
private struct KGlassStyle: ButtonStyle {
    var red = false
    var fontSize: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if red {
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.925, green: 0.275, blue: 0.353),
                                                           Color(red: 0.78, green: 0.118, blue: 0.204)],
                                                  startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(Color(red: 1, green: 0.745, blue: 0.776).opacity(0.55), lineWidth: 1))
                }
            }
            .glassEffect(red ? .regular.tint(KColor.fish.opacity(0.4)).interactive() : .regular.interactive(), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .contentShape(Capsule())
    }
}

/// 下に並ぶ「決める1つ」と「＋」
private struct ActionRow: View {
    let title: String
    let action: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) { Text(title) }
                .buttonStyle(KGlassStyle(red: true))
                .frame(height: 40)
            Button(action: onPlus) { Text("＋") }
                .buttonStyle(KGlassStyle(fontSize: 20))
                .frame(width: 40, height: 40)
                .accessibilityLabel("あとに回す")
        }
    }
}

// MARK: - 1 今

private struct NowScreen: View {
    @EnvironmentObject private var store: WatchStore
    let onCapture: () -> Void

    var body: some View {
        KScreen(seigaiha: true) {
            NowLabel()
        } content: {
            BowlArt(fish: true)
                .padding(.top, 12)
            Text(store.snapshot.nowText ?? "")
                .font(.system(size: 20, weight: .black))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            if let deadline = store.snapshot.nowDeadline {
                Text(WatchSnapshot.deadlineLabel(deadline))
                    .font(KFont.dot(15))
                    .foregroundStyle(KColor.now)
                    .padding(.top, 3)
            }
        } footer: {
            ActionRow(title: "▶ 集中する", action: {
                WKInterfaceDevice.current().play(.start)
                store.startFocus()
            }, onPlus: onCapture)
        }
    }
}

// MARK: - 2 あとに回す（話して、放す）

private struct CaptureScreen: View {
    @EnvironmentObject private var store: WatchStore
    @Binding var screen: WatchScreen
    @State private var text = WatchApp.debugCaptureText

    var body: some View {
        KScreen {
            Button { screen = .home } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(KColor.quiet)
                    Text("あとに回す").font(KFont.display(15))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("やめる")
        } content: {
            VoiceWave(active: !text.isEmpty)
                .padding(.top, 12)
            Group {
                if text.isEmpty {
                    Text("マイクを押して話す")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KColor.quiet)
                } else {
                    // 終わりに紅の細いカーソル
                    (Text(text) + Text(" |").font(.system(size: 18, weight: .ultraLight)).foregroundColor(KColor.now))
                        .font(.system(size: 18, weight: .black))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        } footer: {
            HStack(spacing: 6) {
                // マイクのボタン＝システムの入力（音声・手書き）を開く。書いたものは上に出す。
                TextField("話す", text: Binding(get: { "" }, set: { new in
                    let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { text = t }
                }), prompt: Text(" "))
                // プロンプトに画像を入れると入力が開かないので、マイクは上に重ねて描く
                .foregroundStyle(.clear)
                .frame(width: 40, height: 40)
                .background {
                    Capsule().fill(.white.opacity(0.15))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.26), lineWidth: 1))
                        .allowsHitTesting(false)
                }
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .allowsHitTesting(false)
                }
                .clipShape(Capsule())

                Button(action: release) { Text("放す") }
                    .buttonStyle(KGlassStyle(red: true))
                    .frame(height: 40)
                    .opacity(text.isEmpty ? 0.45 : 1)
                    .disabled(text.isEmpty)
            }
        }
    }

    private func release() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // いつ戻すかは聞かない（iPhone の「手が空いたら」と同じ）
        store.capture(text: trimmed, timing: .atBreak)
        text = ""
        screen = .released
    }
}

/// 声の波（ドット）。話したあとは前半が紅。
private struct VoiceWave: View {
    var active: Bool
    private let bars: [(y: CGFloat, h: CGFloat)] = [(5, 3), (3, 7), (1, 11), (4, 5), (2, 9), (5, 3), (0, 13), (3, 7), (5, 3)]

    var body: some View {
        Canvas { ctx, _ in
            let s: CGFloat = 2
            for i in 0..<18 {
                let x = CGFloat(2 + i * 5) * s
                if active && i < bars.count {
                    let b = bars[i]
                    ctx.fill(Path(CGRect(x: x, y: b.y * s, width: 2 * s, height: b.h * s)), with: .color(KColor.now))
                } else {
                    ctx.fill(Path(CGRect(x: x, y: 5 * s, width: 2 * s, height: 3 * s)), with: .color(.white.opacity(0.3)))
                }
            }
        }
        .frame(width: 182, height: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - 3 放したあと（稚魚が沈んで、今に戻る）

private struct ReleasedScreen: View {
    @Binding var screen: WatchScreen
    @State private var sunk = WatchApp.debugFrozen

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let surface = h * 132 / 248
            ZStack(alignment: .topLeading) {
                DarkWater()
                    .frame(width: w, height: h - surface)
                    .offset(y: surface)
                Wave()
                    .stroke(KColor.waterLine, lineWidth: 1.6)
                    .frame(width: w, height: 10)
                    .offset(y: surface - 5)
                Ellipse().stroke(.white.opacity(sunk ? 0.7 : 0), lineWidth: 1.2)
                    .frame(width: sunk ? 44 : 8, height: sunk ? 8 : 2)
                    .position(x: w / 2, y: surface)
                Ellipse().stroke(.white.opacity(sunk ? 0.3 : 0), lineWidth: 1)
                    .frame(width: sunk ? 76 : 10, height: sunk ? 14 : 2)
                    .position(x: w / 2, y: surface)
                Rectangle().fill(.white.opacity(0.55)).frame(width: 2, height: 2)
                    .position(x: w / 2, y: sunk ? surface + 15 : surface)
                Rectangle().fill(.white.opacity(0.45)).frame(width: 2, height: 2)
                    .position(x: w / 2 - 4, y: sunk ? surface + 25 : surface)
                PixelArt(rows: KPixel.fry, cell: 3, color: .white)
                    .position(x: w / 2, y: sunk ? surface + 45 : surface - 6)
                VStack(spacing: 6) {
                    Text("あとに回した")
                        .font(.system(size: 20, weight: .black))
                    Text("今に戻ろう")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KColor.quiet)
                }
                .frame(width: w)
                .padding(.top, 52)
            }
        }
        .ignoresSafeArea()
        .task {
            WKInterfaceDevice.current().play(.click)
            withAnimation(.easeIn(duration: 1.1)) { sunk = true }
            guard !WatchApp.debugFrozen else { return }
            try? await Task.sleep(for: .seconds(2))
            screen = .home
        }
    }
}

/// 水面のゆるい波
private struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let step = rect.width / 8
        p.move(to: CGPoint(x: 0, y: mid))
        for i in 0..<8 {
            let x0 = CGFloat(i) * step
            p.addQuadCurve(to: CGPoint(x: x0 + step, y: mid),
                           control: CGPoint(x: x0 + step / 2, y: i % 2 == 0 ? mid - 5 : mid + 5))
        }
        return p
    }
}

// MARK: - 4 集中している

private struct FocusScreen: View {
    @EnvironmentObject private var store: WatchStore
    let onCapture: () -> Void
    let onDone: () -> Void

    var body: some View {
        KScreen {
            NowLabel(text: "集中")
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.snapshot.focusText ?? "")
                    .font(.system(size: 18, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 10)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(store.snapshot.focusStart ?? timeline.date)
                    let planned = Double(store.snapshot.focusPlanned ?? 25) * 60
                    VStack(alignment: .leading, spacing: 0) {
                        Text(WatchSnapshot.elapsedLabel(elapsed))
                            .font(KFont.dot(52))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.top, 4)
                        WaterStrip(progress: min(1, elapsed / planned))
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            ActionRow(title: "できた", action: {
                WKInterfaceDevice.current().play(.success)
                store.finish()
                onDone()
            }, onPlus: onCapture)
        }
    }
}

/// 細い水の帯を金魚が泳ぐ（経った時間で右へ）
private struct WaterStrip: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let fishW: CGFloat = 9 * 1.8
            let fill = max(16, w * progress)
            ZStack(alignment: .leading) {
                DarkWater().frame(height: 12).clipShape(Capsule())
                Capsule().fill(KColor.waterDot.opacity(0.35)).frame(width: fill, height: 12)
                PixelArt(rows: KPixel.fish, cell: 1.8, color: KColor.now)
                    .offset(x: min(w - fishW, max(0, fill - 8)))
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - 5 お椀がからっぽ

private struct EmptyBowlScreen: View {
    let onCapture: () -> Void

    var body: some View {
        KScreen(seigaiha: true) {
            NowLabel(color: KColor.quiet, fish: false)
        } content: {
            BowlArt(fish: false)
                .padding(.top, 14)
            Text("お椀はからっぽ")
                .font(.system(size: 18, weight: .black))
                .padding(.top, 12)
            Text("iPhone で\nあとでから すくう")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KColor.quiet)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 4)
        } footer: {
            Button(action: onCapture) { Text("＋ あとに回す") }
                .buttonStyle(KGlassStyle())
                .frame(height: 40)
        }
    }
}

// MARK: - 6 水槽がいっぱい

private struct FullTankScreen: View {
    @Binding var screen: WatchScreen

    var body: some View {
        KScreen {
            Button { screen = .home } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(KColor.quiet)
                    Text("あとに回す").font(KFont.display(15))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("もどる")
        } content: {
            FullTank()
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("水槽がいっぱい")
                .font(.system(size: 18, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            Text("iPhone で1匹放すと\nまた回せる")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KColor.quiet)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } footer: {
            EmptyView()
        }
    }
}

/// 金魚でぎゅうぎゅうの水槽（91×31 を2倍）
private struct FullTank: View {
    private let fish: [(x: CGFloat, y: CGFloat, red: Bool)] = [
        (5, 4, true), (18, 9, false), (31, 3, true), (44, 12, false), (57, 5, true), (72, 10, false),
        (8, 19, false), (24, 21, true), (40, 20, false), (58, 20, true), (74, 22, false),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            DarkWater()
            ForEach(Array(fish.enumerated()), id: \.offset) { _, f in
                PixelArt(rows: KPixel.fish, cell: 2, color: f.red ? KColor.fish : .white)
                    .offset(x: f.x * 2, y: f.y * 2)
            }
        }
        .frame(width: 180, height: 60, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.7), lineWidth: 2))
        .accessibilityLabel("金魚でいっぱいの水槽")
    }
}

// MARK: - できた（袋の絵が一瞬）

private struct TakenHomeScreen: View {
    @Binding var screen: WatchScreen

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                PixelArt(rows: KPixel.bag, cell: 6, color: .white)
                PixelArt(rows: KPixel.fish, cell: 4, color: KColor.fish).offset(y: 10)
            }
            Text("持ち帰った")
                .font(.system(size: 18, weight: .black))
            Text("iPhone の金魚鉢へ")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KColor.quiet)
        }
        .task {
            guard !WatchApp.debugFrozen else { return }
            try? await Task.sleep(for: .seconds(1.2))
            screen = .home
        }
    }
}
