import SwiftUI
import SwiftData

@main
struct AtohaApp: App {
    @State private var router = AppRouter.shared
    private let container = AtohaStore.makeContainer()

    init() { Theme.registerFonts() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

/// SwiftData のストア。ウィジェットと共有できるよう App Group のフォルダに置く。
enum AtohaStore {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, Axis.self])
        // 署名なしのビルドなどで App Group が使えないときは、アプリ専用の保存場所に置く（ウィジェットとは共有されない）
        let hasGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AtohaGroup.identifier) != nil
        if hasGroup { migrateLegacyStoreIfNeeded() }
        let config = hasGroup
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AtohaGroup.identifier))
            : ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("ModelContainer: \(error)")
        }
    }

    /// 以前の保存場所（アプリ専用の Application Support）にあるストアを、App Group に移す。
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: AtohaGroup.identifier),
              let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let newDir = group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let target = newDir.appending(path: "default.store")
        let legacy = legacyDir.appending(path: "default.store")
        guard !fm.fileExists(atPath: target.path), fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try? fm.moveItem(at: legacy.deletingLastPathComponent().appending(path: "default.store" + suffix),
                             to: newDir.appending(path: "default.store" + suffix))
        }
    }
}

/// 画面をまたぐ状態。App Intent（アクションボタン）からも書き出し画面を開けるようにする。
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showCapture = false
    /// いま持ち帰ったもの（「持ち帰りました」の知らせを出す）
    var takenHomeID: UUID?
    /// 金魚鉢を開く（地図から）
    var showCollection = false
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var focus = FocusSession.shared

    @State private var tab = (DebugLaunch.tab == "axes" ? "map" : DebugLaunch.tab) ?? "now"
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $tab) {
            // タブのアイコンもドットの絵
            Tab(value: "now") { HomeView() } label: { Label { Text("今") } icon: { Image(uiImage: PixelIcon.fish) } }
            Tab(value: "later") { LaterView() } label: { Label { Text("あとで") } icon: { Image(uiImage: PixelIcon.waves) } }
            Tab(value: "map") { MapScreen() } label: { Label { Text("地図") } icon: { Image(uiImage: PixelIcon.pond) } }
        }
        .overlay(alignment: .bottom) {
            if let id = router.takenHomeID {
                TakeHomeToast {
                    router.takenHomeID = nil
                    tab = "map"
                    router.showCollection = true
                }
                .id(id)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: id) {
                    try? await Task.sleep(for: .seconds(4))
                    if router.takenHomeID == id { withAnimation { router.takenHomeID = nil } }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: router.takenHomeID)
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !DebugLaunch.skipOnboarding }, set: { if !$0 { onboarded = true } })) {
            StoryBookView { onboarded = true }
        }
        // 夜の色の組は、明るい設定でも暗い画面として扱う（ステータスバーの文字色など）
        .preferredColorScheme(ThemeStore.shared.palette.alwaysDark ? .dark : nil)
        // 集中中は、書き出し画面を集中の画面の上に出す（FocusView 側で出す）
        .fullScreenCover(isPresented: Binding(
            get: { router.showCapture && !focus.isActive },
            set: { router.showCapture = $0 }
        )) {
            CaptureView()
        }
        .fullScreenCover(isPresented: Binding(get: { focus.isActive }, set: { _ in })) {
            FocusView()
        }
        .task {
            DebugLaunch.apply(context: context, router: router)
            WatchBridge.shared.activate(context: context)
            if !DebugLaunch.skipNotifications { await NotificationScheduler.requestAuthorization() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { ReturnService.returnDue(in: context) }
        }
    }
}

/// シミュレータで画面を確かめるための起動引数（DEBUGのみ）。
/// 例: -atohaSeed -atohaTab map -atohaNoNotif -atohaCapture -atohaAxes
enum DebugLaunch {
    private static let args = ProcessInfo.processInfo.arguments

    static var tab: String? {
        #if DEBUG
        if let i = args.firstIndex(of: "-atohaTab"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }

    /// `-atohaTab axes` は地図タブを開いて軸のシートを出す。
    static var showAxesSheet: Bool { tab == "axes" }

    /// 設定を開いた状態で起動する（`-atohaSettings`）
    static var openSettings: Bool {
        #if DEBUG
        return args.contains("-atohaSettings")
        #else
        return false
        #endif
    }

    /// 初回の絵本を出さない（`-atohaNoStory`）。画面の確認用
    static var skipOnboarding: Bool {
        #if DEBUG
        return args.contains("-atohaNoStory")
        #else
        return false
        #endif
    }

    /// 地図を横から（`-atohaMapView side`）・上から（`-atohaMapView top`）で開く
    static var mapSide: Bool? {
        #if DEBUG
        if let i = args.firstIndex(of: "-atohaMapView"), i + 1 < args.count { return args[i + 1] == "side" }
        #endif
        return nil
    }

    /// 地図の池の傾きを固定する（`-atohaMapTilt 50`、0＝上から〜90＝横から）。動きの途中の確認用
    static var mapTilt: Double? {
        #if DEBUG
        if let i = args.firstIndex(of: "-atohaMapTilt"), i + 1 < args.count { return Double(args[i + 1]) }
        #endif
        return nil
    }

    /// 地図で金魚を1匹選んだ状態で開く（`-atohaMapSelect`）
    static var mapSelect: Bool {
        #if DEBUG
        return args.contains("-atohaMapSelect")
        #else
        return false
        #endif
    }

    static var skipNotifications: Bool {
        #if DEBUG
        return args.contains("-atohaNoNotif")
        #else
        return false
        #endif
    }

    @MainActor
    static func apply(context: ModelContext, router: AppRouter) {
        #if DEBUG
        if args.contains("-atohaReset") {
            try? context.delete(model: Item.self)
            try? context.delete(model: Axis.self)
        }
        if args.contains("-atohaAxes"), ((try? context.fetchCount(FetchDescriptor<Axis>())) ?? 0) == 0 {
            context.insert(Axis(negativePole: "一人で", positivePole: "人と", order: 0))
            context.insert(Axis(negativePole: "作る", positivePole: "整える", order: 1))
            context.insert(Axis(negativePole: "今", positivePole: "将来", order: 2))
        }
        if args.contains("-atohaSeed") { SampleData.insert(into: context) }
        try? context.save()
        if args.contains("-atohaFocus"), !FocusSession.shared.isActive {
            let returned = ItemState.returned.rawValue
            var d = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returned }, sortBy: [SortDescriptor(\.createdAt)])
            d.fetchLimit = 1
            if let item = try? context.fetch(d).first { FocusSession.shared.start(item) }
        }
        if args.contains("-atohaCapture") { router.showCapture = true }
        if args.contains("-atohaCollection") { router.showCollection = true }
        try? context.save()
        #endif
    }
}
