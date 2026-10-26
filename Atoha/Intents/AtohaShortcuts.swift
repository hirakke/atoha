import AppIntents

struct AtohaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["\(.applicationName)であとに回す", "\(.applicationName)であとで", "\(.applicationName)"],
            shortTitle: "あとに回す",
            systemImageName: "square.and.arrow.down"
        )
    }
}
