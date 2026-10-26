import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 集中しているあいだのライブアクティビティ。お椀に泡、名前、経過、＋（あとに回す）。
struct AtohaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AtohaActivityAttributes.self) { context in
            LiveBannerView(text: context.state.text, start: context.state.startedAt, ended: context.state.endedAt)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(K.navy)
                .widgetURL(AtohaLink.now)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        IslandExpandedRow(text: context.state.text, start: context.state.startedAt, ended: context.state.endedAt)
                        IslandButtons()
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                IslandCompactLeading()
            } compactTrailing: {
                IslandCompactTrailing(start: context.state.startedAt, ended: context.state.endedAt)
            } minimal: {
                IslandMinimal()
            }
            .widgetURL(AtohaLink.now)
            .keylineTint(K.red)
        }
    }
}
