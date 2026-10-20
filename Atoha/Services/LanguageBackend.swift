import Foundation
import FoundationModels

/// Seam between atoha's AI features and whatever language model is available.
///
/// - `OnDeviceBackend`：iPhone 内の `SystemLanguageModel`（4K）。1件ずつの振り分けと、小さなまとめ処理。
/// - `PCCBackend`（PCCBackend.swift）：iOS 27 の Private Cloud Compute（32K、1日の上限あり）。
///   区切りで返すときのまとめ処理と軸の候補だけに使う。Xcode 27 以降でビルドしたときだけ有効。
protocol LanguageBackend {
    var isAvailable: Bool { get }
    /// 一度に渡してよいメモの数（文脈の長さで決まる）
    var batchLimit: Int { get }
    /// Returns nil when the model cannot answer; caller falls back to heuristics.
    func classify(_ text: String) async -> (kind: ItemKind, theme: String?)?
    /// Up to `limit` bipolar pole pairs, each with a few related everyday words per pole
    /// (used to expand the pole for embedding-based scoring). `avoid` lists existing "A↔B".
    func proposeAxes(from texts: [String], avoid: [String], limit: Int) async -> [ProposedAxis]
    /// まとめ処理：各メモに「まとまり」の名前を付ける。`known` は既存のまとまり名（なるべく再利用させる）。
    /// 戻り値は texts と同じ順の名前。答えられないときは nil。
    func groupThemes(_ texts: [String], known: [String]) async -> [String]?
    /// 2つのメモのグループの違いを、対になる短い言葉で表す（negative = low 側、positive = high 側）。答えられないときは nil。
    func namePoles(low: [String], high: [String]) async -> (negative: String, positive: String)?
}

extension LanguageBackend {
    func namePoles(low: [String], high: [String]) async -> (negative: String, positive: String)? { nil }
}

/// まとめ処理と軸の候補のプロンプト。どのモデルでも同じものを使い、渡す量だけを変える。
enum BatchPrompts {
    static let groupInstructions = """
    メモ全体を、内容の近さで少数のまとまりに分ける。まとまりの数はメモの数の3分の1以下にする。
    各メモに、属するまとまりの名前を付ける。同じまとまりのメモには必ず同じ名前を付ける。
    名前は日本語の名詞2〜6文字で、個々のメモより広い言葉にする（例：卒論・就活・仕事 → 進路）。
    既存の名前に合うものはそれを使う。
    """

    static func groupPrompt(_ texts: [String], known: [String], maxChars: Int) -> String {
        var prompt = ""
        if !known.isEmpty { prompt += "既存の名前: \(known.prefix(30).joined(separator: "、"))\n" }
        prompt += "メモ:\n"
        prompt += texts.enumerated().map { "\($0.offset): \(String($0.element.prefix(maxChars)))" }.joined(separator: "\n")
        return prompt
    }

    /// モデルの答えを texts と同じ順の配列にそろえる。抜けがあれば nil。
    static func align(_ gen: GenGroups, count: Int) -> [String]? {
        var names = [String?](repeating: nil, count: count)
        for a in gen.items where (0..<count).contains(a.index) {
            let n = a.theme.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { names[a.index] = String(n.prefix(10)) }
        }
        let filled = names.compactMap { $0 }
        return filled.count == count ? filled : nil
    }
}

@Generable
struct GenGroupAssignment {
    @Guide(description: "メモの番号")
    var index: Int
    @Guide(description: "まとまりの名前。名詞2〜6文字")
    var theme: String
}

@Generable
struct GenGroups {
    @Guide(description: "すべてのメモについて1つずつ")
    var items: [GenGroupAssignment]
}

@Generable
struct GenPolePair {
    @Guide(description: "グループAを表す短い言葉。2〜6文字")
    var a: String
    @Guide(description: "グループBを表す短い言葉。2〜6文字")
    var b: String
}

extension BatchPrompts {
    static let namePolesInstructions = """
    同じ人が書いた2つのメモのグループから、その人自身を知る手がかりになる違いを、対になる短い言葉で表す。
    何に惹かれるか、どう取り組むのが好きか、何を大事にしているか、という本人の傾向を表す言葉にする。
    話題の分類（勉強↔遊び）、時期や締め切り、気分や体調は使わない。良し悪しを含まない。メモの単語をそのまま使わない。
    例: 一人で↔人と、作る↔整える、考える↔動く、深める↔広げる、自分のため↔誰かのため
    """

    static func namePolesPrompt(low: [String], high: [String]) -> String {
        func list(_ xs: [String]) -> String { xs.map { "・" + String($0.prefix(60)) }.joined(separator: "\n") }
        return "グループA:\n\(list(low))\nグループB:\n\(list(high))\nAとBの違いを表す対の言葉。"
    }

    static func clean(_ pair: (String, String)) -> (String, String) {
        let t = { (x: String) in String(x.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)) }
        return (t(pair.0), t(pair.1))
    }
}

struct ProposedAxis {
    var negative: String
    var positive: String
    var negativeWords: [String]
    var positiveWords: [String]
}

// MARK: - Structured output types

@Generable
enum GenKind {
    case errand
    case concern
}

@Generable
struct GenClassification {
    @Guide(description: "errand=買う・出す・連絡などすぐ済む用事。concern=アイデア・悩み・考えたいこと")
    var kind: GenKind
    @Guide(description: "まとまりの名前。日本語の名詞2〜6文字（英語は使わない）")
    var theme: String
}

@Generable
struct GenAxis {
    @Guide(description: "片側の極。2〜6文字")
    var negative: String
    @Guide(description: "反対側の極。2〜6文字")
    var positive: String
    @Guide(description: "片側の極に近い、メモに出そうな語", .count(3))
    var negativeWords: [String]
    @Guide(description: "反対側の極に近い、メモに出そうな語", .count(3))
    var positiveWords: [String]
}

@Generable
struct GenAxes {
    @Guide(description: "対になる2極の軸", .maximumCount(3))
    var axes: [GenAxis]
}

// MARK: - On-device implementation

struct OnDeviceBackend: LanguageBackend {
    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }
    var batchLimit: Int { 24 }

    func groupThemes(_ texts: [String], known: [String]) async -> [String]? {
        guard isAvailable, !texts.isEmpty else { return nil }
        let batch = Array(texts.prefix(batchLimit))
        let session = LanguageModelSession(instructions: BatchPrompts.groupInstructions)
        do {
            let r = try await session.respond(
                to: BatchPrompts.groupPrompt(batch, known: known, maxChars: 40),
                generating: GenGroups.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return BatchPrompts.align(r.content, count: batch.count)
        } catch {
            return nil
        }
    }

    func classify(_ text: String) async -> (kind: ItemKind, theme: String?)? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: "短いメモを「用事」か「気になること」に分ける。")
        do {
            let r = try await session.respond(
                to: String(text.prefix(200)),
                generating: GenClassification.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let kind: ItemKind = r.content.kind == .errand ? .errand : .concern
            let theme = r.content.theme.trimmingCharacters(in: .whitespacesAndNewlines)
            return (kind, theme.isEmpty ? nil : String(theme.prefix(10)))
        } catch {
            return nil
        }
    }

    func namePoles(low: [String], high: [String]) async -> (negative: String, positive: String)? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: BatchPrompts.namePolesInstructions)
        do {
            let r = try await session.respond(to: BatchPrompts.namePolesPrompt(low: low, high: high),
                                              generating: GenPolePair.self)
            let c = BatchPrompts.clean((r.content.a, r.content.b))
            return (c.0, c.1)
        } catch { return nil }
    }

    func proposeAxes(from texts: [String], avoid: [String], limit: Int) async -> [ProposedAxis] {
        guard isAvailable, !texts.isEmpty else { return [] }
        // Keep well inside 4K tokens: ≤24 texts × ≤40 chars.
        let session = LanguageModelSession(instructions: BatchPrompts.axesInstructions)
        return await BatchPrompts.proposeAxes(session: session, texts: Array(texts.prefix(batchLimit)),
                                              avoid: avoid, limit: limit, maxChars: 40)
    }
}

extension BatchPrompts {
    static let axesInstructions = """
    メモ全体から、その人自身を知る手がかりになる「対の軸」を出す。
    何に惹かれるか、どう取り組むのが好きか、何を大事にしているか、という本人の傾向を表す軸にする。
    話題の分類（勉強↔遊び）や時期・締め切りの軸にはしない。
    両極はどちらも良い悪いのない、対等な言葉にする。気分や体調（不安、疲労、元気など）は使わない。
    どちらの極にもメモがいくつか当てはまる軸にする。メモの単語をそのまま使わない。
    例: 一人で↔人と、作る↔整える、今↔将来、考える↔動く、自分のため↔誰かのため、深める↔広げる
    """

    static func proposeAxes(session: LanguageModelSession, texts: [String], avoid: [String],
                            limit: Int, maxChars: Int) async -> [ProposedAxis] {
        let list = texts.map { "・" + String($0.prefix(maxChars)) }.joined(separator: "\n")
        var prompt = "メモ:\n\(list)\n"
        if !avoid.isEmpty { prompt += "除外: \(avoid.joined(separator: "、"))\n" }
        prompt += "対の軸を\(limit)つ。"
        do {
            let r = try await session.respond(to: prompt, generating: GenAxes.self)
            return r.content.axes.prefix(limit).compactMap { a in
                let n = a.negative.trimmingCharacters(in: .whitespacesAndNewlines)
                let p = a.positive.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty, !p.isEmpty, n != p else { return nil }
                func clean(_ ws: [String]) -> [String] {
                    ws.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { String($0.prefix(10)) }
                }
                return ProposedAxis(negative: String(n.prefix(8)), positive: String(p.prefix(8)),
                                    negativeWords: clean(a.negativeWords), positiveWords: clean(a.positiveWords))
            }
        } catch {
            return []
        }
    }
}
