import AppIntents

struct AtohaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["\(.applicationName)であとでに回す", "\(.applicationName)であとで", "\(.applicationName)"],
            shortTitle: "あとでに回す",
            systemImageName: "square.and.arrow.down"
        )
    }
}
