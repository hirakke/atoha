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
    @AppStorage(SettingsKey.tankGlassKey) private var tankGlassRaw = TankGlass.drawn.rawValue
    @AppStorage(SettingsKey.notifyReturnKey) private var notifyReturn = true
    @AppStorage(SettingsKey.notifyFocusEndKey) private var notifyFocusEnd = true

    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var showLicenses = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "0"
        let b = info?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("色") { PalettePicker().padding(.vertical, 6) }
                section("今と あとで") {
                    row("お椀の数") {
                        CubeSegmented(options: [3, 5, 7], label: { String($0) }, selection: $nowCapacity)
                    }
                    divider
                    row("水槽の数") {
                        CubeSegmented(options: [10, 20, 30], label: { String($0) }, selection: $laterCapacity)
                    }
                    divider
                    VStack(alignment: .leading, spacing: 0) {
                        row("ガラスの見え方") {
                            CubeSegmented(options: TankGlass.allCases.map(\.rawValue),
                                          label: { TankGlass(rawValue: $0)?.label ?? $0 }, selection: $tankGlassRaw)
                        }
                        Text("水槽・池・金魚鉢のガラスに使います").atype(.small, color: Theme.quiet)
                            .padding(.bottom, 12)
                    }
                }
                section("集中") {
                    row("最初の時間") {
                        CubeSegmented(options: [0, 25, 50], label: { $0 == 0 ? "なし" : "\($0)分" },
                                      selection: $focusMinutes)
                    }
                    divider
                    row("時間が来たら知らせる") {
                        Toggle("時間が来たら知らせる", isOn: $notifyFocusEnd)
                            .labelsHidden()
                            .toggleStyle(.switch).tint(Theme.accent)
                    }
                }
                section("整理のしかた") {
                    CloudStatusRow().frame(minHeight: 56)
                    if FeatureFlags.chatGPTEnabled {
                        divider
                        ChatGPTRow().frame(minHeight: 56)
                    }
                }
                section("データ") {
                    row("書き出す") {
                        if let exportURL {
                            ShareLink(item: exportURL) { Text("JSON") }
                                .buttonStyle(.cube(.secondary))
                        } else {
                            Button("JSON") {}
                                .buttonStyle(.cube(.secondary))
                                .disabled(true)
                        }
                    }
                    divider
                    Button { confirmDelete = true } label: {
                        Text("すべて削除").atype(.body, color: Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 12) {
                    section("atoha") {
                        Button { showLicenses = true } label: {
                            HStack {
                                Text("ライセンス").atype(.body)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.quiet)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("atoha \(version)").atype(.small, color: Theme.quiet)
                        .frame(maxWidth: .infinity)
                }
                #if DEBUG
                section("DEBUG") {
                    row("サンプル") {
                        Button("入れる") { SampleData.insert(into: context) }
                            .buttonStyle(.cube(.secondary))
                    }
                }
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showLicenses) { LicensesView() }
        .confirmationDialog("すべて削除", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleteAll() }
            Button("やめる", role: .cancel) {}
        }
        .task(id: items.count) { exportURL = writeExport() }
    }

    // MARK: Parts

    /// 看板の見出しと、丸い閉じるボタン。
    private var header: some View {
        HStack {
            Text("設定").font(Theme.display(.title)).foregroundStyle(Theme.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
    }

    /// 灰色の小見出しと、白いカード1枚。
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.sans(13, weight: .bold))
                .foregroundStyle(Theme.quiet)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .onPaper(padding: 14)
        }
    }

    /// 左に名前、右に操作。
    private func row<Trailing: View>(_ title: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).atype(.body)
            Spacer(minLength: 12)
            trailing()
        }
        .frame(minHeight: 56)
    }

    /// 行と行のあいだの線。
    private var divider: some View {
        Rectangle().fill(Theme.faint).frame(height: 2)
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

/// 小さな状態の札。強調するときは紅。
private struct StatusPill: View {
    let text: String
    var strong = false

    var body: some View {
        Text(text)
            .atype(.label, color: strong ? Theme.accent : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(strong ? Theme.accent : Theme.ink, lineWidth: 2))
    }
}

/// PCC の状態。名前と札だけ。上限に近い・達したときは、上限を増やす選択肢へのボタンを出す。
struct CloudStatusRow: View {
    @State private var status = CloudAI.status
    @State private var uses = CloudAI.usesToday

    var body: some View {
        HStack(spacing: 8) {
            Text("Apple のクラウド").atype(.body)
            Spacer(minLength: 12)
            if (status == .approaching || status == .reached) && CloudAI.canShowLimitOptions {
                Button("増やす") { CloudAI.showLimitOptions() }
                    .buttonStyle(.cube(.secondary))
            }
            StatusPill(text: pillText, strong: status == .approaching || status == .reached)
        }
        .onAppear { status = CloudAI.status; uses = CloudAI.usesToday }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var pillText: String {
        switch status {
        case .ready: "使える"
        case .approaching: "もうすぐ上限"
        case .reached: "今日はここまで"
        case .unavailable: "使えない"
        case .unsupported: "この機種は未対応"
        }
    }

    private var accessibilityText: String {
        switch status {
        case .ready: "Apple のクラウド 使える 今日 \(uses)回"
        case .approaching: "Apple のクラウド もうすぐ上限"
        case .reached: "Apple のクラウド 今日はここまで"
        case .unavailable: "Apple のクラウド 使えない"
        case .unsupported: "Apple のクラウド この機種は未対応"
        }
    }
}

struct ChatGPTRow: View {
    @ObservedObject private var auth = ChatGPTAuth.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("ChatGPT").atype(.body)
            Spacer(minLength: 12)
            Button(auth.isSignedIn ? "ログアウト" : (auth.busy ? "…" : "ログイン")) {
                if auth.isSignedIn { auth.signOut() } else { auth.signIn() }
            }
            .buttonStyle(.cube(.secondary))
            .disabled(auth.busy && !auth.isSignedIn)
            if auth.isSignedIn {
                let reached = ChatGPTStore.reachedToday
                StatusPill(text: reached ? "今日はここまで" : "使える", strong: reached)
            }
        }
        .sheet(isPresented: Binding(get: { auth.safariURL != nil },
                                    set: { if !$0 { auth.cancel() } })) {
            if let url = auth.safariURL { SafariSheet(url: url).ignoresSafeArea() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(auth.isSignedIn ? "ChatGPT ログイン中" : "ChatGPT ログインしていない")
    }
}

/// 色の組を選ぶ。紙の色の丸に、アクセントの色を重ねた見本を横に並べる。
private struct PalettePicker: View {
    @Environment(\.colorScheme) private var scheme
    private var store = ThemeStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Palette.all) { palette in
                    let tone = scheme == .dark || palette.alwaysDark ? palette.dark : palette.light
                    let on = palette.id == store.palette.id
                    Button { store.palette = palette } label: {
                        Circle()
                            .fill(Color(UIColor(hex: tone.accent)))
                            .padding(on ? 6 : 0)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(UIColor(hex: tone.paper))))
                            .overlay(Circle().strokeBorder(on ? Theme.ink : Theme.faint, lineWidth: on ? Theme.stroke : 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(palette.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(2)
        }
    }
}

/// 同梱している書体のライセンス（SIL Open Font License 1.1）。
private struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private let fonts: [(name: String, file: String)] = [
        ("Dela Gothic One", "OFL-DelaGothicOne"),
        ("DotGothic16", "OFL-DotGothic16"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("atoha は次の書体を使っています。どちらも SIL Open Font License 1.1 で配布されています。")
                        .atype(.small, color: Theme.quiet)
                    ForEach(fonts, id: \.file) { font in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(font.name).atype(.title)
                            Text(text(font.file)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                        }
                        .onPaper(padding: 14)
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("ライセンス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func text(_ file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "（ライセンス文が見つかりません）" }
        return s
    }
}
