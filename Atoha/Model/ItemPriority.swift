import Foundation

extension Item {
    /// 表示・補充の順番（優先順位）。高いほど先。
    /// やらなきゃは期限が近いほど重く、やりたいはそのまま足す。続けているもの（集中した時間）を少しだけ上げる。
    func priority(now: Date = .now) -> Double {
        let urgency: Double
        if let deadline {
            let hours = deadline.timeIntervalSince(now) / 3600
            urgency = hours <= 24 ? 1 : max(0.2, 1 - (hours - 24) / (24 * 6))
        } else {
            urgency = 0.3
        }
        let mustPart = effectiveMust * (0.4 + 0.6 * urgency)
        let continuing = min(focusSeconds / 7200, 1)
        return 0.55 * mustPart + 0.4 * effectiveWant + 0.05 * continuing
    }

    /// 返す時が来ているが、今がいっぱいで預かりのまま待っている（空いたら）。
    /// 区切りで返すものは、区切りを押した時に returnAt = その時刻 にして表す。
    func isReady(now: Date = .now) -> Bool {
        state == .waiting && (returnAt.map { $0 <= now } ?? false)
    }
}
