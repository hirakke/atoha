import Foundation

/// iPhone から届いた「今」と集中の様子。アプリとコンプリケーションが App Group の UserDefaults で共有する。
struct WatchSnapshot: Equatable {
    static let appGroup = "group.app.atoha.prototype"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    enum Key {
        static let nowID = "watch.now.id"
        static let nowText = "watch.now.text"
        static let nowDeadline = "watch.now.deadline"
        static let focusID = "watch.focus.id"
        static let focusText = "watch.focus.text"
        static let focusStart = "watch.focus.start"
        static let focusPlanned = "watch.focus.planned"
    }

    /// 今の1匹（お椀の先頭）
    var nowID: String?
    var nowText: String?
    var nowDeadline: Date?
    /// 集中しているもの
    var focusID: String?
    var focusText: String?
    var focusStart: Date?
    /// 目安の分（なければ 25 分で帯を描く）
    var focusPlanned: Int?

    var isFocusing: Bool { focusText != nil && focusStart != nil }

    static func load(from d: UserDefaults = defaults) -> WatchSnapshot {
        WatchSnapshot(
            nowID: d.string(forKey: Key.nowID),
            nowText: d.string(forKey: Key.nowText),
            nowDeadline: d.object(forKey: Key.nowDeadline) as? Date,
            focusID: d.string(forKey: Key.focusID),
            focusText: d.string(forKey: Key.focusText),
            focusStart: d.object(forKey: Key.focusStart) as? Date,
            focusPlanned: (d.object(forKey: Key.focusPlanned) as? Int).flatMap { $0 > 0 ? $0 : nil })
    }

    func save(to d: UserDefaults = defaults) {
        func put(_ value: Any?, _ key: String) {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        put(nowID, Key.nowID)
        put(nowText, Key.nowText)
        put(nowDeadline, Key.nowDeadline)
        put(focusID, Key.focusID)
        put(focusText, Key.focusText)
        put(focusStart, Key.focusStart)
        put(focusPlanned, Key.focusPlanned)
    }

    /// iPhone の applicationContext から読む（キーがなければ「なし」）。
    init(context c: [String: Any]) {
        nowID = c["nowID"] as? String
        nowText = c["nowText"] as? String
        nowDeadline = c["nowDeadline"] as? Date
        focusID = c["focusID"] as? String
        focusText = c["focusText"] as? String
        focusStart = c["focusStart"] as? Date
        focusPlanned = (c["focusPlanned"] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    init(nowID: String? = nil, nowText: String? = nil, nowDeadline: Date? = nil,
         focusID: String? = nil, focusText: String? = nil, focusStart: Date? = nil, focusPlanned: Int? = nil) {
        self.nowID = nowID
        self.nowText = nowText
        self.nowDeadline = nowDeadline
        self.focusID = focusID
        self.focusText = focusText
        self.focusStart = focusStart
        self.focusPlanned = focusPlanned
    }

    /// 「18:00 まで」。今日でなければ「10/28 まで」。
    static func deadlineLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "H:mm" : "M/d"
        return "\(f.string(from: date)) まで"
    }

    static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
