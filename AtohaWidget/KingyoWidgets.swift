import SwiftUI
import WidgetKit

/// アプリが App Group に置いた写しを読む。アプリが書き直すたびに reloadAllTimelines で呼ばれる。
struct NowProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: WidgetSnapshot
        var display: NowDisplay { snapshot.display(at: date) }
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let s = WidgetSnapshot.load()
        completion(Entry(date: .now, snapshot: context.isPreview && s.isEmpty ? .sample : s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date.now
        let s = WidgetSnapshot.load()
        var entries = [Entry(date: now, snapshot: s)]
        // 「持ち帰った」は少しだけ出して、ふだんの表示に戻す
        if let doneAt = s.doneAt, doneAt.addingTimeInterval(WidgetSnapshot.doneMoment) > now {
            entries.append(Entry(date: doneAt.addingTimeInterval(WidgetSnapshot.doneMoment), snapshot: s))
        }
        // 期限の「今日／明日」が変わる日付の変わり目に読み直す
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

/// 今の1匹（小・中・ロック画面）
struct NowWidget: Widget {
    static let kind = "app.atoha.prototype.now"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowProvider()) { entry in
            NowWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今の1匹")
        .description("お椀に入っている今の1つだけを出す")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct NowWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowProvider.Entry

    var body: some View {
        let d = entry.display
        switch family {
        case .systemMedium:
            MediumNowWidgetView(display: d)
                .containerBackground(for: .widget) { MediumNowBackground(display: d) }
                .widgetURL(SmallNowWidgetView.url(for: d))
        case .accessoryInline:
            LockInlineView(display: d)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(SmallNowWidgetView.url(for: d))
        case .accessoryRectangular:
            LockRectangularView(display: d)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(SmallNowWidgetView.url(for: d))
        default:
            SmallNowWidgetView(display: d)
                .containerBackground(for: .widget) { SmallNowBackground(display: d) }
                .widgetURL(SmallNowWidgetView.url(for: d))
        }
    }
}

/// あとに回す（小・ロック画面の丸）。押すと書き出し画面へ。
struct CaptureWidget: Widget {
    static let kind = "app.atoha.prototype.capturewidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowProvider()) { _ in
            CaptureWidgetEntryView()
        }
        .configurationDisplayName("あとに回す")
        .description("気になっていることを書いて、あとに回す")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

struct CaptureWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                LockCircularView()
                    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            } else {
                SmallCaptureWidgetView()
                    .containerBackground(for: .widget) { WaterBackground() }
            }
        }
        .widgetURL(AtohaLink.capture)
    }
}
