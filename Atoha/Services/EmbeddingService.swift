import Foundation
import NaturalLanguage

/// 文章 → ベクトル。オフライン・決定的・L2正規化済み。
///
/// - Japanese sentence embedding (`NLEmbedding.sentenceEmbedding(for: .japanese)`) is used
///   when the OS ships one (it usually does not for Japanese; the simulator never does).
///   When present, its vector is concatenated with the hashed n-gram vector so that literal
///   keyword overlap still counts.
/// - Otherwise: hashed character unigram + bigram vector (dim 256, signed feature hashing,
///   FNV-1a so it is stable across launches — Swift's `Hasher` is randomly seeded).
///
/// Vector length is constant per device, but can differ between devices / OS versions.
/// `cosine` returns 0 for mismatched lengths; `AxisEngine` re-embeds such items.
enum EmbeddingService {
    static let hashedDimension = 256

    /// Lazily loaded; `nil` when the OS has no Japanese sentence embedding.
    private static let sentenceModel: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .japanese)

    /// Length of vectors `embed` currently produces on this device.
    static var dimension: Int {
        hashedDimension + (sentenceModel?.dimension ?? 0)
    }

    static func embed(_ text: String) -> [Double] {
        let normalized = normalize(text)
        let hashed = hashedVector(normalized)
        guard let model = sentenceModel, !normalized.isEmpty,
              let semantic = model.vector(for: normalized), !semantic.isEmpty else {
            if let model = sentenceModel {
                // Keep the length stable even if the model fails on this string.
                return l2(hashed + [Double](repeating: 0, count: model.dimension))
            }
            return hashed
        }
        // Weighted concatenation: semantic part dominates, n-grams keep literal overlap.
        let s = l2(semantic).map { $0 * 0.8 }
        let h = hashed.map { $0 * 0.6 }
        return l2(h + s)
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    // MARK: - Internals

    /// Lowercase, full-width ASCII → half-width (digits/letters only), drop whitespace & punctuation.
    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            var s = scalar
            // Full-width ASCII block (！..～) → ASCII. Leaves kana untouched.
            if (0xFF01...0xFF5E).contains(s.value), let h = Unicode.Scalar(s.value - 0xFEE0) {
                s = h
            }
            if CharacterSet.whitespacesAndNewlines.contains(s) { continue }
            if CharacterSet.punctuationCharacters.contains(s) || CharacterSet.symbols.contains(s) { continue }
            out.append(s)
        }
        return String(out)
    }

    private static func hashedVector(_ text: String) -> [Double] {
        var v = [Double](repeating: 0, count: hashedDimension)
        let chars = Array(text)
        guard !chars.isEmpty else { return v }
        func add(_ feature: String, weight: Double) {
            let h = fnv1a(feature)
            let index = Int(h % UInt64(hashedDimension))
            let sign: Double = (h >> 63) == 0 ? 1 : -1
            v[index] += sign * weight
        }
        for c in chars { add("u" + String(c), weight: 0.5) }
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) { add("b" + String(chars[i]) + String(chars[i + 1]), weight: 1.0) }
        }
        return l2(v)
    }

    private static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        // Final avalanche so the top bit (sign) is well mixed.
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        return hash
    }

    static func l2(_ v: [Double]) -> [Double] {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard n > 0 else { return v }
        return v.map { $0 / n }
    }

    /// Normalized mean of vectors (empty → []).
    static func centroid(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var sum = [Double](repeating: 0, count: first.count)
        for v in vectors where v.count == first.count {
            for i in 0..<v.count { sum[i] += v[i] }
        }
        return l2(sum)
    }
}
