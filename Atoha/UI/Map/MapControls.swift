import SwiftUI

enum MapMode: String, CaseIterable {
    case axis, graph
    var label: String { self == .axis ? "軸" : "つながり" }
}

enum MapPeriod: String, CaseIterable {
    case week, month, year, all
    var label: String {
        switch self {
        case .week: "週"
        case .month: "月"
        case .year: "年"
        case .all: "全部"
        }
    }
    var days: Double? {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        case .all: nil
        }
    }
}
