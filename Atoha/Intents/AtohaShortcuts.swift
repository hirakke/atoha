import AppIntents

struct AtohaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // 文を受け取って、アプリを開かずに入れる（Siri は「何をあとに回しますか？」と聞く）
        AppShortcut(
            intent: PutLaterIntent(),
            phrases: ["\(.applicationName)であとに回す", "\(.applicationName)であとで", "\(.applicationName)"],
            shortTitle: "あとに回す",
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["\(.applicationName)で書く", "\(.applicationName)の書き出しを開く"],
            shortTitle: "書いて回す",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: ScoopIntent(),
            phrases: ["\(.applicationName)で\(\.$target)を今に入れる", "\(.applicationName)で今に入れる"],
            shortTitle: "今に入れる",
            systemImageName: "fish"
        )
        AppShortcut(
            intent: TakeHomeIntent(),
            phrases: ["\(.applicationName)で\(\.$target)を持ち帰る", "\(.applicationName)で持ち帰る"],
            shortTitle: "持ち帰る",
            systemImageName: "bag"
        )
    }
}
