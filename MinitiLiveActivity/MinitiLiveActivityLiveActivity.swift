import ActivityKit
import WidgetKit
import SwiftUI

struct MinitiLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                            .frame(width: 8, height: 8)
                        Text(context.state.isRecording ? "REC" : "PAUSED")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startTime...Date.distantFuture, countsDown: false)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "3FB950"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.state.meetingTitle.isEmpty {
                        Text(context.state.meetingTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.currentTranscript.isEmpty {
                        Text(context.state.currentTranscript)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: "8B949E"))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    Text("miniti")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
            } compactLeading: {
                // MARK: - Compact Leading: Red recording dot
                Circle()
                    .fill(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                // MARK: - Compact Trailing: Elapsed timer
                Text(timerInterval: context.attributes.startTime...Date.distantFuture, countsDown: false)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "3FB950"))
                    .monospacedDigit()
            } minimal: {
                // MARK: - Minimal: Just the red dot
                Circle()
                    .fill(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                // Left side: recording indicator + title
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                            .frame(width: 8, height: 8)
                        Text(context.state.isRecording ? "Recording" : "Paused")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(context.state.isRecording ? Color(hex: "F85149") : Color(hex: "6E7681"))
                    }
                    if !context.state.meetingTitle.isEmpty {
                        Text(context.state.meetingTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "C9D1D9"))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Right side: elapsed timer
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timerInterval: context.attributes.startTime...Date.distantFuture, countsDown: false)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "3FB950"))
                        .monospacedDigit()
                    Text("miniti")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
            }

            // Live transcript line
            if !context.state.currentTranscript.isEmpty {
                Text(context.state.currentTranscript)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "8B949E"))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(hex: "0D1117"))
    }
}

// MARK: - Hex Color Extension (Widget)
// Duplicated from ColorPalette since widget extensions have a separate module.
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
