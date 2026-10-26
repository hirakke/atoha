import SwiftUI
import WidgetKit

/// 文字盤のコンプリケーションとスマートスタック。今の1匹と、＋で回すことだけ。
@main
struct AtohaWatchWidgetBundle: WidgetBundle {
    init() { KFont.registerFonts() }

    var body: some Widget {
        NowWidget()
        CaptureWidget()
    }
}

struct NowEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot

    /// 期限が近いほど、スマートスタックの上に上がってくる
    var relevance: TimelineEntryRelevance? {
        if snapshot.isFocusing { return TimelineEntryRelevance(score: 80) }
        guard snapshot.nowText != nil else { return TimelineEntryRelevance(score: 1) }
        guard let deadline = snapshot.nowDeadline else { return TimelineEntryRelevance(score: 10) }
        let hours = deadline.timeIntervalSince(date) / 3600
        let score: Float = hours < 0 ? 60 : Float(max(10, 60 - hours * 5))
        return TimelineEntryRelevance(score: score)
    }
}

struct NowProvider: TimelineProvider {
    static let sample = WatchSnapshot(nowText: "母に電話",
                                      nowDeadline: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now))

    func placeholder(in context: Context) -> NowEntry { NowEntry(date: .now, snapshot: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        let s = WatchSnapshot.load()
        completion(NowEntry(date: .now, snapshot: context.isPreview && s.nowText == nil ? Self.sample : s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        // 期限の関連度を上げるため、1時間ごとに描き直す。中身の変化はアプリから reload する
        let s = WatchSnapshot.load()
        let entries = (0..<6).map { NowEntry(date: Date().addingTimeInterval(Double($0) * 3600), snapshot: s) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - 今（角・四角・1行・スマートスタック）

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.atoha.watch.now", provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
                .containerBackground(for: .widget) { CardBackground() }
                .widgetURL(URL(string: "atoha-watch://now"))
        }
        .configurationDisplayName("今")
        .description("お椀の1匹（次にやること）")
        .supportedFamilies([.accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// 藍の札に、うすい青海波
private struct CardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [KColor.cardTop, KColor.cardBottom], startPoint: .top, endPoint: .bottom)
            Seigaiha()
        }
    }
}

struct NowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowEntry
    private var s: WatchSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // 角：金魚と、今の名前
    private var corner: some View {
        PixelArt(rows: KPixel.fish, cell: 3, color: KColor.fish)
            .widgetAccentable()
            .widgetLabel {
                Text(s.focusText ?? s.nowText ?? "お椀はからっぽ")
            }
    }

    // 1行：今：母に電話 ／ 集中しているとき 12:34 母に電話
    @ViewBuilder private var inline: some View {
        if s.isFocusing, let start = s.focusStart {
            Text("\(Image(systemName: "fish.fill")) \(start, style: .timer) \(s.focusText ?? "")")
        } else if let text = s.nowText {
            Text("\(Image(systemName: "fish.fill")) 今：\(text)")
        } else {
            Text("\(Image(systemName: "fish")) お椀はからっぽ")
        }
    }

    // 四角（スマートスタックの札）
    @ViewBuilder private var rectangular: some View {
        if s.isFocusing, let start = s.focusStart {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("集中している").font(KFont.display(13)).foregroundStyle(KColor.now).widgetAccentable()
                    Text(s.focusText ?? "").font(.system(size: 16, weight: .black)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(start, style: .timer)
                    .font(KFont.dot(26))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 76, alignment: .trailing)
                    .minimumScaleFactor(0.6)
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        PixelArt(rows: KPixel.fish, cell: 16.0 / 9.0, color: KColor.now)
                        Text("今").font(KFont.display(15)).foregroundStyle(KColor.now)
                    }
                    .widgetAccentable()
                    Text(s.nowText ?? "お椀はからっぽ")
                        .font(.system(size: 17, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let deadline = s.nowDeadline, s.nowText != nil {
                        Text(WatchSnapshot.deadlineLabel(deadline)).font(KFont.dot(13)).foregroundStyle(KColor.now)
                    }
                }
                Spacer(minLength: 0)
                Text("＋")
                    .font(.system(size: 20, weight: .black))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.26), lineWidth: 1))
                    .accessibilityLabel("あとに回す")
            }
        }
    }
}

// MARK: - 丸：＋ 回す（押すと話す画面）

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.atoha.watch.capture", provider: NowProvider()) { _ in
            CaptureCircle()
                .containerBackground(for: .widget) { Color.black }
                .widgetURL(URL(string: "atoha-watch://capture"))
        }
        .configurationDisplayName("＋ 回す")
        .description("押すと、あとに回す画面が開く")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct CaptureCircle: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(KColor.fish, lineWidth: 3).widgetAccentable()
            VStack(spacing: 0) {
                Text("＋").font(.system(size: 22, weight: .black))
                Text("回す").font(.system(size: 11, weight: .black))
            }
        }
        .accessibilityLabel("あとに回す")
    }
}
