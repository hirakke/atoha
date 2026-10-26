import SwiftUI
import SwiftData

private extension Locale {
    /// 端末の言語によらず、日付は日本語で出す
    static let ja = Locale(identifier: "ja_JP")
}

/// 金魚鉢：持ち帰った金魚（できたもの）を集めて見る。一覧・カレンダー・1年で切り替える。
struct CollectionView: View {
    enum Mode: String, CaseIterable { case list, calendar, year
        var label: String {
            switch self {
            case .list: "一覧"
            case .calendar: "カレンダー"
            case .year: "1年"
            }
        }
    }

    @Query(filter: #Predicate<Item> { $0.stateRaw == "done" }, sort: \Item.createdAt) private var done: [Item]
    @AppStorage("collectionMode") private var modeRaw = Mode.list.rawValue
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?
    @State private var detail: Item?

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .list }
    private let calendar = Calendar.current

    private func finished(_ item: Item) -> Date { item.resolvedAt ?? item.createdAt }

    /// 持ち帰った順の番号（No.001 から）
    private var numbers: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: done.sorted { finished($0) < finished($1) }.enumerated().map { ($1.id, $0 + 1) })
    }

    private var inMonth: [Item] {
        done.filter { calendar.isDate(finished($0), equalTo: month, toGranularity: .month) }
            .sorted { finished($0) > finished($1) }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("金魚鉢").font(Theme.display(.largeTitle)).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    summary
                    CubeSegmented(options: Mode.allCases, label: { $0.label },
                                  selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue }), fill: true)
                    switch mode {
                    case .list: listView
                    case .calendar: calendarView
                    case .year: yearView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .sheet(item: $detail) { item in
            CollectionDetail(item: item, number: numbers[item.id] ?? 0)
                .presentationDetents([.large])
        }
    }

    // MARK: 上の札

    private var summary: some View {
        let count = mode == .year ? done.filter { calendar.isDate(finished($0), equalTo: month, toGranularity: .year) }.count : inMonth.count
        return HStack(spacing: 14) {
            FishbowlIcon(count: min(3, count), width: 64, onDark: true)
            VStack(alignment: .leading, spacing: 4) {
                (Text("\(count)").font(Theme.dot(.largeTitle))
                 + Text("匹").font(.system(.headline, weight: .bold)))
                Text(mode == .year ? "\(month.formatted(.dateTime.year().locale(.ja)))に持ち帰った　これまで \(done.count)匹"
                                   : "\(month.formatted(.dateTime.month(.wide).locale(.ja)))に持ち帰った　これまで \(done.count)匹")
                    .font(.system(.footnote, weight: .bold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.band))
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent).offset(x: Theme.shadow, y: Theme.shadow))
        .padding(.trailing, Theme.shadow)
        .accessibilityElement(children: .combine)
    }

    private var monthSwitcher: some View {
        HStack {
            stepButton("chevron.left", "前の月") { shift(-1) }
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(.ja))).atype(.title)
            Spacer()
            stepButton("chevron.right", "次の月") { shift(1) }
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .black)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func shift(_ months: Int) {
        if let m = calendar.date(byAdding: .month, value: months, to: month) {
            withAnimation(.easeOut(duration: 0.15)) { month = m; selectedDay = nil }
        }
    }

    // MARK: 一覧

    @ViewBuilder private var listView: some View {
        monthSwitcher
        if inMonth.isEmpty {
            empty("この月に持ち帰った金魚はいません")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(inMonth.enumerated()), id: \.element.id) { index, item in
                    Button { detail = item } label: { card(item, latest: index == 0) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ item: Item, latest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "No.%03d", numbers[item.id] ?? 0))
                Spacer()
                Text(finished(item).formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(.ja)))
            }
            .font(Theme.dot(.caption))
            .foregroundStyle(Theme.quiet)
            fish(item, width: 54)
            Text(item.text).atype(.small).fontWeight(.bold).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        .background(RoundedRectangle(cornerRadius: 16).fill(latest ? Theme.accent : Theme.ink).offset(x: 3, y: 3))
        .accessibilityElement(children: .combine)
        .accessibilityHint("詳しく見る")
    }

    // MARK: カレンダー

    @ViewBuilder private var calendarView: some View {
        monthSwitcher
        let days = monthDays()
        let byDay = Dictionary(grouping: inMonth) { calendar.startOfDay(for: finished($0)) }
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { i, d in
                    Text(d).font(.system(.caption, weight: .black))
                        .foregroundStyle(i == 0 ? Theme.accent : Theme.ink)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, items: byDay[day] ?? [])
                    } else {
                        Color.clear.frame(height: 56)
                    }
                }
            }
        }
        if let selectedDay, let picked = byDay[selectedDay], !picked.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(selectedDay.formatted(.dateTime.month().day().weekday(.abbreviated).locale(.ja)))に持ち帰った")
                    .atype(.small, color: Theme.quiet).fontWeight(.bold)
                ForEach(picked) { item in
                    Button { detail = item } label: {
                        HStack(spacing: 10) {
                            fish(item, width: 27)
                            Text(item.text).atype(.body).frame(maxWidth: .infinity, alignment: .leading)
                            if item.focusSeconds > 0 { TimeText(seconds: item.focusSeconds) }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onPaper(padding: 14)
        }
    }

    /// 月のマス（前の月の空きは nil）
    private func monthDays() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func dayCell(_ day: Date, items: [Item]) -> some View {
        let today = calendar.isDateInToday(day)
        let future = day > .now && !today
        let picked = selectedDay == day
        let sunday = calendar.component(.weekday, from: day) == 1
        return Button {
            guard !items.isEmpty else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedDay = picked ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.dot(.caption))
                    .foregroundStyle(picked ? Theme.paper : (future ? Theme.quiet.opacity(0.6) : (sunday || today ? Theme.accent : Theme.ink)))
                if let first = items.first {
                    fish(first, width: 24, onDark: picked)
                    if items.count > 1 {
                        Text("+\(items.count - 1)").font(.system(.caption2, weight: .black))
                            .foregroundStyle(picked ? Theme.paper : Theme.quiet)
                    }
                } else if today {
                    Text("今日").font(.system(.caption2, weight: .black)).foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 10).fill(picked ? Theme.ink : (future ? Color.clear : Theme.surface)))
            .overlay {
                if today && !picked {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2)
                } else if future {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.month().day().locale(.ja)))、\(items.count)匹")
    }

    // MARK: 1年

    @ViewBuilder private var yearView: some View {
        let year = calendar.component(.year, from: month)
        let counts = Dictionary(grouping: done.filter { calendar.component(.year, from: finished($0)) == year }) {
            calendar.component(.month, from: finished($0))
        }.mapValues(\.count)
        let best = counts.max { $0.value < $1.value }?.key
        HStack {
            stepButton("chevron.left", "前の年") { shiftYear(-1) }
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.year().locale(.ja))).atype(.title)
                if let best { Text("いちばん多い \(best)月").atype(.small, color: Theme.quiet) }
            }
            Spacer()
            stepButton("chevron.right", "次の年") { shiftYear(1) }
                .disabled(year >= calendar.component(.year, from: .now))
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(1...12, id: \.self) { m in
                let n = counts[m] ?? 0
                let isThis = year == calendar.component(.year, from: .now) && m == calendar.component(.month, from: .now)
                let future = year == calendar.component(.year, from: .now) && m > calendar.component(.month, from: .now)
                Button {
                    if let d = calendar.date(from: DateComponents(year: year, month: m, day: 1)) {
                        month = d
                        modeRaw = Mode.calendar.rawValue
                    }
                } label: {
                    VStack(spacing: 4) {
                        FishbowlIcon(count: min(3, n), width: 44)
                            .opacity(future ? 0.3 : 1)
                        Text(future ? "\(m)月" : "\(m)月　\(n)").atype(.small).fontWeight(.black)
                            .foregroundStyle(isThis ? Theme.accent : (n == 0 ? Theme.quiet : Theme.ink))
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(RoundedRectangle(cornerRadius: 14).fill(future ? Color.clear : Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isThis ? Theme.accent : Theme.faint,
                                                                             style: StrokeStyle(lineWidth: isThis ? 3 : 2, dash: future ? [3, 2] : [])))
                }
                .buttonStyle(.plain)
                .disabled(future)
                .accessibilityLabel("\(m)月 \(n)匹")
            }
        }
    }

    private func shiftYear(_ years: Int) {
        if let m = calendar.date(byAdding: .year, value: years, to: month) { month = m }
    }

    // MARK: 部品

    private func empty(_ text: String) -> some View {
        Text(text).atype(.small, color: Theme.quiet)
            .frame(maxWidth: .infinity, minHeight: 120)
            .onPaper()
    }

    /// 金魚鉢では、持ち帰る前の色（やりたい・やらなきゃ）で見せる
    @ViewBuilder private func fish(_ item: Item, width: CGFloat, onDark: Bool = false) -> some View {
        let tint = GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust)
        if onDark {
            GoldfishMark(color: tint == .black || tint == .faint ? Theme.paper : Theme.accent, width: width)
        } else if item.isRated {
            GoldfishMark(tint: tint, width: width)
        } else {
            GoldfishMark(color: Theme.ink, style: .fry, width: width)
        }
    }
}

/// 1匹の詳しいところ：いつ思いついて、いつすくって、いつ持ち帰ったか。
private struct CollectionDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let item: Item
    let number: Int
    @State private var full = false

    var body: some View {
        let tint = GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(String(format: "No.%03d", number)).font(Theme.dot(.body))
                        .foregroundStyle(Theme.quiet)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                }
                HStack(spacing: 16) {
                    GoldfishMark(tint: item.isRated ? tint : .black, width: 72)
                        .frame(width: 100, height: 100)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.ink).offset(x: 4, y: 4))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.text).font(.system(.title3, weight: .black)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.isRated {
                            Text(tint.label).atype(.small).fontWeight(.bold)
                                .padding(.horizontal, 10).padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                        }
                    }
                }
                VStack(spacing: 0) {
                    row(icon: AnyView(GoldfishMark(color: Theme.ink, style: .fry, width: 27)), "思いついた", date(item.createdAt))
                    if let scooped = item.scoopedAt {
                        divider
                        row(icon: AnyView(BowlIcon(filled: false, width: 27)), "すくった", date(scooped))
                    }
                    divider
                    row(icon: AnyView(BagIcon(tint: tint, width: 22)), "持ち帰った", date(item.resolvedAt ?? item.createdAt))
                    if item.focusSeconds > 0 {
                        divider
                        row(icon: AnyView(Image(systemName: "timer").foregroundStyle(Theme.accent)), "集中した時間",
                            FocusView.format(item.focusSeconds))
                    }
                }
                .onPaper(padding: 14)
                if let theme = item.theme, !theme.isEmpty {
                    Text("まとまり：\(theme)").atype(.small, color: Theme.quiet)
                }
                Button {
                    again()
                } label: {
                    Label("もう一度やる（水槽に放す）", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.cube(.secondary, fill: true))
                if full {
                    Text("水槽がいっぱいです（\(SettingsStore.laterCapacity)匹）").atype(.small, color: Theme.accent)
                }
            }
            .padding(20)
        }
        .background(Theme.paper)
    }

    private var divider: some View { Rectangle().fill(Theme.faint).frame(height: 2) }

    private func row(icon: AnyView, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 30)
            Text(title).atype(.body)
            Spacer()
            Text(value).font(Theme.dot(.body)).foregroundStyle(Theme.ink)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func date(_ d: Date) -> String { d.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(.ja)) }

    /// 同じことを、新しい稚魚として水槽に放す
    private func again() {
        guard ReturnService.laterRoom(in: context) > 0 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            full = true
            return
        }
        let copy = Item(text: item.text, timing: .atBreak)
        copy.kind = item.kind
        context.insert(copy)
        ReturnService.sync(in: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// 家の金魚鉢。丸い鉢に水と、入っている数だけ金魚。ガラスの見え方は設定にしたがう。
struct FishbowlIcon: View {
    var count: Int
    var width: CGFloat = 40
    var onDark = false
    @AppStorage(SettingsKey.tankGlassKey) private var glassRaw = TankGlass.drawn.rawValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let line = onDark ? Color.white : Theme.ink
        let water = onDark ? Color.white.opacity(0.18) : Theme.ink.opacity(0.12)
        let c = width / 14
        ZStack {
            if TankGlass(rawValue: glassRaw) == .system {
                // Liquid Glass の丸い鉢。水は鉢の下半分、白い内側の線
                let bowl = Circle().inset(by: c * 0.5)
                ZStack {
                    Color.clear.glassEffect(.regular, in: .circle)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(water).frame(height: 7.5 * c)
                    }
                    .clipShape(bowl)
                    bowl.strokeBorder(Color.white.opacity(0.9), lineWidth: max(1, c * 0.5))
                }
                .frame(width: 12 * c, height: 12 * c)
            } else {
                Canvas { context, size in
                    let c = size.width / 14
                    func cells(_ rects: [(CGFloat, CGFloat, CGFloat, CGFloat)]) -> Path {
                        var p = Path()
                        for r in rects { p.addRect(CGRect(x: r.0 * c, y: r.1 * c, width: r.2 * c, height: r.3 * c)) }
                        return p
                    }
                    let light = GlassTone.light(scheme)
                    // ガラスの中の空気（ごく淡く）
                    context.fill(cells([(4, 1, 6, 1), (3, 2, 8, 1), (2, 3, 10, 1)]), with: .color(light.opacity(onDark ? 0.1 : 0.5)))
                    context.fill(cells([(2, 4, 10, 5), (3, 9, 8, 1), (4, 10, 6, 1)]), with: .color(water))
                    // 縁
                    context.fill(cells([
                        (4, 0, 6, 1), (3, 1, 1, 1), (10, 1, 1, 1), (2, 2, 1, 1), (11, 2, 1, 1), (1, 3, 1, 6), (12, 3, 1, 6),
                        (2, 9, 1, 1), (11, 9, 1, 1), (3, 10, 1, 1), (10, 10, 1, 1), (4, 11, 6, 1),
                    ]), with: .color(line))
                    // 左上の映り込みと、水面のきらめき
                    context.fill(cells([(3, 2, 1, 1), (2, 3, 1, 2), (2, 6, 1, 1)]), with: .color(light.opacity(onDark ? 0.6 : 1)))
                    context.fill(cells([(9, 4, 1, 1)]), with: .color(light.opacity(onDark ? 0.8 : 1)))
                }
            }
            let spots: [(CGFloat, CGFloat, GoldfishTint)] = [(-0.12, 0.08, .red), (0.16, 0.18, .both), (0.0, 0.3, .black)]
            ForEach(0..<count, id: \.self) { i in
                let s = spots[i]
                GoldfishMark(tint: onDark && s.2 == .black ? .faint : s.2, width: width * 0.3)
                    .offset(x: s.0 * width, y: s.1 * width)
            }
        }
        .frame(width: width, height: width * 12 / 14)
        .accessibilityHidden(true)
    }
}

/// 持ち帰った直後の知らせ。袋がふわっと浮き、押すと金魚鉢を開く。
struct TakeHomeToast: View {
    @Query(filter: #Predicate<Item> { $0.stateRaw == "done" }, sort: \Item.resolvedAt, order: .reverse) private var done: [Item]
    let onOpen: () -> Void
    @State private var lift = false

    var body: some View {
        let item = done.first
        Button(action: onOpen) {
            HStack(spacing: 12) {
                BagIcon(tint: item.map { GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust) } ?? .red, width: 30)
                    .offset(y: lift ? -6 : 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("持ち帰りました").atype(.body).fontWeight(.black)
                    Text("金魚鉢で見る").atype(.small, color: Theme.quiet)
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .black)).foregroundStyle(Theme.quiet)
            }
            .padding(.leading, 14).padding(.trailing, 18).padding(.vertical, 10)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
            .background(Capsule().fill(Theme.ink).offset(x: 3, y: 3))
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { lift = true } }
        .accessibilityLabel("持ち帰りました。金魚鉢で見る")
    }
}
