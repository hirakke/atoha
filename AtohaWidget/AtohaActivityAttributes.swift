import ActivityKit
import Foundation

/// 集中しているあいだだけ出すライブアクティビティ。アプリ本体とウィジェットの両方で使う。
struct AtohaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 集中している1匹の名前
        var text: String
        /// 集中を始めた時刻（経過はこれから数える）
        var startedAt: Date
        /// 区切りを押して計測が止まった時刻
        var endedAt: Date?
        /// 持ち帰った時刻。入っていれば数秒だけ袋と金魚を見せて閉じる
        var takenHomeAt: Date? = nil
    }

    /// 集中している1匹
    var itemID: UUID
}

/// アプリ本体とウィジェットで共有する App Group。
enum AtohaGroup {
    static let identifier = "group.app.atoha.prototype"
}
