import ActivityKit
import WidgetKit
import SwiftUI

// Palette values mirrored from ColorPalette.swift. Widget extension is a separate
// target and cannot import the main app module, so these must stay in sync by hand.
private let recordingRed = "F85149"      // ColorPalette.Status.recording
private let pausedGray = "6E7681"        // ColorPalette.Text.dim
private let timerGreen = "3FB950"        // ColorPalette.Accent.greenGitHub
private let textPrimary = "E6EDF3"       // ColorPalette.Text.primary
private let textMuted = "C9D1D9"         // ColorPalette.Text.muted
private let textMeta = "8B949E"          // ColorPalette.Text.meta
private let textDisabled = "3F3F46"      // ColorPalette.Text.disabled
private let backgroundPrimary = "0B0B0D" // ColorPalette.Background.primary

struct MinitiLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                            .frame(width: 7, height: 7)
                        Text(context.state.isRecording ? "REC" : "STOPPED")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerView(context: context, size: 15, weight: .bold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !context.state.meetingTitle.isEmpty {
                            Text(context.state.meetingTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: context.state.isRecording ? textPrimary : pausedGray))
                                .lineLimit(1)
                        }
                        if !context.state.isRecording {
                            Text("tap to return to miniti")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: textDisabled))
                        } else if !context.state.currentTranscript.isEmpty {
                            Text(context.state.currentTranscript)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color(hex: textMeta))
                                .lineLimit(2)
                        }
                        HStack {
                            Spacer()
                            Text("miniti")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: textDisabled))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Circle()
                    .fill(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                    .frame(width: 6, height: 6)
                    .padding(.leading, 4)
            } compactTrailing: {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    timerView(context: context, size: 12, weight: .semibold)
                }
            } minimal: {
                Circle()
                    .fill(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Timer View

    /// Shows live counting timer when recording, frozen static time when stopped.
    @ViewBuilder
    private func timerView(context: ActivityViewContext<RecordingActivityAttributes>, size: CGFloat, weight: Font.Weight) -> some View {
        if context.state.isRecording {
            Text(timerInterval: context.attributes.startTime...Date.distantFuture, countsDown: false)
                .font(.system(size: size, weight: weight, design: .monospaced))
                .foregroundStyle(Color(hex: timerGreen))
        } else if let elapsed = context.state.elapsedSeconds {
            Text(formatDuration(elapsed))
                .font(.system(size: size, weight: weight, design: .monospaced))
                .foregroundStyle(Color(hex: pausedGray))
        } else {
            Text(timerInterval: context.attributes.startTime...Date.distantFuture, countsDown: false)
                .font(.system(size: size, weight: weight, design: .monospaced))
                .foregroundStyle(Color(hex: pausedGray))
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                        .frame(width: 8, height: 8)
                    Text(context.state.isRecording ? "Recording" : "Stopped")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: context.state.isRecording ? recordingRed : pausedGray))
                }
                if !context.state.meetingTitle.isEmpty {
                    Text(context.state.meetingTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: context.state.isRecording ? textMuted : pausedGray))
                        .lineLimit(1)
                }
                if !context.state.isRecording {
                    Text("tap to return to miniti")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: textDisabled))
                } else if !context.state.currentTranscript.isEmpty {
                    Text(context.state.currentTranscript)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: textMeta))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                timerView(context: context, size: 22, weight: .bold)
                Text("miniti")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: textDisabled))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(hex: backgroundPrimary))
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
