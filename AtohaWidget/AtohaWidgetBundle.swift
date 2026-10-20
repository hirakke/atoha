import SwiftUI
import WidgetKit

@main
struct AtohaWidgetBundle: WidgetBundle {
    var body: some Widget {
        AtohaLiveActivity()
        CaptureControl()
    }
}
