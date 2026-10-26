import SwiftUI
import WidgetKit

@main
struct AtohaWidgetBundle: WidgetBundle {
    init() { Theme.registerFonts() }

    var body: some Widget {
        NowWidget()
        CaptureWidget()
        AtohaLiveActivity()
        CaptureControl()
    }
}
