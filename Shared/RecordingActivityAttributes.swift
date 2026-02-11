import Foundation
import ActivityKit

/// Shared between the MinitiMobile app target and the MinitiLiveActivity widget extension.
/// Defines the static and dynamic data for the recording Live Activity.
struct RecordingActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts.
    let startTime: Date

    /// Dynamic data — updated when title changes, recording stops, or new transcript arrives.
    struct ContentState: Codable, Hashable {
        var meetingTitle: String
        var isRecording: Bool
        /// The most recent transcript line (interim or last finalized segment).
        var currentTranscript: String
    }
}
