import Foundation

/// ChatGPT のプラン枠で動くまとめ処理（Sign in with ChatGPT）。1件ずつの振り分けは iPhone 内のモデルのまま。
struct ChatGPTBackend: LanguageBackend {
    var isAvailable: Bool { FeatureFlags.chatGPTEnabled && ChatGPTConsent.granted && ChatGPTStore.loadCredentials() != nil }
    var batchLimit: Int { 200 }

    func classify(_ text: String) async -> (kind: ItemKind, theme: String?)? { nil }

    func groupThemes(_ texts: [String], known: [String]) async -> [String]? {
        guard isAvailable, !texts.isEmpty else { return nil }
        let batch = Array(texts.prefix(batchLimit))
        let instructions = BatchPrompts.groupInstructions
            + "\nJSON だけを返す。説明は書かない。形式: {\"items\":[{\"index\":0,\"theme\":\"進路\"}]}"
        guard let json = await ask(instructions, BatchPrompts.groupPrompt(batch, known: known, maxChars: 60)),
              let items = json["items"] as? [[String: Any]] else { return nil }
        var names = [String?](repeating: nil, count: batch.count)
        for a in items {
            guard let i = a["index"] as? Int, names.indices.contains(i),
                  let t = (a["theme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            names[i] = String(t.prefix(10))
        }
        let filled = names.compactMap { $0 }
        return filled.count == batch.count ? filled : nil
    }

    func namePoles(low: [String], high: [String]) async -> (negative: String, positive: String)? {
        guard isAvailable else { return nil }
        let instructions = BatchPrompts.namePolesInstructions
            + "\nJSON だけを返す。説明は書かない。形式: {\"a\":\"一人で\",\"b\":\"人と\"}"
        guard let json = await ask(instructions, BatchPrompts.namePolesPrompt(low: low, high: high)),
              let a = json["a"] as? String, let b = json["b"] as? String else { return nil }
        let c = BatchPrompts.clean((a, b))
        return (c.0, c.1)
    }

    func proposeAxes(from texts: [String], avoid: [String], limit: Int) async -> [ProposedAxis] {
        guard isAvailable, !texts.isEmpty else { return [] }
        let list = texts.prefix(batchLimit).map { "・" + String($0.prefix(60)) }.joined(separator: "\n")
        var prompt = "メモ:\n\(list)\n"
        if !avoid.isEmpty { prompt += "除外: \(avoid.joined(separator: "、"))\n" }
        prompt += "対の軸を\(limit)つ。"
        let instructions = BatchPrompts.axesInstructions
            + "\nJSON だけを返す。説明は書かない。形式: {\"axes\":[{\"negative\":\"一人で\",\"positive\":\"人と\","
            + "\"negativeWords\":[\"単独\",\"集中\",\"静か\"],\"positiveWords\":[\"相談\",\"一緒\",\"会う\"]}]}"
        guard let json = await ask(instructions, prompt), let axes = json["axes"] as? [[String: Any]] else { return [] }
        func words(_ v: Any?) -> [String] {
            (v as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.map { String($0.prefix(10)) }
        }
        return axes.prefix(limit).compactMap { a in
            let n = (a["negative"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let p = (a["positive"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !p.isEmpty, n != p else { return nil }
            return ProposedAxis(negative: String(n.prefix(8)), positive: String(p.prefix(8)),
                                negativeWords: words(a["negativeWords"]), positiveWords: words(a["positiveWords"]))
        }
    }

    // MARK: 通信

    private func ask(_ instructions: String, _ input: String) async -> [String: Any]? {
        do {
            let raw = try await respond(instructions: instructions, input: input)
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("```json") { s.removeFirst(7) } else if s.hasPrefix("```") { s.removeFirst(3) }
            if s.hasSuffix("```") { s.removeLast(3) }
            if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a <= b { s = String(s[a...b]) }
            return try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
        } catch ChatGPTError.limitReached {
            ChatGPTStore.markReached()
            return nil
        } catch {
            return nil
        }
    }

    private func respond(instructions: String, input: String) async throws -> String {
        let token = try await ChatGPTAuth.shared.validAccessToken()
        let model = try await ChatGPTAuth.shared.currentModel(token: token)
        var req = URLRequest(url: URL(string: ChatGPTAuth.api + "/responses")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": instructions, "store": false, "stream": true,
            "input": [["role": "user", "content": input]],
        ] as [String: Any])

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            await ChatGPTAuth.shared.signOutQuietly()
            throw ChatGPTError.notSignedIn
        }
        var out = ""
        var errBody = ""
        for try await line in bytes.lines {
            if status >= 400 { errBody += line; continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let ev = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            switch ev["type"] as? String {
            case "response.output_text.delta": out += ev["delta"] as? String ?? ""
            case "response.failed":
                let err = (ev["response"] as? [String: Any])?["error"] as? [String: Any]
                try await Self.throwFor(code: err?["code"] as? String)
                throw ChatGPTError.failed(err?["message"] as? String ?? "failed")
            case "response.completed": return out
            default: break
            }
        }
        if status >= 400 {
            let code = (try? JSONSerialization.jsonObject(with: Data(errBody.utf8)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["code"] as? String ?? $0["error"] as? String }
            try await Self.throwFor(code: code)
            throw ChatGPTError.failed("HTTP \(status)")
        }
        throw ChatGPTError.failed("no completion")
    }

    private static func throwFor(code: String?) async throws {
        switch code {
        case "subscription_sharing_usage_limit_exceeded", "subscription_sharing_usage_unavailable":
            throw ChatGPTError.limitReached
        case "invalid_grant":
            await ChatGPTAuth.shared.signOutQuietly()
            throw ChatGPTError.notSignedIn
        default: break
        }
    }
}
