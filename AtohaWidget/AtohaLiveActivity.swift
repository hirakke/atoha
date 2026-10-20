import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 預かり中の件数をドットで、次に返す時刻をドット文字で出す。文章は出さない。
struct AtohaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AtohaActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Theme.paper)
                .activitySystemActionForegroundColor(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DotCountRow(count: context.state.count, max: 8, dotSize: 7)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReturnTime(date: context.state.nextReturn, dotSize: 3.5, spacing: 1)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CaptureButton().frame(maxWidth: .infinity)
                }
            } compactLeading: {
                DotMatrixText("\(context.state.count)", dotSize: 2, spacing: 0.6, color: Theme.accent)
            } compactTrailing: {
                ReturnTime(date: context.state.nextReturn, dotSize: 1.1, spacing: 0.4)
            } minimal: {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
            }
            .keylineTint(Theme.accent)
        }
    }
}

private struct LockScreenView: View {
    let state: AtohaActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                DotCountRow(count: state.count, max: 16, dotSize: 8)
                ReturnTime(date: state.nextReturn, dotSize: 4.5, spacing: 1.5)
            }
            Spacer(minLength: 0)
            CaptureButton()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// 次に返す時刻。区切りだけのときは --:-- を薄く出す。
private struct ReturnTime: View {
    let date: Date?
    let dotSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        if let date {
            DotMatrixText(
                date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()),
                dotSize: dotSize, spacing: spacing)
        } else {
            DotMatrixText("--:--", dotSize: dotSize, spacing: spacing, color: Theme.quiet)
        }
    }
}

private struct CaptureButton: View {
    var body: some View {
        Button(intent: CaptureIntent()) {
            Text("あとでに回す")
                .font(Theme.mono(15, weight: .medium))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.accent, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
