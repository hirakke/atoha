import Foundation
import UserNotifications

/// 集中の状態。1つだけ。UserDefaults に残して、再起動しても戻れるようにする。
@Observable
final class FocusSession {
    static let shared = FocusSession()

    private enum Key {
        static let item = "focus.itemID"
        static let start = "focus.startedAt"
        static let planned = "focus.plannedMinutes"
        static let end = "focus.endedAt"
    }
    private static let notificationID = "focus-end"

    private(set) var itemID: UUID?
    private(set) var startedAt: Date = .now
    private(set) var plannedMinutes: Int?
    /// 区切りを押した時刻。入ったら計測は止まり、選ぶ段階になる。
    private(set) var endedAt: Date?

    var isActive: Bool { itemID != nil }

    private init() {
        let d = UserDefaults.standard
        if let s = d.string(forKey: Key.item), let id = UUID(uuidString: s) {
            itemID = id
            startedAt = (d.object(forKey: Key.start) as? Date) ?? .now
            let m = d.integer(forKey: Key.planned)
            plannedMinutes = m > 0 ? m : nil
            endedAt = d.object(forKey: Key.end) as? Date
        }
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    func start(_ item: Item) {
        guard itemID == nil else { return }
        itemID = item.id
        startedAt = .now
        plannedMinutes = SettingsStore.focusDefaultMinutes
        endedAt = nil
        persist()
        notifyWidgets()
    }

    func setPlanned(_ minutes: Int?) {
        guard endedAt == nil else { return }
        plannedMinutes = minutes
        persist()
        scheduleNotification()
    }

    /// 計測を止める。経過秒を返す（すでに止めていたら nil）。
    func stop() -> TimeInterval? {
        guard itemID != nil, endedAt == nil else { return nil }
        endedAt = .now
        persist()
        notifyWidgets()
        cancelNotification()
        return elapsed()
    }

    func clear() {
        cancelNotification()
        itemID = nil
        plannedMinutes = nil
        endedAt = nil
        persist()
        notifyWidgets()
    }

    /// ウィジェットとライブアクティビティに知らせる
    private func notifyWidgets() {
        Task { @MainActor in WidgetSync.focusChanged() }
    }

    private func persist() {
        let d = UserDefaults.standard
        if let itemID {
            d.set(itemID.uuidString, forKey: Key.item)
            d.set(startedAt, forKey: Key.start)
            d.set(plannedMinutes ?? 0, forKey: Key.planned)
            if let endedAt { d.set(endedAt, forKey: Key.end) } else { d.removeObject(forKey: Key.end) }
        } else {
            for k in [Key.item, Key.start, Key.planned, Key.end] { d.removeObject(forKey: k) }
        }
    }

    /// 目安の時間が来たら知らせる（アプリが裏にあるとき用）。
    func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard SettingsStore.notifyFocusEnd, let plannedMinutes, endedAt == nil else { return }
        let remaining = startedAt.addingTimeInterval(Double(plannedMinutes) * 60).timeIntervalSinceNow
        guard remaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "atoha"
        content.body = "\(plannedMinutes)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
}
