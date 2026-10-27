import SwiftUI
import WidgetKit
import AppIntents

// ウィジェットとライブアクティビティの中身。アプリ（DEBUG のギャラリー）とウィジェットの両方で使う。
// 背景は containerBackground に渡すので、中身とは分けて書く。

/// 色を抜いた表示（アクセント／クリア）かどうか。ギャラリーでは force で決める。
private struct AccentedReader<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    var force: Bool?
    @ViewBuilder var content: (Bool) -> Content
    var body: some View { content(force ?? (mode != .fullColor)) }
}

// MARK: - 小：お椀に今の1匹

struct SmallNowBackground: View {
    var display: NowDisplay
    var body: some View {
        ZStack {
            Color.white
            if case .focusing = display {} else { SeigaihaFade() }
        }
    }
}

struct SmallNowWidgetView: View {
    var display: NowDisplay
    var accented: Bool? = nil

    var body: some View {
        AccentedReader(force: accented) { a in
            let ink: Color = a ? .white : K.navy
            Group {
                switch display {
                case .item(_, let text, let deadline):
                    VStack(alignment: .leading, spacing: 0) {
                        PixelBowl(look: a ? .white(water: 0.3) : .color, width: 104)
                            .frame(maxWidth: .infinity).padding(.top, 4)
                        Text(text).font(K.item(19)).lineSpacing(1).lineLimit(2).minimumScaleFactor(0.7)
                            .foregroundStyle(ink).padding(.top, 12)
                        Spacer(minLength: 0)
                        if let deadline {
                            Text(K.deadline(deadline)).font(K.dot(13)).foregroundStyle(a ? Color.white.opacity(0.85) : K.red)
                                .accessibilityLabel(K.deadlineSpoken(deadline))
                        }
                    }
                case .focusing(_, let text, let start, let ended):
                    // 名前は出さず、泡のお椀と経過だけ
                    VStack(spacing: 0) {
                        PixelBowl(bubbles: true, look: a ? .white(water: 0.3) : .color, width: 108)
                            .padding(.top, 4)
                        Spacer(minLength: 0)
                        FocusTimer(start: start, ended: ended).font(K.dot(36)).foregroundStyle(ink)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("集中している：\(text)")
                case .done(let text):
                    // 袋に入れて持ち帰った金魚だけ
                    PixelBag(line: a ? .white : nil, width: 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("できた。持ち帰った：\(text)")
                case .empty:
                    // 水だけのお椀
                    PixelBowl(fish: false, look: a ? .white(water: 0.3) : .color, width: 132)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("お椀はからっぽ")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 押したときの行き先
    static func url(for display: NowDisplay) -> URL {
        if case .empty = display { return AtohaLink.later }
        return AtohaLink.now
    }
}

/// 集中の経過（ひとりでに進む）。止まっていればその時間。
struct FocusTimer: View {
    var start: Date
    var ended: Date?
    var body: some View {
        if let ended {
            Text(K.elapsed(ended.timeIntervalSince(start)))
        } else {
            Text(timerInterval: start...start.addingTimeInterval(60 * 60 * 24), countsDown: false)
                .monospacedDigit()
        }
    }
}

// MARK: - 小：あとに回す（水面）

struct WaterBackground: View {
    var body: some View { WaterDots() }
}

struct SmallCaptureWidgetView: View {
    var accented: Bool? = nil

    var body: some View {
        AccentedReader(force: accented) { a in
            GeometryReader { g in
                let s = g.size.width / 170
                ZStack(alignment: .topLeading) {
                    Ripple(color: a ? .white : K.waterDot,
                           inner: CGSize(width: 92 * s, height: 30 * s), outer: CGSize(width: 136 * s, height: 46 * s))
                        .position(x: g.size.width / 2, y: g.size.height / 2 + 18 * s)
                    PixelFry(color: (a ? Color.white : K.navy).opacity(0.45), unit: 2.4 * s)
                        .position(x: 26 * s + 10.8 * s, y: 120 * s + 6 * s)
                    PixelFry(color: (a ? Color.white : K.navy).opacity(0.3), unit: 2 * s, mirrored: true)
                        .position(x: 120 * s + 9 * s, y: 28 * s + 5 * s)
                    Text("＋").font(.system(size: 34, weight: .black)).foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(a ? Color.white.opacity(0.25) : K.red))
                        .background(Circle().fill(a ? Color.clear : K.navy).offset(y: 4))
                        .position(x: g.size.width / 2, y: g.size.height / 2 - 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("あとに回す")
    }
}

// MARK: - 中：お椀と今の1匹、集中する

struct MediumNowBackground: View {
    var display: NowDisplay
    var body: some View {
        ZStack(alignment: .trailing) {
            SmallNowBackground(display: display)
            WaterDots().frame(width: 70)
        }
    }
}

struct MediumNowWidgetView: View {
    var display: NowDisplay
    var accented: Bool? = nil

    var body: some View {
        AccentedReader(force: accented) { a in
            let ink: Color = a ? .white : K.navy
            HStack(spacing: 0) {
                Group {
                    switch display {
                    case .done(let text):
                        // 袋に入った金魚だけ
                        PixelBag(line: a ? .white : nil, width: 84)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement()
                            .accessibilityLabel("できた。持ち帰った：\(text)")
                    case .empty:
                        // 水だけのお椀
                        PixelBowl(fish: false, look: a ? .white(water: 0.3) : .color, width: 168)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement()
                            .accessibilityLabel("お椀はからっぽ")
                    case .item(let id, let text, let deadline):
                        HStack(spacing: 12) {
                            PixelBowl(look: a ? .white(water: 0.3) : .color, width: 128)
                                .frame(width: 128).frame(maxHeight: .infinity)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(text).font(K.item(22)).lineLimit(2).minimumScaleFactor(0.7).foregroundStyle(ink).padding(.top, 6)
                                if let deadline {
                                    Text(K.deadline(deadline)).font(K.dot(13)).foregroundStyle(a ? Color.white.opacity(0.85) : K.red).padding(.top, 4)
                                        .accessibilityLabel(K.deadlineSpoken(deadline))
                                }
                                Spacer(minLength: 4)
                                Link(destination: AtohaLink.focus(id)) {
                                    Image(systemName: "play.fill").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                                        .padding(.leading, 3)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(a ? Color.white.opacity(0.25) : K.navy))
                                }
                                .accessibilityLabel("集中する")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    case .focusing(_, let text, let start, let ended):
                        HStack(spacing: 12) {
                            PixelBowl(bubbles: true, look: a ? .white(water: 0.3) : .color, width: 128)
                                .frame(width: 128).frame(maxHeight: .infinity)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(text).font(K.item(22)).lineLimit(2).minimumScaleFactor(0.7).foregroundStyle(ink).padding(.top, 6)
                                Spacer(minLength: 4)
                                FocusTimer(start: start, ended: ended).font(K.dot(30)).foregroundStyle(ink)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .padding(16)
                .padding(.trailing, -4)

                Link(destination: AtohaLink.capture) {
                    VStack(spacing: 0) {
                        Text("＋").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(a ? Color.white.opacity(0.25) : K.red))
                            .background(Circle().fill(a ? Color.clear : K.navy).offset(y: 3))
                    }
                    .frame(width: 70)
                    .frame(maxHeight: .infinity)
                }
                .accessibilityLabel("あとに回す")
            }
        }
    }
}

// MARK: - ロック画面

/// 1行：金魚と名前（「今：」は付けない）
struct LockInlineView: View {
    var display: NowDisplay
    var body: some View {
        let text: String = switch display {
        case .item(_, let t, _), .focusing(_, let t, _, _): t
        case .done, .empty: ""
        }
        Label {
            Text(text)
        } icon: {
            Image(uiImage: PixelFish.templateImage(height: 10))
        }
        .accessibilityLabel(text.isEmpty ? (display == .empty ? "お椀はからっぽ" : "できた") : "今：\(text)")
    }
}

/// 長方形：白い線のお椀と金魚、名前と期限
struct LockRectangularView: View {
    var display: NowDisplay
    var body: some View {
        switch display {
        case .done(let text):
            // 袋に入った金魚だけ、まんなかに
            PixelBag(onDark: true, line: .white, width: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement().accessibilityLabel("できた。持ち帰った：\(text)")
        case .empty:
            // 水だけのお椀、まんなかに
            PixelBowl(fish: false, look: .white(water: 0.35), width: 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement().accessibilityLabel("お椀はからっぽ")
        default:
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            switch display {
            case .done:
                EmptyView()
            default:
                PixelBowl(fish: display != .empty, bubbles: { if case .focusing = display { return true } else { return false } }(),
                          look: .white(water: 0.35), width: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                switch display {
                case .item(_, let text, let deadline):
                    Text(text).font(K.item(15)).lineLimit(2).minimumScaleFactor(0.8)
                    if let deadline { Text(K.deadline(deadline)).font(K.dot(11)).opacity(0.8).accessibilityLabel(K.deadlineSpoken(deadline)) }
                case .focusing(_, let text, let start, let ended):
                    Text(text).font(K.item(15)).lineLimit(1).minimumScaleFactor(0.8)
                    FocusTimer(start: start, ended: ended).font(K.dot(15))
                case .done(let text):
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel("できた。持ち帰った：\(text)")
                case .empty:
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel("お椀はからっぽ")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// 丸：波紋の＋（あとに回す）
struct LockCircularView: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width / 68
            ZStack {
                Ripple(color: .white, inner: CGSize(width: 40 * s, height: 12 * s), outer: CGSize(width: 56 * s, height: 18 * s),
                       opacities: (0.7, 0.35), lineWidth: 1.4)
                    .position(x: g.size.width / 2, y: 40 * s)
                Text("＋").font(.system(size: 26 * s, weight: .black)).foregroundStyle(.white)
                    .position(x: g.size.width / 2, y: 34 * s - 6 * s)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("あとに回す")
    }
}

// MARK: - ライブアクティビティ

/// ロック画面のバナー：泡のお椀、今と名前、経過、紅の＋、下に水の帯
struct LiveBannerView: View {
    var text: String
    var start: Date
    var ended: Date?

    var body: some View {
        HStack(spacing: 12) {
            PixelBowl(bubbles: true, width: 74)
            Text(text).font(K.item(18)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(K.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
            FocusTimer(start: start, ended: ended).font(K.dot(32)).foregroundStyle(K.navy)
                .multilineTextAlignment(.trailing).frame(maxWidth: 96, alignment: .trailing)
            Button(intent: CaptureIntent()) {
                Text("＋").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Circle().fill(K.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("あとに回す")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
        .background(alignment: .bottom) { WaterDots().frame(height: 10) }
    }
}

/// アイランド（小さく・左）：白い縁のお椀に金魚
struct IslandCompactLeading: View {
    var body: some View { PixelBowl(look: .island(surface: false), width: 30) }
}

/// アイランド（小さく・右）：経過
struct IslandCompactTrailing: View {
    var start: Date
    var ended: Date?
    var body: some View {
        FocusTimer(start: start, ended: ended).font(K.dot(15)).foregroundStyle(.white)
            .multilineTextAlignment(.trailing).frame(maxWidth: 52, alignment: .trailing)
    }
}

/// アイランド（いちばん小さく）：紅の金魚
struct IslandMinimal: View {
    var body: some View { PixelFish(color: K.red, width: 18) }
}

/// アイランド（広げたとき）の下のボタン2つ
struct IslandButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CaptureIntent()) {
                Text("＋").font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(K.navy2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("あとに回す")
            Button(intent: FocusDoneIntent()) {
                PixelBag(lineOnly: true, line: .white, width: 18)
                .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(K.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("できた。持ち帰る")
        }
    }
}

/// アイランド（広げたとき）の上の段：お椀・名前・経過
struct IslandExpandedRow: View {
    var text: String
    var start: Date
    var ended: Date?
    var body: some View {
        HStack(spacing: 10) {
            PixelBowl(look: .island(surface: true), width: 64)
            Text(text).font(K.item(17)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            FocusTimer(start: start, ended: ended).font(K.dot(28)).foregroundStyle(.white)
                .multilineTextAlignment(.trailing).frame(maxWidth: 90, alignment: .trailing)
        }
    }
}

/// ロック画面のバナー（できたとき、数秒だけ）：袋と金魚だけ
struct LiveDoneBannerView: View {
    var body: some View {
        HStack(spacing: 12) {
            PixelBag(width: 34)
            PixelFish(color: K.red, width: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement()
        .accessibilityLabel("持ち帰りました")
    }
}

/// アイランド（できたとき、数秒だけ）：袋と金魚。「持ち帰りました」の文字は出さない
struct IslandDoneView: View {
    var body: some View {
        HStack(spacing: 8) {
            PixelBag(onDark: true, line: .white, width: 14)
            PixelFish(color: K.red, width: 20)
            Spacer(minLength: 0)
        }
        .accessibilityElement()
        .accessibilityLabel("持ち帰りました")
    }
}
