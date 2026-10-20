import Foundation
import FoundationModels

struct Classification {
    var kind: ItemKind
    var deadline: Date?
    var theme: String?
}

enum AtohaAI {
    /// The language backend in use. Swap here to plug in another model later.
    static let backend: LanguageBackend = OnDeviceBackend()

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Set false to force the heuristic path (debug / comparison). Main-thread use only.
    nonisolated(unsafe) static var prefersModel = true

    static var usesModel: Bool { prefersModel && isModelAvailable }

    /// Kind + theme from the model when available, otherwise keyword heuristics.
    /// Deadline is always parsed deterministically (the small model is unreliable with dates).
    static func classify(_ text: String, now: Date = .now) async -> Classification {
        let deadline = Heuristics.parseDeadline(text, now: now)
        if usesModel, let r = await backend.classify(text) {
            // モデルは意味を、ルールははっきりした言い回し（〜返す、〜たい、？）を拾う。
            // 食い違ったときは、ルールの差が2票以上ならルールを優先する。
            let v = Heuristics.votes(for: text, hasDeadline: deadline != nil)
            var kind = r.kind
            if kind == .concern && v.errand - v.concern >= 2 { kind = .errand }
            if kind == .errand && v.concern - v.errand >= 2 { kind = .concern }
            return Classification(kind: kind, deadline: deadline,
                                  theme: r.theme ?? Heuristics.theme(for: text))
        }
        return Classification(kind: Heuristics.kind(for: text, hasDeadline: deadline != nil),
                              deadline: deadline,
                              theme: Heuristics.theme(for: text))
    }
}

// MARK: - Non-AI fallback

enum Heuristics {
    static let errandWords: [String] = [
        "買う", "買い", "かう", "出す", "提出", "予約", "連絡", "返信", "払う", "支払", "振込", "振り込",
        "持って", "持ってく", "送る", "送信", "申し込", "申込", "締切", "締め切", "〆切", "電話", "取りに",
        "返す", "返却", "受け取", "届け", "更新", "解約", "登録", "手続", "印刷", "洗濯", "掃除", "ゴミ",
        "ごみ", "メール", "LINE", "ライン", "確認", "準備", "片付け", "行く", "病院", "銀行", "郵便",
        "スーパー", "コンビニ", "シフト", "課題", "レポート", "提出物",
        "申請", "発送", "集める", "まとめる", "もらう", "もらって", "チャージ", "コピー", "回す", "頼む",
        "お願い", "入力", "再発行", "延長", "取ってくる", "かける", "干す", "取り込む", "揃える", "そろえる",
        "資料", "書類", "荷物", "お礼", "返事", "出欠", "会計", "部費", "入れる", "借りた", "詰め替え", "つめかえ", "交換", "補充",
    ]
    static let concernWords: [String] = [
        "?", "？", "かも", "どう", "したい", "やりたい", "アイデア", "案", "将来", "考え", "不安", "気になる",
        "なぜ", "なんで", "だろう", "かな", "悩", "迷", "いつか", "企画", "試し", "挑戦", "面白", "おもしろ",
        "興味", "もし", "べき", "向いて", "好き", "嫌", "やめ", "モヤ", "もや", "夢", "目標", "人生", "進路",
        "どうして", "なんか", "こだわり", "憧れ", "あこがれ", "ほうがいい", "方がいい", "自分", "私", "人間関係",
        "やる気", "モヤモヤ", "どこ", "どれ", "安心",
    ]

    /// Sentence-final / predicate forms that mark a wish, worry, feeling or question → 気になること.
    private static let concernEndings: [String] = [
        "たい", "たいな", "たいなあ", "たいです", "たいね", "ほしい", "欲しい", "かな", "かなあ", "かも", "かもしれない",
        "だろう", "だろうか", "のか", "べきか", "どうしよう", "どうする", "なんだろう", "かしら", "だなあ",
        "苦手", "億劫", "しんどい", "つらい", "辛い", "寂しい", "さみしい", "虚しい", "むなしい", "怖い", "きつい",
        "だるい", "嫌だ", "いやだ", "憂鬱", "不安", "心配", "気がする", "てしまう", "ちゃう", "すぎる", "過ぎる",
        "思う", "思った", "ようになりたい", "てみたい", "たいけど", "あこがれる", "憧れる",
        "てみようかな", "できたら", "いいな", "いいなあ", "うらやましい", "虚しさ", "安心する", "出ない", "やる気",
    ]

    /// Obligation / memo-to-self forms → 用事.
    private static let errandEndings: [String] = [
        "なきゃ", "ないと", "なくちゃ", "なければ", "しとく", "とく", "ておく", "しておく", "しよう", "忘れずに",
        "お願いする", "頼む", "してくる", "てくる", "忘れない",
    ]

    /// Honorific / role words after which 「に」 + verb reads as an errand ("田中さんに連絡").
    private static let personPattern = try! NSRegularExpression(
        pattern: "(さん|くん|君|ちゃん|先生|先輩|教授|後輩|店長|部長|母|父|兄|姉|友達)(に|へ)")

    /// errand vs concern by keyword votes plus sentence-final form.
    /// No signal: noun-only / very short notes ("牛乳", "トイレットペーパー") read as errands
    /// (shopping-list style), longer ones as concerns.
    static func kind(for rawText: String, hasDeadline: Bool) -> ItemKind {
        let v = votes(for: rawText, hasDeadline: hasDeadline)
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "…。、！!〜~ー")))
        let errand = v.errand, concern = v.concern
        if errand > concern { return .errand }
        if concern > errand { return .concern }

        let compact = text.filter { !$0.isWhitespace }
        if errand == 0 {
            // Bare noun phrase (no kana-only predicate at the end): shopping-list style.
            if isNounPhrase(trimmed), compact.count <= 16 { return .errand }
            return compact.count <= 8 ? .errand : .concern
        }
        return hasDeadline ? .errand : .concern
    }

    /// 用事と気になることの票数。モデルの答えと食い違ったとき、差が大きければこちらを優先する。
    static func votes(for rawText: String, hasDeadline: Bool) -> (errand: Int, concern: Int) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "…。、！!〜~ー")))
        var errand = errandWords.reduce(0) { text.contains($1) ? $0 + 1 : $0 }
        var concern = concernWords.reduce(0) { text.contains($1) ? $0 + 1 : $0 }

        // Strong concern: wish / worry / question / feeling at the end of the note.
        let isQuestion = text.contains("?") || text.contains("？") || trimmed.hasSuffix("のか") || trimmed.hasSuffix("かな")
            || trimmed.hasSuffix("かなあ") || trimmed.hasSuffix("だろう") || trimmed.hasSuffix("だろうか")
            || trimmed.hasSuffix("どうしよう") || trimmed.hasSuffix("かも")
        let hasQuestionWord = ["どこ", "どれ", "どっち", "どの", "何を", "何が", "なにを"].contains { text.contains($0) }
        if isQuestion || hasQuestionWord { concern += 4 }
        if concernEndings.contains(where: { trimmed.hasSuffix($0) }) { concern += 3 }
        if trimmed.contains("たいけど") || trimmed.contains("たいな") { concern += 2 }
        if trimmed.hasSuffix("てみよう") && !trimmed.hasSuffix("しよう") { concern += 2 }

        // Strong errand: obligation / memo forms. Not when it is a wish or question.
        if concern < 3, errandEndings.contains(where: { trimmed.hasSuffix($0) }) { errand += 3 }
        if trimmed.hasSuffix("なきゃ") || trimmed.hasSuffix("ないと") || trimmed.hasSuffix("なくちゃ") { errand += 2 }
        // Person + に + verb ("田中さんに連絡", "佐藤さんに資料送る").
        if personPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil,
           errand > 0 { errand += 1 }
        if hasDeadline { errand += 1 }
        return (errand, concern)
    }

    /// True when the note has no predicate: ends in kanji / katakana / digits / latin
    /// (e.g. "トイレットペーパー", "学食カードのチャージ", "プリンターのインク").
    private static func isNounPhrase(_ s: String) -> Bool {
        guard let last = s.unicodeScalars.last else { return false }
        let v = last.value
        let isKana = (0x3041...0x309F).contains(v)
        return !isKana
    }

    /// Small built-in theme vocabulary; nil when nothing matches.
    private static let themes: [(String, [String])] = [
        ("買い物", ["買う", "買い", "牛乳", "スーパー", "コンビニ", "卵", "パン", "洗剤", "ティッシュ", "Amazon"]),
        ("連絡", ["電話", "連絡", "返信", "メール", "LINE", "ライン"]),
        ("手続き", ["提出", "申し込", "申込", "振込", "振り込", "払う", "支払", "予約", "更新", "解約", "登録", "手続"]),
        ("バイト", ["シフト", "バイト", "店長"]),
        ("学校", ["授業", "レポート", "課題", "試験", "テスト", "ゼミ", "履修"]),
        ("サークル", ["サークル", "新入生", "部活", "合宿"]),
        ("将来", ["将来", "進路", "就活", "キャリア", "インターン", "人生"]),
        ("アイデア", ["企画", "アイデア", "ゲーム", "作り", "作る"]),
        ("家", ["掃除", "洗濯", "ゴミ", "ごみ", "片付け", "部屋"]),
        ("体", ["病院", "歯医者", "運動", "睡眠", "ジム"]),
        ("気持ち", ["不安", "悩", "モヤ", "もや", "疲れ"]),
    ]

    static func theme(for text: String) -> String? {
        var best: (String, Int)? = nil
        for (label, words) in themes {
            let hits = words.reduce(0) { text.contains($1) ? $0 + 1 : $0 }
            if hits > 0, hits > (best?.1 ?? 0) { best = (label, hits) }
        }
        return best?.0
    }

    // MARK: Deadline

    /// Parses 今日/今夜/明日/明後日/N日後/N週間後/来週(X曜)/再来週/今週末/今週中/週明け/月末/来月N日/N月N日/N/N/N日/
    /// (午前・午後)N時(半)/N:MM/朝・昼・夕方・夜 relative to `now`.
    /// Date without time → 9:00 (今日・今夜 → 21:00; 朝 8:00, 昼 12:00, 夕方 17:00, 夜 21:00).
    /// Time without date → today, or tomorrow if already past.
    static func parseDeadline(_ raw: String, now: Date, calendar: Calendar = .current) -> Date? {
        let text = halfwidthDigits(raw)
        let today = calendar.startOfDay(for: now)
        var day: Date? = nil
        var defaultHour = 9

        func match(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<m.numberOfRanges).map { i in
                guard let r = Range(m.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
        }
        func addDays(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: today) }
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        /// Sunday of the week (Mon-start) that is `weeks` weeks from this one.
        func sunday(weeksAhead weeks: Int) -> Date? {
            let current = calendar.component(.weekday, from: today)
            let toSunday = (8 - current) % 7           // Sun → 0, Mon → 6, Tue → 5 …
            return addDays(toSunday + 7 * weeks)
        }

        if let g = match(#"(\d{1,2})月(\d{1,2})日"#) ?? match(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"#),
           let mo = Int(g[1]), let d = Int(g[2]), (1...12).contains(mo), (1...31).contains(d) {
            // Explicit month/day first.
            var c = calendar.dateComponents([.year], from: now)
            c.month = mo; c.day = d
            if let date = calendar.date(from: c) {
                day = date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
            }
        } else if let g = match(#"来月(\d{1,2})日"#), let d = Int(g[1]), (1...31).contains(d) {
            var c = calendar.dateComponents([.year, .month], from: now)
            c.month = (c.month ?? 1) + 1; c.day = d
            day = calendar.date(from: c)
        } else if let g = match(#"(\d{1,3})日後"#), let n = Int(g[1]) {
            day = addDays(n)
        } else if let g = match(#"(\d{1,2})週間後"#), let n = Int(g[1]) {
            day = addDays(7 * n)
        } else if let g = match(#"(\d{1,2})(か|ヶ|ケ|カ)?月後"#), let n = Int(g[1]) {
            day = calendar.date(byAdding: .month, value: n, to: today)
        } else if text.contains("明後日") || text.contains("あさって") {
            day = addDays(2)
        } else if text.contains("明日") || text.contains("あした") || text.contains("あす") {
            day = addDays(1)
        } else if text.contains("今夜") || text.contains("今晩") {
            day = today; defaultHour = 21
        } else if text.contains("今日") || text.contains("きょう") {
            day = today; defaultHour = 21
        } else if has("再来週") {
            day = nextWeekday(in: text, after: now, calendar: calendar, weeksAhead: 2) ?? addDays(14)
        } else if has("来週中", "来週いっぱい") {
            day = sunday(weeksAhead: 1)
        } else if has("来週") {
            day = nextWeekday(in: text, after: now, calendar: calendar, weeksAhead: 1) ?? addDays(7)
        } else if has("週明け") {
            day = nextWeekday(in: "月曜", after: now, calendar: calendar, weeksAhead: nil)
        } else if has("今週中", "今週いっぱい") {
            day = sunday(weeksAhead: 0)
        } else if has("週末", "今週末") {
            let current = calendar.component(.weekday, from: today)
            day = current == 7 || current == 1 ? today : nextWeekday(in: "土曜", after: now, calendar: calendar, weeksAhead: nil)
        } else if has("今週"), let wd = nextWeekday(in: text, after: now, calendar: calendar, weeksAhead: 0) {
            day = wd
        } else if let wd = nextWeekday(in: text, after: now, calendar: calendar, weeksAhead: nil) {
            day = wd
        } else if has("月末") {
            // "月末" = this month's last day; "11月末" = that month's (next year if already past).
            var c = calendar.dateComponents([.year, .month], from: now)
            if let g = match(#"(\d{1,2})月末"#), let mo = Int(g[1]), (1...12).contains(mo) {
                c.month = mo
                if mo < (calendar.component(.month, from: now)) { c.year = (c.year ?? 0) + 1 }
            }
            c.day = 1
            if let first = calendar.date(from: c), let range = calendar.range(of: .day, in: .month, for: first) {
                c.day = range.count
                day = calendar.date(from: c)
            }
        } else if let g = match(#"(?<![\d月/週])(\d{1,2})日(?!間|後|\d|に\d)"#), let d = Int(g[1]), (1...31).contains(d) {
            var c = calendar.dateComponents([.year, .month], from: now)
            c.day = d
            if let date = calendar.date(from: c) {
                day = date < today ? calendar.date(byAdding: .month, value: 1, to: date) : date
            }
        }

        // Time of day.
        var hour: Int? = nil
        var minute = 0
        if let g = match(#"(\d{1,2})[:：](\d{2})"#), let h = Int(g[1]), let m = Int(g[2]), h < 24, m < 60 {
            hour = h; minute = m
        } else if let g = match(#"(\d{1,2})時(半|(\d{1,2})分)?(?!間)"#), let h = Int(g[1]), h <= 24 {
            hour = h % 24
            if g[2] == "半" { minute = 30 } else if let m = Int(g[3]), m < 60 { minute = m }
        }
        if var h = hour, h < 12, text.contains("午後") || text.contains("夜") || text.contains("夕方") {
            h += 12; hour = h
        }
        // Part of the day without a clock time ("明日の朝", "明後日の夜").
        if hour == nil, day != nil {
            if has("朝") { defaultHour = 8 }
            else if has("昼") { defaultHour = 12 }
            else if has("夕方") { defaultHour = 17 }
            else if has("夜", "晩") { defaultHour = 21 }
        }

        if let h = hour {
            let base = day ?? today
            guard var date = calendar.date(bySettingHour: h, minute: minute, second: 0, of: base) else { return nil }
            if day == nil, date < now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return date
        }
        guard let d = day else { return nil }
        return calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: d)
    }

    /// "月曜" / "金曜日" etc. `weeksAhead` nil → next such day strictly after today;
    /// 0/1/2 → that weekday in this / next / the week after next (weeks start on Monday).
    private static func nextWeekday(in text: String, after now: Date, calendar: Calendar, weeksAhead: Int?) -> Date? {
        let names = ["日曜": 1, "月曜": 2, "火曜": 3, "水曜": 4, "木曜": 5, "金曜": 6, "土曜": 7]
        guard let target = names.first(where: { text.contains($0.key) })?.value else { return nil }
        let today = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: today)
        var delta = (target - current + 7) % 7
        if delta == 0 { delta = 7 }
        if let weeks = weeksAhead {
            let mondayOffset = (current + 5) % 7          // days since Monday
            let thisMonday = -mondayOffset
            let targetFromMonday = (target + 5) % 7
            delta = thisMonday + 7 * weeks + targetFromMonday
        }
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    private static func halfwidthDigits(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u -> Unicode.Scalar in
            switch u.value {
            case 0xFF10...0xFF19, 0xFF0F, 0xFF1A: return Unicode.Scalar(u.value - 0xFEE0) ?? u
            default: return u
            }
        }))
    }
}
