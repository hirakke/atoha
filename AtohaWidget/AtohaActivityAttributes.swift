import ActivityKit
import Foundation

/// 預かり中を示すライブアクティビティ。アプリ本体とウィジェットの両方で使う。
struct AtohaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 預かり中の件数
        var count: Int
        /// 次に返す時刻。区切りだけなら nil。
        var nextReturn: Date?
    }
}

/// アプリ本体とウィジェットで共有する App Group。
enum AtohaGroup {
    static let identifier = "group.app.atoha.prototype"
}
