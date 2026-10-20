import Foundation

/// モデルが使えないとき、主成分の両端のメモに合う組み込みの軸を選ぶ。
/// 両端のメモが実際にその軸の向きに寄っているかを1つずつ確かめ、合っているメモだけを見本にする。
enum PoleNamer {
    struct Match {
        /// 低い側＝negative になるよう向きをそろえた軸
        let construct: PoleConstruct
        let lowSamples: [String]
        let highSamples: [String]
        let score: Double
    }

    /// `pool`：寄り方を比べる基準にする本人のメモ全体。`embed`：意味ベクトル（使えなければ nil）。
    static func best(low: [String], high: [String], pool: [String], constructs: [PoleConstruct],
                     excluded: Set<String>, embed: (String) async -> [Double]?) async -> Match? {
        guard !low.isEmpty, !high.isEmpty else { return nil }
        let texts = Array(Set(pool + low + high))
        var noteVecs: [String: [Double]] = [:]
        for t in texts { if let v = await embed(t) { noteVecs[t] = v } }

        var best: Match?
        for c in constructs {
            if excluded.contains(c.negative) || excluded.contains(c.positive)
                || excluded.contains(c.negative + "|" + c.positive) || excluded.contains(c.positive + "|" + c.negative) { continue }
            let leans = await leanings(texts: texts, construct: c, noteVecs: noteVecs, embed: embed)
            for sign in [1.0, -1.0] {
                // sign をかけた値が正なら「高い側の極」寄り
                let lowLean = low.map { -sign * (leans[$0] ?? 0) }   // 正なら低い側の極寄り
                let highLean = high.map { sign * (leans[$0] ?? 0) }
                let gap = mean(highLean) + mean(lowLean)
                // どちらかの側で、はっきり寄っているメモが2つ以上
                let lowStrong = lowLean.filter { $0 > strongLean }.count
                let highStrong = highLean.filter { $0 > strongLean }.count
                guard gap >= minGap, max(lowStrong, highStrong) >= 2 else { continue }
                // もう一方の側に、逆の極へはっきり寄ったメモがあれば合わない
                guard !lowLean.contains(where: { $0 < -strongLean }), !highLean.contains(where: { $0 < -strongLean }) else { continue }
                let score = gap * Double(lowStrong + highStrong + 1)
                if score > (best?.score ?? 0) {
                    let oriented = sign > 0 ? c : PoleConstruct(negative: c.positive, positive: c.negative,
                                                               negativeWords: c.positiveWords, positiveWords: c.negativeWords)
                    best = Match(construct: oriented, lowSamples: samples(low, lowLean), highSamples: samples(high, highLean), score: score)
                }
            }
        }
        return best
    }

    private static let strongLean = 0.5
    private static let minGap = 0.8

    /// その極に寄っている順に2つ。弱い側は寄りが0以下でも、相対的に寄っている順に出す。
    private static func samples(_ texts: [String], _ lean: [Double]) -> [String] {
        zip(texts, lean).sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
    }

    /// 各メモの「positive 寄り」の度合い。言葉がそのまま入っていれば強く、意味の近さは本人のメモ全体の中での偏差で足す。
    static func leanings(texts: [String], construct c: PoleConstruct, noteVecs: [String: [Double]],
                         embed: (String) async -> [Double]?) async -> [String: Double] {
        var negVecs: [[Double]] = [], posVecs: [[Double]] = []
        for w in [c.negative] + c.negativeWords { if let v = await embed(w) { negVecs.append(v) } }
        for w in [c.positive] + c.positiveWords { if let v = await embed(w) { posVecs.append(v) } }

        func maxCos(_ v: [Double], _ ws: [[Double]]) -> Double {
            ws.map { w in zip(v, w).reduce(0) { $0 + $1.0 * $1.1 } }.max() ?? 0
        }
        var semantic: [String: Double] = [:]
        if !negVecs.isEmpty, !posVecs.isEmpty {
            for (t, v) in noteVecs { semantic[t] = maxCos(v, posVecs) - maxCos(v, negVecs) }
        }
        let vals = Array(semantic.values)
        let m = mean(vals)
        let sd = max((vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(max(vals.count, 1))).squareRoot(), 1e-6)

        var out: [String: Double] = [:]
        for t in texts {
            let pos = ([c.positive] + c.positiveWords).filter { t.contains($0) }.count
            let neg = ([c.negative] + c.negativeWords).filter { t.contains($0) }.count
            let keyword = Double(max(-1, min(1, pos - neg)))
            let z = semantic[t].map { ($0 - m) / sd } ?? 0
            out[t] = keyword + 0.35 * z
        }
        return out
    }

    private static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
}
