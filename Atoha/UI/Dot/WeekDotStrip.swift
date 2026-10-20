import SwiftUI

struct DayCount: Identifiable {
    let date: Date
    let errands: Int
    let concerns: Int
    /// その日に預けたものに使った時間（秒）
    var focusSeconds: Double = 0
    var id: Date { date }
}

/// 1週間のドット。列ごとに下から用事（塗り）、その上に気になること（枠）。
struct WeekDotStrip: View {
    let days: [DayCount]
    var dotSize: CGFloat = 8

    static let maxDots = 12
    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    init(days: [DayCount], dotSize: CGFloat = 8) {
        self.days = days
        self.dotSize = dotSize
    }

    private var gap: CGFloat { dotSize * 0.4 }
    private var columnHeight: CGFloat { CGFloat(Self.maxDots) * dotSize + CGFloat(Self.maxDots - 1) * gap }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    column(for: day)
                    // 使った時間（ゼロは出さない。高さは揃える）
                    TimeText(seconds: day.focusSeconds, compact: true)
                        .frame(height: 22)
                    Text(Self.weekdaySymbol(for: day.date))
                        .atype(.label)
                }
            }
        }
    }

    private func column(for day: DayCount) -> some View {
        let errands = min(max(day.errands, 0), Self.maxDots)
        let concerns = min(max(day.concerns, 0), Self.maxDots - errands)
        return VStack(spacing: gap) {
            ForEach(0..<concerns, id: \.self) { _ in DotMark(kind: .concern, size: dotSize, flat: true) }
            ForEach(0..<errands, id: \.self) { _ in DotMark(kind: .errand, size: dotSize, flat: true) }
        }
        .frame(width: 34, height: columnHeight, alignment: .bottom)
    }

    private static func weekdaySymbol(for date: Date, calendar: Calendar = .current) -> String {
        weekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// 直近7日（今日を含む）を作成日で振り分ける。未分類は気になることとして数える。
    static func lastSevenDays(from items: [Item], now: Date = .now) -> [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var errands: [Date: Int] = [:]
        var concerns: [Date: Int] = [:]
        var seconds: [Date: Double] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.createdAt)
            seconds[day, default: 0] += item.focusSeconds
            if item.kind == .errand {
                errands[day, default: 0] += 1
            } else {
                concerns[day, default: 0] += 1
            }
        }
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.map { day in
            DayCount(date: day, errands: errands[day] ?? 0, concerns: concerns[day] ?? 0,
                     focusSeconds: seconds[day] ?? 0)
        }
    }
}

#Preview {
    let today = Calendar.current.startOfDay(for: .now)
    let samples = [(2, 1), (0, 3), (4, 2), (1, 0), (6, 9), (3, 3), (0, 0)]
    let days = samples.enumerated().map { index, counts in
        DayCount(
            date: Calendar.current.date(byAdding: .day, value: index - 6, to: today)!,
            errands: counts.0, concerns: counts.1)
    }
    return WeekDotStrip(days: days)
        .padding()
        .background(Theme.paper)
}
