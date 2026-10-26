import Foundation
import WatchConnectivity
import WidgetKit

/// ウォッチ側の状態と iPhone との同期。送信待ちは UserDefaults に残し、落とさない。
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var count: Int
    @Published private(set) var nextReturn: Date?
    /// 水槽（あとで）に入る数。iPhone の設定から届く
    @Published private(set) var capacity: Int
    /// 水槽がいっぱい
    var isFull: Bool { count >= capacity }
    /// 今の1匹と集中の様子（iPhone から届く。コンプリケーションと共有）
    @Published private(set) var snapshot: WatchSnapshot

    private let defaults = UserDefaults.standard
    private let pendingKey = "pendingCaptures"

    override init() {
        count = defaults.integer(forKey: "count")
        nextReturn = defaults.object(forKey: "nextReturn") as? Date
        capacity = defaults.object(forKey: "capacity") as? Int ?? 20
        snapshot = WatchSnapshot.load()
        super.init()
    }

    // MARK: 今・集中（iPhone へ頼む。届くまで手元は先に変えておく）

    /// ▶ 集中する
    func startFocus() {
        guard let text = snapshot.nowText else { return }
        var s = snapshot
        s.focusID = s.nowID
        s.focusText = text
        s.focusStart = .now
        setSnapshot(s)
        send(["action": "focus", "itemID": s.nowID ?? "", "at": Date()])
    }

    /// できた：持ち帰る（iPhone の金魚鉢へ）
    func finish() {
        let id = snapshot.focusID ?? snapshot.nowID
        var s = snapshot
        s.focusID = nil
        s.focusText = nil
        s.focusStart = nil
        if s.nowID == id { s.nowID = nil; s.nowText = nil; s.nowDeadline = nil }
        setSnapshot(s)
        send(["action": "done", "itemID": id ?? "", "at": Date()])
    }

    private func setSnapshot(_ s: WatchSnapshot) {
        s.save()
        if Thread.isMainThread { snapshot = s } else { DispatchQueue.main.async { self.snapshot = s } }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// すぐ届くなら sendMessage、だめなら OS のキューに積む。
    private func send(_ info: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(info, replyHandler: nil) { _ in session.transferUserInfo(info) }
        } else {
            session.transferUserInfo(info)
        }
    }

    #if DEBUG
    /// 画面の確認用（-watchState now|capture|released|full|focus|empty）
    func debugSet(count: Int, capacity: Int, snapshot s: WatchSnapshot) {
        self.count = count
        self.capacity = capacity
        setSnapshot(s)
    }
    #endif

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
        let newCapacity = context["capacity"] as? Int ?? capacity
        defaults.set(newCount, forKey: "count")
        defaults.set(newCapacity, forKey: "capacity")
        if let next { defaults.set(next, forKey: "nextReturn") } else { defaults.removeObject(forKey: "nextReturn") }
        DispatchQueue.main.async {
            self.count = newCount
            self.nextReturn = next
            self.capacity = newCapacity
        }
        // 今・集中のキーは iPhone が新しいときだけ送ってくる。古い iPhone アプリなら触らない
        if context.keys.contains("hasNow") { setSnapshot(WatchSnapshot(context: context)) }
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
