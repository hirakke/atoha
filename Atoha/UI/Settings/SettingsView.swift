import SwiftUI
import SwiftData
import UserNotifications

/// 設定。ラベルと印だけ。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]

    @AppStorage(SettingsKey.tonightHourKey) private var tonightHour = 21
    @AppStorage(SettingsKey.morningHourKey) private var morningHour = 8
    @AppStorage(SettingsKey.defaultTimingKey) private var defaultTimingRaw = ReturnTiming.tonight.rawValue
    @AppStorage(SettingsKey.focusDefaultMinutesKey) private var focusMinutes = 0
    @AppStorage(SettingsKey.nowCapacityKey) private var nowCapacity = 3
    @AppStorage(SettingsKey.laterCapacityKey) private var laterCapacity = 20
    @AppStorage(SettingsKey.notifyReturnKey) private var notifyReturn = true
    @AppStorage(SettingsKey.notifyFocusEndKey) private var notifyFocusEnd = true

    @State private var exportURL: URL?
    @State private var confirmDelete = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "0"
        let b = info?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    topBar
                    section("色") { PalettePicker() }
                    section("今") {
                        row("上限") {
                            CubeSegmented(options: [3, 5, 7], label: { String($0) }, selection: $nowCapacity)
                        }
                    }
                    section("あとで") {
                        row("上限") {
                            CubeSegmented(options: [10, 20, 30], label: { "\($0)匹" }, selection: $laterCapacity)
                        }
                    }
                    section("集中") {
                        row("初期") {
                            CubeSegmented(options: [0, 25, 50], label: { $0 == 0 ? "—" : String($0) },
                                          selection: $focusMinutes)
                        }
                    }
                    section("通知") {
                        row("集中の時間") { Mark(isOn: $notifyFocusEnd) }
                    }
                    section("AI") {
                        CloudStatusRow()
                        if FeatureFlags.chatGPTEnabled { ChatGPTRow() }
                    }
                    section("データ") {
                        row("書き出し") {
                            if let exportURL {
                                ShareLink(item: exportURL) { Text("JSON") }
                                    .buttonStyle(.cube(.secondary))
                            } else {
                                Button("JSON") {}
                                    .buttonStyle(.cube(.secondary))
                                    .disabled(true)
                            }
                        }
                        row("すべて削除") {
                            Button("削除") { confirmDelete = true }
                                .buttonStyle(.cube(.secondary))
                        }
                    }
                    section("atoha") {
                        row("版") { Text(version).atype(.small, color: Theme.quiet) }
                        HStack(spacing: 8) {
                            ForEach(["iPhone内", "PCC", "ChatGPT（ログイン時）"], id: \.self) { label in
                                Text(label).atype(.label)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.faint, lineWidth: 1))
                            }
                        }
                    }
                    #if DEBUG
                    section("DEBUG") {
                        Button("サンプルを入れる") { SampleData.insert(into: context) }
                            .buttonStyle(.cube(.secondary))
                    }
                    #endif
                }
                .padding(24)
            }
        }
        .confirmationDialog("すべて削除", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleteAll() }
            Button("やめる", role: .cancel) {}
        }
        .task(id: items.count) { exportURL = writeExport() }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Text("設定").atype(.display)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.cube(.quiet))
            .accessibilityLabel("閉じる")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title)
            content()
        }
        .onPaper(padding: 14)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).atype(.small)
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func hourMenu(_ hour: Binding<Int>) -> some View {
        Menu {
            Picker("", selection: hour) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
            }
        } label: {
            Text(String(format: "%02d:00", hour.wrappedValue))
                .cubeFace(.secondary)
        }
    }

    // MARK: Data

    private func writeExport() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items.map(ExportItem.init)) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atoha.json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    private func deleteAll() {
        try? context.delete(model: Item.self)
        try? context.delete(model: Axis.self)
        try? context.save()
        FocusSession.shared.clear()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        LiveActivityService.sync(in: context)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct ExportItem: Encodable {
    let id: UUID
    let text: String
    let createdAt: Date
    let timing: String
    let returnAt: Date?
    let kind: String
    let state: String
    let deadline: Date?
    let theme: String?
    let want: Double?
    let must: Double?
    let focusSeconds: Double
    let resolvedAt: Date?

    init(_ item: Item) {
        id = item.id; text = item.text; createdAt = item.createdAt
        timing = item.timingRaw; returnAt = item.returnAt
        kind = item.kindRaw; state = item.stateRaw
        deadline = item.deadline; theme = item.theme
        want = item.want; must = item.must
        focusSeconds = item.focusSeconds; resolvedAt = item.resolvedAt
    }
}

/// 入／切の立方体。
private struct Mark: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            SquareMark(isOn ? .accent() : .outline(), size: 16)
                .padding(6)
        }
        .buttonStyle(.cube(.quiet))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "入" : "切")
    }
}

/// PCC の状態。文章は出さず、ラベルと印だけ。上限に近い・達したときは、上限を増やす選択肢へのボタンを出す。
struct CloudStatusRow: View {
    @State private var status = CloudAI.status
    @State private var uses = CloudAI.usesToday

    var body: some View {
        HStack(spacing: 8) {
            SectionLabel("PCC", ruled: false)
            mark
            if status == .ready || status == .approaching {
                DotCountRow(count: uses, max: CloudAI.dailyBudget, dotSize: 5)
            }
            Spacer()
            if (status == .approaching || status == .reached) && CloudAI.canShowLimitOptions {
                Button("上限") { CloudAI.showLimitOptions() }
                    .buttonStyle(.cube(.secondary))
            }
        }
        .onAppear { status = CloudAI.status; uses = CloudAI.usesToday }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var mark: some View {
        switch status {
        case .ready: DotMark(kind: .errand, size: 7)
        case .approaching: DotMark(kind: .errand, highlighted: true, size: 7)
        case .reached: Text("上限").atype(.label, color: Theme.accent)
        case .unavailable, .unsupported: DotMark(kind: .unsorted, size: 7)
        }
    }

    private var accessibilityText: String {
        switch status {
        case .ready: "PCC 使用可"
        case .approaching: "PCC 上限に近い"
        case .reached: "PCC 上限"
        case .unavailable: "PCC 使用不可"
        case .unsupported: "PCC 非対応"
        }
    }
}

struct ChatGPTRow: View {
    @ObservedObject private var auth = ChatGPTAuth.shared

    var body: some View {
        HStack(spacing: 8) {
            SectionLabel("ChatGPT", ruled: false)
            DotMark(kind: auth.isSignedIn ? .errand : .unsorted, size: 7)
            if auth.isSignedIn && ChatGPTStore.reachedToday {
                Text("上限").atype(.label, color: Theme.accent)
            }
            Spacer()
            Button(auth.isSignedIn ? "ログアウト" : (auth.busy ? "…" : "ログイン")) {
                if auth.isSignedIn { auth.signOut() } else { auth.signIn() }
            }
            .buttonStyle(.cube(.secondary))
            .disabled(auth.busy && !auth.isSignedIn)
        }
        .sheet(isPresented: Binding(get: { auth.safariURL != nil },
                                    set: { if !$0 { auth.cancel() } })) {
            if let url = auth.safariURL { SafariSheet(url: url).ignoresSafeArea() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(auth.isSignedIn ? "ChatGPT ログイン済み" : "ChatGPT 未ログイン")
    }
}

/// 色の組を選ぶ。紙の上にアクセントの立方体を置いた見本を並べる。
private struct PalettePicker: View {
    @Environment(\.colorScheme) private var scheme
    private var store = ThemeStore.shared

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Palette.all) { palette in
                let tone = scheme == .dark || palette.alwaysDark ? palette.dark : palette.light
                let on = palette.id == store.palette.id
                Button { store.palette = palette } label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color(UIColor(hex: tone.accent)))
                            .overlay(Rectangle().strokeBorder(Color(UIColor(hex: tone.ink)), lineWidth: 1.5))
                            .frame(width: 16, height: 16)
                        Text(palette.name)
                            .font(Theme.sans(13, weight: .bold))
                            .foregroundStyle(Color(UIColor(hex: tone.ink)))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Color(UIColor(hex: tone.paper)))
                    .overlay(Rectangle().strokeBorder(on ? Theme.ink : Theme.faint, lineWidth: on ? Theme.stroke : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
