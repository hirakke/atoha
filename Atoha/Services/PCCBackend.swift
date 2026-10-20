import Foundation
import FoundationModels

/// Private Cloud Compute の状態。画面には文章ではなく、小さな印として出す。
enum CloudStatus: Equatable {
    case unsupported  // この SDK／OS では PCC がない（Xcode 26 ビルド、iOS 26）
    case unavailable  // 非対応の端末・地域、ネットワークなし、準備中
    case ready
    case approaching  // 1日の上限に近い
    case reached      // 1日の上限に達した
}

/// まとめ処理にどのモデルを使うかを決める。
/// PCC は 1日の上限があるので、まとめ処理（区切りで返すとき・軸の候補）にだけ使い、
/// 1件ずつの振り分けは常に iPhone 内のモデルで行う。
@MainActor
enum CloudAI {
    static var status: CloudStatus {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) { return PCCBackend.status }
        #endif
        return .unsupported
    }

    /// PCC が使えれば PCC、使えなければ iPhone 内のモデル。
    static var batchBackend: LanguageBackend {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *), [.ready, .approaching].contains(PCCBackend.status) {
            return PCCBackend()
        }
        #endif
        let gpt = ChatGPTBackend()
        if FeatureFlags.chatGPTEnabled && gpt.isAvailable && !ChatGPTStore.reachedToday { return gpt }
        return AtohaAI.backend
    }

    static func isCloud(_ backend: LanguageBackend) -> Bool {
        if backend is ChatGPTBackend { return true }
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) { return backend is PCCBackend }
        #endif
        return false
    }

    /// 上限を増やす選択肢（iCloud+）を出せるか。
    static var canShowLimitOptions: Bool {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) { return PCCBackend.limitIncreaseAvailable }
        #endif
        return false
    }

    /// Apple が用意した、上限を増やす選択肢の画面を出す。
    static func showLimitOptions() {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) { PCCBackend.showLimitOptions() }
        #endif
    }

    // MARK: 使った回数（上限の数値は公開されていないので、自分で数えて控えめに使う）

    /// PCC を使ってよい1日の回数。Apple の上限より十分少なくしておく。
    static let dailyBudget = 3
    private static let usesKey = "atoha.pcc.uses"

    static var usesToday: Int {
        let stamps = UserDefaults.standard.array(forKey: usesKey) as? [Double] ?? []
        return stamps.filter { Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0)) }.count
    }

    static var hasBudget: Bool { usesToday < dailyBudget }

    static func recordUse(of backend: LanguageBackend) {
        guard isCloud(backend) else { return }
        var stamps = UserDefaults.standard.array(forKey: usesKey) as? [Double] ?? []
        stamps = stamps.filter { Date().timeIntervalSince1970 - $0 < 86_400 * 2 }
        stamps.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(stamps, forKey: usesKey)
    }
}

#if compiler(>=6.3)
/// iOS 27 の Private Cloud Compute（32K、推論あり、1日の上限あり）。
/// 使うには App Store Small Business Program への登録と、PCC の entitlement の申請が必要。
@available(iOS 27.0, *)
struct PCCBackend: LanguageBackend {
    private static let model = PrivateCloudComputeLanguageModel()

    static var status: CloudStatus {
        guard case .available = model.availability else { return .unavailable }
        if model.quotaUsage.isLimitReached { return .reached }
        if case .belowLimit(let info) = model.quotaUsage.status, info.isApproachingLimit { return .approaching }
        return .ready
    }

    static var limitIncreaseAvailable: Bool { model.quotaUsage.limitIncreaseSuggestion != nil }

    static func showLimitOptions() {
        model.quotaUsage.limitIncreaseSuggestion?.show()
    }

    var isAvailable: Bool { [.ready, .approaching].contains(Self.status) }
    /// 32K に収まる量。1件60文字までに切る。
    var batchLimit: Int { 200 }

    /// 1件ずつの振り分けには使わない（回数を節約する）。
    func classify(_ text: String) async -> (kind: ItemKind, theme: String?)? { nil }

    func proposeAxes(from texts: [String], avoid: [String], limit: Int) async -> [ProposedAxis] {
        guard isAvailable, !texts.isEmpty else { return [] }
        let session = LanguageModelSession(model: Self.model, instructions: BatchPrompts.axesInstructions)
        return await BatchPrompts.proposeAxes(session: session, texts: Array(texts.prefix(batchLimit)),
                                              avoid: avoid, limit: limit, maxChars: 60)
    }

    func groupThemes(_ texts: [String], known: [String]) async -> [String]? {
        guard isAvailable, !texts.isEmpty else { return nil }
        let batch = Array(texts.prefix(batchLimit))
        let session = LanguageModelSession(model: Self.model, instructions: BatchPrompts.groupInstructions)
        do {
            let r = try await session.respond(
                to: BatchPrompts.groupPrompt(batch, known: known, maxChars: 60),
                generating: GenGroups.self
            )
            return BatchPrompts.align(r.content, count: batch.count)
        } catch {
            return nil
        }
    }
}
#endif
