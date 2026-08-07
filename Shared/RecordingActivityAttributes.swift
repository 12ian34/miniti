import Foundation
import ActivityKit

enum LiveActivityPreferences {
    static let showTranscriptKey = "liveActivity.showTranscript"

    /// Privacy remains opt-out for continuity with the existing Live Activity.
    static var showsTranscript: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: showTranscriptKey) != nil else { return true }
        return defaults.bool(forKey: showTranscriptKey)
    }

    static func presentedTranscript(_ transcript: String, isEnabled: Bool = showsTranscript) -> String {
        isEnabled ? transcript : ""
    }
}

/// Shared between the MinitiMobile app target and the MinitiLiveActivity widget extension.
/// Defines the static and dynamic data for the recording Live Activity.
struct RecordingActivityAttributes: ActivityAttributes {
    /// Stable meeting identifier so the app can reconcile existing activities after lifecycle resets.
    let meetingID: String
    /// Static data — set once when the activity starts.
    let startTime: Date

    /// Dynamic data — updated when title changes, recording stops, or new transcript arrives.
    struct ContentState: Codable, Hashable {
        var meetingTitle: String
        var isRecording: Bool
        /// The most recent transcript line (interim or last finalized segment).
        var currentTranscript: String
        /// Elapsed seconds when recording was stopped. Used to show frozen timer instead of live counter.
        var elapsedSeconds: Int?
    }
}
