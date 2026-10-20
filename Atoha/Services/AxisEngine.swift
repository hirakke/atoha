import Foundation
import SwiftData

struct AxisCandidate: Identifiable, Hashable {
    let id: UUID
    var negativePole: String
    var positivePole: String
    /// 低い側（negativePole 寄り）と高い側（positivePole 寄り）の、本人のメモ
    var lowSamples: [String]
    var highSamples: [String]
    /// 主成分分析由来のとき、その成分が全体のばらつきに占める割合（0...1）。それ以外は nil。
    var explainedVariance: Double? = nil
}

/// Built-in bipolar constructs (used for pole expansion and as the no-model candidate pool).
struct PoleConstruct {
    let negative: String
    let positive: String
    let negativeWords: [String]
    let positiveWords: [String]
}

@MainActor
enum AxisEngine {

    // MARK: Pole vocabulary

    static let constructs: [PoleConstruct] = [
        PoleConstruct(negative: "一人で", positive: "人と",
                      negativeWords: ["一人", "ひとり", "自分で", "集中", "静か", "読書", "黙々", "一人で考える",
                                      "こもる", "ソロ", "孤独", "マイペース", "没頭", "自習", "一人旅", "一人暮らし", "自分だけ"],
                      positiveWords: ["みんな", "友達", "仲間", "一緒", "サークル", "イベント", "会う", "話す", "飲み会", "チーム", "新入生",
                                      "誰かと", "語る", "語り", "おしゃべり", "ご飯", "遊ぶ", "先輩", "ゼミ", "合宿", "交流", "相談",
                                      "仲良く", "会いたい", "集まり", "パーティ", "協力", "共有", "恋人", "夜通し", "フットサル", "バンド"]),
        PoleConstruct(negative: "作る", positive: "整える",
                      negativeWords: ["作る", "企画", "アイデア", "新しい", "描く", "書く", "制作", "ゲーム", "デザイン", "作品",
                                      "作って", "作りたい", "創作", "小説", "曲", "絵", "描いて", "書いて", "オリジナル", "アプリ",
                                      "ブログ", "漫画", "動画", "表現", "レゴ", "発明"],
                      positiveWords: ["片付け", "整理", "掃除", "見直す", "管理", "習慣", "生活", "部屋", "記録", "準備",
                                      "断捨離", "整頓", "片づけ", "整える", "机", "クローゼット", "収納", "スケジュール", "家計",
                                      "ルーティン", "規則正しい", "朝型", "洗濯", "模様替え", "見直し", "手帳"]),
        PoleConstruct(negative: "今", positive: "将来",
                      negativeWords: ["今", "いま", "今日", "今週", "今すぐ", "最近", "目の前", "明日",
                                      "今週末", "今日は", "疲れ", "眠い", "早く寝", "ゆっくり", "休み", "今だけ", "いまの", "今夜"],
                      positiveWords: ["将来", "未来", "進路", "就活", "キャリア", "何年後", "いつか", "夢", "人生",
                                      "年後", "老後", "数年後", "卒業後", "就職", "結婚", "何年", "長い目", "先のこと", "10年後"]),
        PoleConstruct(negative: "自分のため", positive: "誰かのため",
                      negativeWords: ["自分", "趣味", "好き", "休む", "自分の時間", "楽しみ", "欲しい", "ご褒美",
                                      "自分へ", "好きなだけ", "食べたい", "ケーキ", "自由", "ダラダラ", "贅沢", "買いたい", "寝たい"],
                      positiveWords: ["誰か", "人のため", "手伝う", "喜ぶ", "プレゼント", "後輩", "家族", "役に立つ", "支える", "母", "友達に",
                                      "贈る", "贈りたい", "誕生日", "手紙", "恩返し", "感謝", "お礼", "ありがとう", "ボランティア",
                                      "貢献", "寄付", "応援", "親孝行", "助ける", "世話"]),
        PoleConstruct(negative: "考える", positive: "動く",
                      negativeWords: ["考える", "考え", "悩む", "どう", "なぜ", "迷う", "不安", "気になる", "調べる", "だろう",
                                      "どうして", "理由", "正解", "緊張", "わからない", "悩み", "振り返", "迷ってる"],
                      positiveWords: ["やってみる", "行く", "始める", "動く", "挑戦", "試す", "実行", "参加", "やる",
                                      "行ってみ", "やってみ", "見学", "体験", "申し込み", "応募", "踏み出", "一歩", "とにかく",
                                      "始めたい", "通う", "行動", "練習", "始めて", "試して"]),
        PoleConstruct(negative: "安定", positive: "変化",
                      negativeWords: ["安定", "いつも通り", "続ける", "安心", "守る", "慣れた", "習慣", "毎日",
                                      "ずっと同じ", "変わらない", "同じ", "毎朝", "日課", "ルーティン", "落ち着", "いつもの", "定番", "馴染み"],
                      positiveWords: ["変える", "新しい", "変化", "初めて", "違う", "転職", "引っ越し", "やめる", "挑戦",
                                      "海外", "住んでみ", "髪型", "変えたい", "がらっと", "イメチェン", "留学", "環境", "刺激", "冒険", "新生活"]),
    ]

    /// Pole word list → expanded with built-in related words when the pole matches a construct,
    /// or with model-supplied related words remembered in `learnedWords`.
    private static func words(for pole: String) -> [String] {
        for c in constructs {
            if c.negative == pole { return [pole] + c.negativeWords }
            if c.positive == pole { return [pole] + c.positiveWords }
        }
        return [pole] + (learnedWords[pole] ?? [])
    }

    /// Related words for model-proposed poles, persisted so adopted axes keep scoring well
    /// after relaunch (the `Axis` model has no field for them).
    private static let learnedKey = "atoha.axis.learnedPoleWords"
    private static var learnedWords: [String: [String]] = {
        (UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: [String]]) ?? [:]
    }()

    private static func learn(_ pole: String, _ related: [String]) {
        guard !related.isEmpty, constructs.allSatisfy({ $0.negative != pole && $0.positive != pole }) else { return }
        learnedWords[pole] = Array(related.prefix(6))
        poleCache = poleCache.filter { !$0.key.hasPrefix(pole + "#") }
        UserDefaults.standard.set(learnedWords, forKey: learnedKey)
    }

    private static var poleCache: [String: [[Double]]] = [:]

    private static func poleVectors(_ pole: String) -> [[Double]] {
        let key = "\(pole)#\(EmbeddingService.dimension)"
        if let v = poleCache[key] { return v }
        let v = words(for: pole).map(EmbeddingService.embed)
        poleCache[key] = v
        return v
    }

    /// Max cosine to any word of the pole: sharper than a centroid for short notes.
    private static func poleSimilarity(_ e: [Double], _ pole: String) -> Double {
        poleVectors(pole).map { EmbeddingService.cosine(e, $0) }.max() ?? 0
    }

    /// Unscaled score: positive side minus negative side.
    static func rawScore(_ e: [Double], negative: String, positive: String) -> Double {
        poleSimilarity(e, positive) - poleSimilarity(e, negative)
    }

    // MARK: Scaling

    /// Per-axis scale k, learned from the spread of raw scores in the last `rescore`
    /// (k = 1 / 90th percentile of |raw|), so typical items use most of -1...1.
    /// `scoreSingle` reuses it so a freshly captured item lands consistently.
    private static var scaleCache: [String: Double] = [:]
    private static let defaultScale = 3.0

    private static func axisKey(_ negative: String, _ positive: String) -> String { "\(negative)↔\(positive)" }

    private static func clamp(_ x: Double) -> Double { min(1, max(-1, x)) }

    private static func ensureEmbedding(_ item: Item) -> [Double] {
        if let e = item.embedding, e.count == EmbeddingService.dimension { return e }
        let e = EmbeddingService.embed(item.text)
        item.embedding = e
        return e
    }

    private static func sortedAxes(_ axes: [Axis]) -> [(String, String)] {
        axes.sorted { $0.order < $1.order }.map { ($0.negativePole, $0.positivePole) }
    }

    // MARK: Public API

    static func rescore(items: [Item], axes: [Axis]) {
        let poles = sortedAxes(axes)
        let concerns = items.filter { $0.kind == .concern }
        for item in items where item.kind != .concern {
            item.axisScores = []
            item.axisAffinity = 0
        }
        guard !concerns.isEmpty else { return }

        let embeddings = concerns.map(ensureEmbedding)

        // Raw scores per axis, then learn scale.
        var scaled = [[Double]](repeating: [], count: concerns.count)
        for (neg, pos) in poles {
            let raws = embeddings.map { rawScore($0, negative: neg, positive: pos) }
            let mags = raws.map(abs).sorted()
            let p90 = mags[min(mags.count - 1, Int(Double(mags.count - 1) * 0.9))]
            let k = p90 > 0.02 ? 1 / p90 : defaultScale
            scaleCache[axisKey(neg, pos)] = k
            for i in raws.indices { scaled[i].append(clamp(raws[i] * k)) }
        }

        // Density reference: concerns the user chose to keep growing (or all concerns if none yet).
        let keptIdx = concerns.indices.filter { concerns[$0].state == .grown }
        let refIdx = keptIdx.isEmpty ? Array(concerns.indices) : keptIdx

        let raw = concerns.indices.map { i -> Double in
            let a = affinity(scores: scaled[i], density: density(of: i, embeddings: embeddings, reference: refIdx))
            // 本人の「やりたい」を強く混ぜる（未評価は 1.0 倍）
            return a * (0.5 + (concerns[i].want ?? 0.5))
        }
        // 埋め込みの質で絶対値がぶれるので、本人の気になることの中での順位（0...1）にそろえる
        let order = raw.indices.sorted { raw[$0] < raw[$1] }
        var rank = [Double](repeating: 0, count: raw.count)
        for (position, index) in order.enumerated() {
            rank[index] = raw.count > 1 ? Double(position) / Double(raw.count - 1) : 0
        }
        for i in concerns.indices {
            concerns[i].axisScores = scaled[i]
            concerns[i].axisAffinity = rank[i]
        }
    }

    /// Scores one item against `axes` using the scale learned by the last `rescore`.
    static func scoreSingle(_ item: Item, axes: [Axis], neighbors: [[Double]] = []) {
        guard item.kind == .concern else {
            item.axisScores = []
            item.axisAffinity = 0
            return
        }
        let e = ensureEmbedding(item)
        let scores = sortedAxes(axes).map { neg, pos in
            clamp(rawScore(e, negative: neg, positive: pos) * (scaleCache[axisKey(neg, pos)] ?? defaultScale))
        }
        item.axisScores = scores
        let sims = neighbors.map { EmbeddingService.cosine(e, $0) }.sorted(by: >).prefix(3)
        let dens = sims.isEmpty ? 0 : max(0, sims.reduce(0, +) / Double(sims.count))
        item.axisAffinity = affinity(scores: scores, density: dens)
    }

    /// Affinity = how much an item "belongs" to this person:
    /// 60% how far it sits from the middle of their axes (mean |score|),
    /// 40% how close it is to their dense region (mean cosine to its 3 nearest kept concerns).
    /// With no axes yet, density alone.
    private static func affinity(scores: [Double], density: Double) -> Double {
        let d = min(1, max(0, density))
        guard !scores.isEmpty else { return d }
        let onAxes = scores.map(abs).reduce(0, +) / Double(scores.count)
        return min(1, max(0, 0.6 * onAxes + 0.4 * d))
    }

    private static func density(of i: Int, embeddings: [[Double]], reference: [Int]) -> Double {
        let sims = reference.filter { $0 != i }
            .map { EmbeddingService.cosine(embeddings[i], embeddings[$0]) }
            .sorted(by: >).prefix(3)
        guard !sims.isEmpty else { return 0 }
        return max(0, sims.reduce(0, +) / Double(sims.count))
    }

    static func suggestCandidates(from items: [Item], existing: [Axis]) async -> [AxisCandidate] {
        // Most recent concerns first; cap work for small model context and O(n^3) clustering.
        let concerns = items
            .filter { $0.kind == .concern && $0.state != .released }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(120)
        guard concerns.count >= 3 else { return [] }
        let texts = concerns.map(\.text)
        let embeddings = concerns.map(ensureEmbedding)
        let existingKeys = Set(existing.map { pairKey($0.negativePole, $0.positivePole) })

        var result: [AxisCandidate] = []

        // 本人のメモの主成分から（最大2つ）。名前が付けられなければ組み込みの軸に寄せる。
        var excludedForPCA = Set(existing.map { $0.negativePole + "|" + $0.positivePole })
        for a in existing { excludedForPCA.insert(a.negativePole); excludedForPCA.insert(a.positivePole) }
        for c in await PersonalPCA.candidates(from: items, excluded: excludedForPCA, limit: 2)
        where !existingKeys.contains(pairKey(c.negativePole, c.positivePole)) {
            result.append(c)
        }

        // PCC が使えれば PCC（多くのメモを一度に見られる）、だめなら iPhone 内のモデル
        let backend = CloudAI.batchBackend
        // iPhone 内の小さなモデルは、メモの言葉をそのまま使ったり気分の軸（疲れ↔元気）を出したりしがち。
        // 軸の候補をモデルに作らせるのは PCC のときだけにし、それ以外は組み込みの軸から選ぶ。
        if result.count < 3 && AtohaAI.prefersModel && backend.isAvailable && CloudAI.isCloud(backend) {
            let avoid = existing.map { axisKey($0.negativePole, $0.positivePole) }
            let proposals = await backend.proposeAxes(from: Array(texts.prefix(backend.batchLimit)), avoid: avoid, limit: 3)
            CloudAI.recordUse(of: backend)
            for p in proposals where !existingKeys.contains(pairKey(p.negative, p.positive)) {
                learn(p.negative, p.negativeWords)
                learn(p.positive, p.positiveWords)
                let raws = embeddings.map { rawScore($0, negative: p.negative, positive: p.positive) }
                // Keep a model axis only if it actually separates some of this person's concerns.
                let samples = sampleTexts(texts: Array(texts), raws: raws, allowWeak: false)
                guard samples.low.count + samples.high.count >= 2 else { continue }
                let poles = Set(result.flatMap { [$0.negativePole, $0.positivePole] })
                guard !poles.contains(p.negative), !poles.contains(p.positive) else { continue }
                result.append(AxisCandidate(id: UUID(), negativePole: p.negative, positivePole: p.positive,
                                            lowSamples: samples.low, highSamples: samples.high))
                if result.count == 3 { return result }
            }
        }

        // Fallback / fill-up: rank built-in constructs by how well they separate this person's concerns.
        let clusters = cluster(embeddings, threshold: 0.35)
        var ranked: [(PoleConstruct, Double, (low: [String], high: [String]))] = []
        let taken = existingKeys.union(result.map { pairKey($0.negativePole, $0.positivePole) })
        let takenPoles = Set(result.flatMap { [$0.negativePole, $0.positivePole] })
        for c in constructs where !taken.contains(pairKey(c.negative, c.positive))
            && !takenPoles.contains(c.negative) && !takenPoles.contains(c.positive) {
            let raws = embeddings.map { rawScore($0, negative: c.negative, positive: c.positive) }
            let samples = sampleTexts(texts: Array(texts), raws: raws, allowWeak: false)
            guard samples.low.count + samples.high.count >= 2 else { continue }
            ranked.append((c, separation(raws, clusters: clusters), samples))
        }
        ranked.sort { $0.1 > $1.1 }
        for (c, _, samples) in ranked.prefix(max(0, 3 - result.count)) {
            result.append(AxisCandidate(id: UUID(), negativePole: c.negative, positivePole: c.positive,
                                        lowSamples: samples.low, highSamples: samples.high))
        }
        return result
    }

    // MARK: Candidate helpers

    private static func pairKey(_ a: String, _ b: String) -> String {
        let s = [a.trimmingCharacters(in: .whitespaces), b.trimmingCharacters(in: .whitespaces)].sorted()
        return s[0] + "|" + s[1]
    }

    /// Up to 2 texts from each pole's extreme. Items with ~no signal are skipped unless `allowWeak`.
    private static func sampleTexts(texts: [String], raws: [Double], allowWeak: Bool) -> (low: [String], high: [String]) {
        let minSignal = allowWeak ? 0 : 0.03
        let order = raws.indices.sorted { raws[$0] < raws[$1] }
        let low = order.prefix(2).filter { raws[$0] < -minSignal }
        let high = order.reversed().prefix(2).filter { raws[$0] > minSignal && !low.contains($0) }
        var seen = Set<String>()
        let pick = { (ids: [Int]) in ids.map { texts[$0] }.filter { seen.insert($0).inserted } }
        return (pick(low), pick(high))
    }

    /// Item-level spread plus between-cluster spread of raw scores.
    private static func separation(_ raws: [Double], clusters: [[Int]]) -> Double {
        func std(_ xs: [Double]) -> Double {
            guard xs.count > 1 else { return 0 }
            let m = xs.reduce(0, +) / Double(xs.count)
            return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)).squareRoot()
        }
        let itemSpread = std(raws)
        let means = clusters.map { idx in idx.map { raws[$0] }.reduce(0, +) / Double(idx.count) }
        return itemSpread + (clusters.count > 1 ? std(means) : 0)
    }

    /// Threshold agglomerative clustering (centroid linkage). Returns index groups.
    static func cluster(_ vectors: [[Double]], threshold: Double) -> [[Int]] {
        var groups: [[Int]] = vectors.indices.map { [$0] }
        var centroids: [[Double]] = vectors
        while groups.count > 1 {
            var best = (i: -1, j: -1, sim: threshold)
            for i in 0..<groups.count {
                for j in (i + 1)..<groups.count {
                    let s = EmbeddingService.cosine(centroids[i], centroids[j])
                    if s > best.sim { best = (i, j, s) }
                }
            }
            guard best.i >= 0 else { break }
            groups[best.i] += groups[best.j]
            groups.remove(at: best.j)
            centroids.remove(at: best.j)
            centroids[best.i] = EmbeddingService.centroid(groups[best.i].map { vectors[$0] })
        }
        return groups
    }
}
