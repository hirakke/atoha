import SwiftUI

/// 使った時間。0 のときは何も出さない。
/// 通常は小さな立方体 + H:MM。compact は列が狭いとき用で、1時間未満は分だけ、以上は時間 + H。
struct TimeText: View {
    let seconds: Double
    var compact = false
    @Environment(\.atypeInk) private var ink

    init(seconds: Double, compact: Bool = false) {
        self.seconds = seconds
        self.compact = compact
    }

    static func format(_ seconds: Double, compact: Bool = false) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if compact {
            return minutes < 100 ? "\(minutes)" : "\(Int((Double(minutes) / 60).rounded()))H"
        }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    var body: some View {
        if let text = Self.format(seconds, compact: compact) {
            HStack(spacing: 4) {
                if !compact { SquareMark(.outline(alpha: 0.45), size: 8) }
                DotMatrixText(text, size: .tiny, color: ink?.opacity(0.85) ?? Theme.quiet)
            }
        }
    }
}
