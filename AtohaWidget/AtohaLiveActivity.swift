import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 集中しているあいだのライブアクティビティ。お椀に泡、名前、経過、＋（あとに回す）。
struct AtohaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AtohaActivityAttributes.self) { context in
            Group {
                if context.state.takenHomeAt != nil {
                    LiveDoneBannerView()
                } else {
                    LiveBannerView(text: context.state.text, start: context.state.startedAt, ended: context.state.endedAt)
                }
            }
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(K.navy)
                .widgetURL(AtohaLink.now)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.takenHomeAt != nil {
                        // 持ち帰ったとき：袋と金魚を数秒だけ
                        IslandDoneView().fixedSize().frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            IslandExpandedRow(text: context.state.text, start: context.state.startedAt, ended: context.state.endedAt)
                            IslandButtons()
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                if context.state.takenHomeAt != nil {
                    PixelBag(onDark: true, line: .white, width: 12)
                } else {
                    IslandCompactLeading()
                }
            } compactTrailing: {
                if context.state.takenHomeAt != nil {
                    PixelFish(color: K.red, width: 18)
                } else {
                    IslandCompactTrailing(start: context.state.startedAt, ended: context.state.endedAt)
                }
            } minimal: {
                if context.state.takenHomeAt != nil {
                    PixelBag(onDark: true, line: .white, width: 12)
                } else {
                    IslandMinimal()
                }
            }
            .widgetURL(AtohaLink.now)
            .keylineTint(K.red)
        }
    }
}
