import AppIntents

/// アクションボタン、ショートカット、ロック画面のライブアクティビティ、コントロールから、書き出し画面を直接開く。
struct CaptureIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "あとでに回す"
    static let description = IntentDescription("気になっていることを書いて、あとでに回す")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.showCapture = true
        return .result()
    }
}
