import Foundation
import SwiftData
import WatchConnectivity
import UserNotifications

/// Apple Watch との橋。ウォッチから届いた「あとで」を Item にし、件数と次の返却時刻をウォッチへ返す。
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var context: ModelContext?

    func activate(context: ModelContext) {
        self.context = context
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated { pushContext() } else { session.activate() }
        observeFocus()
    }

    /// 集中が始まった・終わったら、ウォッチへ送り直す（FocusSession は @Observable）。
    private func observeFocus() {
        withObservationTracking {
            _ = FocusSession.shared.itemID
            _ = FocusSession.shared.endedAt
        } onChange: {
            Task { @MainActor in
                self.pushContext()
                self.observeFocus()
            }
        }
    }

    /// 預かり中の件数と次の返却時刻をウォッチへ送る。
    func pushContext() {
        guard let context, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting })
        guard let items = try? context.fetch(descriptor) else { return }
        var payload: [String: Any] = ["count": items.count, "capacity": SettingsStore.laterCapacity]
        if let next = items.compactMap(\.returnAt).filter({ $0 > .now }).min() { payload["nextReturn"] = next }
        addNowAndFocus(to: &payload, in: context)
        try? session.updateApplicationContext(payload)
    }

    // MARK: 今の1匹と集中（ウォッチに出す・ウォッチから操作する）

    /// 今の1匹（お椀の先頭＝優先順位の一番高いもの）と、集中しているものを載せる。
    private func addNowAndFocus(to payload: inout [String: Any], in context: ModelContext) {
        payload["hasNow"] = true
        let returnedRaw = ItemState.returned.rawValue
        let returned = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returnedRaw }))) ?? []
        if let now = returned.max(by: { $0.priority() < $1.priority() }) {
            payload["nowID"] = now.id.uuidString
            payload["nowText"] = now.text
            if let deadline = now.deadline { payload["nowDeadline"] = deadline }
        }
        let focus = FocusSession.shared
        if let id = focus.itemID, focus.endedAt == nil, let item = item(id: id, in: context) {
            payload["focusID"] = id.uuidString
            payload["focusText"] = item.text
            payload["focusStart"] = focus.startedAt
            if let planned = focus.plannedMinutes { payload["focusPlanned"] = planned }
        }
    }

    private func item(id: UUID, in context: ModelContext) -> Item? {
        var d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// ウォッチの「▶ 集中する」「できた」。
    private func handleAction(_ action: String, _ info: [String: Any]) {
        guard let context else { return }
        let target = (info["itemID"] as? String).flatMap(UUID.init(uuidString:)).flatMap { item(id: $0, in: context) }
        let focus = FocusSession.shared
        switch action {
        case "focus":
            guard let target, target.state == .returned, !focus.isActive else { break }
            focus.start(target)
        case "done":
            guard let target, target.state == .returned else { break }
            if focus.itemID == target.id {
                if let seconds = focus.stop() { target.focusSeconds += seconds }
                focus.clear()
            }
            ReturnService.takeHome(target, in: context)
        default:
            break
        }
        pushContext()
    }

    private func receive(_ info: [String: Any]) {
        if let action = info["action"] as? String {
            handleAction(action, info)
            return
        }
        guard let context,
              let text = (info["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return }
        let timing = (info["timing"] as? String).flatMap(ReturnTiming.init(rawValue:)) ?? .tonight
        let createdAt = info["createdAt"] as? Date ?? .now

        // 水槽（あとで）がいっぱいなら入れずに預かっておく。空いたら入れる（書いたものは落とさない）
        guard ReturnService.laterRoom(in: context) > 0 else {
            hold(text: text, timing: timing, createdAt: createdAt)
            pushContext()
            return
        }
        insert(text: text, timing: timing, createdAt: createdAt, in: context)
        pushContext()
    }

    /// CaptureView と同じ手順で水槽に入れる。再配信されても二重にならないよう、同じ時刻・同じ文なら入れない。
    private func insert(text: String, timing: ReturnTiming, createdAt: Date, in context: ModelContext) {
        let existing = FetchDescriptor<Item>(predicate: #Predicate { $0.createdAt == createdAt && $0.text == text })
        if ((try? context.fetchCount(existing)) ?? 0) > 0 { return }

        let item = Item(text: text, timing: timing, now: createdAt)
        context.insert(item)
        try? context.save()
        if let date = item.returnAt { NotificationScheduler.reschedule(for: date, in: context) }
        LiveActivityService.sync(in: context)
        let axes = (try? context.fetch(FetchDescriptor<Axis>(sortBy: [SortDescriptor(\.order)]))) ?? []
        Task { @MainActor in
            await ItemProcessor.process(item, axes: axes)
            try? context.save()
        }
    }

    // MARK: 水槽がいっぱいのときに預かったもの

    private static let heldKey = "watch.held"

    private func hold(text: String, timing: ReturnTiming, createdAt: Date) {
        var held = UserDefaults.standard.array(forKey: Self.heldKey) as? [[String: Any]] ?? []
        guard !held.contains(where: { ($0["text"] as? String) == text && ($0["createdAt"] as? Date) == createdAt }) else { return }
        held.append(["text": text, "timing": timing.rawValue, "createdAt": createdAt])
        UserDefaults.standard.set(held, forKey: Self.heldKey)

        let content = UNMutableNotificationContent()
        content.title = "水槽がいっぱいです"
        content.body = "Apple Watch から回した「\(text)」は預かっています。「あとで」を減らすと水槽に入ります。"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "watch.held.\(createdAt.timeIntervalSince1970)", content: content, trigger: nil))
    }

    /// 水槽に空きができたら、預かっていたものを古い順に入れる。
    func flushHeld() {
        guard let context else { return }
        var held = UserDefaults.standard.array(forKey: Self.heldKey) as? [[String: Any]] ?? []
        guard !held.isEmpty else { return }
        var moved = false
        while !held.isEmpty, ReturnService.laterRoom(in: context) > 0 {
            let info = held.removeFirst()
            guard let text = info["text"] as? String, let createdAt = info["createdAt"] as? Date else { continue }
            let timing = (info["timing"] as? String).flatMap(ReturnTiming.init(rawValue:)) ?? .atBreak
            insert(text: text, timing: timing, createdAt: createdAt, in: context)
            moved = true
        }
        UserDefaults.standard.set(held, forKey: Self.heldKey)
        if moved { pushContext() }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.pushContext() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        nonisolated(unsafe) let info = userInfo
        Task { @MainActor in self.receive(info) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let info = message
        Task { @MainActor in self.receive(info) }
    }
}
