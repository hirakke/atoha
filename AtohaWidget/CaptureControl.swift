import AppIntents
import SwiftUI
import WidgetKit

/// コントロールセンター／ロック画面のコントロール。押すと書き出し画面へ直行する。
struct CaptureControl: ControlWidget {
    static let kind = "app.atoha.prototype.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureIntent()) {
                Label("あとで", systemImage: "square.and.arrow.down")
            }
            .tint(Theme.accent)
        }
        .displayName("あとで")
        .description("atoha の書き出し画面を開く")
    }
}
