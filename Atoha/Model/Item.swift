import Foundation
import SwiftData

/// 預けたものの種類。預けた直後は unsorted で、AI（または手動）で振り分ける。
enum ItemKind: String, Codable, CaseIterable {
    case unsorted
    case errand   // 用事
    case concern  // 気になること
}

/// 預けたものの状態。
enum ItemState: String, Codable {
    case waiting   // 預かり中
    case returned  // 返ってきた（未処理）
    case done      // 用事が済んだ
    case grown     // 気になることを育てる（残す）
    case released  // 手放した
}

/// 設定の保存キーと、画面なしで読める値（Watch からも使う）。
enum SettingsKey {
    static let tonightHourKey = "settings.tonightHour"
    static let morningHourKey = "settings.morningHour"
    static let defaultTimingKey = "settings.defaultTiming"
    static let focusDefaultMinutesKey = "settings.focusDefaultMinutes"
    static let notifyReturnKey = "settings.notifyReturn"
    static let notifyFocusEndKey = "settings.notifyFocusEnd"
    static let nowCapacityKey = "settings.nowCapacity"

    static func hour(_ key: String, default value: Int) -> Int {
        let d = UserDefaults.standard
        guard d.object(forKey: key) != nil else { return value }
        return min(23, max(0, d.integer(forKey: key)))
    }
    static var tonightHour: Int { hour(tonightHourKey, default: 21) }
    static var morningHour: Int { hour(morningHourKey, default: 8) }
}

/// いつ返すか。
enum ReturnTiming: String, Codable, CaseIterable, Identifiable {
    case atBreak          // 区切りで（「区切り」ボタンを押したとき）
    case tonight          // 今夜
    case tomorrowMorning  // 明日の朝

    var id: String { rawValue }

    var label: String {
        switch self {
        case .atBreak: "終わったら"
        case .tonight: "今夜"
        case .tomorrowMorning: "明日の朝"
        }
    }

    /// 返す時刻。区切りは時刻を持たない。
    func returnDate(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .atBreak:
            return nil
        case .tonight:
            let today21 = calendar.date(bySettingHour: SettingsKey.tonightHour, minute: 0, second: 0, of: now)!
            return today21 > now ? today21 : calendar.date(byAdding: .day, value: 1, to: today21)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            return calendar.date(bySettingHour: SettingsKey.morningHour, minute: 0, second: 0, of: tomorrow)
        }
    }
}

@Model
final class Item {
    var id: UUID
    var text: String
    var createdAt: Date
    var timingRaw: String
    /// 返す時刻。区切りの場合は nil。
    var returnAt: Date?
    var kindRaw: String
    var stateRaw: String
    /// AIが文章から読み取った期限。
    var deadline: Date?
    /// AIが付けたテーマ（まとまり）の名前。
    var theme: String?
    /// 意味の近さを計算するためのベクトル。
    var embedding: [Double]?
    /// 各軸（Axis.order 順）上の位置。-1...1。
    var axisScores: [Double]
    /// 確定した軸への近さ。0...1。
    var axisAffinity: Double
    var resolvedAt: Date?
    /// 本人がつけた「やりたい」0...1。未評価は nil。
    var want: Double?
    /// 本人がつけた「やらなきゃ」0...1。未評価は nil。
    var must: Double?
    /// 集中した時間の合計（秒）。
    var focusSeconds: Double = 0

    init(text: String, timing: ReturnTiming, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.createdAt = now
        self.timingRaw = timing.rawValue
        self.returnAt = timing.returnDate(from: now)
        self.kindRaw = ItemKind.unsorted.rawValue
        self.stateRaw = ItemState.waiting.rawValue
        self.axisScores = []
        self.axisAffinity = 0
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .unsorted }
        set { kindRaw = newValue.rawValue }
    }

    var state: ItemState {
        get { ItemState(rawValue: stateRaw) ?? .waiting }
        set { stateRaw = newValue.rawValue }
    }

    /// 軸に近いとみなす境目。axisAffinity は気になることの中での順位なので、上位4分の1。
    static let closeToAxisThreshold = 0.75

    var isRated: Bool { want != nil && must != nil }

    /// 評価済みならその値、未評価なら AI の振り分けから決めた仮の値。
    /// 用事 → (やりたい 0.3, やらなきゃ 0.7)、気になること・未分類 → (0.6, 0.2)。
    var effectiveWant: Double {
        if isRated, let want { return want }
        return kind == .errand ? 0.3 : 0.6
    }

    var effectiveMust: Double {
        if isRated, let must { return must }
        return kind == .errand ? 0.7 : 0.2
    }

    /// 地図に出すか。手放していない・済んでいない、かつ、やりたい寄りか気になること。
    var showsOnMap: Bool {
        state != .released && state != .done && (effectiveWant >= 0.3 || kind == .concern)
    }

    /// やりたくも、やらなきゃでもない。
    var isBothLow: Bool {
        guard let want, let must else { return false }
        return want < 0.25 && must < 0.25
    }

    var isCloseToAxis: Bool { kind == .concern && axisAffinity >= Item.closeToAxisThreshold }

    var timing: ReturnTiming {
        get { ReturnTiming(rawValue: timingRaw) ?? .atBreak }
        set {
            timingRaw = newValue.rawValue
            returnAt = newValue.returnDate()
        }
    }
}

/// 本人が採用した「自分だけの軸」。対になる2つの極を持つ。
@Model
final class Axis {
    var id: UUID
    /// 低い側の極（例：一人で）
    var negativePole: String
    /// 高い側の極（例：人と）
    var positivePole: String
    var order: Int
    var createdAt: Date

    init(negativePole: String, positivePole: String, order: Int) {
        self.id = UUID()
        self.negativePole = negativePole
        self.positivePole = positivePole
        self.order = order
        self.createdAt = .now
    }
}
