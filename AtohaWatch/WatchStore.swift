import Foundation
import WatchConnectivity

/// ウォッチ側の状態と iPhone との同期。送信待ちは UserDefaults に残し、落とさない。
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var count: Int
    @Published private(set) var nextReturn: Date?

    private let defaults = UserDefaults.standard
    private let pendingKey = "pendingCaptures"

    override init() {
        count = defaults.integer(forKey: "count")
        nextReturn = defaults.object(forKey: "nextReturn") as? Date
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 預ける。キューに積んでから送る。
    func capture(text: String, timing: ReturnTiming) {
        var pending = defaults.array(forKey: pendingKey) as? [[String: Any]] ?? []
        pending.append(["text": text, "timing": timing.rawValue, "createdAt": Date()])
        defaults.set(pending, forKey: pendingKey)
        count += 1
        defaults.set(count, forKey: "count")
        if let at = timing.returnDate(), nextReturn.map({ at < $0 }) ?? true {
            nextReturn = at
            defaults.set(at, forKey: "nextReturn")
        }
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let pending = defaults.array(forKey: pendingKey) as? [[String: Any]] ?? []
        guard !pending.isEmpty else { return }
        // transferUserInfo は OS が永続キューに入れる。キューに渡せた時点で手元の控えを消す。
        for info in pending { WCSession.default.transferUserInfo(info) }
        defaults.removeObject(forKey: pendingKey)
    }

    private func apply(_ context: [String: Any]) {
        let newCount = context["count"] as? Int ?? 0
        let next = context["nextReturn"] as? Date
        defaults.set(newCount, forKey: "count")
        if let next { defaults.set(next, forKey: "nextReturn") } else { defaults.removeObject(forKey: "nextReturn") }
        DispatchQueue.main.async {
            self.count = newCount
            self.nextReturn = next
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        if !session.receivedApplicationContext.isEmpty { apply(session.receivedApplicationContext) }
        flush()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
