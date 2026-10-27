import AppIntents
import CoreSpotlight
import SwiftData

// MARK: - あとに回す（アプリを開かずに）

/// Siri・ショートカット・アクションボタンから、文を受け取ってそのまま水槽に入れる。アプリは開かない。
struct PutLaterIntent: AppIntent {
    static let title: LocalizedStringResource = "文をあとに回す"
    static let description = IntentDescription("気になっていることを、アプリを開かずにあとに回す")
    static let openAppWhenRun = false

    @Parameter(title: "回すこと", requestValueDialog: "何をあとに回しますか？")
    var text: String

    @Parameter(title: "戻すとき")
    var timing: ReturnTiming?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text)をあとに回す") { \.$timing }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<GoldfishEntity?> {
        let context = AtohaStore.shared.mainContext
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result(value: nil, dialog: "書くことが空でした") }
        // 水槽がいっぱいなら入れない（アプリの書き出し画面と同じ決まり）
        guard ReturnService.laterRoom(in: context) > 0 else {
            return .result(value: nil, dialog: "水槽がいっぱいです。1匹放すと、また回せます")
        }
        let timing = timing ?? SettingsStore.defaultTiming
        let item = Item(text: trimmed, timing: timing)
        context.insert(item)
        try? context.save()
        if let date = item.returnAt { NotificationScheduler.reschedule(for: date, in: context) }
        // 振り分けは待ちすぎない（間に合わなければ次に開いたときの処理に任せる）
        let axes = (try? context.fetch(FetchDescriptor<Axis>(sortBy: [SortDescriptor(\.order)]))) ?? []
        _ = await withTimeout(6) { await ItemProcessor.process(item, axes: axes); return true }
        ReturnService.sync(in: context)
        return .result(value: GoldfishEntity(item), dialog: "\(timing.returnMessage())")
    }
}

extension ReturnTiming: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "戻すとき"
    static let caseDisplayRepresentations: [ReturnTiming: DisplayRepresentation] = [
        .atBreak: "手が空いたら",
        .tonight: "今夜",
        .tomorrowMorning: "明日の朝"
    ]
}

// MARK: - 金魚（Siri・Spotlight・ショートカットから扱う）

/// あとで・今・持ち帰った金魚。手放したものは出さない。
struct GoldfishEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "金魚", numericFormat: "\(placeholder: .int)匹の金魚")
    static let defaultQuery = GoldfishQuery()

    let id: UUID
    @Property(title: "名前") var text: String
    @Property(title: "いるところ") var place: String
    @Property(title: "期限") var deadline: Date?

    init(_ item: Item) {
        id = item.id
        text = item.text
        place = GoldfishEntity.placeName(item.state)
        deadline = item.deadline
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(text)", subtitle: "\(place)", image: .init(systemName: "fish"))
    }

    static func placeName(_ state: ItemState) -> String {
        switch state {
        case .waiting: "あとで"
        case .returned: "今"
        case .done: "持ち帰った"
        case .grown: "池"
        case .released: "手放した"
        }
    }
}

struct GoldfishQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GoldfishEntity] {
        let context = AtohaStore.shared.mainContext
        return identifiers.compactMap { WidgetSync.fetch($0, in: context) }
            .filter { $0.state != .released }
            .map(GoldfishEntity.init)
    }

    /// 候補は今とあとで（今を先に）
    @MainActor
    func suggestedEntities() async throws -> [GoldfishEntity] {
        let context = AtohaStore.shared.mainContext
        let returned = ItemState.returned.rawValue, waiting = ItemState.waiting.rawValue
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == returned || $0.stateRaw == waiting }))) ?? []
        return items
            .sorted { ($0.state == .returned ? 0 : 1, -$0.priority()) < ($1.state == .returned ? 0 : 1, -$1.priority()) }
            .map(GoldfishEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GoldfishEntity] {
        let context = AtohaStore.shared.mainContext
        let released = ItemState.released.rawValue
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw != released && $0.text.localizedStandardContains(string) }))) ?? []
        return items.map(GoldfishEntity.init)
    }
}

// MARK: - 金魚への操作

/// あとでの金魚を今に入れる（すくう）。お椀がいっぱいなら入れない。
struct ScoopIntent: AppIntent {
    static let title: LocalizedStringResource = "今に入れる"
    static let description = IntentDescription("あとでの金魚を1匹すくって、今に入れる")
    static let openAppWhenRun = false

    @Parameter(title: "金魚") var target: GoldfishEntity

    static var parameterSummary: some ParameterSummary { Summary("\(\.$target)を今に入れる") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AtohaStore.shared.mainContext
        guard let item = WidgetSync.fetch(target.id, in: context), item.state == .waiting else {
            return .result(dialog: "その金魚はあとでにいません")
        }
        guard ReturnService.accept(item, in: context) else {
            return .result(dialog: "お椀がいっぱいです")
        }
        return .result(dialog: "今に入れました")
    }
}

/// 今の金魚を持ち帰る（できた）。集中していたら、その時間も足して終える。
struct TakeHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "持ち帰る"
    static let description = IntentDescription("できた金魚を袋に入れて持ち帰る")
    static let openAppWhenRun = false

    @Parameter(title: "金魚") var target: GoldfishEntity

    static var parameterSummary: some ParameterSummary { Summary("\(\.$target)を持ち帰る") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AtohaStore.shared.mainContext
        guard let item = WidgetSync.fetch(target.id, in: context), item.state == .returned || item.state == .waiting else {
            return .result(dialog: "その金魚は持ち帰れません")
        }
        let session = FocusSession.shared
        if session.itemID == item.id {
            if let seconds = session.stop() { item.focusSeconds += seconds }
            ReturnService.takeHome(item, in: context)
            session.clear()
        } else {
            ReturnService.takeHome(item, in: context)
        }
        return .result(dialog: "持ち帰りました")
    }
}

/// 金魚を開く（Spotlight から選んだとき）。いるところのタブを出す。
struct OpenGoldfishIntent: OpenIntent {
    static let title: LocalizedStringResource = "金魚を開く"

    @Parameter(title: "金魚") var target: GoldfishEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = AtohaStore.shared.mainContext
        if let item = WidgetSync.fetch(target.id, in: context) {
            switch item.state {
            case .returned: AppRouter.shared.tab = "now"
            case .waiting: AppRouter.shared.tab = "later"
            case .done: AppRouter.shared.showCollection = true
            default: AppRouter.shared.tab = "map"
            }
        }
        return .result()
    }
}

// MARK: - Spotlight

/// 金魚を Spotlight に載せる。手放したものは外す。
@MainActor
enum GoldfishIndex {
    private static var last: [UUID: String] = [:]

    static func update(in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        // 名前かいるところが変わったものだけ載せ直す
        var current: [UUID: String] = [:]
        var changed: [GoldfishEntity] = []
        var removed: [UUID] = []
        for item in items {
            guard item.state != .released else { removed.append(item.id); continue }
            let key = item.text + "|" + item.stateRaw
            current[item.id] = key
            if last[item.id] != key { changed.append(GoldfishEntity(item)) }
        }
        removed += last.keys.filter { current[$0] == nil && !removed.contains($0) }
        last = current
        guard !changed.isEmpty || !removed.isEmpty else { return }
        Task {
            if !changed.isEmpty { try? await CSSearchableIndex.default().indexAppEntities(changed) }
            if !removed.isEmpty { try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: removed, ofType: GoldfishEntity.self) }
        }
    }
}
