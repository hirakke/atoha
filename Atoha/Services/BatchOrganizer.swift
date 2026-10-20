import Foundation
import SwiftData

/// まとめ処理。区切りで返ってきたとき（アプリを開いて返ってきたものがあるとき）に、
/// 気になることを「まとまり」に分けて名前を付け直し、軸の位置を計算し直す。
/// PCC が使えれば一度に最大200件、使えなければ iPhone 内のモデルで最新24件。
@MainActor
enum BatchOrganizer {
    private static let lastRunKey = "atoha.batch.lastRun"
    private(set) static var isRunning = false

    static var lastRun: Date? {
        let t = UserDefaults.standard.double(forKey: lastRunKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// 前回のまとめ処理のあとに預けたものがあれば実行する。実行したら true。
    @discardableResult
    static func organizeIfNeeded(in context: ModelContext, now: Date = .now) async -> Bool {
        guard !isRunning else { return false }
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let concerns = all
            .filter { $0.kind == .concern && $0.state != .released }
            .sorted { $0.createdAt > $1.createdAt }
        guard concerns.count >= 3 else { return false }
        if let lastRun, !concerns.contains(where: { $0.createdAt > lastRun }) { return false }

        isRunning = true
        defer { isRunning = false }

        var backend = CloudAI.batchBackend
        // PCC は自分で決めた1日の回数まで。超えたら iPhone 内のモデルに切り替える。
        if CloudAI.isCloud(backend) && !CloudAI.hasBudget { backend = AtohaAI.backend }

        if AtohaAI.prefersModel && backend.isAvailable {
            let batch = Array(concerns.prefix(backend.batchLimit))
            let known = Array(Set(concerns.compactMap(\.theme)))
            if let names = await backend.groupThemes(batch.map(\.text), known: known) {
                for (item, name) in zip(batch, names) { item.theme = name }
            }
            CloudAI.recordUse(of: backend)
        }

        let axes = (try? context.fetch(FetchDescriptor<Axis>(sortBy: [SortDescriptor(\.order)]))) ?? []
        AxisEngine.rescore(items: all, axes: axes)
        try? context.save()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastRunKey)
        return true
    }
}
