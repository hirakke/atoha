import Foundation
import AppIntents

/// アプリがウィジェットに渡す、今の1匹の小さな写し。App Group の UserDefaults に JSON で置く。
/// アプリは状態が変わるたび（ReturnService.sync、集中の始まり・終わり、持ち帰り）に書き直す。
struct WidgetSnapshot: Codable, Equatable {
    /// 今の1匹（ホームの「次」の札の先頭と同じ選び方）
    var nowID: UUID?
    var nowText: String?
    var nowDeadline: Date?
    /// 集中している1匹
    var focusID: UUID?
    var focusText: String?
    var focusStart: Date?
    /// 区切りを押して計測が止まった時刻
    var focusEnded: Date?
    /// いま持ち帰ったもの（数十秒だけ「持ち帰った」を出す）
    var doneText: String?
    var doneAt: Date?

    /// 今がからっぽ（集中もしていない）
    var isEmpty: Bool { nowText == nil && focusText == nil }
    var isFocusing: Bool { focusText != nil && focusStart != nil }

    /// 「持ち帰った」を出しておく長さ
    static let doneMoment: TimeInterval = 60

    static let key = "widget.snapshot.v1"
    static var defaults: UserDefaults? { UserDefaults(suiteName: AtohaGroup.identifier) }

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
    }

    /// ウィジェットに出す今の様子
    func display(at date: Date) -> NowDisplay {
        if let focusText, let focusStart {
            return .focusing(id: focusID, text: focusText, start: focusStart, ended: focusEnded)
        }
        if let doneText, let doneAt, date < doneAt.addingTimeInterval(Self.doneMoment), date >= doneAt {
            return .done(text: doneText)
        }
        if let nowText { return .item(id: nowID, text: nowText, deadline: nowDeadline) }
        return .empty
    }

    /// ギャラリー・プレビュー用
    static let sample = WidgetSnapshot(nowID: UUID(), nowText: "母に電話", nowDeadline: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now))
    static let sampleFocus = WidgetSnapshot(nowID: nil, nowText: "母に電話", focusID: UUID(), focusText: "母に電話", focusStart: Date.now.addingTimeInterval(-754))
}

enum NowDisplay: Equatable {
    case item(id: UUID?, text: String, deadline: Date?)
    case focusing(id: UUID?, text: String, start: Date, ended: Date?)
    case done(text: String)
    case empty
}

/// ウィジェットからアプリを開く行き先。
enum AtohaLink {
    static let capture = URL(string: "atoha://capture")!
    static let later = URL(string: "atoha://later")!
    static let now = URL(string: "atoha://now")!
    static func focus(_ id: UUID?) -> URL {
        guard let id else { return now }
        return URL(string: "atoha://focus?id=\(id.uuidString)")!
    }
}

/// ライブアクティビティの「できた」。アプリのプロセスで動き、集中していた1匹を持ち帰って集中を終える。
struct FocusDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "できた"
    static let description = IntentDescription("集中していたものを袋に入れて持ち帰る")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusDoneAction.run()
        return .result()
    }
}
