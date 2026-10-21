import SwiftUI

/// 設定の値。画面では @AppStorage(SettingsKey.xxxKey) で束ね、それ以外は SettingsStore から読む。
enum SettingsStore {
    private static var defaults: UserDefaults { .standard }

    static var defaultTiming: ReturnTiming {
        ReturnTiming(rawValue: defaults.string(forKey: SettingsKey.defaultTimingKey) ?? "") ?? .tonight
    }

    static var focusDefaultMinutes: Int? {
        let m = defaults.integer(forKey: SettingsKey.focusDefaultMinutesKey)
        return m > 0 ? m : nil
    }

    /// 今に置ける数の上限（3/5/7）。初期は3（作業記憶の研究で3〜5、個人のカンバンの慣習で3）。
    static var nowCapacity: Int {
        guard defaults.object(forKey: SettingsKey.nowCapacityKey) != nil else { return 3 }
        let n = defaults.integer(forKey: SettingsKey.nowCapacityKey)
        return [3, 5, 7].contains(n) ? n : 3
    }

    /// あとで（水槽）に入れておける数の上限（10/20/30）。初期は20。たまりすぎないように
    static var laterCapacity: Int {
        guard defaults.object(forKey: SettingsKey.laterCapacityKey) != nil else { return 20 }
        let n = defaults.integer(forKey: SettingsKey.laterCapacityKey)
        return [10, 20, 30].contains(n) ? n : 20
    }

    static var notifyReturn: Bool { bool(SettingsKey.notifyReturnKey) }
    static var notifyFocusEnd: Bool { bool(SettingsKey.notifyFocusEndKey) }

    private static func bool(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }
}
