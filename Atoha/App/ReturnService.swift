import Foundation
import SwiftData
import UserNotifications
import ActivityKit

/// あとでに回したものが戻ってくる。
/// 戻ってきたもの（戻る時が来たもの）は「今」へ自動では入れず、おすすめとして見せる。今に入れるかは本人が決める。
@MainActor
enum ReturnService {
    /// 起動時・画面に戻ったとき。戻ってきたものの見え方（ライブアクティビティなど）をそろえる。
    static func returnDue(in context: ModelContext, now: Date = .now) {
        sync(in: context)
    }

    /// 「区切りがついた」：終わったらで回したものを、戻ってきた状態（returnAt = 今）にする。
    static func returnAtBreak(in context: ModelContext, now: Date = .now) {
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting })
        if let items = try? context.fetch(descriptor) {
            for item in items where item.timing == .atBreak && item.returnAt == nil {
                item.returnAt = now
            }
        }
        sync(in: context)
    }

    /// 今に入っている数。
    static func nowCount(in context: ModelContext) -> Int {
        let returnedRaw = ItemState.returned.rawValue
        return (try? context.fetchCount(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returnedRaw }))) ?? 0
    }

    /// 今にあと何件入れられるか。
    static func room(in context: ModelContext) -> Int {
        max(0, SettingsStore.nowCapacity - nowCount(in: context))
    }

    /// あとで（水槽）に入っている数。
    static func laterCount(in context: ModelContext) -> Int {
        let waitingRaw = ItemState.waiting.rawValue
        return (try? context.fetchCount(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waitingRaw }))) ?? 0
    }

    /// あとでにあと何匹入れられるか。
    static func laterRoom(in context: ModelContext) -> Int {
        max(0, SettingsStore.laterCapacity - laterCount(in: context))
    }

    /// 本人が選んで、今に入れる。上限なら入れずに false。
    @discardableResult
    static func accept(_ item: Item, in context: ModelContext) -> Bool {
        guard item.state == .waiting, room(in: context) > 0 else { return false }
        let old = item.returnAt
        item.state = .returned
        try? context.save()
        if let old { NotificationScheduler.reschedule(for: old, in: context) }
        sync(in: context)
        return true
    }

    /// 保存して、ライブアクティビティを今の状態に合わせる。今へは何も動かさない。
    static func sync(in context: ModelContext) {
        try? context.save()
        LiveActivityService.sync(in: context)
    }

    /// サンプル用：おすすめの上から n 件を今に入れた状態にする。
    static func acceptTop(_ n: Int, in context: ModelContext, now: Date = .now) {
        let waitingRaw = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waitingRaw })
        guard let items = try? context.fetch(descriptor) else { return }
        let ready = items.filter { $0.isReady(now: now) }.sorted { $0.priority(now: now) > $1.priority(now: now) }
        for item in ready.prefix(min(n, room(in: context))) { item.state = .returned }
        sync(in: context)
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
