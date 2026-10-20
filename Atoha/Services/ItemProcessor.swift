import Foundation
import SwiftData

@MainActor
enum ItemProcessor {
    /// Called right after capture. Mutates `item` only; the caller saves the context.
    static func process(_ item: Item, axes: [Axis]) async {
        let text = item.text            // copy value out; never send Item across actors
        let created = item.createdAt
        if item.kind == .unsorted {
            let c = await AtohaAI.classify(text, now: created)
            item.kind = c.kind
            if item.deadline == nil { item.deadline = c.deadline }
            if item.theme == nil { item.theme = c.theme }
        } else if item.deadline == nil {
            item.deadline = Heuristics.parseDeadline(text, now: created)
        }
        item.embedding = EmbeddingService.embed(text)
        AxisEngine.scoreSingle(item, axes: axes)
    }
}
