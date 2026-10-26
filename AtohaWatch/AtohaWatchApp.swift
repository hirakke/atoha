import SwiftUI

@main
struct AtohaWatchApp: App {
    @StateObject private var store = WatchStore.shared
    @State private var screen: WatchScreen = WatchApp.debugScreen

    init() {
        KFont.registerFonts()
        WatchApp.applyDebugState()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(screen: $screen)
                .environmentObject(store)
                .tint(KColor.now)
                .task { store.activate() }
                // コンプリケーションの「＋ 回す」から開いたとき
                .onOpenURL { url in
                    if url.host == "capture" { screen = store.isFull ? .full : .capture } else { screen = .home }
                }
        }
    }
}

/// 起動引数で画面を確かめる（DEBUG のみ）。-watchState now|capture|released|full|focus|empty|taken
enum WatchApp {
    static let debugState: String? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-watchState"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }()

    /// アニメーションと自動で戻るのを止める（スクリーンショット用）
    static var debugFrozen: Bool { debugState != nil }

    static var debugScreen: WatchScreen {
        switch debugState {
        case "capture": .capture
        case "released": .released
        case "full": .full
        case "taken": .taken
        default: .home
        }
    }

    static var debugCaptureText: String { debugState == "capture" ? "企画書のしめきりを確かめる" : "" }

    static func applyDebugState() {
        #if DEBUG
        guard let state = debugState else { return }
        let deadline = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)
        let now = WatchSnapshot(nowID: UUID().uuidString, nowText: "母に電話", nowDeadline: deadline)
        var snapshot = now
        var count = 3
        switch state {
        case "empty":
            snapshot = WatchSnapshot()
        case "focus":
            snapshot.focusID = now.nowID
            snapshot.focusText = now.nowText
            snapshot.focusStart = Date().addingTimeInterval(-754)
            snapshot.focusPlanned = 25
        case "full":
            count = 20
        default:
            break
        }
        WatchStore.shared.debugSet(count: count, capacity: 20, snapshot: snapshot)
        #endif
    }
}
