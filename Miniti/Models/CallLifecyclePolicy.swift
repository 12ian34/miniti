import Foundation

// Pure call-lifecycle types and policy for macOS call detection. Platform-neutral on purpose:
// the Core Audio monitor that produces snapshots lives in CallActivityMonitor.swift (macOS
// only), while everything here is deterministic value-type logic covered by both test bundles.
// See docs/call-lifecycle-and-recording-presence-plan.md.

// MARK: - Snapshot types

enum CallApplicationConfidence: String, Sendable, Equatable, Codable {
    /// A dedicated call application (Zoom, Teams, FaceTime…). Mic activity means a call.
    case native
    /// A browser holding the microphone. Core Audio identifies only the browser, never the
    /// site, so this could be any WebRTC page, dictation, or a recording tool. Prompts must
    /// stay generic and end evidence is weaker.
    case browser
}

struct ActiveCallApplication: Sendable, Equatable, Hashable, Identifiable {
    /// Canonical owning-application bundle ID after helper normalization.
    let bundleID: String
    let displayName: String
    let deviceUIDs: Set<String>
    let confidence: CallApplicationConfidence

    var id: String { bundleID }
}

struct CallActivitySnapshot: Sendable, Equatable {
    let capturedAt: Date
    /// Recognized applications currently running an active input stream, sorted native-first
    /// then by display name so snapshots compare deterministically. Unknown microphone users
    /// are never included: their bundle IDs stay local to the monitor.
    let activeCalls: [ActiveCallApplication]
    /// False when the HAL process-list query itself failed (coreaudiod restart, transient
    /// error). An unreliable reading is "no information", never "no calls": policy must not
    /// advance start or end detection from it, or an audio-daemon hiccup plus a quiet
    /// transcript becomes indistinguishable from the call ending.
    let isReliable: Bool

    init(capturedAt: Date, activeCalls: [ActiveCallApplication], isReliable: Bool = true) {
        self.capturedAt = capturedAt
        self.activeCalls = activeCalls
        self.isReliable = isReliable
    }

    func hasSameCalls(as other: CallActivitySnapshot) -> Bool {
        activeCalls == other.activeCalls && isReliable == other.isReliable
    }
}

// MARK: - Known-application directory

/// Maps raw Core Audio process bundle IDs to the recognized owning call application.
/// Extending coverage means editing the tables below; policy never changes with them.
enum CallApplicationDirectory {
    struct KnownApplication: Sendable, Equatable {
        let canonicalBundleID: String
        let displayName: String
        let confidence: CallApplicationConfidence
    }

    /// Canonical bundle ID → application. Helper processes resolve here via `aliases`
    /// or longest-prefix matching (`com.google.Chrome.helper` → `com.google.Chrome`).
    static let knownApplications: [String: KnownApplication] = {
        var table: [String: KnownApplication] = [:]
        func add(_ id: String, _ name: String, _ confidence: CallApplicationConfidence) {
            table[id] = KnownApplication(canonicalBundleID: id, displayName: name, confidence: confidence)
        }
        add("us.zoom.xos", "Zoom", .native)
        add("com.microsoft.teams2", "Microsoft Teams", .native)
        add("com.microsoft.teams", "Microsoft Teams", .native)
        add("com.tinyspeck.slackmacgap", "Slack", .native)
        add("com.apple.FaceTime", "FaceTime", .native)
        add("Cisco-Systems.Spark", "Webex", .native)
        add("com.webex.meetingmanager", "Webex", .native)
        add("com.hnc.Discord", "Discord", .native)
        add("net.whatsapp.WhatsApp", "WhatsApp", .native)
        add("app.tuple.app", "Tuple", .native)
        add("com.dialpad.dialpad", "Dialpad", .native)
        add("town.gather.app", "Gather", .native)
        add("com.google.Chrome", "Chrome", .browser)
        add("com.apple.Safari", "Safari", .browser)
        add("com.apple.SafariTechnologyPreview", "Safari", .browser)
        add("com.microsoft.edgemac", "Edge", .browser)
        add("company.thebrowser.Browser", "Arc", .browser)
        add("com.brave.Browser", "Brave", .browser)
        add("org.mozilla.firefox", "Firefox", .browser)
        return table
    }()

    /// Helper bundle IDs that do not share their owner's prefix.
    static let aliases: [String: String] = [
        // Safari performs media capture in the WebKit GPU process.
        "com.apple.WebKit.GPU": "com.apple.Safari",
        "com.apple.WebKit.WebContent": "com.apple.Safari"
    ]

    /// Processes that must never be treated as a call application: Miniti itself and its
    /// test hosts. The monitor also excludes its own PID; this catches renamed helpers.
    static let excludedBundleIDPrefixes: [String] = [
        "com.miniti."
    ]

    static func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDPrefixes.contains { bundleID.hasPrefix($0) || bundleID == String($0.dropLast()) }
    }

    /// Resolves a raw process bundle ID (possibly a helper) to its recognized application.
    static func normalize(bundleID: String) -> KnownApplication? {
        guard !bundleID.isEmpty, !isExcluded(bundleID: bundleID) else { return nil }
        if let direct = knownApplications[bundleID] { return direct }
        if let alias = aliases[bundleID], let owner = knownApplications[alias] { return owner }
        // Helper processes normally extend the owner's bundle ID: pick the longest known prefix.
        var best: KnownApplication?
        for (canonical, app) in knownApplications where bundleID.hasPrefix(canonical + ".") {
            if best == nil || canonical.count > best!.canonicalBundleID.count { best = app }
        }
        return best
    }

    /// Sort order for snapshots: native apps before browsers, then alphabetical, then bundle
    /// ID so two apps with one display name (Teams classic/new) stay deterministic.
    static func snapshotOrder(_ a: ActiveCallApplication, _ b: ActiveCallApplication) -> Bool {
        if a.confidence != b.confidence { return a.confidence == .native }
        if a.displayName != b.displayName { return a.displayName < b.displayName }
        return a.bundleID < b.bundleID
    }
}

/// The reversible pre-finalization countdown shown after a strong call end. A deferred stop:
/// nothing in the finalization path runs until the deadline passes.
struct EndingGraceState: Equatable {
    let appBundleID: String
    let appDisplayName: String
    let deadline: Date
    var remainingSeconds: Int
}

// MARK: - Lifecycle engine

/// What the engine asks AppState to do. The engine never mutates product state itself.
enum CallLifecycleEvent: Equatable {
    /// A recognized app has held the microphone continuously for the start debounce and no
    /// recording exists: offer to take notes.
    case offerStartPrompt(ActiveCallApplication)
    /// The detected call went away before the user acted on the start prompt.
    case clearStartPrompt
    /// The recording's associated call app released input for the end debounce while audio
    /// and transcript were quiet: begin the ending grace (or ask first for short sessions).
    case beginEndingGrace(app: ActiveCallApplication, askOnly: Bool)
    /// The associated app came back before grace began.
    case cancelEndCandidate
    /// The associated app came back while ending grace was pending: resume the meeting.
    case reactivateDuringGrace
    /// A different recognized call app became active during the recording. Never an
    /// automatic split — at most a visible handoff decision.
    case offerTransition(to: ActiveCallApplication)
    /// A recording that expected its call (join link / calendar conference link) has
    /// adopted the call that appeared. Informational: no prompt, no state change in AppState.
    case adoptExpectedCall(ActiveCallApplication)
}

/// Inputs the engine needs from AppState each tick. Gaps use the existing
/// `lastAudioActivityAt` / `lastTranscriptReceivedAt` semantics (`.infinity` when never).
struct CallLifecycleContext: Sendable {
    var isRecording: Bool
    var smartMeetingsEnabled: Bool
    var hasMeaningfulContent: Bool
    var recordingDuration: TimeInterval
    var transcriptGap: TimeInterval
    var audioGap: TimeInterval
    var isInEndingGrace: Bool
}

/// Deterministic call-lifecycle state machine. Owned by AppState on macOS; a value type so
/// tests drive it with synthetic snapshots and contexts.
struct CallLifecycleEngine {
    // Policy constants.
    /// Continuous input required before a start prompt.
    static let startDebounce: TimeInterval = 2
    /// Continuous input absence required before an end candidate matures.
    static let endDebounce: TimeInterval = 4
    /// The transcript must have been quiet this long before an end candidate can begin grace.
    /// Mic release alone never proves a call ended (push-to-talk, listen-only attendance, apps
    /// that release input on mute); live call speech keeps producing transcript, so a fresh
    /// transcript vetoes the end. Deliberately transcript-based rather than audio-level-based:
    /// post-call music keeps system audio levels hot and would otherwise block ending forever.
    static let endQuietRequirement: TimeInterval = 5
    /// Browsers get slower, more skeptical end detection: the browser's mic use is app-level
    /// (another tab can mask or mimic a call), so browser end evidence leans harder on time
    /// and quiet than native call apps do.
    static let browserEndDebounce: TimeInterval = 8
    static let browserEndQuietRequirement: TimeInterval = 8

    static func endDebounce(for confidence: CallApplicationConfidence) -> TimeInterval {
        confidence == .browser ? browserEndDebounce : endDebounce
    }

    static func endQuietRequirement(for confidence: CallApplicationConfidence) -> TimeInterval {
        confidence == .browser ? browserEndQuietRequirement : endQuietRequirement
    }
    /// All calls must be gone this long before start-prompt suppression resets.
    static let startResetGap: TimeInterval = 3
    /// Recordings shorter than this receive an ask-only prompt instead of automatic ending.
    static let shortSessionMinimumDuration: TimeInterval = 60

    // Start-detection state (only meaningful while not recording).
    private(set) var startCandidate: (app: ActiveCallApplication, firstSeenAt: Date)?
    private(set) var promptedStartBundleID: String?
    private(set) var suppressedStartBundleID: String?
    private var lastStartAppSeenAt: Date?
    private var startPromptVisible = false

    // Association state (only meaningful while recording).
    private(set) var associatedApp: ActiveCallApplication?
    private(set) var hasObservedAssociatedActive = false
    private(set) var endCandidateSince: Date?
    private var transitionCandidates: [String: Date] = [:]
    private var offeredTransitionBundleIDs: Set<String> = []
    /// While set, a recording that has no associated call adopts the first recognized
    /// call that appears (after the start debounce) instead of offering a transition.
    /// Armed only for starts that explicitly expect a call: a calendar meeting with a
    /// conference link, or a join link opened by the user.
    private(set) var expectedCallUntil: Date?

    /// How long after a join-style start the recording waits for its own call to appear.
    /// Covers a Meet lobby and a slow browser launch; bounded so an unrelated call much
    /// later stays a transition candidate.
    static let expectedCallWindow: TimeInterval = 300

    /// Association forms at recording start — from the start prompt's app, or from
    /// exactly one recognized call being active. Apps appearing mid-recording never
    /// associate retroactively, so an unrelated call ending cannot end this recording.
    /// The one exception is a start that expects a call (`expectsCall`): the user just
    /// pressed Join or started notes for a meeting with a conference link, so the call
    /// that appears in the next `expectedCallWindow` is this recording's own call.
    mutating func noteRecordingStarted(
        activeCalls: [ActiveCallApplication],
        startedFrom promptApp: ActiveCallApplication?,
        expectsCall: Bool = false,
        at now: Date = Date()
    ) {
        endCandidateSince = nil
        hasObservedAssociatedActive = false
        transitionCandidates = [:]
        offeredTransitionBundleIDs = []
        if let promptApp {
            associatedApp = promptApp
        } else if activeCalls.count == 1 {
            associatedApp = activeCalls[0]
        } else {
            associatedApp = nil
        }
        if associatedApp == nil, expectsCall {
            expectedCallUntil = now.addingTimeInterval(Self.expectedCallWindow)
        } else if associatedApp != nil {
            expectedCallUntil = nil
        }
        // An expectation armed by a join link opened before the recording registered
        // (managed starts are asynchronous) survives this call.
        startCandidate = nil
        promptedStartBundleID = nil
        suppressedStartBundleID = nil
        startPromptVisible = false
    }

    /// The user opened (or re-opened) the meeting's conference link. If the recording
    /// has no associated call yet, expect its call to appear shortly.
    mutating func noteJoinLinkOpened(at now: Date = Date()) {
        guard associatedApp == nil else { return }
        expectedCallUntil = now.addingTimeInterval(Self.expectedCallWindow)
    }

    mutating func noteRecordingEnded() {
        associatedApp = nil
        hasObservedAssociatedActive = false
        endCandidateSince = nil
        transitionCandidates = [:]
        offeredTransitionBundleIDs = []
        expectedCallUntil = nil
    }

    /// The user dismissed the start prompt: suppress further prompts for this uninterrupted call.
    mutating func noteStartPromptDismissed(bundleID: String) {
        suppressedStartBundleID = bundleID
        startPromptVisible = false
    }

    /// AppState could not show the offered start prompt (terms gate, force update, a stopped
    /// session still open…). Un-mark it so the same call is offered again once the gate clears,
    /// instead of being swallowed for the rest of the call.
    mutating func noteStartPromptNotShown(bundleID: String) {
        if promptedStartBundleID == bundleID {
            promptedStartBundleID = nil
            startPromptVisible = false
        }
    }

    mutating func ingest(snapshot: CallActivitySnapshot, context: CallLifecycleContext) -> [CallLifecycleEvent] {
        // Smart meetings off leaves lifecycle snapshots inert.
        guard context.smartMeetingsEnabled else { return [] }
        // An unreliable reading is no information: freeze rather than infer. Debounces
        // restart from the next reliable snapshot.
        guard snapshot.isReliable else {
            endCandidateSince = nil
            startCandidate = nil
            return []
        }
        return context.isRecording
            ? ingestWhileRecording(snapshot: snapshot, context: context)
            : ingestWhileIdle(snapshot: snapshot)
    }

    private mutating func ingestWhileRecording(snapshot: CallActivitySnapshot, context: CallLifecycleContext) -> [CallLifecycleEvent] {
        var events: [CallLifecycleEvent] = []
        let now = snapshot.capturedAt
        startCandidate = nil

        if let associated = associatedApp {
            if let current = snapshot.activeCalls.first(where: { $0.bundleID == associated.bundleID }) {
                // Present again (a device switch changes UIDs, never the association).
                hasObservedAssociatedActive = true
                associatedApp = current
                if endCandidateSince != nil {
                    endCandidateSince = nil
                    events.append(context.isInEndingGrace ? .reactivateDuringGrace : .cancelEndCandidate)
                } else if context.isInEndingGrace {
                    events.append(.reactivateDuringGrace)
                }
            } else if hasObservedAssociatedActive, !context.isInEndingGrace {
                if let since = endCandidateSince {
                    if now.timeIntervalSince(since) >= Self.endDebounce(for: associated.confidence),
                       context.transcriptGap >= Self.endQuietRequirement(for: associated.confidence) {
                        let askOnly = !context.hasMeaningfulContent ||
                            context.recordingDuration < Self.shortSessionMinimumDuration
                        events.append(.beginEndingGrace(app: associated, askOnly: askOnly))
                        endCandidateSince = nil
                    }
                } else {
                    endCandidateSince = now
                }
            }
        }

        // Other recognized calls are transition candidates after the same start debounce.
        // A recording still waiting for its own call (join link, calendar meeting with a
        // conference link) adopts the first matured candidate instead of prompting.
        if let until = expectedCallUntil, now > until {
            expectedCallUntil = nil
        }
        let activeIDs = Set(snapshot.activeCalls.map(\.bundleID))
        transitionCandidates = transitionCandidates.filter { activeIDs.contains($0.key) }
        for app in snapshot.activeCalls where app.bundleID != associatedApp?.bundleID {
            if let since = transitionCandidates[app.bundleID] {
                guard now.timeIntervalSince(since) >= Self.startDebounce else { continue }
                if associatedApp == nil, expectedCallUntil != nil {
                    associatedApp = app
                    hasObservedAssociatedActive = true
                    expectedCallUntil = nil
                    transitionCandidates[app.bundleID] = nil
                    events.append(.adoptExpectedCall(app))
                } else if !offeredTransitionBundleIDs.contains(app.bundleID) {
                    offeredTransitionBundleIDs.insert(app.bundleID)
                    events.append(.offerTransition(to: app))
                }
            } else {
                transitionCandidates[app.bundleID] = now
            }
        }
        return events
    }

    private mutating func ingestWhileIdle(snapshot: CallActivitySnapshot) -> [CallLifecycleEvent] {
        var events: [CallLifecycleEvent] = []
        let now = snapshot.capturedAt
        endCandidateSince = nil

        if let preferred = snapshot.activeCalls.first {
            lastStartAppSeenAt = now
            if startCandidate?.app.bundleID != preferred.bundleID {
                startCandidate = (preferred, now)
            } else if now.timeIntervalSince(startCandidate!.firstSeenAt) >= Self.startDebounce,
                      promptedStartBundleID != preferred.bundleID,
                      suppressedStartBundleID != preferred.bundleID {
                promptedStartBundleID = preferred.bundleID
                startPromptVisible = true
                events.append(.offerStartPrompt(preferred))
            }
        } else {
            startCandidate = nil
            if let lastSeen = lastStartAppSeenAt, now.timeIntervalSince(lastSeen) >= Self.startResetGap {
                // The uninterrupted call is over: prompt suppression resets and any
                // still-visible offer is stale.
                lastStartAppSeenAt = nil
                promptedStartBundleID = nil
                suppressedStartBundleID = nil
                if startPromptVisible {
                    startPromptVisible = false
                    events.append(.clearStartPrompt)
                }
            }
        }
        return events
    }
}

// MARK: - Automatic meeting environment inference

/// Internal, evidence-backed description of the meeting environment. Never
/// shown as a user choice or status badge; never allowed to start, stop,
/// split, or transition a meeting, change capture topology, or alter
/// transcript content. Old meetings decode as `unknown`.
enum InferredMeetingEnvironment: String, Codable, Sendable, Equatable {
    case unknown
    case remoteLikely
    case inRoomLikely
    case hybridLikely
}

/// Shared rule for the implicit "You" default on the primary mic speaker (1000).
/// Dual-source capture keeps "You" while there is at most one mic speaker, or
/// when the meeting is remote-likely (headset clones must not withdraw You).
/// In-room / hybrid / unknown with multiple mic IDs stay neutral.
enum ImplicitSelfPolicy {
    static func allowed(
        micSpeakerCount: Int,
        hasDualSourceOrLegacy: Bool,
        environment: InferredMeetingEnvironment
    ) -> Bool {
        guard hasDualSourceOrLegacy else { return false }
        if micSpeakerCount <= 1 { return true }
        return environment == .remoteLikely
    }
}

/// Snapshot of the independent signals the inference combines. Absence of a
/// signal is "no information", never evidence by itself (a missing system
/// transcript is consistent with a muted call; call-monitor unreliability is
/// not in-room evidence).
struct MeetingEnvironmentEvidence: Sendable, Equatable {
    /// A recognized call application is associated with this recording.
    var hasAssociatedCallApp = false
    /// A recognized call application is currently active (association may be
    /// incomplete) while the call monitor is reliable.
    var recognizedCallAppActive = false
    /// The linked calendar event has a conference URL. Nil when there is no
    /// calendar context for this meeting.
    var calendarEventHasConferenceURL: Bool? = nil
    /// Distinct speakers Deepgram has confirmed on the microphone source.
    var confirmedMicSpeakerCount = 0
    /// A meaningful finalized microphone transcript exists.
    var hasMeaningfulMicFinal = false
    /// A meaningful finalized system-channel transcript exists.
    var hasMeaningfulSystemFinal = false
    /// A meaningful system final arrived while independent call-app or
    /// calendar-conference evidence was present (strong remote evidence, as
    /// opposed to media playback in a room).
    var systemFinalWithCallContext = false
    /// Accumulated seconds of meaningful finalized microphone speech.
    var meaningfulMicSpeechSeconds: Double = 0
    /// Accumulated seconds of meaningful finalized speech from microphone
    /// speakers other than the primary (1000). A diarizer clone of the sole
    /// local talker rarely accrues much; a real second person in the room does.
    var additionalMicSpeakerSpeechSeconds: Double = 0
}

/// Pure, deterministic policy mapping evidence to an inferred environment.
/// Recomputed from the full evidence snapshot on each update, so stronger
/// later evidence naturally supersedes earlier conclusions
/// (e.g. `inRoomLikely` becomes `hybridLikely` when a remote participant
/// finally speaks). The state is monotonic only with respect to evidence
/// strength, not enum order.
enum MeetingEnvironmentInferenceEngine {
    /// Meaningful mic speech required before `inRoomLikely` may be concluded.
    /// Speech time, not wall time. Policy constant — tune from fixtures and
    /// field measurement, not in UI code.
    static let inRoomObservationWindowSeconds: Double = 30

    /// Words below this count are not "meaningful" transcript evidence.
    static let meaningfulFinalMinimumWordCount = 3

    /// Speech from additional mic speakers required before a remote meeting is
    /// promoted to hybrid. Without this floor, one promoted diarizer clone on a
    /// solo headset call flipped the meeting to hybrid, which switched the
    /// promotion policy back to standard and withdrew "You" from the primary
    /// speaker: the exact case the strict policy exists to protect.
    static let hybridSecondaryMicSpeechSeconds: Double = 20

    static func infer(_ evidence: MeetingEnvironmentEvidence) -> InferredMeetingEnvironment {
        let multipleMicSpeakers = evidence.confirmedMicSpeakerCount >= 2
        let strongRemote = evidence.hasAssociatedCallApp || evidence.systemFinalWithCallContext
        let secondaryMicSpeakerIsReal =
            evidence.additionalMicSpeakerSpeechSeconds >= hybridSecondaryMicSpeechSeconds

        // Hybrid: several people in the room, one of them with real speech time,
        // and confirmed remote participation.
        if multipleMicSpeakers, secondaryMicSpeakerIsReal {
            if evidence.systemFinalWithCallContext {
                return .hybridLikely
            }
            if evidence.hasAssociatedCallApp && evidence.hasMeaningfulSystemFinal {
                return .hybridLikely
            }
        }

        if strongRemote {
            return .remoteLikely
        }

        // Supporting remote evidence needs corroboration: any single signal
        // alone (a conference URL on the calendar, an active but unassociated
        // call app, system speech that could be media playback) stays unknown.
        let supportingRemoteSignals = [
            evidence.calendarEventHasConferenceURL == true,
            evidence.recognizedCallAppActive,
            evidence.hasMeaningfulSystemFinal
        ].filter { $0 }.count
        if supportingRemoteSignals >= 2 {
            return .remoteLikely
        }

        // In-room: several confirmed mic speakers, a bounded observation window
        // of meaningful speech, and no remote evidence of any strength.
        if multipleMicSpeakers,
           evidence.hasMeaningfulMicFinal,
           !evidence.hasMeaningfulSystemFinal,
           !evidence.hasAssociatedCallApp,
           !evidence.recognizedCallAppActive,
           evidence.calendarEventHasConferenceURL != true,
           evidence.meaningfulMicSpeechSeconds >= inRoomObservationWindowSeconds {
            return .inRoomLikely
        }

        return .unknown
    }
}
