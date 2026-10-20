import AppIntents

struct AtohaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["\(.applicationName)であとで", "\(.applicationName)"],
            shortTitle: "あとで",
            systemImageName: "square.and.arrow.down"
        )
    }
}
