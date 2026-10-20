import Foundation
import SwiftData
import WatchConnectivity

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
    }

    /// 預かり中の件数と次の返却時刻をウォッチへ送る。
    func pushContext() {
        guard let context, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let waiting = ItemState.waiting.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == waiting })
        guard let items = try? context.fetch(descriptor) else { return }
        var payload: [String: Any] = ["count": items.count]
        if let next = items.compactMap(\.returnAt).filter({ $0 > .now }).min() { payload["nextReturn"] = next }
        try? session.updateApplicationContext(payload)
    }

    private func receive(_ info: [String: Any]) {
        guard let context,
              let text = (info["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return }
        let timing = (info["timing"] as? String).flatMap(ReturnTiming.init(rawValue:)) ?? .tonight
        let createdAt = info["createdAt"] as? Date ?? .now

        // 再配信されても二重にならないよう、同じ時刻・同じ文なら捨てる。
        let existing = FetchDescriptor<Item>(predicate: #Predicate { $0.createdAt == createdAt && $0.text == text })
        if ((try? context.fetchCount(existing)) ?? 0) > 0 { return }

        // CaptureView と同じ手順
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
        pushContext()
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
}
