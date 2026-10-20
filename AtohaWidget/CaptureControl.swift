import AppIntents
import SwiftUI
import WidgetKit

/// コントロールセンター／ロック画面のコントロール。押すと書き出し画面へ直行する。
struct CaptureControl: ControlWidget {
    static let kind = "app.atoha.prototype.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureIntent()) {
                Label("あとでに回す", systemImage: "plus.square")
            }
            .tint(Theme.accent)
        }
        .displayName("あとでに回す")
        .description("気になっていることを書いて、あとでに回す")
    }
}
