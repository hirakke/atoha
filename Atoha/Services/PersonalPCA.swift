import Foundation

/// 本人のメモの意味ベクトルを主成分分析して、「この人の関心がいちばんばらつく方向」を軸の候補にする。
/// 重みは「やりたい」と集中した時間が大きいメモほど重く。両端のメモをモデルに見せて、2つの極に名前を付ける。
@MainActor
enum PersonalPCA {
    struct Component {
        /// 全体のばらつきのうち、この成分が占める割合（0...1）
        var explainedVariance: Double
        /// 低い側（負）の端のメモ
        var lowTexts: [String]
        /// 高い側（正）の端のメモ
        var highTexts: [String]
        /// 成分の向き（単位ベクトル。`semantic` が false ならハッシュ埋め込みの空間）
        var direction: [Double]
        var semantic: Bool
    }

    static let minimumItems = 8
    static let maximumItems = 150

    // MARK: PCA

    static func components(from items: [Item]) async -> [Component] {
        var seen = Set<String>()
        let pool = items
            .filter { $0.state != .released && ($0.kind == .concern || $0.isRated) }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.text).inserted }
            .prefix(maximumItems)
        guard pool.count >= minimumItems else { return [] }
        let texts = pool.map(\.text)
        let weights = pool.map { 0.5 + $0.effectiveWant + min($0.focusSeconds / 3600, 1) * 0.5 }

        // 意味ベクトル。1つでも作れなければ全部ハッシュにそろえる（空間を混ぜない）
        var vectors: [[Double]] = []
        for t in texts {
            guard let v = await EmbeddingService.semanticEmbed(t) else { vectors = []; break }
            vectors.append(v)
        }
        let semantic = vectors.count == texts.count
        if !semantic { vectors = texts.map(EmbeddingService.embed) }

        return pca(vectors: vectors, weights: weights, texts: texts, count: 3).map {
            var c = $0; c.semantic = semantic; return c
        }
    }

    /// 重みつき PCA（べき乗法＋逐次的な除去）。
    nonisolated static func pca(vectors: [[Double]], weights: [Double], texts: [String], count: Int) -> [Component] {
        let n = vectors.count
        guard n >= 2, let d = vectors.first?.count, d > 0, weights.count == n else { return [] }
        let wSum = weights.reduce(0, +)
        guard wSum > 0 else { return [] }

        // 重みつき平均を引く
        var mean = [Double](repeating: 0, count: d)
        for i in 0..<n { for k in 0..<d { mean[k] += weights[i] * vectors[i][k] } }
        for k in 0..<d { mean[k] /= wSum }
        var x = vectors.map { v in (0..<d).map { v[$0] - mean[$0] } }

        let total = (0..<n).reduce(0.0) { acc, i in acc + weights[i] * x[i].reduce(0) { $0 + $1 * $1 } } / wSum
        guard total > 1e-12 else { return [] }

        var out: [Component] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<count {
            // 決まった乱数で初期化
            var v = (0..<d).map { _ -> Double in
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(Int64(bitPattern: seed >> 11) % 2001) / 1000 - 1
            }
            var eigen = 0.0
            for _ in 0..<80 {
                let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
                guard norm > 1e-12 else { break }
                v = v.map { $0 / norm }
                // w = Cov · v = Σ wᵢ xᵢ (xᵢ·v) / Σw
                var next = [Double](repeating: 0, count: d)
                for i in 0..<n {
                    var dot = 0.0
                    for k in 0..<d { dot += x[i][k] * v[k] }
                    let s = weights[i] * dot
                    for k in 0..<d { next[k] += s * x[i][k] }
                }
                next = next.map { $0 / wSum }
                eigen = next.reduce(0) { $0 + $1 * $1 }.squareRoot()
                let delta = zip(next, v).reduce(0.0) { $0 + abs($1.0 / max(eigen, 1e-12) - $1.1) }
                v = next
                if delta < 1e-6 { break }
            }
            let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
            guard norm > 1e-12, eigen / total > 0.005 else { break }
            v = v.map { $0 / norm }

            let proj = x.map { row in zip(row, v).reduce(0.0) { $0 + $1.0 * $1.1 } }
            let order = proj.indices.sorted { proj[$0] < proj[$1] }
            out.append(Component(explainedVariance: eigen / total,
                                 lowTexts: order.prefix(3).map { texts[$0] },
                                 highTexts: order.suffix(3).reversed().map { texts[$0] },
                                 direction: v, semantic: true))
            // 除去：この方向の成分を引く
            for i in 0..<n { for k in 0..<d { x[i][k] -= proj[i] * v[k] } }
        }
        return out
    }

    // MARK: 候補

    /// `excluded`：すでにある軸（pairKey 形式ではなく「負極|正極」の組）。
    static func candidates(from items: [Item], excluded: Set<String>, limit: Int) async -> [AxisCandidate] {
        let comps = await components(from: items)
        guard !comps.isEmpty else { return [] }
        var backend = CloudAI.batchBackend
        if CloudAI.isCloud(backend) && !CloudAI.hasBudget { backend = AtohaAI.backend }
        let cloud = CloudAI.isCloud(backend)
        var result: [AxisCandidate] = []
        var usedPoles = Set<String>()

        for comp in comps {
            guard result.count < limit else { break }
            let samples = comp.lowTexts + comp.highTexts
            var named: (String, String)?

            if AtohaAI.prefersModel, backend.isAvailable,
               let r = await withTimeout(20, { await backend.namePoles(low: comp.lowTexts, high: comp.highTexts) }) {
                if cloud { CloudAI.recordUse(of: backend) }
                if valid(r.negative, r.positive, samples: samples, strict: !cloud) { named = (r.negative, r.positive) }
            }
            if named == nil, let c = await closestConstruct(to: comp, excluded: excluded.union(usedPoles)) {
                named = (c.negative, c.positive)
            }
            guard let (neg, pos) = named,
                  !excluded.contains(neg + "|" + pos), !excluded.contains(pos + "|" + neg),
                  !usedPoles.contains(neg), !usedPoles.contains(pos) else { continue }
            usedPoles.insert(neg); usedPoles.insert(pos)
            result.append(AxisCandidate(id: UUID(), negativePole: neg, positivePole: pos,
                                        lowSamples: Array(comp.lowTexts.prefix(2)),
                                        highSamples: Array(comp.highTexts.prefix(2)),
                                        explainedVariance: comp.explainedVariance))
        }
        return result
    }

    private static func valid(_ n: String, _ p: String, samples: [String], strict: Bool) -> Bool {
        guard !n.isEmpty, !p.isEmpty, n != p else { return false }
        guard strict else { return true }
        return !samples.contains { $0.contains(n) || $0.contains(p) }
    }

    /// 成分の方向に、いちばん沿っている組み込みの軸（極のベクトルの差を成分に射影）。
    private static func closestConstruct(to comp: Component, excluded: Set<String>) async -> PoleConstruct? {
        func pole(_ words: [String]) async -> [Double]? {
            var vs: [[Double]] = []
            for w in words {
                if comp.semantic {
                    guard let v = await EmbeddingService.semanticEmbed(w) else { return nil }
                    vs.append(v)
                } else {
                    vs.append(EmbeddingService.embed(w))
                }
            }
            let c = EmbeddingService.centroid(vs)
            return c.count == comp.direction.count ? c : nil
        }
        var best: (PoleConstruct, Double)?
        for c in AxisEngine.constructs {
            if excluded.contains(c.negative) || excluded.contains(c.positive)
                || excluded.contains(c.negative + "|" + c.positive) || excluded.contains(c.positive + "|" + c.negative) { continue }
            guard let n = await pole([c.negative] + c.negativeWords),
                  let p = await pole([c.positive] + c.positiveWords) else { continue }
            let s = zip(zip(p, n), comp.direction).reduce(0.0) { $0 + ($1.0.0 - $1.0.1) * $1.1 }
            if best == nil || abs(s) > abs(best!.1) { best = (c, s) }
        }
        guard let (c, s) = best else { return nil }
        // 向きが逆なら極を入れ替える（低い側＝負極）
        return s >= 0 ? c : PoleConstruct(negative: c.positive, positive: c.negative,
                                          negativeWords: c.positiveWords, positiveWords: c.negativeWords)
    }
}
