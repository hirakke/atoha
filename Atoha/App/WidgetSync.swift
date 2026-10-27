import Foundation
import SwiftData
import WidgetKit
import ActivityKit

/// ウィジェットへ今の1匹の写しを渡す。状態が変わるたびに書き直して、ウィジェットを読み直させる。
@MainActor
enum WidgetSync {
    /// 今の1匹・集中の様子を写して保存する。変わっていればウィジェットを読み直させる。
    static func publish(in context: ModelContext, now: Date = .now) {
        let old = WidgetSnapshot.load()
        var s = WidgetSnapshot()
        // ホームの「次」の札の先頭と同じ選び方（今にあるものを優先順位の高い順に）
        let returned = ItemState.returned.rawValue
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returned }))) ?? []
        if let next = items.sorted(by: { $0.priority(now: now) > $1.priority(now: now) }).first {
            s.nowID = next.id
            s.nowText = next.text
            s.nowDeadline = next.deadline
        }
        let focus = FocusSession.shared
        if let id = focus.itemID, let item = fetch(id, in: context) {
            s.focusID = id
            s.focusText = item.text
            s.focusStart = focus.startedAt
            s.focusEnded = focus.endedAt
        }
        // 「持ち帰った」は少しのあいだ残す
        if let doneAt = old.doneAt, doneAt.addingTimeInterval(WidgetSnapshot.doneMoment) > now {
            s.doneText = old.doneText
            s.doneAt = old.doneAt
        }
        guard s != old else { return }
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 持ち帰ったときに呼ぶ（このあと sync で publish される）
    static func markDone(_ text: String, at date: Date = .now) {
        var s = WidgetSnapshot.load()
        s.doneText = text
        s.doneAt = date
        s.save()
    }

    static func fetch(_ id: UUID, in context: ModelContext) -> Item? {
        var d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// 集中が始まった・止まった・終わったとき（FocusSession から）
    static func focusChanged() {
        LiveActivityService.sync(in: AtohaStore.shared.mainContext)
    }
}

/// ロック画面／ダイナミックアイランドのライブアクティビティ。集中しているあいだだけ出す。
/// あわせてウィジェットの写しも書き直す（呼ばれる場面が同じなので）。
@MainActor
enum LiveActivityService {
    static func sync(in context: ModelContext, now: Date = .now) {
        WidgetSync.publish(in: context, now: now)

        let focus = FocusSession.shared
        let current = Activity<AtohaActivityAttributes>.activities
        guard let id = focus.itemID, let item = WidgetSync.fetch(id, in: context) else {
            // 持ち帰った直後なら、袋と金魚を数秒だけ見せてから閉じる
            if let doneAt = WidgetSnapshot.load().doneAt, now.timeIntervalSince(doneAt) < 5 {
                for activity in current where activity.content.state.takenHomeAt == nil {
                    var state = activity.content.state
                    state.takenHomeAt = doneAt
                    let content = ActivityContent(state: state, staleDate: nil)
                    Task {
                        await activity.update(content, alertConfiguration: AlertConfiguration(title: "持ち帰りました", body: "", sound: .default))
                        try? await Task.sleep(for: .seconds(4))
                        await activity.end(content, dismissalPolicy: .immediate)
                    }
                }
                return
            }
            for activity in current {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let state = AtohaActivityAttributes.ContentState(text: item.text, startedAt: focus.startedAt, endedAt: focus.endedAt)
        let content = ActivityContent(state: state, staleDate: nil)
        // 別の1匹のものは閉じる
        for activity in current where activity.attributes.itemID != id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        if let activity = current.first(where: { $0.attributes.itemID == id }) {
            if activity.content.state != state { Task { await activity.update(content) } }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: AtohaActivityAttributes(itemID: id), content: content)
        }
    }
}

/// ライブアクティビティの「できた」：集中していた1匹を持ち帰り、集中を終える。
enum FocusDoneAction {
    @MainActor static func run() {
        let context = AtohaStore.shared.mainContext
        let session = FocusSession.shared
        guard let id = session.itemID else {
            LiveActivityService.sync(in: context)
            return
        }
        let seconds = session.stop()
        if let item = WidgetSync.fetch(id, in: context) {
            if let seconds { item.focusSeconds += seconds }
            ReturnService.takeHome(item, in: context)
        }
        session.clear()
    }
}

/// ウィジェットからの行き先（atoha://capture, atoha://later, atoha://now, atoha://focus?id=）
enum AtohaDeepLink {
    @MainActor
    static func handle(_ url: URL, context: ModelContext, router: AppRouter) {
        guard url.scheme == "atoha" else { return }
        switch url.host() {
        case "capture":
            router.showCapture = true
        case "later":
            router.tab = "later"
        case "now":
            router.tab = "now"
        case "focus":
            router.tab = "now"
            let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
            if let idString, let id = UUID(uuidString: idString), let item = WidgetSync.fetch(id, in: context),
               item.state == .returned, !FocusSession.shared.isActive {
                FocusSession.shared.start(item)
            }
        default:
            break
        }
    }
}
