import Foundation
import SwiftData

/// 試すためのサンプル。過去1週間に預けたことにする。
@MainActor
enum SampleData {
    static let texts: [(String, ItemKind?)] = [
        ("牛乳", .errand), ("シフト提出 明日", .errand), ("母に電話 18時", .errand),
        ("レポート提出 金曜", .errand), ("図書館の本を返す", .errand), ("ゼミの資料印刷", .errand),
        ("新入生企画 ゲーム形式どう？", .concern), ("家庭教師の教え方を変えたい", .concern),
        ("後輩の相談にのる", .concern), ("将来なにしたいんだろう", .concern), ("一人旅に行きたい", .concern),
        ("写真展を作ってみたい", .concern), ("部屋を片付けたい", .concern), ("ノートの取り方を整えたい", .concern),
        ("サークルの引き継ぎ資料", .concern), ("カフェで作業する日を作る", .concern), ("友達とアプリを作りたい", .concern),
        ("留学どうしよう", .concern), ("毎朝の習慣を整える", .concern), ("ポスターのデザイン案", .concern)
    ]

    static func insert(into context: ModelContext, now: Date = .now) {
        let axes = (try? context.fetch(FetchDescriptor<Axis>(sortBy: [SortDescriptor(\.order)]))) ?? []
        var inserted: [Item] = []
        for (index, entry) in texts.enumerated() {
            let created = now.addingTimeInterval(-Double(index % 7) * 86_400 - Double(index) * 1_800)
            let item = Item(text: entry.0, timing: .atBreak, now: created)
            if let kind = entry.1 { item.kind = kind }
            // 半分は返す時が来ている状態にする（今に入りきらないものは「空いたら」に残る）
            if index.isMultiple(of: 2) { item.returnAt = created }
            if index % 3 != 1 {
                item.want = Double((index * 37) % 100) / 99
                item.must = Double((index * 61 + 17) % 100) / 99
            }
            // 使った時間（秒）。見え方を確かめるため、決まった値を入れる
            if index % 4 != 3 { item.focusSeconds = Double(600 + (index * 997) % 4801 / 60 * 60) }
            context.insert(item)
            inserted.append(item)
        }
        // 金魚鉢を確かめるため、この月と先月に持ち帰ったものも入れる
        let takenHome: [(String, Int, Double, Double)] = [
            ("洗濯物を取り込む", 1, 0.2, 0.9), ("美術館の企画展を見に行く", 3, 0.9, 0.3),
            ("履歴書の写真を撮る", 6, 0.3, 0.8), ("友達に誕生日のメッセージ", 9, 0.8, 0.7), ("自転車の空気を入れる", 34, 0.1, 0.6)
        ]
        for (text, daysAgo, want, must) in takenHome {
            let done = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            let item = Item(text: text, timing: .atBreak, now: done.addingTimeInterval(-86_400))
            item.want = want
            item.must = must
            item.state = .done
            item.resolvedAt = done
            context.insert(item)
        }
        try? context.save()
        ReturnService.acceptTop(2, in: context, now: now)
        Task { @MainActor in
            for item in inserted { await ItemProcessor.process(item, axes: axes) }
            AxisEngine.rescore(items: inserted, axes: axes)
            try? context.save()
        }
    }
}
