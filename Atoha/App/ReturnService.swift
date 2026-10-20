import Foundation
import SwiftData
import UserNotifications
import ActivityKit

/// 預かり中のものを返す。
@MainActor
enum ReturnService {
    /// 返す時刻を過ぎたものを、上限の範囲で返す。
    static func returnDue(in context: ModelContext, now: Date = .now) {
        refill(in: context, now: now)
    }

    /// 「区切り」：区切りで返すものを返せる状態（returnAt = 今）にして、上限の範囲で返す。
    static func returnAtBreak(in context: ModelContext, now: Date = .now) {
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting })
        if let items = try? context.fetch(descriptor) {
            for item in items where item.timing == .atBreak && item.returnAt == nil {
                item.returnAt = now
            }
        }
        refill(in: context, now: now)
    }

    /// 返す時が来ているもの（ready）を、優先順位の高い順に、今が上限になるまで返す。
    /// 今から出たとき・起動時・区切りのときに必ず通る入口。
    static func refill(in context: ModelContext, now: Date = .now) {
        let capacity = SettingsStore.nowCapacity
        let returnedRaw = ItemState.returned.rawValue
        let used = (try? context.fetchCount(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returnedRaw }))) ?? 0
        let waitingRaw = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waitingRaw })
        if used < capacity, let items = try? context.fetch(descriptor) {
            let ready = items.filter { $0.isReady(now: now) }.sorted { $0.priority(now: now) > $1.priority(now: now) }
            for item in ready.prefix(capacity - used) { item.state = .returned }
        }
        try? context.save()
        LiveActivityService.sync(in: context)
    }
}

/// ロック画面／ダイナミックアイランドのライブアクティビティ。預かり中が1件以上の間だけ出す。
@MainActor
enum LiveActivityService {
    static func sync(in context: ModelContext, now: Date = .now) {
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting })
        guard let items = try? context.fetch(descriptor) else { return }
        let state = AtohaActivityAttributes.ContentState(
            count: items.count,
            nextReturn: items.compactMap(\.returnAt).filter { $0 > now }.min())
        let current = Activity<AtohaActivityAttributes>.activities

        if items.isEmpty {
            for activity in current {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = current.first {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: AtohaActivityAttributes(), content: content)
        }
    }
}

/// 返す時刻にローカル通知を出す。同じ時刻のものは1つの通知にまとめる。
enum NotificationScheduler {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(at date: Date, count: Int) {
        guard SettingsStore.notifyReturn else { return }
        let content = UNMutableNotificationContent()
        content.title = "atoha"
        content.body = "\(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())) · \(count)"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "return-\(Int(date.timeIntervalSince1970))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// その時刻に返す件数を数え直して、通知を置き換える。
    @MainActor
    static func reschedule(for date: Date, in context: ModelContext) {
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting && $0.returnAt == date })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        let id = "return-\(Int(date.timeIntervalSince1970))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        if count > 0 { schedule(at: date, count: count) }
    }
}
