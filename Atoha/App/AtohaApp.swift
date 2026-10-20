import SwiftUI
import SwiftData

@main
struct AtohaApp: App {
    @State private var router = AppRouter.shared
    private let container = AtohaStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Theme.ink)
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
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var focus = FocusSession.shared

    @State private var tab = (DebugLaunch.tab == "axes" ? "map" : DebugLaunch.tab) ?? "now"

    var body: some View {
        @Bindable var router = router
        TabView(selection: $tab) {
            Tab("今", systemImage: "square.stack", value: "now") { HomeView() }
            Tab("あとで", systemImage: "square.dashed", value: "later") { LaterView() }
            Tab("地図", systemImage: "cube", value: "map") { MapScreen() }
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
        try? context.save()
        #endif
    }
}
