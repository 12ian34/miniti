import Foundation
import SwiftUI
import SwiftData
import Combine
import os
@preconcurrency import UserNotifications
#if os(iOS)
import ActivityKit
import StoreKit
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

@MainActor
final class AudioLevelsState: ObservableObject {
    struct Snapshot: Equatable {
        let combinedLevel: Float
        let microphoneLevel: Float
        let systemAudioLevel: Float

        static let zero = Snapshot(combinedLevel: 0, microphoneLevel: 0, systemAudioLevel: 0)
    }

    @Published private(set) var snapshot = Snapshot.zero

    var combinedLevel: Float { snapshot.combinedLevel }
    var microphoneLevel: Float { snapshot.microphoneLevel }
    var systemAudioLevel: Float { snapshot.systemAudioLevel }

    /// Publish all meters together so a mic/system sample pair invalidates waveform views once.
    func update(microphoneLevel: Float, systemAudioLevel: Float) {
        let next = Snapshot(
            combinedLevel: max(microphoneLevel, systemAudioLevel),
            microphoneLevel: microphoneLevel,
            systemAudioLevel: systemAudioLevel
        )
        guard next != snapshot else { return }
        snapshot = next
    }

    func reset() {
        guard snapshot != .zero else { return }
        snapshot = .zero
    }
}

@MainActor
final class TranscriptRuntimeState: ObservableObject {
    struct Snapshot: Equatable {
        let interimText: String
        let currentSpeaker: Int
        let interimSpeaker: Int?
        let revision: UInt64

        static let zero = Snapshot(
            interimText: "",
            currentSpeaker: 0,
            interimSpeaker: nil,
            revision: 0
        )
    }

    @Published private(set) var snapshot = Snapshot.zero

    var interimText: String {
        get { snapshot.interimText }
        set {
            update(
                interimText: newValue,
                currentSpeaker: snapshot.currentSpeaker,
                interimSpeaker: snapshot.interimSpeaker
            )
        }
    }

    var currentSpeaker: Int {
        get { snapshot.currentSpeaker }
        set {
            update(
                interimText: snapshot.interimText,
                currentSpeaker: newValue,
                interimSpeaker: snapshot.interimSpeaker
            )
        }
    }

    var interimSpeaker: Int? {
        get { snapshot.interimSpeaker }
        set {
            update(
                interimText: snapshot.interimText,
                currentSpeaker: snapshot.currentSpeaker,
                interimSpeaker: newValue
            )
        }
    }

    func update(interimText: String, currentSpeaker: Int, interimSpeaker: Int?) {
        snapshot = Snapshot(
            interimText: interimText,
            currentSpeaker: currentSpeaker,
            interimSpeaker: interimSpeaker,
            revision: snapshot.revision &+ 1
        )
    }

    func clear() {
        update(interimText: "", currentSpeaker: 0, interimSpeaker: nil)
    }
}

private let appStatePerformanceLog = OSLog(
    subsystem: "com.miniti.app",
    category: .pointsOfInterest
)

// MARK: - App Mode

/// Two parallel modes that coexist without conflict.
/// BYOK: user's own API keys, unlimited, no backend.
/// Managed: 500 free min/month, proxied through backend, hard-blocked at limit.
enum AppMode: String {
    case byok      // User's own keys — no limits, no tracking
    case managed   // Miniti's backend — 500 min/month free
}

@MainActor
final class AppState: ObservableObject {
    struct LiveInsightCadencePolicy: Equatable {
        let minimumInterval: TimeInterval
        let minimumSegmentDelta: Int
        let maximumInterval: TimeInterval
    }

    enum AudioRecoveryState: String {
        case healthy
        case recovering
        case degraded
        
        var label: String {
            switch self {
            case .healthy: return "audio healthy"
            case .recovering: return "recovering audio..."
            case .degraded: return "audio degraded"
            }
        }
    }

    /// Why a recording stopped itself. Kept distinct from the banner flag so the stopped-state
    /// copy can be honest: a stalled transcript pipeline is not the same as a quiet room.
    enum AutoStopReason: String {
        case silence
        case stalledPipeline

        var label: String {
            switch self {
            case .silence: return "auto-stopped — no speech detected"
            case .stalledPipeline: return "auto-stopped — live transcription stopped responding"
            }
        }

        var icon: String {
            switch self {
            case .silence: return "moon.zzz.fill"
            case .stalledPipeline: return "wifi.exclamationmark"
            }
        }
    }
    
    private struct PendingSessionEndReport: Codable, Identifiable, Equatable {
        let id: UUID
        let deviceId: String
        let sessionId: String
        let durationMinutes: Double
        let createdAt: Date
        var retryCount: Int
        var meetingId: UUID?
        
        init(
            id: UUID = UUID(),
            deviceId: String,
            sessionId: String,
            durationMinutes: Double,
            createdAt: Date = Date(),
            retryCount: Int = 0,
            meetingId: UUID? = nil
        ) {
            self.id = id
            self.deviceId = deviceId
            self.sessionId = sessionId
            self.durationMinutes = durationMinutes
            self.createdAt = createdAt
            self.retryCount = retryCount
            self.meetingId = meetingId
        }
    }

    private struct ManagedInsightsRequestPlan {
        let transcriptForRequest: String
        let incrementalPayload: MinitiAPIService.IncrementalInsightsPayload?
        let usesIncrementalPayload: Bool
    }

    private struct LiveInsightsFetchResult {
        let insights: InsightsService.LiveInsights
        let usedIncrementalPayload: Bool
        let meta: ManagedInsightsMeta?
    }

    struct GoogleOAuthCallbackPayload: Equatable {
        let status: String?
        let message: String?
    }

    struct LiveSegmentSaveSnapshot: Sendable {
        let id: UUID
        let text: String
        let speaker: Int
        let timestamp: TimeInterval
    }

    struct PersistedSegmentSnapshot: Sendable {
        let id: UUID
        let text: String
        let speaker: Int
        let timestamp: TimeInterval
    }

    struct SegmentSyncPlan: Sendable {
        let deleteIDs: [UUID]
        let upserts: [LiveSegmentSaveSnapshot]
    }

    struct EchoComparisonSegment: Equatable {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    private struct PendingMicSegment {
        let segment: DeepgramService.SpeakerSegment
        let deadline: Date
    }

    private struct BufferedSystemSegment {
        let segment: DeepgramService.SpeakerSegment
        let receivedAt: Date
    }

    private struct MeetingSavePayload {
        let meeting: Meeting
        let periodicFingerprint: Int?
        let finalSegments: [LiveSegmentSaveSnapshot]
        let summary: String
        let actionItems: [String]
        let topics: [String]
        let discussionFlow: [String]
        let notes: String
        let meddpiccMetrics: String?
        let meddpiccEconomicBuyer: String?
        let meddpiccDecisionCriteria: String?
        let meddpiccDecisionProcess: String?
        let meddpiccPaperProcess: String?
        let meddpiccIdentifiedPain: String?
        let meddpiccChampion: String?
        let meddpiccCompetition: String?
        let suggestedQuestions: [SuggestedQuestion]
        let docTopics: [DocTopic]
        let speakerNames: [String: String]
        let speakerOverrides: Set<String>
        let selfSpeakerIDs: Set<Int>
    }
    
    // MARK: - Recording State
    @Published var isRecording = false
    @Published var isStartingMeeting = false
    @Published var isResumingRecording = false
    @Published var currentMeeting: Meeting?
    @Published var pendingOpenSavedMeetingID: UUID?
    @Published var recordingDuration: TimeInterval = 0
    @Published private(set) var recordingErrorMessage: String?
    @Published private(set) var isFinalizingMeeting = false
    @Published private(set) var finalizationStatusText = ""
    @Published private(set) var finalizingInsightMeetingIDs: Set<UUID> = []
    @Published private(set) var lastInsightsUpdatedAt: [InsightsMode: Date] = [:]
    private var shouldOpenMeetingAfterFinalization = false

    var isCurrentMeetingGeneratingFinalInsights: Bool {
        guard let meetingID = currentMeeting?.id else { return false }
        return finalizingInsightMeetingIDs.contains(meetingID)
    }
    
    // MARK: - Session Management
    var modelContext: ModelContext?
    @Published var hasUnsavedSession = false
    let audioLevels = AudioLevelsState()
    let transcriptRuntime = TranscriptRuntimeState()
    
    // MARK: - Live Transcript
    /// Finalized, non-empty transcript segments only. Interim text lives in `transcriptRuntime`.
    @Published var liveSegments: [LiveSegment] = [] {
        didSet { updateLiveTranscriptCaches(previous: oldValue, current: liveSegments) }
    }
    @Published var detectedSpeakers: Set<Int> = []  // Track unique speakers
    private var liveTranscriptRevision: UInt64 = 0
    private var cachedFullTranscript = ""
    private var cachedSpeakerIDTranscript = ""
    private var cachedSaveSegments: [LiveSegmentSaveSnapshot] = []
    private var lastPeriodicSaveRequestedFingerprint: Int?
    private var trainingMetricsTask: Task<Void, Never>?
    
    // MARK: - UI State
    @Published var showSettings = false
    @Published var selectedTab: Tab = .transcript
    @Published var isGeneratingInsights = false
    @Published var isLiveInsightsCollapsed = UserDefaults.standard.bool(forKey: "mainWindow.insightsCollapsed") {
        didSet {
            UserDefaults.standard.set(isLiveInsightsCollapsed, forKey: "mainWindow.insightsCollapsed")
        }
    }
    @Published var isMonitoring = false  // Audio monitoring active (home screen)
    @Published var audioRecoveryState: AudioRecoveryState = .healthy

    var interimText: String {
        get { transcriptRuntime.interimText }
        set { transcriptRuntime.interimText = newValue }
    }

    var currentSpeaker: Int {
        get { transcriptRuntime.currentSpeaker }
        set { transcriptRuntime.currentSpeaker = newValue }
    }

    var interimSpeaker: Int? {
        get { transcriptRuntime.interimSpeaker }
        set { transcriptRuntime.interimSpeaker = newValue }
    }

    var audioLevel: Float {
        audioLevels.combinedLevel
    }

    var microphoneLevel: Float {
        audioLevels.microphoneLevel
    }

    var systemAudioLevel: Float {
        audioLevels.systemAudioLevel
    }
    
    // MARK: - Insights Mode
    @Published var insightsMode: InsightsMode = .standard
    @Published var trainingMetrics: TrainingMetrics?
    
    // MARK: - Live Notes
    @Published var liveNotes: String = ""
    
    // MARK: - Live Insights
    @Published var liveSummary: String = ""
    @Published var liveActionItems: [String] = []
    @Published var liveTopics: [String] = []
    @Published var liveDiscussionFlow: [String] = []
    // MEDDPICC fields
    @Published var liveMetrics: String? = nil
    @Published var liveEconomicBuyer: String? = nil
    @Published var liveDecisionCriteria: String? = nil
    @Published var liveDecisionProcess: String? = nil
    @Published var livePaperProcess: String? = nil
    @Published var liveIdentifiedPain: String? = nil
    @Published var liveChampion: String? = nil
    @Published var liveCompetition: String? = nil
    // Questions
    @Published var liveQuestions: [SuggestedQuestion] = []
    // Docs topics: an updating list of lookup-worthy subjects extracted from the
    // transcript. Each topic is looked up independently (auto for Pro/BYOK,
    // manual for managed-free), rather than one bulk fetch of the transcript.
    @Published var liveDocTopics: [DocTopic] = []
    // True while the docs-topic extraction pass is running.
    @Published var isExtractingDocsTopics = false
    // User-facing message when topic extraction or a lookup failed (nil = no error).
    @Published var docsLookupError: String? = nil
    // Inferred speaker names: [speakerID as string: name]
    @Published var liveSpeakerNames: [String: String] = [:]
    // Speaker IDs the user has manually named. Inference will not overwrite these.
    @Published var liveSpeakerOverrides: Set<String> = []
    // Speaker IDs the user has marked as themselves. Empty = platform default (mic on macOS).
    // Supports multiple IDs so split diarization (one person across two IDs) can be unified.
    @Published var liveSelfSpeakerIDs: Set<Int> = []

    // MARK: - Zoned Out catch-up (user-triggered, one-shot)
    @Published var zonedOutCatchUp: CatchUpResult?
    @Published var isGeneratingCatchUp: Bool = false
    @Published var zonedOutCatchUpError: String?
    @Published var isZonedOutPresented: Bool = false
    @Published var zonedOutCatchUpGeneratedAt: Date?
    private var activeCatchUpTask: Task<Void, Never>?
    private let catchUpRecentWindowSeconds: TimeInterval = 180
    /// Minimum finalized segments before the "i zoned out" button becomes usable.
    private let catchUpTriggerMinSegments: Int = 2
    /// Fallback floor for the window passed to the LLM in quiet meetings — we always
    /// include at least this many trailing segments even if they fall outside the window.
    private let catchUpFallbackWindowSegments: Int = 8

    private var lastInsightSegmentCount = 0
    private let firstInsightThreshold = 3 // First insight after 3 sentences
    private let insightUpdateThreshold = 8 // Subsequent updates every 8 sentences
    
    // MARK: - MEDDPICC Tracking
    private var lastMEDDPICCSegmentCount = 0
    private var lastMEDDPICCRequestAt: Date? = nil
    private let firstMEDDPICCInsightThreshold = 6
    private let meddpiccInsightUpdateThreshold = 12
    private let meddpiccMinUpdateInterval: TimeInterval = 60
    
    // MARK: - Questions Tracking
    private var lastQuestionsSegmentCount = 0
    private var lastQuestionsRequestAt: Date? = nil
    private let firstQuestionsInsightThreshold = 6
    private let questionsInsightUpdateThreshold = 12
    private let questionsMinUpdateInterval: TimeInterval = 60

    // MARK: - Speaker Names Tracking
    private var lastSpeakerNamesSegmentCount = 0
    private var lastSpeakerNamesRequestAt: Date? = nil
    /// First inference fires once enough of the meeting has happened for names to show up.
    private let firstSpeakerNamesThreshold = 8
    /// Subsequent inferences are rare — names don't change often.
    private let speakerNamesUpdateThreshold = 40
    private let speakerNamesMinUpdateInterval: TimeInterval = 120
    private var isGeneratingSpeakerNames = false
    
    // MARK: - Title Updates
    private var lastTitleUpdateCount = 0
    private let titleUpdateThreshold = 15 // Update title less often (every 15 segments)
    private var currentTitleSuffix: String = ""
    private var lastStandardSummaryContext: String = ""
    private var lastMeddpiccSummaryContext: String = ""
    private let managedIncrementalRecentWindowChars = 10_000
    // The managed backend supports the same delta + rolling-state transport for
    // Questions as standard and MEDDPICC, including degraded-response preservation.
    private let managedQuestionsIncrementalEnabled = true
    private var managedStandardAckedSegmentCount = 0
    private var managedMeddpiccAckedSegmentCount = 0
    private var managedQuestionsAckedSegmentCount = 0
    private var standardRequestSeq = 0
    private var meddpiccRequestSeq = 0
    private var questionsRequestSeq = 0
    private var lastAppliedStandardSeq = -1
    private var lastAppliedMeddpiccSeq = -1
    private var lastAppliedQuestionsSeq = -1
    private var standardSuccessCount = 0
    private var meddpiccSuccessCount = 0
    private var questionsSuccessCount = 0
    private var docsSuccessCount = 0
    private var docsRequestSeq = 0
    // Docs-topic extraction throttle (cadence-driven while docs tab is active).
    private var lastDocsTopicsRequestAt: Date?
    private var docsTopicsLastFiredSegmentCount = 0
    private let docsTopicsMinInterval: TimeInterval = 20
    // Skip topic extraction below this transcript length: too little to extract
    // anything useful, and the managed backend rejects tiny transcripts with 400.
    // Matches the BYOK `InsightsService.extractDocsTopics` guard.
    private let docsMinTranscriptChars = 40
    // Topic ids with an in-flight lookup, to bound auto-lookup concurrency.
    private var docsLookupInFlight: Set<String> = []
    private let maxConcurrentDocsLookups = 2
    private var standardCadenceAnchor: Date?
    private var meddpiccCadenceAnchor: Date?
    private var questionsCadenceAnchor: Date?
    private var standardLastAttemptAt: Date?
    private var meddpiccLastAttemptAt: Date?
    private var questionsLastAttemptAt: Date?
    private var lastWarmupInsightsAttemptAt: Date?
    private var standardLastFiredSegmentCount = 0
    private var meddpiccLastFiredSegmentCount = 0
    private var questionsLastFiredSegmentCount = 0
    private var insightsCadenceTask: Task<Void, Never>?
    private let standardCadencePolicy = LiveInsightCadencePolicy(
        minimumInterval: 60,
        minimumSegmentDelta: 4,
        maximumInterval: 120
    )
    private let meddpiccCadencePolicy = LiveInsightCadencePolicy(
        minimumInterval: 90,
        minimumSegmentDelta: 8,
        maximumInterval: 180
    )
    private let questionsCadencePolicy = LiveInsightCadencePolicy(
        minimumInterval: 60,
        minimumSegmentDelta: 6,
        maximumInterval: 120
    )
    private let warmupInsightsRetryInterval: TimeInterval = 30
    private let meddpiccCadenceStagger: TimeInterval = 15
    private let questionsCadenceStagger: TimeInterval = 22
    
    // MARK: - App Mode (persisted)
    /// Raw storage — use `appMode` computed property for type-safe access.
    @AppStorage("appMode") var appModeRaw: String = AppMode.managed.rawValue
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("hasAcceptedTerms") private var legacyHasAcceptedTerms: Bool = false
    @AppStorage("acceptedTermsVersion") private var acceptedTermsVersion: Int = 0
    private let currentTermsVersion = 1

    var hasAcceptedTerms: Bool {
        get { acceptedTermsVersion >= currentTermsVersion }
        set {
            if newValue {
                acceptedTermsVersion = currentTermsVersion
                legacyHasAcceptedTerms = true
            } else {
                acceptedTermsVersion = 0
                legacyHasAcceptedTerms = false
            }
        }
    }
    
    /// Type-safe app mode. Changing this is a pure routing toggle — doesn't reset anything.
    var appMode: AppMode {
        get { AppMode(rawValue: appModeRaw) ?? .managed }
        set { appModeRaw = newValue.rawValue }
    }
    
    // MARK: - Markdown Auto-Export (macOS only)
    #if os(macOS)
    @AppStorage("autoExportMarkdown") var autoExportMarkdown: Bool = false
    @AppStorage("markdownExportFolderPath") var markdownExportFolderPath: String = ""
    @AppStorage("markdownExportBookmark") var markdownExportBookmarkData: Data = Data()
    @AppStorage("generateAgentsMd") var generateAgentsMd: Bool = false
    #endif

    // MARK: - Update Check
    @Published var availableUpdate: MinitiAPIService.VersionInfo?
    @Published var requiresForceUpdate = false
    
    // MARK: - Managed Mode State
    @Published var usageInfo: MinitiAPIService.UsageInfo?
    @Published var isLoadingUsage = false
    @Published var managedSessionError: String?
    @Published var isDeviceDisabled = false
    #if os(iOS)
    @Published var hasActiveAppStoreSubscription = false
    #endif
    private var currentSessionId: String?
    private var managedDeepgramAccessToken: String?
    private var managedDeepgramTokenExpiresAt: Date?
    private var managedDeepgramTokenType: String = "Bearer"
    private var managedSessionStartRecordedDuration: TimeInterval?
    
    /// Refresh managed JWTs this far before `expires_at` so reconnects don't race expiry.
    nonisolated static let managedDeepgramTokenRefreshSkew: TimeInterval = 60
    
    /// Whether a stored managed Deepgram JWT is still usable for a new WebSocket handshake.
    nonisolated static func isManagedDeepgramCredentialFresh(
        token: String?,
        expiresAt: Date?,
        now: Date = Date(),
        skew: TimeInterval = managedDeepgramTokenRefreshSkew
    ) -> Bool {
        guard let token, !token.isEmpty, let expiresAt else { return false }
        return now < expiresAt.addingTimeInterval(-skew)
    }
    
    private var hasFreshManagedDeepgramCredential: Bool {
        Self.isManagedDeepgramCredentialFresh(
            token: managedDeepgramAccessToken,
            expiresAt: managedDeepgramTokenExpiresAt
        )
    }
    
    /// Whether managed mode is at its limit.
    var isLimitReached: Bool {
        guard appMode == .managed else { return false }
        #if os(iOS)
        if hasActiveAppStoreSubscription {
            return false
        }
        #endif
        return usageInfo?.isLimitReached ?? false
    }
    
    /// Whether the device has an active Pro subscription.
    var isPro: Bool {
        let backendPro = usageInfo?.isPro ?? false
        #if os(iOS)
        return backendPro || hasActiveAppStoreSubscription
        #else
        return backendPro
        #endif
    }

    /// True after first non-degraded standard insights response (for warmup placeholder).
    var hasReceivedStandardInsights: Bool { standardSuccessCount > 0 }
    /// True after first non-degraded MEDDPICC insights response (for warmup placeholder).
    var hasReceivedMeddpiccInsights: Bool { meddpiccSuccessCount > 0 }
    var hasReceivedQuestionsInsights: Bool { questionsSuccessCount > 0 }
    var hasReceivedDocsInsights: Bool { docsSuccessCount > 0 }

    /// Core views are always available. Specialist views become active only after a person
    /// explicitly chooses them; configuring a Docs MCP also opts Playbook in automatically.
    var enabledInsightModes: [InsightsMode] {
        InsightsMode.coreModes + InsightsMode.specialistModes.filter(isInsightModeEnabled)
    }

    func isInsightModeEnabled(_ mode: InsightsMode) -> Bool {
        switch mode {
        case .standard, .training, .questions:
            return true
        case .meddpicc:
            return salesInsightsEnabled
        case .docs:
            return playbookInsightsEnabled
        }
    }

    func setInsightModeEnabled(_ mode: InsightsMode, enabled: Bool) {
        switch mode {
        case .standard, .training, .questions:
            return
        case .meddpicc:
            salesInsightsEnabled = enabled
        case .docs:
            playbookInsightsEnabled = enabled
        }

        if !enabled, insightsMode == mode {
            insightsMode = .standard
        }
    }

    /// Docs topics can be looked up from live segments or the persisted transcript,
    /// so a stopped meeting with no live segments can still be looked up.
    var canLookupDocs: Bool {
        guard let meeting = currentMeeting else { return false }
        return !liveSegments.isEmpty || !meeting.fullTranscript.isEmpty
    }

    /// Whether topics should be auto-looked-up as they appear. BYOK pays its own
    /// MCP + LLM (and never hits our backend), so it gets auto alongside Pro;
    /// managed-free looks topics up manually against a metered monthly quota.
    var canAutoLookupDocs: Bool {
        validatedDocsMCPURL != nil && (isPro || appMode == .byok)
    }

    /// Remaining metered docs lookups this period for managed-free users, or nil
    /// when unmetered (Pro, BYOK, or backend hasn't reported a cap yet).
    var docsLookupsRemaining: Int? {
        guard appMode == .managed, !isPro else { return nil }
        return usageInfo?.docsLookupsRemaining
    }

    /// True when a managed-free user has exhausted their monthly docs lookups.
    var docsLookupQuotaReached: Bool {
        (docsLookupsRemaining ?? Int.max) <= 0
    }

    /// Trimmed docs MCP URL when valid https; otherwise nil (feature off).
    var validatedDocsMCPURL: String? {
        let trimmed = docsMCPURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? DocsMCPService.validateMCPURL(trimmed))?.absoluteString
    }

    /// Whether managed subscription state is still being resolved.
    var shouldShowManagedSubscriptionPlaceholder: Bool {
        guard appMode == .managed, usageInfo == nil, isLoadingUsage else { return false }
        #if os(iOS)
        if hasActiveAppStoreSubscription {
            return false
        }
        #endif
        return true
    }
    
    /// Managed mode minutes limit displayed in UI.
    var displayMinutesLimit: Double {
        guard appMode == .managed else { return 0 }
        #if os(iOS)
        if hasActiveAppStoreSubscription {
            return 5000
        }
        #endif
        if let serverLimit = usageInfo?.minutesLimit {
            return serverLimit
        }
        return isPro ? 5000 : 500
    }
    
    /// Managed mode minutes used displayed in UI.
    var displayMinutesUsed: Double {
        usageInfo?.minutesUsed ?? 0
    }
    
    /// Managed mode minutes remaining displayed in UI.
    var displayMinutesRemaining: Double {
        max(0, displayMinutesLimit - displayMinutesUsed)
    }
    
    /// Managed mode usage bar value displayed in UI.
    var displayUsagePercentage: Double {
        guard displayMinutesLimit > 0 else { return 0 }
        return min(1.0, displayMinutesUsed / displayMinutesLimit)
    }
    
    /// Managed mode compact remaining-time string used in UI.
    var formattedDisplayRemaining: String {
        let rounded = Int(displayMinutesRemaining.rounded())
        if rounded >= 60 {
            let hours = rounded / 60
            let mins = rounded % 60
            return "\(hours)h \(mins)m"
        }
        return "\(rounded)m"
    }
    
    /// Whether the app can start recording right now.
    var canStartRecording: Bool {
        guard !isFinalizingMeeting else { return false }
        switch appMode {
        case .byok:
            return !deepgramApiKey.isEmpty
        case .managed:
            return !isDeviceDisabled && !isLimitReached
        }
    }
    
    // MARK: - Services
    var audioCaptureService: AudioCaptureService?
    var deepgramService: DeepgramService?
    var insightsService: InsightsService?
    var minitiAPIService: MinitiAPIService?
    #if os(iOS)
    var storeKitService: AppStoreSubscriptionService?
    #endif
    
    // MARK: - Settings (persisted via @AppStorage)
    @AppStorage("deepgramApiKey") var deepgramApiKey: String = "" {
        didSet { updateLogRedaction() }
    }
    @AppStorage("openaiApiKey") var openaiApiKey: String = "" {
        didSet { updateLogRedaction() }
    }
    @AppStorage("captureSystemAudio") var captureSystemAudio: Bool = true
    @AppStorage("captureMicrophone") var captureMicrophone: Bool = true
    @AppStorage("defaultLanguage") var defaultLanguage: String = TranscriptionLanguage.english.rawValue
    @Published var meetingLanguage: String = TranscriptionLanguage.english.rawValue
    @AppStorage("shareDiagnostics") var shareDiagnostics: Bool = false {
        didSet {
            if !shareDiagnostics {
                pendingClientEvents.removeAll()
                persistPendingClientEvents()
            } else {
                Task { await flushClientEvents(trigger: "setting enabled") }
            }
        }
    }
    @AppStorage("webhookURL") var webhookURL: String = ""
    @AppStorage("salesInsightsEnabled") var salesInsightsEnabled: Bool = false
    @AppStorage("playbookInsightsEnabled") var playbookInsightsEnabled: Bool = false
    @AppStorage("docsMCPURL") var docsMCPURL: String = "" {
        didSet {
            if validatedDocsMCPURL != nil {
                playbookInsightsEnabled = true
            } else {
                setInsightModeEnabled(.docs, enabled: false)
            }
        }
    }
    @AppStorage("autoStopMinutes") var autoStopMinutes: Int = 5
    @AppStorage("googleCalendarEnabled") var googleCalendarEnabled: Bool = false
    @AppStorage("autoAttioSync") var autoAttioSync: Bool = false
    @AppStorage("autoStartFromCalendar") var autoStartFromCalendar: Bool = false
    @AppStorage("autoStopFromCalendar") var autoStopFromCalendar: Bool = false
    @AppStorage("notifyOnIncisiveQuestions") var notifyOnIncisiveQuestions: Bool = false
    @AppStorage("notifyOnMonologue") var notifyOnMonologue: Bool = false
    @AppStorage("notifyOnHighFillerRate") var notifyOnHighFillerRate: Bool = false
    @AppStorage("notifyOnUpcomingMeeting") var notifyOnUpcomingMeeting: Bool = false
    @AppStorage("autoInferSpeakerNames") var autoInferSpeakerNames: Bool = true
    /// Timestamp (TimeInterval since 1970) after which the calendar nudge card on the
    /// home screen should stop being hidden. 0 = never dismissed. `.infinity` (or any
    /// value > 10 years from now) = permanently dismissed via the `×` button.
    @AppStorage("calendarNudgeDismissedUntil") var calendarNudgeDismissedUntil: Double = 0

    private var notifiedQuestionIDs: Set<String> = []
    private var lastQuestionNotificationAt: Date?
    private static let questionNotificationMinInterval: TimeInterval = 120 // 2 minutes

    // Real-time nudges (local, no LLM)
    private var lastMonologueNudgeAt: Date?
    private var lastFillerNudgeAt: Date?
    private var monologueNudgedForRun: Bool = false
    private var lastEvaluatedFinalSegmentID: UUID?
    /// Cached pre-tokenized filler phrases for the current meeting language.
    /// Rebuilt lazily when `meetingLanguage` changes or the meeting resets.
    private var cachedFillerTokensLanguage: String?
    private var cachedFillerTokens: [[String]] = []
    nonisolated private static let monologueNudgeMinInterval: TimeInterval = 180   // 3 minutes between monologue nudges
    nonisolated private static let fillerNudgeMinInterval: TimeInterval = 180       // 3 minutes between filler nudges
    nonisolated private static let monologueMinSeconds: TimeInterval = 60           // sustained for at least 60s of "You"
    nonisolated private static let monologueMinWords: Int = 180                     // and at least ~180 words
    nonisolated private static let fillerWindowSeconds: TimeInterval = 60           // rolling filler-rate window
    nonisolated private static let fillerNudgeMinFillersPerMinute: Double = 8       // threshold (you-only)
    nonisolated private static let fillerWindowMinYouWords: Int = 20                // don't nudge on a few words
    
    @Published var isGoogleCalendarConnected: Bool = false
    @Published var googleCalendarEmail: String?
    @Published var upcomingEvents: [MinitiAPIService.CalendarEvent] = []
    @Published var selectedCalendarEvent: MinitiAPIService.CalendarEvent?

    var todayEvents: [MinitiAPIService.CalendarEvent] {
        let calendar = Calendar.current
        return upcomingEvents.filter { event in
            guard let start = event.startDate else { return false }
            return calendar.isDateInToday(start)
        }
    }

    var nextEvent: MinitiAPIService.CalendarEvent? {
        let now = Date()
        return todayEvents.first { event in
            guard let end = event.endDate else { return false }
            return end > now
        }
    }
    @Published var pendingAutoStartEvent: MinitiAPIService.CalendarEvent?
    @Published var autoStartCountdown: Int = 0
    @Published var calendarEventEndedWhileRecording: Bool = false
    private var calendarRefreshTimer: Timer?
    private var autoStartCheckTimer: Timer?
    private var autoStartCountdownTimer: Timer?
    private var dismissedAutoStartEventIDs: Set<String> = []
    
    @Published var wasAutoStopped = false
    @Published var autoStopReason: AutoStopReason?
    @Published var selectedSettingsTab: String = "general"
    
    private var recordingTimer: Timer?
    private var periodicSaveTimer: Timer?
    private var transcriptHealthTimer: Timer?
    private var autoStopTimer: Timer?
    private var lastTranscriptReceivedAt: CFAbsoluteTime = 0
    private var lastTranscriptStarvationRecoveryAt: CFAbsoluteTime = 0
    /// Reconnects since the last time words actually came back. Drives the recovery backoff.
    private var consecutiveTranscriptRecoveries = 0
    private var lastTranscriptHealthDebugLogAt: CFAbsoluteTime = 0
    /// Last time audio was loud enough to plausibly be speech. Tracked continuously from the
    /// level stream rather than sampled inside the 30s auto-stop tick, which would be just as
    /// likely to land in a pause between words as on someone actually talking.
    private var lastAudioActivityAt: CFAbsoluteTime = 0
    static let speechMicLevelThreshold: Float = 0.008
    static let speechSystemLevelThreshold: Float = 0.006
    private var deepgramReconnectTask: Task<Void, Never>?
    private var deepgramReconnectGeneration = 0
    private var lastDeepgramReconnectScheduledAt: CFAbsoluteTime = 0
    private var pendingMicSegments: [PendingMicSegment] = []
    private var recentSystemSegments: [BufferedSystemSegment] = []
    private var pendingMicFlushTask: Task<Void, Never>?
    private let micEchoReconciliationDelay: TimeInterval = 4
    private let echoSystemHistoryWindow: TimeInterval = 8
    private var pendingAudioRecoveryTransitionTask: Task<Void, Never>?
    private var desiredAudioRecoveryState: AudioRecoveryState = .healthy
    private var systemAudioInactiveSince: CFAbsoluteTime = 0
    private let pendingSessionReportsDefaultsKey = "pendingSessionEndReports"
    private var pendingSessionEndReports: [PendingSessionEndReport] = []
    private let pendingClientEventsDefaultsKey = "pendingClientEvents"
    private var pendingClientEvents: [MinitiAPIService.ClientEventPayload] = []
    private var clientEventsFlushTask: Task<Void, Never>?
    private let diagnosticsSessionId = UUID().uuidString
    private var isFlushingPendingSessionReports = false
    private var recordingStartDate: Date?
    private var accumulatedRecordedDuration: TimeInterval = 0
    private var activeMeetingSaveTask: Task<Void, Never>?
    private var queuedMeetingSavePayload: MeetingSavePayload?
    /// Meetings the user discarded or deleted from history. Async work that was already in flight
    /// must never write one back.
    private var deletedMeetingIDs: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    
    #if os(iOS)
    private var currentActivity: Activity<RecordingActivityAttributes>?
    private var lastLiveActivityUpdate: Date = .distantPast
    private let liveActivityUpdateInterval: TimeInterval = 3 // Throttle: max 1 update per 3s
    #endif
    
    enum Tab: String, CaseIterable {
        case transcript = "Transcript"
        case insights = "Insights"
    }
    
    struct LiveSegment: Identifiable, Equatable {
        let id: UUID
        var text: String
        let speaker: Int
        let timestamp: TimeInterval
        var isFinal: Bool
        
        /// Whether this segment came from the local microphone (vs system/remote audio).
        var isLocalMic: Bool {
            speaker == DeepgramService.micSpeakerID
        }
        
        var speakerLabel: String {
            isLocalMic ? "You" : "Speaker \(speaker + 1)"
        }
    }

    enum FinalSegmentMergeResult: Equatable {
        case appended
        case replacedSuperset
        case skippedExactDuplicate
        case skippedContainedDuplicate
    }

    nonisolated static func mergeFinalSegment(
        _ newSegment: LiveSegment,
        into segments: inout [LiveSegment],
        duplicateSearchSuffix: Int = 3
    ) -> FinalSegmentMergeResult {
        let searchStart = max(0, segments.count - duplicateSearchSuffix)
        var containedMatchIndex: Int?

        for index in searchStart..<segments.count {
            let existing = segments[index]
            guard existing.isFinal, existing.speaker == newSegment.speaker else { continue }
            if existing.text == newSegment.text {
                return .skippedExactDuplicate
            }
            if existing.text.contains(newSegment.text) {
                return .skippedContainedDuplicate
            }
            if newSegment.text.contains(existing.text) {
                containedMatchIndex = index
            }
        }

        if let containedMatchIndex {
            let existing = segments[containedMatchIndex]
            segments[containedMatchIndex] = LiveSegment(
                id: existing.id,
                text: newSegment.text,
                speaker: existing.speaker,
                timestamp: existing.timestamp,
                isFinal: true
            )
            return .replacedSuperset
        }

        segments.append(newSegment)
        return .appended
    }

    /// Preserve transcript text that was visible as an interim when a recording stopped but the
    /// streaming socket could not deliver a final result. The normal final-segment merge keeps
    /// this fallback from duplicating a final that arrived during graceful shutdown.
    @discardableResult
    nonisolated static func mergeStoppedInterimTranscript(
        _ text: String,
        speaker: Int,
        timestamp: TimeInterval,
        into segments: inout [LiveSegment]
    ) -> FinalSegmentMergeResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return mergeFinalSegment(
            LiveSegment(
                id: UUID(),
                text: trimmed,
                speaker: speaker,
                timestamp: timestamp,
                isFinal: true
            ),
            into: &segments
        )
    }

    /// Returns true when a mic transcript is best explained by acoustic playback
    /// leaking from the system channel into the microphone. Text/time agreement is
    /// the primary signal; source energy only relaxes the threshold for short or
    /// imperfect matches so genuine overlapping local speech is preserved.
    nonisolated static func isLikelyMicEcho(
        mic: EchoComparisonSegment,
        systemSegments: [EchoComparisonSegment],
        systemDominant: Bool,
        timePadding: TimeInterval = 0.8
    ) -> Bool {
        let overlapping = systemSegments.filter {
            $0.endTime >= mic.startTime - timePadding &&
            $0.startTime <= mic.endTime + timePadding
        }.sorted { $0.startTime < $1.startTime }
        guard !overlapping.isEmpty else { return false }

        let micTokens = echoTokens(mic.text)
        guard !micTokens.isEmpty else { return false }
        let systemTokens = echoTokens(overlapping.map(\.text).joined(separator: " "))
        guard !systemTokens.isEmpty else { return false }

        let matched = longestCommonSubsequenceLength(micTokens, systemTokens)
        let longestContiguousMatch = longestCommonContiguousTokenRun(micTokens, systemTokens)
        let micCoverage = Double(matched) / Double(micTokens.count)

        if micTokens.count <= 2 {
            // Short interjections are easy to match by accident. Only suppress an
            // exact ordered match while the clean system source is dominant.
            return systemDominant && matched == micTokens.count
        }

        // Near-verbatim duplicates are safe to suppress even when speaker volume
        // makes the mic energy look strong. For fuzzier ASR variants, require the
        // clean system source to be dominant as corroborating evidence. A three-word
        // contiguous run catches leakage where one channel invents a different tail
        // (for example "nobody alive today, though" vs "nobody alive today will...")
        // without matching scattered conversational stop words.
        if matched >= 3 && micCoverage >= 0.84 { return true }
        return systemDominant && matched >= 3 && (
            micCoverage >= 0.66 ||
            (longestContiguousMatch >= 3 && micCoverage >= 0.60)
        )
    }

    nonisolated private static func echoTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    nonisolated private static func longestCommonSubsequenceLength(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: rhs.count + 1)
        var current = previous

        for left in lhs {
            current[0] = 0
            for index in rhs.indices {
                if left == rhs[index] {
                    current[index + 1] = previous[index] + 1
                } else {
                    current[index + 1] = max(previous[index + 1], current[index])
                }
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    nonisolated private static func longestCommonContiguousTokenRun(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: rhs.count + 1)
        var longest = 0

        for left in lhs {
            var current = [Int](repeating: 0, count: rhs.count + 1)
            for index in rhs.indices where left == rhs[index] {
                current[index + 1] = previous[index] + 1
                longest = max(longest, current[index + 1])
            }
            previous = current
        }
        return longest
    }
    
    init() {
        // One-time migration from legacy boolean acceptance storage.
        if acceptedTermsVersion == 0, legacyHasAcceptedTerms {
            acceptedTermsVersion = 1
        }

        // Existing Docs users have already expressed intent by configuring an MCP URL. Preserve
        // that intent on the first launch with specialist-view preferences.
        if UserDefaults.standard.object(forKey: "playbookInsightsEnabled") == nil,
           validatedDocsMCPURL != nil {
            playbookInsightsEnabled = true
        }

        // Seed default keys from Secrets.swift only in BYOK mode.
        // In managed mode, API calls go through the backend — user should
        // never see or need the app's own API keys.
        if appMode == .byok {
            if deepgramApiKey.isEmpty {
                deepgramApiKey = Secrets.deepgramApiKey
            }
            if openaiApiKey.isEmpty {
                openaiApiKey = Secrets.openaiApiKey
            }
        } else {
            // Managed mode: strip out Secrets defaults if they were previously
            // seeded (e.g., user started in BYOK, switched to managed).
            // User-entered keys (different from Secrets) are left untouched.
            if deepgramApiKey == Secrets.deepgramApiKey {
                deepgramApiKey = ""
            }
            if openaiApiKey == Secrets.openaiApiKey {
                openaiApiKey = ""
            }
        }
        setupServices()
        updateLogRedaction()
        pendingSessionEndReports = loadPendingSessionEndReports()
        pendingClientEvents = loadPendingClientEvents()
        
        // Load usage info for managed mode
        if appMode == .managed {
            isLoadingUsage = true
            Task {
                await refreshUsage()
                await flushPendingSessionEndReports(trigger: "launch")
                await flushClientEvents(trigger: "launch")
            }
        }
        
        // Check for app updates (all modes)
        Task { await checkForUpdates() }
        
        // Check Google Calendar connection and fetch events
        Task {
            await refreshGoogleCalendarStatus()
            startCalendarRefreshTimer()
            startAutoStartMonitoring()
        }
        
        #if os(iOS)
        // Clean up orphaned Live Activities (app was killed while recording, state lost)
        Task { await cleanupOrphanedLiveActivities() }
        #endif
    }
    
    private func updateLogRedaction() {
        DebugLogger.shared.setRedactPatterns([deepgramApiKey, openaiApiKey])
    }
    
    private func setupServices() {
        audioCaptureService = AudioCaptureService()
        deepgramService = DeepgramService()
        insightsService = InsightsService()
        minitiAPIService = MinitiAPIService()
        #if os(iOS)
        let storeKitService = AppStoreSubscriptionService()
        self.storeKitService = storeKitService
        storeKitService.$hasActiveSubscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasActive in
                guard let self else { return }
                let changed = self.hasActiveAppStoreSubscription != hasActive
                self.hasActiveAppStoreSubscription = hasActive
                if changed && self.appMode == .managed {
                    Task { await self.refreshUsage() }
                }
            }
            .store(in: &cancellables)
        #endif
        
        // Subscribe to transcript updates (handles both interim and final)
        deepgramService?.$transcriptUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let update else { return }
                self?.handleTranscriptUpdate(update)
            }
            .store(in: &cancellables)
        
        // Subscribe to speaker-segmented results for better speaker tracking
        deepgramService?.$speakerSegments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] segments in
                self?.handleSpeakerSegments(segments)
            }
            .store(in: &cancellables)
        
        deepgramService?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDeepgramConnectionState(state)
            }
            .store(in: &cancellables)
        
        // Coalesce the independently sampled mic/system meters into one UI update.
        // The services already cap each source at ~20 Hz; this keeps the combined
        // stream at that same display cadence instead of publishing 3–4 times per pair.
        if let audioService = audioCaptureService {
            audioService.$microphoneLevel
                .combineLatest(audioService.$systemAudioLevel)
                .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] micLevel, sysLevel in
                    guard let self else { return }
                    self.audioLevels.update(
                        microphoneLevel: micLevel,
                        systemAudioLevel: sysLevel
                    )
                    if micLevel > Self.speechMicLevelThreshold
                        || (self.captureSystemAudio && sysLevel > Self.speechSystemLevelThreshold) {
                        self.lastAudioActivityAt = CFAbsoluteTimeGetCurrent()
                    }
                }
                .store(in: &cancellables)
            
            #if os(macOS)
            audioService.$isSystemAudioActive
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isActive in
                    guard let self else { return }
                    guard self.captureSystemAudio else {
                        self.systemAudioInactiveSince = 0
                        self.updateAudioRecoveryState()
                        return
                    }
                    if isActive {
                        self.systemAudioInactiveSince = 0
                    } else if self.isRecording {
                        if self.systemAudioInactiveSince == 0 {
                            self.systemAudioInactiveSince = CFAbsoluteTimeGetCurrent()
                        }
                    } else {
                        self.systemAudioInactiveSince = 0
                    }
                    self.updateAudioRecoveryState()
                }
                .store(in: &cancellables)
            #endif
        }
    }
    
    private func handleTranscriptUpdate(_ update: DeepgramService.TranscriptUpdate) {
        // Skip empty updates
        guard !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastTranscriptReceivedAt = CFAbsoluteTimeGetCurrent()
        
        if update.isFinal {
            // Final result - will be handled by speaker segments for better accuracy
            transcriptRuntime.update(
                interimText: "",
                currentSpeaker: currentSpeaker,
                interimSpeaker: nil
            )
        } else {
            #if os(macOS)
            if captureMicrophone,
               captureSystemAudio,
               update.channelIndex == DeepgramService.micChannelIndex,
               let firstWord = update.words.first,
               let lastWord = update.words.last {
                switch audioCaptureService?.dominantSource(from: firstWord.start, to: lastWord.end) {
                case .system:
                    // Do not flash playback echo as a green "You" interim. A genuine
                    // overlapping mic turn is retained once its final text has been
                    // reconciled against the system-channel transcript.
                    return
                case .mic, .unknown, .none:
                    break
                }
            }
            #endif

            // Interim result - show live typing. Publish text + speaker atomically so a
            // throttled presentation can never pair a new fragment with stale identity.
            let candidateSpeaker = update.speaker
            let lastFinalSpeaker = liveSegments.last(where: \.isFinal)?.speaker
            // Interim gating: avoid jumping to never-confirmed speakers too early.
            let canUseCandidateSpeaker =
                detectedSpeakers.isEmpty ||
                detectedSpeakers.contains(candidateSpeaker) ||
                candidateSpeaker == lastFinalSpeaker ||
                candidateSpeaker == currentSpeaker
            
            let presentedCurrentSpeaker = canUseCandidateSpeaker ? candidateSpeaker : currentSpeaker
            let presentedInterimSpeaker = canUseCandidateSpeaker ? candidateSpeaker : currentSpeaker
            transcriptRuntime.update(
                interimText: update.text,
                currentSpeaker: presentedCurrentSpeaker,
                interimSpeaker: presentedInterimSpeaker
            )
            
            // Push to Live Activity (throttled)
            #if os(iOS)
            updateLiveActivityTranscript()
            #endif
        }
    }
    
    private func handleDeepgramConnectionState(_ state: DeepgramService.ConnectionState) {
        guard isRecording else {
            updateAudioRecoveryState()
            return
        }
        
        switch state {
        case .connected:
            deepgramReconnectTask?.cancel()
            deepgramReconnectTask = nil
            deepgramReconnectGeneration += 1
            lastDeepgramReconnectScheduledAt = 0
            enqueueDiagnosticEvent("deepgram_connected", category: .deepgram)
            updateAudioRecoveryState()
        case .connecting:
            updateAudioRecoveryState()
        case .error:
            enqueueDiagnosticEvent("deepgram_connection_error", category: .deepgram, level: .error)
            scheduleDeepgramReconnect(reason: "connection error")
        case .disconnected:
            // If disconnected while recording, treat as transient and attempt reconnect.
            enqueueDiagnosticEvent("deepgram_unexpected_disconnect", category: .deepgram, level: .warning)
            scheduleDeepgramReconnect(reason: "unexpected disconnect")
        }
    }
    
    private func scheduleDeepgramReconnect(reason: String) {
        guard isRecording else { return }
        guard deepgramReconnectTask == nil else { return }
        guard let deepgramService else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDeepgramReconnectScheduledAt < 1.0 {
            DebugLogger.shared.log(.app, "Deepgram reconnect suppressed (cooldown): \(reason)")
            return
        }
        lastDeepgramReconnectScheduledAt = now
        
        deepgramReconnectGeneration += 1
        let generation = deepgramReconnectGeneration
        updateAudioRecoveryState()
        DebugLogger.shared.log(.app, "Deepgram reconnect scheduled: \(reason)")
        enqueueDiagnosticEvent(
            "deepgram_reconnect_scheduled",
            category: .deepgram,
            level: .warning,
            details: ["reason": reason]
        )
        
        deepgramReconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.deepgramReconnectTask = nil }
            let backoffSeconds: [UInt64] = [1, 2, 5]
            
            for (idx, delay) in backoffSeconds.enumerated() {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.isRecording else { return }
                guard generation == self.deepgramReconnectGeneration else { return }
                
                DebugLogger.shared.log(.app, "Deepgram reconnect attempt \(idx + 1)/\(backoffSeconds.count)")
                self.enqueueDiagnosticEvent(
                    "deepgram_reconnect_attempt",
                    category: .deepgram,
                    details: [
                        "attempt": "\(idx + 1)",
                        "max_attempts": "\(backoffSeconds.count)"
                    ]
                )
                deepgramService.disconnect()
                #if os(macOS)
                if self.captureMicrophone && self.captureSystemAudio {
                    self.resetEchoReconciliation(flushPending: true)
                    self.audioCaptureService?.resetSourceTracking()
                    self.resetSpeakerIdentityForDeepgramReconnect()
                    DebugLogger.shared.log(.app, "Source tracking reset for Deepgram reconnect")
                }
                #endif
                #if os(macOS)
                let useMultichannel = self.captureMicrophone && self.captureSystemAudio
                #else
                let useMultichannel = false
                #endif
                let configured = await self.configureDeepgramCredentialForConnect()
                guard configured else {
                    DebugLogger.shared.log(.app, "Deepgram reconnect skipped attempt \(idx + 1): credential unavailable")
                    continue
                }
                deepgramService.connect(
                    language: self.meetingLanguage,
                    personalDictionaryTerms: PersonalDictionaryPreferences.currentTerms(),
                    sessionKeyterms: self.deepgramSessionKeyterms(),
                    multichannel: useMultichannel
                )
                
                // Give the socket a short window to establish before next retry.
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    guard generation == self.deepgramReconnectGeneration else { return }
                    if deepgramService.connectionState == .connected {
                        DebugLogger.shared.log(.app, "Deepgram reconnect succeeded")
                        self.enqueueDiagnosticEvent("deepgram_reconnect_succeeded", category: .deepgram)
                        self.lastDeepgramReconnectScheduledAt = 0
                        self.updateAudioRecoveryState()
                        return
                    }
                }
            }
            
            if self.isRecording && generation == self.deepgramReconnectGeneration {
                DebugLogger.shared.log(.app, "Deepgram reconnect exhausted")
                self.enqueueDiagnosticEvent("deepgram_reconnect_exhausted", category: .deepgram, level: .error)
                self.applyAudioRecoveryState(.degraded)
            }
        }
    }
    
    private func startTranscriptHealthMonitoring() {
        transcriptHealthTimer?.invalidate()
        transcriptHealthTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTranscriptHealth()
            }
        }
    }
    
    private func stopTranscriptHealthMonitoring() {
        transcriptHealthTimer?.invalidate()
        transcriptHealthTimer = nil
    }
    
    private func startAutoStopMonitoring() {
        autoStopTimer?.invalidate()
        let hasCalendarAutoStop = autoStopFromCalendar && selectedCalendarEvent != nil
        guard autoStopMinutes > 0 || hasCalendarAutoStop else { return }
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAutoStop()
            }
        }
    }
    
    private func stopAutoStopMonitoring() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
    }
    
    enum AutoStopDecision: Equatable {
        case keepRecording
        /// Silence for the configured auto-stop window.
        case silence
        /// Silence for the shorter window that applies once the calendar event has ended.
        case calendarSilence
        /// Audio kept flowing but no transcript came back for far longer than the silence
        /// window — the pipeline is dead rather than the room being quiet.
        case stalledPipeline
    }

    /// How recently audio must have been loud enough to count as "still an active meeting".
    /// Two auto-stop ticks, so a single quiet sample can't flip the decision.
    nonisolated static let autoStopAudioActivityWindow: TimeInterval = 60
    /// Multiple of the silence window we tolerate before giving up on a stalled pipeline.
    nonisolated static let autoStopStalledPipelineMultiplier: Double = 3

    /// Pure auto-stop decision. `audioGap` is seconds since audio was last loud enough to be
    /// speech (`.infinity` if never), `transcriptGap` is seconds since the last transcript.
    nonisolated static func evaluateAutoStop(
        transcriptGap: TimeInterval,
        audioGap: TimeInterval,
        autoStopMinutes: Int,
        calendarEventEnded: Bool
    ) -> AutoStopDecision {
        let configuredWindow = autoStopMinutes > 0 ? Double(autoStopMinutes) * 60.0 : 0
        let silenceWindow: TimeInterval
        if calendarEventEnded {
            silenceWindow = configuredWindow > 0 ? min(configuredWindow, 120) : 120
        } else {
            guard configuredWindow > 0 else { return .keepRecording }
            silenceWindow = configuredWindow
        }

        // Audio still arriving means the transcript pipeline stalled (Deepgram dropped, system
        // audio not captured) rather than the meeting going quiet. Stopping here would kill a
        // live meeting under a misleading "no speech detected" label, so hold off and let
        // checkTranscriptHealth() reconnect — but still give up eventually so a permanently
        // dead pipeline can't record forever.
        if audioGap < autoStopAudioActivityWindow {
            return transcriptGap >= silenceWindow * autoStopStalledPipelineMultiplier
                ? .stalledPipeline
                : .keepRecording
        }

        guard transcriptGap >= silenceWindow else { return .keepRecording }
        return calendarEventEnded ? .calendarSilence : .silence
    }

    enum TranscriptHealthAction: Equatable {
        case none
        /// The socket claims to be connected but no words are coming back.
        case reconnectStarvation
        /// Reconnect attempts already gave up and the socket is still down while audio flows.
        case reconnectAfterExhaustion
    }

    /// Outer bound on how stale audio activity can be before a transcript gap is just a quiet room.
    nonisolated static let transcriptHealthAudioActivityWindow: TimeInterval = 60
    /// Slack for the delay between someone speaking and Deepgram finalizing those words, so normal
    /// end-of-turn latency never reads as a stall.
    nonisolated static let transcriptFinalizeLatencyMargin: TimeInterval = 5
    /// Transcript gap that counts as starvation while audio is still arriving.
    nonisolated static let transcriptStarvationGap: TimeInterval = 20
    nonisolated static let transcriptStarvationCooldown: TimeInterval = 30
    /// Longer cooldown for retrying after the backoff ladder gave up, so a genuinely dead network
    /// isn't hammered every health tick.
    nonisolated static let transcriptExhaustedRetryCooldown: TimeInterval = 60
    nonisolated static let transcriptRecoveryMaxCooldown: TimeInterval = 600

    /// Cooldown after `consecutiveRecoveries` reconnects that produced no transcript. Reconnecting
    /// isn't free (it drops the socket and resets macOS multichannel speaker identity), so when it
    /// keeps not helping — a room whose ambient noise clears the speech threshold, say — back off
    /// instead of churning every 30s for the rest of the meeting.
    nonisolated static func transcriptRecoveryCooldown(
        base: TimeInterval,
        consecutiveRecoveries: Int
    ) -> TimeInterval {
        let factor = pow(2.0, Double(min(max(consecutiveRecoveries, 0), 5)))
        return min(base * factor, transcriptRecoveryMaxCooldown)
    }

    /// Pure transcript-health decision. Gaps are in seconds, `.infinity` when the corresponding
    /// event has never happened.
    nonisolated static func evaluateTranscriptHealth(
        transcriptGap: TimeInterval,
        audioGap: TimeInterval,
        sinceLastRecoveryAttempt: TimeInterval,
        consecutiveRecoveries: Int = 0,
        isConnected: Bool,
        isConnecting: Bool,
        hasPendingReconnect: Bool
    ) -> TranscriptHealthAction {
        // Judge audio from the level stream's timestamp, never from an instantaneous sample, which
        // is as likely to land in a pause between words as on speech. The signal for a stall is
        // relative rather than absolute: someone spoke *after* the last words came back. Comparing
        // against a fixed recency window instead would reconnect during any ordinary pause that
        // outlasts the starvation gap.
        guard audioGap < transcriptHealthAudioActivityWindow else { return .none }
        guard transcriptGap > transcriptStarvationGap else { return .none }
        guard audioGap + transcriptFinalizeLatencyMargin < transcriptGap else { return .none }
        guard !hasPendingReconnect, !isConnecting else { return .none }

        let base = isConnected ? transcriptStarvationCooldown : transcriptExhaustedRetryCooldown
        let cooldown = transcriptRecoveryCooldown(base: base, consecutiveRecoveries: consecutiveRecoveries)
        guard sinceLastRecoveryAttempt > cooldown else { return .none }

        // Connected but starving means a zombie socket. Not connected with nothing retrying means
        // the backoff ladder has already been exhausted — reconnects are otherwise only triggered
        // by a connection-state *transition*, so without this the transcript stays dead for the
        // rest of the meeting.
        return isConnected ? .reconnectStarvation : .reconnectAfterExhaustion
    }

    /// Seconds since audio was last loud enough to plausibly be speech (`.infinity` if never).
    private func audioActivityGap(at now: CFAbsoluteTime) -> TimeInterval {
        lastAudioActivityAt > 0 ? now - lastAudioActivityAt : .infinity
    }

    private func checkAutoStop() {
        guard isRecording, lastTranscriptReceivedAt > 0 else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let transcriptGap = now - lastTranscriptReceivedAt
        let audioGap = audioActivityGap(at: now)

        var calendarEventEnded = false
        if autoStopFromCalendar,
           let event = selectedCalendarEvent,
           let endDate = event.endDate,
           Date() > endDate {
            calendarEventEnded = true
            if !calendarEventEndedWhileRecording {
                calendarEventEndedWhileRecording = true
                DebugLogger.shared.log(.app, "Calendar event ended — using 2-min silence threshold")
            }
        }

        let decision = Self.evaluateAutoStop(
            transcriptGap: transcriptGap,
            audioGap: audioGap,
            autoStopMinutes: autoStopMinutes,
            calendarEventEnded: calendarEventEnded
        )

        switch decision {
        case .keepRecording:
            return
        case .silence:
            DebugLogger.shared.log(.app, "Auto-stop: no transcript activity for \(autoStopMinutes) min")
            autoStopReason = .silence
        case .calendarSilence:
            DebugLogger.shared.log(.app, "Auto-stop: calendar event ended + 2 min silence")
            autoStopReason = .silence
        case .stalledPipeline:
            DebugLogger.shared.log(.app, "Auto-stop: transcript pipeline stalled for \(Int(transcriptGap / 60)) min despite active audio")
            autoStopReason = .stalledPipeline
        }

        wasAutoStopped = true
        stopRecording()
    }
    
    private func checkTranscriptHealth() {
        guard isRecording else { return }
        guard let deepgramService else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        let transcriptGap = now - lastTranscriptReceivedAt
        let audioGap = audioActivityGap(at: now)
        if now - lastTranscriptHealthDebugLogAt > 20.0 {
            lastTranscriptHealthDebugLogAt = now
            DebugLogger.shared.log(
                .app,
                "Transcript health: gap=\(String(format: "%.1f", transcriptGap))s, audioGap=\(String(format: "%.1f", audioGap))s, dg=\(deepgramService.connectionState), packets=\(deepgramService.packetsSentCount), micLevel=\(String(format: "%.4f", microphoneLevel)), sysLevel=\(String(format: "%.4f", systemAudioLevel)), micActive=\(audioCaptureService?.isMicActive ?? false), sysActive=\(audioCaptureService?.isSystemAudioActive ?? false), recovery=\(audioRecoveryState)"
            )
        }

        // Words are flowing again — whatever we last did worked, so start the backoff over.
        if transcriptGap < Self.transcriptStarvationGap {
            consecutiveTranscriptRecoveries = 0
        }

        let action = Self.evaluateTranscriptHealth(
            transcriptGap: transcriptGap,
            audioGap: audioGap,
            sinceLastRecoveryAttempt: lastTranscriptStarvationRecoveryAt > 0
                ? now - lastTranscriptStarvationRecoveryAt
                : .infinity,
            consecutiveRecoveries: consecutiveTranscriptRecoveries,
            isConnected: deepgramService.connectionState == .connected,
            isConnecting: deepgramService.connectionState == .connecting,
            hasPendingReconnect: deepgramReconnectTask != nil
        )

        if action != .none {
            lastTranscriptStarvationRecoveryAt = now
            consecutiveTranscriptRecoveries += 1
            let reason = action == .reconnectStarvation
                ? "transcript starvation"
                : "transcript still dead after reconnect gave up"
            DebugLogger.shared.log(
                .app,
                "Transcript stall detected (\(String(format: "%.1f", transcriptGap))s gap with active audio, dg=\(deepgramService.connectionState)) — reconnecting Deepgram: \(reason)"
            )
            enqueueDiagnosticEvent(
                action == .reconnectStarvation
                    ? "transcript_starvation_detected"
                    : "transcript_reconnect_reattempt",
                category: .deepgram,
                level: .warning,
                details: [
                    "gap_seconds": String(format: "%.1f", transcriptGap),
                    "audio_gap_seconds": String(format: "%.1f", audioGap),
                    "mic_level": String(format: "%.4f", microphoneLevel),
                    "system_level": String(format: "%.4f", systemAudioLevel)
                ]
            )
            scheduleDeepgramReconnect(reason: reason)
        }
        
        updateAudioRecoveryState()
    }
    
    private func updateAudioRecoveryState() {
        guard isRecording else {
            pendingAudioRecoveryTransitionTask?.cancel()
            pendingAudioRecoveryTransitionTask = nil
            desiredAudioRecoveryState = .healthy
            audioRecoveryState = .healthy
            return
        }
        
        if deepgramReconnectTask != nil || deepgramService?.connectionState == .connecting {
            applyAudioRecoveryState(.recovering)
            return
        }
        
        if deepgramService?.connectionState == .error {
            applyAudioRecoveryState(.degraded)
            return
        }
        
        #if os(macOS)
        if captureSystemAudio {
            let isSystemActive = audioCaptureService?.isSystemAudioActive ?? false
            if !isSystemActive {
                let now = CFAbsoluteTimeGetCurrent()
                if systemAudioInactiveSince == 0 {
                    systemAudioInactiveSince = now
                }
                let inactiveFor = now - systemAudioInactiveSince
                applyAudioRecoveryState(inactiveFor > 12 ? .degraded : .recovering)
                return
            }
            systemAudioInactiveSince = 0
        }
        #endif
        
        applyAudioRecoveryState(.healthy)
    }
    
    nonisolated static func recoverySeverity(_ state: AudioRecoveryState) -> Int {
        switch state {
        case .healthy: return 0
        case .recovering: return 1
        case .degraded: return 2
        }
    }
    
    private func applyAudioRecoveryState(_ nextState: AudioRecoveryState) {
        desiredAudioRecoveryState = nextState
        guard nextState != audioRecoveryState else { return }

        if nextState == .degraded {
            enqueueDiagnosticEvent("audio_recovery_degraded", category: .audio, level: .warning)
        } else if nextState == .recovering {
            enqueueDiagnosticEvent("audio_recovery_recovering", category: .audio)
        } else if audioRecoveryState != .healthy {
            enqueueDiagnosticEvent("audio_recovery_healthy", category: .audio)
        }
        
        pendingAudioRecoveryTransitionTask?.cancel()
        pendingAudioRecoveryTransitionTask = nil
        
        let currentSeverity = Self.recoverySeverity(audioRecoveryState)
        let nextSeverity = Self.recoverySeverity(nextState)
        if nextSeverity > currentSeverity {
            audioRecoveryState = nextState
            return
        }
        
        // Hold healthier transitions briefly so status doesn't flicker.
        let delayNanoseconds: UInt64 = nextState == .healthy ? 1_400_000_000 : 700_000_000
        pendingAudioRecoveryTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self else { return }
            guard self.isRecording else { return }
            guard self.desiredAudioRecoveryState == nextState else { return }
            self.audioRecoveryState = nextState
            self.pendingAudioRecoveryTransitionTask = nil
        }
    }
    
    private func handleSpeakerSegments(_ segments: [DeepgramService.SpeakerSegment]) {
        let finalSegments = segments.filter { $0.isFinal }
        guard !finalSegments.isEmpty else { return }

        #if os(macOS)
        if captureMicrophone && captureSystemAudio {
            handleDualSourceFinalSegments(finalSegments)
            return
        }
        #endif

        commitFinalSpeakerSegments(finalSegments)
    }

    #if os(macOS)
    private func handleDualSourceFinalSegments(_ segments: [DeepgramService.SpeakerSegment]) {
        let systemSegments = segments.filter {
            $0.channelIndex == DeepgramService.systemChannelIndex
        }
        let micSegments = segments.filter {
            $0.channelIndex == DeepgramService.micChannelIndex
        }
        let unclassified = segments.filter {
            $0.channelIndex != DeepgramService.micChannelIndex &&
            $0.channelIndex != DeepgramService.systemChannelIndex
        }

        if !systemSegments.isEmpty {
            let now = Date()
            recentSystemSegments.append(contentsOf: systemSegments.map {
                BufferedSystemSegment(segment: $0, receivedAt: now)
            })
            pruneSystemEchoHistory(now: now)
            suppressPendingMicEchoes()
            releasePendingMicSegmentsCoveredBySystem()
            commitFinalSpeakerSegments(systemSegments)
        }

        var immediateMic: [DeepgramService.SpeakerSegment] = []
        for segment in micSegments {
            if isLikelyEcho(segment) {
                DebugLogger.shared.log(
                    .deepgram,
                    "Suppressed mic playback echo: words=\(Self.echoTokens(segment.text).count), start=\(String(format: "%.2f", segment.startTime))"
                )
                continue
            }

            switch audioCaptureService?.dominantSource(from: segment.startTime, to: segment.endTime) {
            case .mic:
                // Clear local speech stays fully live with no reconciliation delay.
                immediateMic.append(segment)
            case .system, .unknown, .none:
                pendingMicSegments.append(
                    PendingMicSegment(
                        segment: segment,
                        deadline: Date().addingTimeInterval(micEchoReconciliationDelay)
                    )
                )
            }
        }

        if !immediateMic.isEmpty {
            commitFinalSpeakerSegments(immediateMic)
        }
        if !unclassified.isEmpty {
            // Defensive fallback for malformed multichannel results. Never drop
            // transcript content merely because Deepgram omitted channel_index.
            commitFinalSpeakerSegments(unclassified)
        }
        schedulePendingMicFlush()
    }

    private func isLikelyEcho(_ micSegment: DeepgramService.SpeakerSegment) -> Bool {
        let sourceIsSystemDominant: Bool
        switch audioCaptureService?.dominantSource(from: micSegment.startTime, to: micSegment.endTime) {
        case .system:
            sourceIsSystemDominant = true
        case .mic, .unknown, .none:
            sourceIsSystemDominant = false
        }

        return Self.isLikelyMicEcho(
            mic: EchoComparisonSegment(
                text: micSegment.text,
                startTime: micSegment.startTime,
                endTime: micSegment.endTime
            ),
            systemSegments: recentSystemSegments.map {
                EchoComparisonSegment(
                    text: $0.segment.text,
                    startTime: $0.segment.startTime,
                    endTime: $0.segment.endTime
                )
            },
            systemDominant: sourceIsSystemDominant
        )
    }

    private func suppressPendingMicEchoes() {
        guard !pendingMicSegments.isEmpty else { return }
        var survivors: [PendingMicSegment] = []
        survivors.reserveCapacity(pendingMicSegments.count)

        for pending in pendingMicSegments {
            if isLikelyEcho(pending.segment) {
                DebugLogger.shared.log(
                    .deepgram,
                    "Suppressed delayed mic playback echo: words=\(Self.echoTokens(pending.segment.text).count), start=\(String(format: "%.2f", pending.segment.startTime))"
                )
            } else {
                survivors.append(pending)
            }
        }
        pendingMicSegments = survivors
    }

    private func pruneSystemEchoHistory(now: Date = Date()) {
        recentSystemSegments.removeAll {
            now.timeIntervalSince($0.receivedAt) > echoSystemHistoryWindow
        }
    }

    /// Once the clean system channel has finalized beyond an ambiguous mic segment,
    /// a surviving non-match is genuine local speech and does not need to wait for
    /// the fallback deadline. Word timestamps share the same multichannel clock.
    private func releasePendingMicSegmentsCoveredBySystem() {
        guard let systemWatermark = recentSystemSegments.map(\.segment.endTime).max() else { return }
        let covered = pendingMicSegments.filter {
            $0.segment.endTime + 0.8 <= systemWatermark
        }
        guard !covered.isEmpty else { return }

        let coveredIDs = Set(covered.map(\.segment.id))
        pendingMicSegments.removeAll { coveredIDs.contains($0.segment.id) }
        commitFinalSpeakerSegments(covered.map(\.segment))
    }

    private func schedulePendingMicFlush() {
        pendingMicFlushTask?.cancel()
        pendingMicFlushTask = nil
        guard let deadline = pendingMicSegments.map(\.deadline).min() else { return }

        let delay = max(0, deadline.timeIntervalSinceNow)
        let nanoseconds = UInt64(delay * 1_000_000_000)
        pendingMicFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.flushExpiredPendingMicSegments()
        }
    }

    private func flushExpiredPendingMicSegments(now: Date = Date()) {
        suppressPendingMicEchoes()
        let due = pendingMicSegments.filter { $0.deadline <= now }.map(\.segment)
        pendingMicSegments.removeAll { $0.deadline <= now }
        if !due.isEmpty {
            commitFinalSpeakerSegments(due)
        }
        pruneSystemEchoHistory(now: now)
        schedulePendingMicFlush()
    }

    private func flushAllPendingMicSegments() {
        pendingMicFlushTask?.cancel()
        pendingMicFlushTask = nil
        suppressPendingMicEchoes()
        let remaining = pendingMicSegments.map(\.segment)
        pendingMicSegments.removeAll()
        if !remaining.isEmpty {
            commitFinalSpeakerSegments(remaining)
        }
    }

    private func resetEchoReconciliation(flushPending: Bool = false) {
        if flushPending {
            flushAllPendingMicSegments()
        } else {
            pendingMicFlushTask?.cancel()
            pendingMicFlushTask = nil
            pendingMicSegments.removeAll()
        }
        recentSystemSegments.removeAll()
    }
    #endif

    private func commitFinalSpeakerSegments(_ finalSegments: [DeepgramService.SpeakerSegment]) {
        guard !finalSegments.isEmpty else { return }
        
        // Build new array state atomically to avoid multiple @Published mutations.
        // Previously, removeAll + append fired per iteration, causing SwiftUI's
        // AttributeGraph to see intermediate states and corrupt weak references
        // during ForEach diffing (EXC_BAD_ACCESS in AGGraphGetWeakValue).
        // `liveSegments` contains finalized, non-empty segments by contract, so copying it
        // avoids an O(n) filter allocation on every final transcript callback.
        var updated = liveSegments
        var receivedTranscriptContent = false
        
        for segment in finalSegments {
            // Skip empty segments
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            receivedTranscriptContent = true
            
            // Track this speaker
            detectedSpeakers.insert(segment.speaker)
            
            // Create live segment
            let liveSegment = LiveSegment(
                id: segment.id,
                text: text,
                speaker: segment.speaker,
                timestamp: recordingDuration,
                isFinal: true
            )
            
            let mergeResult = Self.mergeFinalSegment(liveSegment, into: &updated)
            switch mergeResult {
            case .appended:
                break
            case .replacedSuperset:
                DebugLogger.shared.log(
                    .deepgram,
                    "Merged cumulative final transcript instead of dropping suffix: speaker=\(segment.speaker)"
                )
            case .skippedExactDuplicate, .skippedContainedDuplicate:
                DebugLogger.shared.log(
                    .deepgram,
                    "Skipped duplicate final transcript: reason=\(mergeResult), speaker=\(segment.speaker)"
                )
            }
        }
        
        // Words landing here mean the pipeline is alive, even when the sibling transcript update
        // carried no text of its own and so never stamped the timestamp.
        if receivedTranscriptContent {
            lastTranscriptReceivedAt = CFAbsoluteTimeGetCurrent()
        }
        
        // Single atomic mutation — one @Published change instead of N
        liveSegments = updated
        transcriptRuntime.update(
            interimText: "",
            currentSpeaker: currentSpeaker,
            interimSpeaker: nil
        )
        
        // Push final segment to Live Activity (throttled)
        #if os(iOS)
        updateLiveActivityTranscript()
        #endif
        
        // Update training metrics if in training mode
        if insightsMode == .training {
            scheduleTrainingMetricsRecompute()
        }
        
        // Warmup: fire first request when we have 4 segments (standard) or 6 (MEDDPICC).
        // Steady-state: cadence task handles 30s intervals.
        let finalCount = updated.count
        let standardWarmup = standardSuccessCount < 2 && finalCount >= 4
        let meddpiccWarmup = salesInsightsEnabled && meddpiccSuccessCount < 2 && finalCount >= 6
        let questionsWarmup = questionsSuccessCount < 2 && finalCount >= 6
        let now = Date()
        let warmupRetryReady = lastWarmupInsightsAttemptAt.map {
            now.timeIntervalSince($0) >= warmupInsightsRetryInterval
        } ?? true
        let shouldTrigger = (standardWarmup || meddpiccWarmup || questionsWarmup)
            && finalCount > lastInsightSegmentCount
            && warmupRetryReady
        if shouldTrigger {
            lastInsightSegmentCount = finalCount
            lastWarmupInsightsAttemptAt = now
            Task { await updateLiveInsights() }
        }

        evaluateRealtimeNudges()
    }

    private var isGeneratingMeddpiccInsights = false
    private var isGeneratingQuestionsInsights = false

    nonisolated static func shouldFireLiveInsightCadence(
        now: Date,
        lastSuccessAt: Date?,
        lastAttemptAt: Date?,
        lastSuccessfulSegmentCount: Int,
        currentSegmentCount: Int,
        policy: LiveInsightCadencePolicy
    ) -> Bool {
        guard currentSegmentCount > lastSuccessfulSegmentCount else { return false }

        if let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < policy.minimumInterval {
            return false
        }

        let elapsedSinceSuccess = lastSuccessAt.map { now.timeIntervalSince($0) } ?? .infinity
        let segmentDelta = currentSegmentCount - lastSuccessfulSegmentCount
        return elapsedSinceSuccess >= policy.maximumInterval
            || (elapsedSinceSuccess >= policy.minimumInterval
                && segmentDelta >= policy.minimumSegmentDelta)
    }

    private func startInsightsCadenceTask() {
        insightsCadenceTask?.cancel()
        insightsCadenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, isRecording {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, isRecording else { break }
                let liveSegmentsSnapshot = liveSegments
                let finalCount = liveSegmentsSnapshot.count
                var finalizedSegmentsCache: [LiveSegment]?
                func finalizedSegments() -> [LiveSegment] {
                    if let finalizedSegmentsCache {
                        return finalizedSegmentsCache
                    }
                    let snapshot = liveSegmentsSnapshot
                    finalizedSegmentsCache = snapshot
                    return snapshot
                }
                let now = Date()
                if standardSuccessCount >= 2,
                   Self.shouldFireLiveInsightCadence(
                       now: now,
                       lastSuccessAt: standardCadenceAnchor,
                       lastAttemptAt: standardLastAttemptAt,
                       lastSuccessfulSegmentCount: standardLastFiredSegmentCount,
                       currentSegmentCount: finalCount,
                       policy: standardCadencePolicy
                   ) {
                    standardLastAttemptAt = now
                    await updateLiveInsights(standardOnly: true)
                }
                if salesInsightsEnabled, meddpiccSuccessCount >= 2 {
                    let anchor = meddpiccCadenceAnchor
                        ?? standardCadenceAnchor?.addingTimeInterval(meddpiccCadenceStagger)
                        ?? recordingStartDate
                    if Self.shouldFireLiveInsightCadence(
                        now: now,
                        lastSuccessAt: anchor,
                        lastAttemptAt: meddpiccLastAttemptAt,
                        lastSuccessfulSegmentCount: meddpiccLastFiredSegmentCount,
                        currentSegmentCount: finalCount,
                        policy: meddpiccCadencePolicy
                    ) {
                        meddpiccLastAttemptAt = now
                        let finalSegments = finalizedSegments()
                        let transcript = transcriptText(from: finalSegments)
                        guard let meetingID = currentMeeting?.id, !transcript.isEmpty else { continue }
                        await updateMeddpiccInBackground(
                            transcript: transcript,
                            finalSegments: finalSegments,
                            segmentCount: finalCount,
                            existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                            meetingID: meetingID
                        )
                    }
                }
                if questionsSuccessCount >= 2 {
                    let anchor = questionsCadenceAnchor
                        ?? standardCadenceAnchor?.addingTimeInterval(questionsCadenceStagger)
                        ?? recordingStartDate
                    if Self.shouldFireLiveInsightCadence(
                        now: now,
                        lastSuccessAt: anchor,
                        lastAttemptAt: questionsLastAttemptAt,
                        lastSuccessfulSegmentCount: questionsLastFiredSegmentCount,
                        currentSegmentCount: finalCount,
                        policy: questionsCadencePolicy
                    ) {
                        questionsLastAttemptAt = now
                        let finalSegments = finalizedSegments()
                        let transcript = transcriptText(from: finalSegments)
                        guard let meetingID = currentMeeting?.id, !transcript.isEmpty else { continue }
                        await updateQuestionsInBackground(
                            transcript: transcript,
                            finalSegments: finalSegments,
                            segmentCount: finalCount,
                            meetingID: meetingID
                        )
                    }
                }
                // Docs topics: only while the docs tab is active and an MCP URL is
                // configured. Low cadence, own throttle. Extraction merges new
                // topics and (for Pro/BYOK) auto-looks-them-up.
                if insightsMode == .docs, validatedDocsMCPURL != nil, !isExtractingDocsTopics {
                    let meetsTime = lastDocsTopicsRequestAt.map {
                        now.timeIntervalSince($0) >= self.docsTopicsMinInterval
                    } ?? true
                    if meetsTime, finalCount > docsTopicsLastFiredSegmentCount {
                        lastDocsTopicsRequestAt = now
                        docsTopicsLastFiredSegmentCount = finalCount
                        await refreshDocsTopics()
                    }
                }
                // Speaker names: low-cadence, best-effort. Rely on its own throttle.
                if autoInferSpeakerNames, !isGeneratingSpeakerNames {
                    let meetsSegmentThreshold = finalCount >= lastSpeakerNamesSegmentCount + (
                        lastSpeakerNamesSegmentCount == 0 ? firstSpeakerNamesThreshold : speakerNamesUpdateThreshold
                    )
                    let meetsTimeThreshold = lastSpeakerNamesRequestAt.map {
                        now.timeIntervalSince($0) >= self.speakerNamesMinUpdateInterval
                    } ?? true
                    if meetsSegmentThreshold && meetsTimeThreshold {
                        let finalSegments = finalizedSegments()
                        if let meetingID = currentMeeting?.id, !finalSegments.isEmpty {
                            await updateSpeakerNamesInBackground(
                                finalSegments: finalSegments,
                                segmentCount: finalCount,
                                meetingID: meetingID
                            )
                        }
                    }
                }
            }
        }
    }

    private func resetCadenceAnchors() {
        standardCadenceAnchor = Date()
        meddpiccCadenceAnchor = Date()
        questionsCadenceAnchor = Date()
    }

    private func updateLiveInsights(standardOnly: Bool = false) async {
        guard !isGeneratingInsights else {
            DebugLogger.shared.log(.app, "Live insights skipped: request already in flight")
            return
        }
        
        let finalSegments = liveSegments
        
        let transcript = transcriptText(from: finalSegments)
        
        guard !transcript.isEmpty else { return }
        guard let meetingIDAtRequest = currentMeeting?.id else { return }
        standardLastAttemptAt = Date()
        
        let segmentCount = finalSegments.count
        let shouldUpdateTitle = segmentCount >= lastTitleUpdateCount + titleUpdateThreshold
        let existingTitle = shouldUpdateTitle ? nil : currentTitleSuffix
        let titleForRequest = existingTitle.flatMap { $0.isEmpty ? nil : $0 }
        
        DebugLogger.shared.log(
            .app,
            "Live insights start: segments=\(segmentCount), transcriptChars=\(transcript.count), updateTitle=\(shouldUpdateTitle)"
        )
        
        // Standard insights — inline, applies immediately
        isGeneratingInsights = true
        let standardSummary = lastStandardSummaryContext.isEmpty ? nil : lastStandardSummaryContext
        if let standardResult = await fetchLiveInsights(
            mode: .standard,
            transcript: transcript,
            finalSegments: finalSegments,
            existingSummary: standardSummary,
            existingTitle: titleForRequest
        ) {
            guard currentMeeting?.id == meetingIDAtRequest else {
                DebugLogger.shared.log(.app, "Dropping stale standard insights response (meeting changed)")
                isGeneratingInsights = false
                return
            }
            let isDegraded = standardResult.meta?.degraded ?? false
            if !isDegraded {
                if let seq = standardResult.meta?.requestSeq {
                    lastAppliedStandardSeq = seq
                }
                standardCadenceAnchor = Date()
                standardLastFiredSegmentCount = segmentCount
                lastStandardSummaryContext = standardResult.insights.summary
                applyInsights(standardResult.insights, segmentCount: segmentCount, mode: .standard)
                markManagedInsightsSuccess(
                    mode: .standard,
                    segmentCount: segmentCount,
                    usedIncrementalPayload: standardResult.usedIncrementalPayload
                )
                standardSuccessCount += 1
            } else {
                DebugLogger.shared.log(.app, "Standard insights degraded — not advancing cursor")
            }
        }
        isGeneratingInsights = false
        
        // MEDDPICC — independent background task, never blocks standard (skip when standardOnly)
        guard !standardOnly else { return }
        let shouldRunMeddpicc: Bool = {
            guard salesInsightsEnabled else { return false }
            guard !isGeneratingMeddpiccInsights else { return false }
            let meetsSegmentThreshold = segmentCount >= lastMEDDPICCSegmentCount + (
                lastMEDDPICCSegmentCount == 0 ? firstMEDDPICCInsightThreshold : meddpiccInsightUpdateThreshold
            )
            let meetsTimeThreshold = lastMEDDPICCRequestAt.map {
                Date().timeIntervalSince($0) >= meddpiccMinUpdateInterval
            } ?? true
            return meetsSegmentThreshold && meetsTimeThreshold
        }()
        
        if shouldRunMeddpicc {
            let capturedTranscript = transcript
            let capturedSegmentCount = segmentCount
            let capturedTitle = titleForRequest
            let capturedFinalSegments = finalSegments
            Task {
                await self.updateMeddpiccInBackground(
                    transcript: capturedTranscript,
                    finalSegments: capturedFinalSegments,
                    segmentCount: capturedSegmentCount,
                    existingTitle: capturedTitle,
                    meetingID: meetingIDAtRequest
                )
            }
        }
        
        let shouldRunQuestions: Bool = {
            guard !isGeneratingQuestionsInsights else { return false }
            let meetsSegmentThreshold = segmentCount >= lastQuestionsSegmentCount + (
                lastQuestionsSegmentCount == 0 ? firstQuestionsInsightThreshold : questionsInsightUpdateThreshold
            )
            let meetsTimeThreshold = lastQuestionsRequestAt.map {
                Date().timeIntervalSince($0) >= questionsMinUpdateInterval
            } ?? true
            return meetsSegmentThreshold && meetsTimeThreshold
        }()
        
        if shouldRunQuestions {
            Task {
                await self.updateQuestionsInBackground(
                    transcript: transcript,
                    finalSegments: finalSegments,
                    segmentCount: segmentCount,
                    meetingID: meetingIDAtRequest
                )
            }
        }

    }
    
    private func updateMeddpiccInBackground(
        transcript: String,
        finalSegments: [LiveSegment],
        segmentCount: Int,
        existingTitle: String?,
        meetingID: UUID
    ) async {
        guard salesInsightsEnabled else { return }
        guard !isGeneratingMeddpiccInsights else { return }
        guard currentMeeting?.id == meetingID else { return }
        meddpiccLastAttemptAt = Date()
        isGeneratingMeddpiccInsights = true
        defer { isGeneratingMeddpiccInsights = false }
        
        let meddpiccSummary = lastMeddpiccSummaryContext.isEmpty ? nil : lastMeddpiccSummaryContext
        
        if let meddpiccResult = await fetchLiveInsights(
            mode: .meddpicc,
            transcript: transcript,
            finalSegments: finalSegments,
            existingSummary: meddpiccSummary,
            existingTitle: existingTitle
        ) {
            guard currentMeeting?.id == meetingID else {
                DebugLogger.shared.log(.app, "Dropping stale MEDDPICC insights response (meeting changed)")
                return
            }
            let isDegraded = meddpiccResult.meta?.degraded ?? false
            if !isDegraded {
                if let seq = meddpiccResult.meta?.requestSeq {
                    lastAppliedMeddpiccSeq = seq
                }
                meddpiccCadenceAnchor = Date()
                meddpiccLastFiredSegmentCount = segmentCount
                lastMeddpiccSummaryContext = meddpiccResult.insights.summary
                lastMEDDPICCRequestAt = Date()
                applyInsights(meddpiccResult.insights, segmentCount: segmentCount, mode: .meddpicc)
                lastMEDDPICCSegmentCount = segmentCount
                markManagedInsightsSuccess(
                    mode: .meddpicc,
                    segmentCount: segmentCount,
                    usedIncrementalPayload: meddpiccResult.usedIncrementalPayload
                )
                meddpiccSuccessCount += 1
                let meddpiccFieldCount = [
                    liveMetrics, liveEconomicBuyer, liveDecisionCriteria, liveDecisionProcess,
                    livePaperProcess, liveIdentifiedPain, liveChampion, liveCompetition
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "null" }
                .count
                DebugLogger.shared.log(.app, "Live MEDDPICC applied: fields=\(meddpiccFieldCount), segmentCount=\(segmentCount)")
            } else {
                DebugLogger.shared.log(.app, "MEDDPICC insights degraded — not advancing cursor")
            }
        }
    }
    
    private func updateQuestionsInBackground(
        transcript: String,
        finalSegments: [LiveSegment],
        segmentCount: Int,
        meetingID: UUID
    ) async {
        guard !isGeneratingQuestionsInsights else { return }
        guard currentMeeting?.id == meetingID else { return }
        questionsLastAttemptAt = Date()
        isGeneratingQuestionsInsights = true
        defer { isGeneratingQuestionsInsights = false }
        
        if let questionsResult = await fetchLiveInsights(
            mode: .questions,
            transcript: transcript,
            finalSegments: finalSegments,
            existingSummary: nil,
            existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix
        ) {
            guard currentMeeting?.id == meetingID else {
                DebugLogger.shared.log(.app, "Dropping stale questions insights response (meeting changed)")
                return
            }
            let isDegraded = questionsResult.meta?.degraded ?? false
            if !isDegraded {
                if let seq = questionsResult.meta?.requestSeq {
                    lastAppliedQuestionsSeq = seq
                }
                questionsCadenceAnchor = Date()
                questionsLastFiredSegmentCount = segmentCount
                lastQuestionsRequestAt = Date()
                applyInsights(questionsResult.insights, segmentCount: segmentCount, mode: .questions)
                lastQuestionsSegmentCount = segmentCount
                markManagedInsightsSuccess(
                    mode: .questions,
                    segmentCount: segmentCount,
                    usedIncrementalPayload: questionsResult.usedIncrementalPayload
                )
                questionsSuccessCount += 1
                DebugLogger.shared.log(.app, "Live questions applied: count=\(liveQuestions.count), segmentCount=\(segmentCount)")
            } else {
                DebugLogger.shared.log(.app, "Questions insights degraded — not advancing cursor")
            }
        }
    }

    // MARK: - Docs Topics

    /// Outcome of grounding a single docs topic against the MCP docs.
    private enum DocCardOutcome {
        case answered(DocPlaybookCard)
        case noMatch
        case transient(String)  // docs service busy / timed out — clearly retryable
        case failure(String)
        case quotaReached
    }

    private let docsQuotaReachedMessage =
        "You've used all your docs lookups this month. Upgrade to Pro for unlimited lookups."

    /// Best transcript available for the current meeting (live segments, or the
    /// persisted transcript for a stopped meeting).
    private func currentDocsTranscript() -> String? {
        guard let meeting = currentMeeting else { return nil }
        let liveTranscript = cachedFullTranscript
        let persisted = meeting.fullTranscript
        let transcript = liveTranscript.count > persisted.count ? liveTranscript : persisted
        return transcript.isEmpty ? nil : transcript
    }

    /// Merge freshly extracted topic labels into an existing list, preserving each
    /// existing topic's resolved state and appending new ones as `.pending`.
    static func mergeDocTopics(existing: [DocTopic], newLabels: [String]) -> [DocTopic] {
        var result = existing
        let existingSlugs = Set(existing.map { $0.id })
        for label in newLabels {
            let slug = DocTopic.slug(label)
            guard !slug.isEmpty, !existingSlugs.contains(slug) else { continue }
            result.append(DocTopic(label: label))
        }
        return result
    }

    /// Refresh the docs-topic list for the current live/stopped meeting.
    func refreshDocsTopics() async {
        guard validatedDocsMCPURL != nil else {
            docsLookupError = "Add a docs MCP URL in Settings → Docs MCP."
            return
        }
        guard let transcript = currentDocsTranscript(), transcript.count >= docsMinTranscriptChars else { return }
        guard !isExtractingDocsTopics else { return }
        isExtractingDocsTopics = true
        defer { isExtractingDocsTopics = false }

        guard let labels = await extractDocsTopicLabels(transcript: transcript, language: meetingLanguage) else {
            return // failure already surfaced via docsLookupError
        }
        let merged = Self.mergeDocTopics(existing: liveDocTopics, newLabels: labels)
        liveDocTopics = merged
        currentMeeting?.docTopics = merged
        if !merged.isEmpty { docsSuccessCount += 1 }
        saveCurrentMeetingIfNeeded()
        autoLookupPendingDocTopicsIfEligible()
    }

    /// Refresh the docs-topic list for a saved history meeting.
    func refreshDocsTopics(for meeting: Meeting) async {
        guard validatedDocsMCPURL != nil else {
            docsLookupError = "Add a docs MCP URL in Settings → Docs MCP."
            return
        }
        let meetingID = meeting.id
        let transcript = meeting.fullTranscript
        let language = meeting.language
        guard transcript.count >= docsMinTranscriptChars, !isExtractingDocsTopics else { return }
        isExtractingDocsTopics = true
        defer { isExtractingDocsTopics = false }

        guard let labels = await extractDocsTopicLabels(transcript: transcript, language: language) else {
            return
        }
        // The meeting can be deleted from history while extraction is in flight.
        guard !isMeetingDeleted(meetingID) else { return }
        let merged = Self.mergeDocTopics(existing: meeting.docTopics, newLabels: labels)
        meeting.docTopics = merged
        if currentMeeting?.id == meetingID { liveDocTopics = merged }
        if !merged.isEmpty { docsSuccessCount += 1 }
        try? modelContext?.save()

        if canAutoLookupDocs {
            for topic in merged where topic.lookupState == .pending {
                guard !isMeetingDeleted(meetingID) else { return }
                await lookupDocTopic(id: topic.id, for: meeting)
            }
        }
    }

    /// Extract topic labels via the managed backend or BYOK. Returns nil on
    /// failure (message surfaced through `docsLookupError`).
    private func extractDocsTopicLabels(transcript: String, language: String) async -> [String]? {
        guard let mcpURL = validatedDocsMCPURL else { return nil }
        do {
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.extractDocsTopics(
                    deviceId: deviceId,
                    transcript: transcript,
                    docsMcpURL: mcpURL,
                    model: OpenAIModel.gpt5Mini.rawValue,
                    language: language
                )
                docsLookupError = nil
                return response.topics
            }
            guard let insightsService, !openaiApiKey.isEmpty else {
                docsLookupError = "Add your OpenAI API key in Settings to look up docs."
                return nil
            }
            let topics = try await insightsService.extractDocsTopics(
                transcript: transcript,
                apiKey: openaiApiKey,
                language: language
            )
            docsLookupError = nil
            return topics
        } catch {
            DebugLogger.shared.log(.app, "Docs topic extraction FAILED: \(error.localizedDescription)")
            docsLookupError = (error as? DocsMCPService.MCPError)?.errorDescription
                ?? "Couldn't refresh docs topics. Check the MCP URL and your connection."
            return nil
        }
    }

    /// Ground a single topic against the docs (managed or BYOK). Shared by the
    /// live and history lookup paths.
    private func resolveDocCard(topic: String, transcript: String, language: String) async -> DocCardOutcome {
        guard let mcpURL = validatedDocsMCPURL else {
            return .failure("Add a docs MCP URL in Settings → Docs MCP.")
        }
        do {
            if appMode == .managed, let minitiAPIService {
                if docsLookupQuotaReached { return .quotaReached }
                docsRequestSeq += 1
                let seq = docsRequestSeq
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateDocsPlaybook(
                    deviceId: deviceId,
                    transcript: transcript,
                    docsMcpURL: mcpURL,
                    model: OpenAIModel.gpt5Mini.rawValue,
                    topic: topic,
                    requestSeq: seq,
                    language: language
                )
                if response.meta?.degraded == true {
                    return .transient("Docs service is busy — tap to try again.")
                }
                if let card = response.docs.first(where: { !$0.citations.isEmpty }) {
                    return .answered(card)
                }
                return .noMatch
            }

            guard let insightsService, !openaiApiKey.isEmpty else {
                return .failure("Add your OpenAI API key in Settings to look up docs.")
            }
            let retrieved = try await DocsMCPService.retrieveChunks(mcpURL: mcpURL, query: topic)
            if let card = try await insightsService.generateDocsCard(
                topic: topic,
                chunks: retrieved.chunks,
                transcript: transcript,
                apiKey: openaiApiKey,
                language: language
            ) {
                return .answered(card)
            }
            return .noMatch
        } catch {
            // A 402 (docs quota exhausted) surfaces as ServiceError.limitReached —
            // route it to the upgrade prompt, not a generic lookup failure. This is
            // the backstop for when the client's cached usage is stale.
            if let serviceError = error as? MinitiAPIService.ServiceError,
               case .limitReached = serviceError {
                return .quotaReached
            }
            // Timeouts (MCP or backend) are transient — present them as retryable
            // "busy", not a hard error.
            if let mcpError = error as? DocsMCPService.MCPError, case .timeout = mcpError {
                return .transient("Docs lookup timed out — tap to try again.")
            }
            if let serviceError = error as? MinitiAPIService.ServiceError, case .rateLimited = serviceError {
                return .transient("Docs service is busy — tap to try again.")
            }
            DebugLogger.shared.log(.app, "Docs topic lookup FAILED: \(error.localizedDescription)")
            enqueueDiagnosticEvent(
                "insights_live_failed",
                category: .insights,
                level: .warning,
                details: ["mode": "docs", "error": error.localizedDescription]
            )
            let message = (error as? DocsMCPService.MCPError)?.errorDescription
                ?? "Docs lookup failed. Check the MCP URL and your connection."
            return .failure(message)
        }
    }

    /// Auto-look-up pending topics (Pro/BYOK only), bounded by a small concurrency
    /// cap. Slots are reserved synchronously so a burst can't exceed the cap.
    private func autoLookupPendingDocTopicsIfEligible() {
        guard canAutoLookupDocs else { return }
        for topic in liveDocTopics where topic.lookupState == .pending {
            guard docsLookupInFlight.count < maxConcurrentDocsLookups else { break }
            guard !docsLookupInFlight.contains(topic.id) else { continue }
            docsLookupInFlight.insert(topic.id)
            setLiveDocTopicState(id: topic.id, state: .lookingUp)
            let topicID = topic.id
            Task { @MainActor in await self.runLiveDocTopicLookup(id: topicID) }
        }
    }

    /// Manually look up a single topic for the current meeting.
    func lookupDocTopic(id: String) async {
        guard !docsLookupInFlight.contains(id) else { return }
        if !canAutoLookupDocs, docsLookupQuotaReached {
            docsLookupError = docsQuotaReachedMessage
            return
        }
        docsLookupInFlight.insert(id)
        setLiveDocTopicState(id: id, state: .lookingUp)
        await runLiveDocTopicLookup(id: id)
    }

    /// Runs one live-meeting topic lookup assuming its slot is reserved and its
    /// state is already `.lookingUp`.
    private func runLiveDocTopicLookup(id: String) async {
        defer { docsLookupInFlight.remove(id) }
        guard let topic = liveDocTopics.first(where: { $0.id == id }) else { return }
        guard let transcript = currentDocsTranscript() else {
            setLiveDocTopicState(id: id, state: .failed, errorMessage: "No transcript to look up yet.")
            return
        }
        let outcome = await resolveDocCard(topic: topic.label, transcript: transcript, language: meetingLanguage)
        applyLiveDocOutcome(outcome, toTopicID: id)
        saveCurrentMeetingIfNeeded()
        autoLookupPendingDocTopicsIfEligible()
    }

    private func setLiveDocTopicState(id: String, state: DocTopic.LookupState, errorMessage: String? = nil) {
        guard let idx = liveDocTopics.firstIndex(where: { $0.id == id }) else { return }
        liveDocTopics[idx].lookupState = state
        liveDocTopics[idx].errorMessage = errorMessage
        currentMeeting?.docTopics = liveDocTopics
    }

    private func applyLiveDocOutcome(_ outcome: DocCardOutcome, toTopicID id: String) {
        guard let idx = liveDocTopics.firstIndex(where: { $0.id == id }) else { return }
        var topic = liveDocTopics[idx]
        switch outcome {
        case .answered(let card):
            topic.card = card
            topic.lookupState = .answered
            topic.errorMessage = nil
            docsSuccessCount += 1
            docsLookupError = nil
        case .noMatch:
            topic.card = nil
            topic.lookupState = .noMatch
            topic.errorMessage = nil
        case .transient(let message):
            // Keep any prior card; a busy blip shouldn't wipe an earlier answer.
            topic.lookupState = .busy
            topic.errorMessage = message
            docsLookupError = message
        case .failure(let message):
            topic.lookupState = .failed
            topic.errorMessage = message
            docsLookupError = message
        case .quotaReached:
            topic.lookupState = .pending
            docsLookupError = docsQuotaReachedMessage
        }
        liveDocTopics[idx] = topic
        currentMeeting?.docTopics = liveDocTopics
    }

    /// Manually look up a single topic for a saved history meeting.
    func lookupDocTopic(id: String, for meeting: Meeting) async {
        guard let topic = meeting.docTopics.first(where: { $0.id == id }) else { return }
        if !canAutoLookupDocs, docsLookupQuotaReached {
            docsLookupError = docsQuotaReachedMessage
            return
        }
        let meetingID = meeting.id
        let transcript = meeting.fullTranscript
        let language = meeting.language
        updateHistoryDocTopic(id: id, in: meeting) { t in
            t.lookupState = .lookingUp
            t.errorMessage = nil
        }
        let outcome = await resolveDocCard(topic: topic.label, transcript: transcript, language: language)
        // The meeting can be deleted from history while the lookup is in flight.
        guard !isMeetingDeleted(meetingID) else { return }
        updateHistoryDocTopic(id: id, in: meeting) { t in
            switch outcome {
            case .answered(let card):
                t.card = card
                t.lookupState = .answered
                t.errorMessage = nil
            case .noMatch:
                t.card = nil
                t.lookupState = .noMatch
                t.errorMessage = nil
            case .transient(let message):
                t.lookupState = .busy
                t.errorMessage = message
                self.docsLookupError = message
            case .failure(let message):
                t.lookupState = .failed
                t.errorMessage = message
                self.docsLookupError = message
            case .quotaReached:
                t.lookupState = .pending
                self.docsLookupError = self.docsQuotaReachedMessage
            }
        }
        try? modelContext?.save()

        if case .answered = outcome {
            docsSuccessCount += 1
            docsLookupError = nil
            #if os(macOS)
            if autoExportMarkdown {
                let markdown = meeting.fullMeetingAsMarkdown()
                exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
            }
            #endif
            if !webhookURL.isEmpty {
                WebhookService.send(payload: WebhookService.payloadFromMeeting(meeting), to: webhookURL)
            }
        }
    }

    private func updateHistoryDocTopic(id: String, in meeting: Meeting, _ mutate: (inout DocTopic) -> Void) {
        var topics = meeting.docTopics
        guard let idx = topics.firstIndex(where: { $0.id == id }) else { return }
        mutate(&topics[idx])
        meeting.docTopics = topics
        if currentMeeting?.id == meeting.id { liveDocTopics = topics }
    }

    // MARK: - Speaker Names Inference

    /// Ephemeral Deepgram keyterms from the active meeting/calendar context
    /// (attendee names, company domains, short meeting title).
    private func deepgramSessionKeyterms() -> [String] {
        if let meeting = currentMeeting {
            return PersonalDictionaryPreferences.sessionKeyterms(
                meetingTitle: meeting.displayTitle,
                attendees: meeting.attendees.map {
                    (displayName: $0.displayName, domain: $0.domain, isSelf: $0.isSelf)
                }
            )
        }
        if let event = selectedCalendarEvent {
            return PersonalDictionaryPreferences.sessionKeyterms(
                meetingTitle: event.title,
                attendees: event.attendees.map {
                    (displayName: $0.displayName, domain: $0.domain, isSelf: $0.isSelf)
                }
            )
        }
        return []
    }

    /// Build the list of candidate real names to bias the LLM toward.
    /// Currently drawn from calendar attendees (excluding the local user).
    private func speakerNameCandidates() -> [String] {
        guard let meeting = currentMeeting else { return [] }
        return meeting.attendees.compactMap { attendee -> String? in
            if attendee.isSelf { return nil }
            let name = attendee.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
    }

    /// Kick off a background speaker-name inference. No-op if disabled, already running,
    /// or the transcript is too short. Results are merged into `liveSpeakerNames`.
    private func updateSpeakerNamesInBackground(
        finalSegments: [LiveSegment],
        segmentCount: Int,
        meetingID: UUID
    ) async {
        guard autoInferSpeakerNames else { return }
        guard !isGeneratingSpeakerNames else { return }
        guard currentMeeting?.id == meetingID else { return }
        let transcript = transcriptTextWithSpeakerIDs(from: finalSegments)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isGeneratingSpeakerNames = true
        defer { isGeneratingSpeakerNames = false }

        let candidates = speakerNameCandidates()
        let model = OpenAIModel.gpt5Mini
        DebugLogger.shared.log(
            .app,
            "Speaker-names request: mode=\(appMode.rawValue), segments=\(segmentCount), speakers=\(Set(finalSegments.map(\.speaker)).sorted()), candidates=\(candidates.count), transcriptChars=\(trimmed.count)"
        )

        do {
            let inferred: [String: String]
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                inferred = try await minitiAPIService.inferSpeakerNames(
                    deviceId: deviceId,
                    transcript: transcript,
                    candidates: candidates,
                    model: model.rawValue,
                    language: meetingLanguage
                )
            } else if let insightsService, !openaiApiKey.isEmpty {
                inferred = try await insightsService.inferSpeakerNames(
                    transcript: transcript,
                    candidates: candidates,
                    model: model,
                    apiKey: openaiApiKey,
                    language: meetingLanguage
                )
            } else {
                DebugLogger.shared.log(.app, "Speaker-names skipped: no inference service/key available")
                return
            }

            guard currentMeeting?.id == meetingID else {
                DebugLogger.shared.log(.app, "Dropping stale speaker-names response (meeting changed)")
                return
            }

            lastSpeakerNamesRequestAt = Date()
            lastSpeakerNamesSegmentCount = segmentCount

            guard !inferred.isEmpty else {
                DebugLogger.shared.log(.app, "Speaker-names: no names inferred this cycle")
                return
            }

            let supported = Self.transcriptSupportedSpeakerNames(inferred, finalSegments: finalSegments)
            let sanitized = SpeakerNamesResponse.sanitize(inferred)
            let rejected = inferred.count - supported.count
            let rejectedIDs = Set(sanitized.keys).subtracting(supported.keys).sorted()
            guard !supported.isEmpty else {
                DebugLogger.shared.log(
                    .app,
                    "Speaker-names: rejected \(inferred.count) unsupported inference(s), ids=\(rejectedIDs), inferred=\(Self.speakerNameDebugSummary(sanitized))"
                )
                return
            }

            // Merge: inference can refine prior inferred names, but never overwrite a user override.
            var merged = liveSpeakerNames
            var applied = 0
            var skippedOverrides: [String] = []
            for (key, value) in supported where !liveSpeakerOverrides.contains(key) {
                merged[key] = value
                applied += 1
            }
            for key in supported.keys where liveSpeakerOverrides.contains(key) {
                skippedOverrides.append(key)
            }
            liveSpeakerNames = merged
            DebugLogger.shared.log(
                .app,
                "Speaker-names applied: total=\(merged.count), added/updated=\(applied), supported=\(Self.speakerNameDebugSummary(supported)), skipped_override_ids=\(skippedOverrides.sorted()), rejected_unsupported=\(rejected), rejected_ids=\(rejectedIDs), inferred=\(Self.speakerNameDebugSummary(sanitized))"
            )
        } catch {
            DebugLogger.shared.log(.app, "Speaker-names inference failed: \(error.localizedDescription)")
        }
    }

    /// Set or clear a user-controlled speaker name for the current live meeting.
    /// Pass a non-empty name to set + mark as overridden (inference won't overwrite).
    /// Pass `nil` or whitespace to clear the override so inference can refill.
    func setLiveSpeakerName(id: Int, name: String?) {
        let key = String(id)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var names = liveSpeakerNames
        var overrides = liveSpeakerOverrides
        if trimmed.isEmpty {
            names.removeValue(forKey: key)
            overrides.remove(key)
        } else {
            names[key] = trimmed
            overrides.insert(key)
        }
        liveSpeakerNames = names
        liveSpeakerOverrides = overrides

        // Mirror to the persisted meeting (if any) so the change survives across
        // resume-interrupted, app restarts, history, exports, and webhooks.
        if let meeting = currentMeeting {
            meeting.setSpeakerName(id: key, name: trimmed.isEmpty ? nil : trimmed)
            saveCurrentMeetingIfNeeded()
        }
        DebugLogger.shared.log(.app, "Speaker-name override: id=\(key), name=\(trimmed.isEmpty ? "<cleared>" : trimmed)")
    }

    /// Toggle whether a speaker is marked as the user ("You"). Supports multiple speakers
    /// being marked as self — useful when diarization splits one person across IDs. Marking
    /// clears any inferred/custom name for that ID so the resolver returns "You".
    func setLiveSelfSpeaker(id: Int, isSelf: Bool) {
        var set = liveSelfSpeakerIDs
        if isSelf {
            if set.isEmpty { set = effectiveLiveSelfSpeakerIDs }
            set.insert(id)
        } else {
            set.remove(id)
        }
        liveSelfSpeakerIDs = set

        if isSelf {
            let key = String(id)
            var names = liveSpeakerNames
            var overrides = liveSpeakerOverrides
            if names.removeValue(forKey: key) != nil { liveSpeakerNames = names }
            if overrides.remove(key) != nil { liveSpeakerOverrides = overrides }
        }
        if let meeting = currentMeeting {
            meeting.setSelfSpeaker(id: id, isSelf: isSelf)
            saveCurrentMeetingIfNeeded()
        }
        DebugLogger.shared.log(.app, "Self speaker toggle: id=\(id), isSelf=\(isSelf), total=\(liveSelfSpeakerIDs.count)")
    }

    /// The effective self-speaker set during the live session — explicit markings, or the
    /// mic speaker as a default. Always non-empty.
    var effectiveLiveSelfSpeakerIDs: Set<Int> {
        liveSelfSpeakerIDs.isEmpty ? [DeepgramService.micSpeakerID] : liveSelfSpeakerIDs
    }

    func resetSpeakerIdentityForDeepgramReconnect() {
        let micKey = String(DeepgramService.micSpeakerID)
        let previousNameCount = liveSpeakerNames.count
        let previousOverrideCount = liveSpeakerOverrides.count
        let previousSelfCount = liveSelfSpeakerIDs.count

        liveSpeakerNames = liveSpeakerNames.filter { $0.key == micKey }
        liveSpeakerOverrides = liveSpeakerOverrides.filter { $0 == micKey }
        liveSelfSpeakerIDs = liveSelfSpeakerIDs.filter { $0 == DeepgramService.micSpeakerID }
        lastSpeakerNamesSegmentCount = 0
        lastSpeakerNamesRequestAt = nil

        if let meeting = currentMeeting {
            meeting.speakerNames = liveSpeakerNames
            meeting.speakerOverrides = liveSpeakerOverrides
            meeting.selfSpeakerIDs = liveSelfSpeakerIDs
        }

        DebugLogger.shared.log(
            .app,
            "Speaker identity reset for Deepgram reconnect: names \(previousNameCount)->\(liveSpeakerNames.count), overrides \(previousOverrideCount)->\(liveSpeakerOverrides.count), self \(previousSelfCount)->\(liveSelfSpeakerIDs.count)"
        )
    }

    // MARK: - Zoned Out catch-up

    var canRequestZonedOutCatchUp: Bool {
        guard isRecording, currentMeeting != nil else { return false }
        let finalCount = liveSegments.count
        return finalCount >= catchUpTriggerMinSegments && !isGeneratingCatchUp
    }

    /// Present the Zoned Out catch-up UI and kick off a fresh fetch.
    func triggerZonedOutCatchUp() {
        guard isRecording, currentMeeting != nil else { return }
        DebugLogger.shared.log(.app, "Zoned out catch-up requested")
        isZonedOutPresented = true
        activeCatchUpTask?.cancel()
        activeCatchUpTask = Task { @MainActor [weak self] in
            await self?.fetchZonedOutCatchUp(userInitiated: true)
        }
    }

    /// Re-fetch the catch-up while the sheet is already open.
    func refreshZonedOutCatchUp() {
        guard isRecording, currentMeeting != nil else { return }
        activeCatchUpTask?.cancel()
        activeCatchUpTask = Task { @MainActor [weak self] in
            await self?.fetchZonedOutCatchUp(userInitiated: true)
        }
    }

    func dismissZonedOutCatchUp() {
        // Idempotent — safe to call repeatedly (e.g. when the sheet swipes down
        // AND the user taps "done"). Cancels any in-flight fetch; the in-flight
        // task self-exits via `Task.isCancelled` check before applying state.
        activeCatchUpTask?.cancel()
        activeCatchUpTask = nil
        isGeneratingCatchUp = false
        if isZonedOutPresented {
            isZonedOutPresented = false
        }
    }

    private func resetZonedOutState() {
        activeCatchUpTask?.cancel()
        activeCatchUpTask = nil
        zonedOutCatchUp = nil
        zonedOutCatchUpError = nil
        isGeneratingCatchUp = false
        isZonedOutPresented = false
        zonedOutCatchUpGeneratedAt = nil
    }

    @MainActor
    private func fetchZonedOutCatchUp(userInitiated: Bool) async {
        if isGeneratingCatchUp {
            DebugLogger.shared.log(.app, "Zoned out catch-up skipped: already in flight")
            return
        }

        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }

        guard !finalSegments.isEmpty else {
            zonedOutCatchUpError = "not enough speech captured yet — try again in a few seconds"
            return
        }

        let meetingIDAtRequest = currentMeeting?.id
        let recentSegments = recentCatchUpSegments(from: finalSegments)
        let recentTranscript = transcriptText(from: recentSegments)
        let fullTranscript = transcriptText(from: finalSegments)

        guard !recentTranscript.isEmpty else {
            zonedOutCatchUpError = "not enough speech captured yet — try again in a few seconds"
            return
        }

        isGeneratingCatchUp = true
        zonedOutCatchUpError = nil

        DebugLogger.shared.log(
            .app,
            "Zoned out catch-up start: recentSegments=\(recentSegments.count), recentChars=\(recentTranscript.count), fullChars=\(fullTranscript.count)"
        )

        do {
            let result: CatchUpResult
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                result = try await minitiAPIService.generateCatchUp(
                    deviceId: deviceId,
                    recentTranscript: recentTranscript,
                    fullTranscript: fullTranscript,
                    model: OpenAIModel.gpt5Mini.rawValue,
                    language: meetingLanguage
                )
            } else {
                guard let insightsService, !openaiApiKey.isEmpty else {
                    zonedOutCatchUpError = "openai api key required in settings"
                    isGeneratingCatchUp = false
                    return
                }
                result = try await insightsService.generateCatchUp(
                    recentTranscript: recentTranscript,
                    fullTranscript: fullTranscript,
                    model: .gpt5Mini,
                    apiKey: openaiApiKey,
                    language: meetingLanguage
                )
            }

            if Task.isCancelled {
                DebugLogger.shared.log(.app, "Dropping cancelled catch-up response")
                isGeneratingCatchUp = false
                return
            }

            guard currentMeeting?.id == meetingIDAtRequest else {
                DebugLogger.shared.log(.app, "Dropping stale catch-up response (meeting changed)")
                isGeneratingCatchUp = false
                return
            }

            if result.isEmpty {
                zonedOutCatchUp = nil
                zonedOutCatchUpError = "catch-up not available yet — keep recording for a bit and try again"
            } else {
                zonedOutCatchUp = result
                zonedOutCatchUpError = nil
                zonedOutCatchUpGeneratedAt = Date()
            }
            isGeneratingCatchUp = false
            _ = userInitiated
        } catch {
            // Cancellation is not a failure — the user (or a new request) cancelled us.
            if Task.isCancelled || (error is CancellationError) {
                DebugLogger.shared.log(.app, "Zoned out catch-up cancelled")
                isGeneratingCatchUp = false
                return
            }
            DebugLogger.shared.log(.app, "Zoned out catch-up FAILED: \(error.localizedDescription)")
            enqueueDiagnosticEvent(
                "insights_catchup_failed",
                category: .insights,
                level: .warning,
                details: ["error": error.localizedDescription]
            )
            if zonedOutCatchUp == nil {
                zonedOutCatchUpError = "couldn't generate catch-up — \(error.localizedDescription.lowercased())"
            } else {
                zonedOutCatchUpError = "couldn't refresh catch-up — showing the last one"
            }
            isGeneratingCatchUp = false
        }
    }

    /// Tail segments inside the catch-up window (default 3 minutes of wall-clock transcript time).
    /// Always keeps at least `catchUpFallbackWindowSegments` so we can still catch up in quiet meetings.
    private func recentCatchUpSegments(from finalSegments: [LiveSegment]) -> [LiveSegment] {
        guard !finalSegments.isEmpty else { return [] }
        guard let last = finalSegments.last else { return finalSegments }
        let cutoff = last.timestamp - catchUpRecentWindowSeconds
        let windowed = finalSegments.filter { $0.timestamp >= cutoff }
        if windowed.count >= catchUpFallbackWindowSegments { return windowed }
        let minCount = min(finalSegments.count, catchUpFallbackWindowSegments)
        return Array(finalSegments.suffix(minCount))
    }

    private func fetchLiveInsights(
        mode: InsightsMode,
        transcript: String,
        finalSegments: [LiveSegment],
        existingSummary: String?,
        existingTitle: String?
    ) async -> LiveInsightsFetchResult? {
        let model = OpenAIModel.gpt5Mini
        
        do {
            let insights: InsightsService.LiveInsights
            let requestPlan = makeManagedInsightsRequestPlan(
                mode: mode,
                finalSegments: finalSegments,
                fullTranscript: transcript
            )
            let usedIncrementalPayload = requestPlan.usesIncrementalPayload
            
            if appMode == .managed, let minitiAPIService {
                let seq: Int
                let lastApplied: Int
                switch mode {
                case .standard:
                    standardRequestSeq += 1
                    seq = standardRequestSeq
                    lastApplied = lastAppliedStandardSeq
                case .meddpicc:
                    meddpiccRequestSeq += 1
                    seq = meddpiccRequestSeq
                    lastApplied = lastAppliedMeddpiccSeq
                case .questions:
                    questionsRequestSeq += 1
                    seq = questionsRequestSeq
                    lastApplied = lastAppliedQuestionsSeq
                case .training, .docs:
                    seq = 0
                    lastApplied = -1
                }
                DebugLogger.shared.log(
                    .app,
                    "Live insights request: mode=\(mode.rawValue), model=\(model.rawValue), fullTranscriptChars=\(transcript.count), requestTranscriptChars=\(requestPlan.transcriptForRequest.count), incremental=\(usedIncrementalPayload), requestSeq=\(seq)"
                )
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response: ManagedInsightsResponse
                if mode == .meddpicc {
                    response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: requestPlan.transcriptForRequest,
                        existingSummary: existingSummary, existingTitle: existingTitle,
                        mode: mode.rawValue, model: model.rawValue,
                        incrementalPayload: requestPlan.incrementalPayload,
                        requestSeq: seq,
                        language: meetingLanguage
                    )
                } else {
                    let meetingAttendees = currentMeeting?.attendees ?? []
                    let attendeesPayload: [[String: String]]? = meetingAttendees.isEmpty ? nil : meetingAttendees.compactMap { a in
                        var entry: [String: String] = ["domain": a.domain]
                        if let name = a.displayName { entry["name"] = name }
                        if a.isOrganizer { entry["role"] = "organizer" }
                        else if a.isSelf { entry["role"] = "self" }
                        return entry
                    }
                    response = try await minitiAPIService.generateInsights(
                        deviceId: deviceId, transcript: requestPlan.transcriptForRequest,
                        existingSummary: existingSummary, existingTitle: existingTitle,
                        mode: mode.rawValue, model: model.rawValue,
                        incrementalPayload: requestPlan.incrementalPayload,
                        requestSeq: seq,
                        language: meetingLanguage,
                        attendees: attendeesPayload
                    )
                }
                if let responseSeq = response.meta?.requestSeq, responseSeq < lastApplied {
                    DebugLogger.shared.log(.app, "Dropping stale insights response: mode=\(mode.rawValue), responseSeq=\(responseSeq) < lastApplied=\(lastApplied)")
                    return nil
                }
                insights = response.toLiveInsights()
                return LiveInsightsFetchResult(
                    insights: insights,
                    usedIncrementalPayload: usedIncrementalPayload,
                    meta: response.meta
                )
            } else {
                DebugLogger.shared.log(
                    .app,
                    "Live insights request: mode=\(mode.rawValue), model=\(model.rawValue), fullTranscriptChars=\(transcript.count), requestTranscriptChars=\(requestPlan.transcriptForRequest.count), incremental=\(usedIncrementalPayload)"
                )
                guard let insightsService, !openaiApiKey.isEmpty else { return nil }
                insights = try await insightsService.generateLiveInsights(
                    transcript: requestPlan.transcriptForRequest, existingSummary: existingSummary,
                    existingTitle: existingTitle, mode: mode,
                    model: model, apiKey: openaiApiKey, language: meetingLanguage,
                    incrementalPayload: requestPlan.incrementalPayload
                )
                return LiveInsightsFetchResult(
                    insights: insights,
                    usedIncrementalPayload: usedIncrementalPayload,
                    meta: nil
                )
            }
        } catch {
            DebugLogger.shared.log(.app, "Live insights FAILED (\(mode.rawValue)): \(error.localizedDescription)")
            enqueueDiagnosticEvent(
                "insights_live_failed",
                category: .insights,
                level: .warning,
                details: ["mode": mode.rawValue, "error": error.localizedDescription]
            )
            return nil
        }
    }

    private let managedDeltaFullRequestChars = 35_000

    private func makeManagedInsightsRequestPlan(
        mode: InsightsMode,
        finalSegments: [LiveSegment],
        fullTranscript: String
    ) -> ManagedInsightsRequestPlan {
        if appMode == .managed, mode == .questions, !managedQuestionsIncrementalEnabled {
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        let successCount: Int = {
            switch mode {
            case .standard: return standardSuccessCount
            case .meddpicc: return meddpiccSuccessCount
            case .questions: return questionsSuccessCount
            case .training, .docs: return 0
            }
        }()
        if successCount < 2 {
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        let ackedSegmentCount: Int = {
            switch mode {
            case .standard: return min(managedStandardAckedSegmentCount, finalSegments.count)
            case .meddpicc: return min(managedMeddpiccAckedSegmentCount, finalSegments.count)
            case .questions: return min(managedQuestionsAckedSegmentCount, finalSegments.count)
            case .training, .docs: return 0
            }
        }()
        let deltaSegments = Array(finalSegments.dropFirst(ackedSegmentCount))
        let deltaTranscript = transcriptText(from: deltaSegments)
        if deltaTranscript.count > managedDeltaFullRequestChars {
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        let hasRollingContext: Bool = {
            switch mode {
            case .standard:
                return !lastStandardSummaryContext.isEmpty || !liveSummary.isEmpty
            case .meddpicc:
                let hasMeddpiccFields = [
                    liveMetrics, liveEconomicBuyer, liveDecisionCriteria, liveDecisionProcess,
                    livePaperProcess, liveIdentifiedPain, liveChampion, liveCompetition
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains { !$0.isEmpty && $0.lowercased() != "null" }
                return !lastMeddpiccSummaryContext.isEmpty || hasMeddpiccFields
            case .questions:
                return !liveQuestions.isEmpty
            case .training, .docs:
                return false
            }
        }()

        guard hasRollingContext else {
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        guard !deltaTranscript.isEmpty else {
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        let recentSegments = tailTranscriptSegments(
            from: finalSegments,
            maxChars: managedIncrementalRecentWindowChars
        )
        let recentTranscript = transcriptText(from: recentSegments)
        let transcriptForRequest = recentTranscript.isEmpty ? fullTranscript : recentTranscript

        let rollingState: MinitiAPIService.IncrementalInsightsRollingState
        switch mode {
        case .standard:
            rollingState = MinitiAPIService.IncrementalInsightsRollingState(
                summary: liveSummary.isEmpty ? nil : liveSummary,
                discussionFlow: liveDiscussionFlow,
                actionItems: liveActionItems,
                topics: liveTopics,
                suggestedTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                meddpicc: nil,
                questions: nil
            )
        case .meddpicc:
            var meddpicc: [String: String] = [:]
            func put(_ key: String, _ value: String?) {
                guard let value else { return }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                guard trimmed.lowercased() != "null" else { return }
                meddpicc[key] = trimmed
            }
            put("metrics", liveMetrics)
            put("economic_buyer", liveEconomicBuyer)
            put("decision_criteria", liveDecisionCriteria)
            put("decision_process", liveDecisionProcess)
            put("paper_process", livePaperProcess)
            put("identified_pain", liveIdentifiedPain)
            put("champion", liveChampion)
            put("competition", liveCompetition)

            rollingState = MinitiAPIService.IncrementalInsightsRollingState(
                summary: nil,
                discussionFlow: [],
                actionItems: [],
                topics: [],
                suggestedTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                meddpicc: meddpicc,
                questions: nil
            )
        case .questions:
            rollingState = MinitiAPIService.IncrementalInsightsRollingState(
                summary: nil,
                discussionFlow: [],
                actionItems: [],
                topics: [],
                suggestedTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                meddpicc: nil,
                questions: liveQuestions.map {
                    .init(
                        question: $0.question,
                        type: $0.type,
                        context: $0.context,
                        priority: $0.priority
                    )
                }
            )
        case .training, .docs:
            return ManagedInsightsRequestPlan(
                transcriptForRequest: fullTranscript,
                incrementalPayload: nil,
                usesIncrementalPayload: false
            )
        }

        let payload = MinitiAPIService.IncrementalInsightsPayload(
            strategy: "delta_recent_window_v1",
            fullSegmentCount: finalSegments.count,
            ackedSegmentCount: ackedSegmentCount,
            deltaSegmentCount: deltaSegments.count,
            recentSegmentCount: recentSegments.count,
            transcriptDelta: deltaTranscript,
            recentTranscript: recentTranscript,
            rollingState: rollingState
        )

        return ManagedInsightsRequestPlan(
            transcriptForRequest: transcriptForRequest,
            incrementalPayload: payload,
            usesIncrementalPayload: true
        )
    }

    nonisolated static func transcriptText(from segments: [LiveSegment]) -> String {
        segments
            .map { "[\($0.speakerLabel)] \($0.text)" }
            .joined(separator: "\n")
    }

    private func transcriptText(from segments: [LiveSegment]) -> String {
        if segmentsRepresentCurrentLiveTranscript(segments) {
            return cachedFullTranscript
        }
        return Self.transcriptText(from: segments)
    }

    private func transcriptTextWithSpeakerIDs(from segments: [LiveSegment]) -> String {
        if segmentsRepresentCurrentLiveTranscript(segments) {
            return cachedSpeakerIDTranscript
        }
        return Self.transcriptTextWithSpeakerIDs(from: segments)
    }

    private func segmentsRepresentCurrentLiveTranscript(_ segments: [LiveSegment]) -> Bool {
        guard segments.count == liveSegments.count else { return false }
        guard let first = segments.first, let last = segments.last,
              first.id == liveSegments.first?.id, last.id == liveSegments.last?.id else {
            return segments.isEmpty && liveSegments.isEmpty
        }
        return true
    }

    private func updateLiveTranscriptCaches(previous: [LiveSegment], current: [LiveSegment]) {
        // Array equality exits in O(1) when counts differ (the common append path),
        // but still catches a non-tail replacement accurately when counts match.
        if previous == current { return }

        let unchangedSuffixCount = min(3, min(previous.count, current.count))
        let prefixStillMatches = previous.first?.id == current.first?.id
            && (0..<unchangedSuffixCount).allSatisfy { offset in
                previous[previous.count - 1 - offset] == current[previous.count - 1 - offset]
            }

        liveTranscriptRevision &+= 1
        let canAppend = current.count > previous.count
            && (previous.isEmpty || prefixStillMatches)

        if canAppend {
            for segment in current.dropFirst(previous.count) where Self.isFinalNonEmptyLiveSegment(segment) {
                appendCachedTranscriptSegment(segment)
            }
            return
        }

        let rebuildSignpostID = OSSignpostID(log: appStatePerformanceLog)
        os_signpost(
            .begin,
            log: appStatePerformanceLog,
            name: "TranscriptCacheFullRebuild",
            signpostID: rebuildSignpostID,
            "segments=%{public}d",
            current.count
        )
        let finalized = Self.finalizedLiveSegments(from: current)
        cachedFullTranscript = Self.transcriptText(from: finalized)
        cachedSpeakerIDTranscript = Self.transcriptTextWithSpeakerIDs(from: finalized)
        cachedSaveSegments = finalized.map(Self.saveSnapshot(from:))
        os_signpost(
            .end,
            log: appStatePerformanceLog,
            name: "TranscriptCacheFullRebuild",
            signpostID: rebuildSignpostID,
            "finalized=%{public}d",
            finalized.count
        )
    }

    private func appendCachedTranscriptSegment(_ segment: LiveSegment) {
        let displayLine = "[\(segment.speakerLabel)] \(segment.text)"
        let speakerIDLine = "[SpeakerID:\(segment.speaker)] \(segment.text)"
        if !cachedFullTranscript.isEmpty { cachedFullTranscript.append("\n") }
        if !cachedSpeakerIDTranscript.isEmpty { cachedSpeakerIDTranscript.append("\n") }
        cachedFullTranscript.append(displayLine)
        cachedSpeakerIDTranscript.append(speakerIDLine)
        cachedSaveSegments.append(Self.saveSnapshot(from: segment))
    }

    nonisolated private static func saveSnapshot(from segment: LiveSegment) -> LiveSegmentSaveSnapshot {
        LiveSegmentSaveSnapshot(
            id: segment.id,
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
            speaker: segment.speaker,
            timestamp: segment.timestamp
        )
    }

    /// Build a transcript with raw speaker IDs embedded (e.g. `[SpeakerID:1000] ...`).
    /// Used for speaker-name inference so the model returns a map keyed by the stable internal IDs.
    nonisolated static func transcriptTextWithSpeakerIDs(from segments: [LiveSegment]) -> String {
        segments
            .map { "[SpeakerID:\($0.speaker)] \($0.text)" }
            .joined(separator: "\n")
    }

    nonisolated static func transcriptSupportedSpeakerNames(
        _ inferred: [String: String],
        finalSegments: [LiveSegment]
    ) -> [String: String] {
        let sanitized = SpeakerNamesResponse.sanitize(inferred)
        guard !sanitized.isEmpty else { return [:] }

        var supported: [String: String] = [:]
        for (key, name) in sanitized {
            guard let speaker = Int(key),
                  speakerNameHasTranscriptEvidence(name: name, speaker: speaker, segments: finalSegments) else {
                continue
            }
            supported[key] = name
        }
        return supported
    }

    private nonisolated static func speakerNameDebugSummary(_ names: [String: String]) -> String {
        guard !names.isEmpty else { return "[]" }
        let pairs = names
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .prefix(8)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let suffix = names.count > 8 ? ", +\(names.count - 8) more" : ""
        return "[\(pairs)\(suffix)]"
    }

    private nonisolated static func speakerNameHasTranscriptEvidence(
        name: String,
        speaker: Int,
        segments: [LiveSegment]
    ) -> Bool {
        let nameTokens = speakerNameTokens(name)
        guard let firstName = nameTokens.first else { return false }

        for segment in segments where segment.speaker == speaker {
            if textHasSelfIdentification(segment.text, firstName: firstName) {
                return true
            }
        }

        for index in segments.indices where segments[index].speaker != speaker {
            guard textContainsNameToken(segments[index].text, firstName) else { continue }
            let previousMatches = index > segments.startIndex && segments[segments.index(before: index)].speaker == speaker
            let nextIndex = segments.index(after: index)
            let nextMatches = nextIndex < segments.endIndex && segments[nextIndex].speaker == speaker
            if previousMatches || nextMatches {
                return true
            }
        }

        return false
    }

    private nonisolated static func textHasSelfIdentification(_ text: String, firstName: String) -> Bool {
        let words = normalizedWordTokens(text)
        guard !words.isEmpty else { return false }
        let introductoryPrefixes: [[String]] = [
            ["i", "am"],
            ["im"],
            ["i", "m"],
            ["my", "name", "is"],
            ["this", "is"],
            ["it", "s"],
            ["its"],
        ]

        for prefix in introductoryPrefixes where words.count > prefix.count {
            for index in 0...(words.count - prefix.count - 1) {
                let candidatePrefix = Array(words[index..<(index + prefix.count)])
                if candidatePrefix == prefix, words[index + prefix.count] == firstName {
                    return true
                }
            }
        }
        return false
    }

    private nonisolated static func textContainsNameToken(_ text: String, _ nameToken: String) -> Bool {
        normalizedWordTokens(text).contains(nameToken)
    }

    private nonisolated static func speakerNameTokens(_ name: String) -> [String] {
        normalizedWordTokens(name).filter { $0.count >= 2 }
    }

    private nonisolated static func normalizedWordTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var tokens: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    nonisolated static func tailTranscriptSegments(
        from segments: [LiveSegment],
        maxChars: Int
    ) -> [LiveSegment] {
        guard maxChars > 0 else { return [] }
        var selected: [LiveSegment] = []
        var totalChars = 0

        for segment in segments.reversed() {
            let line = "[\(segment.speakerLabel)] \(segment.text)"
            let lineCost = line.count + (selected.isEmpty ? 0 : 1)
            if !selected.isEmpty && totalChars + lineCost > maxChars {
                break
            }
            selected.append(segment)
            totalChars += lineCost
        }

        return selected.reversed()
    }

    private func tailTranscriptSegments(
        from segments: [LiveSegment],
        maxChars: Int
    ) -> [LiveSegment] {
        Self.tailTranscriptSegments(from: segments, maxChars: maxChars)
    }

    private func markManagedInsightsSuccess(
        mode: InsightsMode,
        segmentCount: Int,
        usedIncrementalPayload: Bool
    ) {
        switch mode {
        case .standard:
            managedStandardAckedSegmentCount = max(managedStandardAckedSegmentCount, segmentCount)
        case .meddpicc:
            managedMeddpiccAckedSegmentCount = max(managedMeddpiccAckedSegmentCount, segmentCount)
        case .questions:
            managedQuestionsAckedSegmentCount = max(managedQuestionsAckedSegmentCount, segmentCount)
        case .training, .docs:
            return
        }

        if usedIncrementalPayload {
            DebugLogger.shared.log(.app, "Live insights incremental cursor advanced: mode=\(mode.rawValue), ackedSegments=\(segmentCount)")
        }
    }

    private func resetManagedIncrementalTracking() {
        managedStandardAckedSegmentCount = 0
        managedMeddpiccAckedSegmentCount = 0
        managedQuestionsAckedSegmentCount = 0
        standardRequestSeq = 0
        meddpiccRequestSeq = 0
        questionsRequestSeq = 0
        docsRequestSeq = 0
        lastAppliedStandardSeq = -1
        lastAppliedMeddpiccSeq = -1
        lastAppliedQuestionsSeq = -1
        standardSuccessCount = 0
        meddpiccSuccessCount = 0
        questionsSuccessCount = 0
        docsSuccessCount = 0
        standardCadenceAnchor = nil
        meddpiccCadenceAnchor = nil
        questionsCadenceAnchor = nil
        standardLastAttemptAt = nil
        meddpiccLastAttemptAt = nil
        questionsLastAttemptAt = nil
        lastWarmupInsightsAttemptAt = nil
        standardLastFiredSegmentCount = 0
        meddpiccLastFiredSegmentCount = 0
        questionsLastFiredSegmentCount = 0
    }

    private func restoreManagedIncrementalTracking(finalCount: Int) {
        managedStandardAckedSegmentCount = finalCount
        managedMeddpiccAckedSegmentCount = finalCount
        managedQuestionsAckedSegmentCount = finalCount
    }
    
    /// Apply insights from either BYOK or managed mode to the live state.
    private func applyInsights(
        _ insights: InsightsService.LiveInsights,
        segmentCount: Int,
        mode: InsightsMode
    ) {
        if mode == .meddpicc {
            if let v = insights.metrics, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveMetrics = v }
            if let v = insights.economicBuyer, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveEconomicBuyer = v }
            if let v = insights.decisionCriteria, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveDecisionCriteria = v }
            if let v = insights.decisionProcess, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveDecisionProcess = v }
            if let v = insights.paperProcess, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { livePaperProcess = v }
            if let v = insights.identifiedPain, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveIdentifiedPain = v }
            if let v = insights.champion, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveChampion = v }
            if let v = insights.competition, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { liveCompetition = v }
        } else if mode == .questions {
            if !insights.questions.isEmpty {
                liveQuestions = insights.questions
                notifyNewHighPriorityQuestions(insights.questions)
            }
        } else {
            if !insights.summary.isEmpty { liveSummary = insights.summary }
            if !insights.actionItems.isEmpty { liveActionItems = insights.actionItems }
            if !insights.topics.isEmpty { liveTopics = insights.topics }
            if !insights.discussionFlow.isEmpty { liveDiscussionFlow = insights.discussionFlow }
        }
        
        // Only standard insights can update title to avoid MEDDPICC-only phrasing leaking into generic context.
        if let suggestedTitle = insights.suggestedTitle,
           !suggestedTitle.isEmpty,
           let meeting = currentMeeting,
           mode == .standard {
            let newSuffix = suggestedTitle.trimmingCharacters(in: .whitespaces)
            if newSuffix != currentTitleSuffix {
                currentTitleSuffix = newSuffix
                meeting.title = newSuffix
                lastTitleUpdateCount = segmentCount
                DebugLogger.shared.log(.app, "Live title updated: \(meeting.title)")
                #if os(iOS)
                updateLiveActivityState(isRecording: isRecording)
                #endif
            }
        }

        markInsightsUpdated(mode)
    }

    private func markInsightsUpdated(_ mode: InsightsMode, meeting: Meeting? = nil) {
        let now = Date()
        lastInsightsUpdatedAt[mode] = now
        let target = meeting ?? currentMeeting
        target?.insightsUpdatedAt = now
    }
    
    func startNewMeeting() {
        DebugLogger.shared.log(.app, "startNewMeeting (mode=\(appMode.rawValue))")
        updateLogRedaction()

        guard !isFinalizingMeeting else { return }
        recordingErrorMessage = nil
        finalizationStatusText = ""
        shouldOpenMeetingAfterFinalization = false

        guard hasAcceptedTerms else {
            DebugLogger.shared.log(.app, "startNewMeeting blocked: terms not accepted")
            return
        }
        
        switch appMode {
        case .byok:
            guard !deepgramApiKey.isEmpty else {
                showSettings = true
                return
            }
        case .managed:
            guard !isLimitReached else {
                return
            }
        }
        
        isStartingMeeting = true
        wasAutoStopped = false
        autoStopReason = nil
        calendarEventEndedWhileRecording = false
        
        // Save previous meeting if exists and has content
        saveCurrentMeetingIfNeeded()
        lastPeriodicSaveRequestedFingerprint = nil
        trainingMetricsTask?.cancel()
        trainingMetricsTask = nil
        
        let meeting = Meeting(title: "untitled")
        meeting.language = meetingLanguage
        currentMeeting = meeting
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
        #if os(macOS)
        resetEchoReconciliation()
        #endif
        liveSegments = []
        interimText = ""
        currentSpeaker = 0
        interimSpeaker = nil
        detectedSpeakers = []
        recordingDuration = 0
        recordingStartDate = nil
        accumulatedRecordedDuration = 0
        hasUnsavedSession = true
        managedSessionError = nil
        
        // Reset live notes and insights
        liveNotes = ""
        liveSummary = ""
        liveActionItems = []
        liveTopics = []
        liveDiscussionFlow = []
        lastStandardSummaryContext = ""
        lastMeddpiccSummaryContext = ""
        trainingMetrics = nil
        liveMetrics = nil
        liveEconomicBuyer = nil
        liveDecisionCriteria = nil
        liveDecisionProcess = nil
        livePaperProcess = nil
        liveIdentifiedPain = nil
        liveChampion = nil
        liveCompetition = nil
        liveQuestions = []
        liveDocTopics = []
        liveSpeakerNames = [:]
        liveSpeakerOverrides = []
        liveSelfSpeakerIDs = []
        notifiedQuestionIDs = []
        lastQuestionNotificationAt = nil
        resetZonedOutState()
        resetNudgeState()
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        lastMEDDPICCRequestAt = nil
        lastQuestionsSegmentCount = 0
        lastQuestionsRequestAt = nil
        lastSpeakerNamesSegmentCount = 0
        lastSpeakerNamesRequestAt = nil
        resetManagedIncrementalTracking()
        lastInsightsUpdatedAt = [:]
        
        if appMode == .managed {
            Task { await startManagedRecording() }
        } else {
            startRecording()
        }
    }
    
    func createNewSession() {
        // Stop recording if active (this saves and clears)
        if isRecording {
            stopRecording()
        } else {
            // Save and clear if not recording and a draft session exists
            if currentMeeting != nil {
                saveCurrentMeetingIfNeeded()
            }
            clearCurrentSession()
        }
    }
    
    /// Go back to home screen (clears current session after saving)
    func goHome() {
        guard !isFinalizingMeeting else { return }
        wasAutoStopped = false
        autoStopReason = nil
        calendarEventEndedWhileRecording = false
        
        // End Live Activity
        #if os(iOS)
        endLiveActivity()
        #endif
        
        // Finalize endTime (stopRecording already sets it; this covers edge cases)
        currentMeeting?.endTime = currentMeeting?.endTime ?? Date()
        
        // Save current meeting if there's content
        saveCurrentMeetingIfNeeded()

        // Auto-export markdown (reads live in-memory state before clearCurrentSession)
        #if os(macOS)
        if autoExportMarkdown, let meeting = currentMeeting {
            // Ensure training metrics are computed for the export
            if trainingMetrics == nil {
                let segments = liveSegments.map {
                    TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal, timestamp: $0.timestamp)
                }
                trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage, names: liveSpeakerNames, selfIDs: liveSelfSpeakerIDs)
            }
            let markdown = fullMeetingAsMarkdown()
            exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        #endif

        // Fire webhook with live in-memory state before clearing
        if !webhookURL.isEmpty, let meeting = currentMeeting {
            let names = liveSpeakerNames
            let selfIDs = liveSelfSpeakerIDs
            let transcriptEntries = liveSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
                .map { seg in
                    WebhookService.MeetingPayload.TranscriptEntry(
                        speaker: resolvedSpeakerLabel(for: seg.speaker, names: names, selfIDs: selfIDs),
                        text: seg.text,
                        timestamp: seg.timestamp
                    )
                }
            if trainingMetrics == nil {
                let segs = liveSegments.map {
                    TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal, timestamp: $0.timestamp)
                }
                trainingMetrics = TrainingMetrics.compute(from: segs, duration: recordingDuration, language: meetingLanguage, names: names, selfIDs: selfIDs)
            }
            let training = WebhookService.trainingData(from: trainingMetrics)
            let payload = WebhookService.payloadFromLiveState(
                meetingID: meeting.id,
                title: meeting.displayTitle,
                startTime: meeting.startTime,
                endTime: meeting.endTime,
                durationSeconds: Int(recordingDuration),
                language: meetingLanguage,
                summary: liveSummary,
                actionItems: liveActionItems,
                keyDecisions: meeting.keyDecisions,
                topics: liveTopics,
                discussionFlow: liveDiscussionFlow,
                notes: liveNotes,
                metrics: liveMetrics,
                economicBuyer: liveEconomicBuyer,
                decisionCriteria: liveDecisionCriteria,
                decisionProcess: liveDecisionProcess,
                paperProcess: livePaperProcess,
                identifiedPain: liveIdentifiedPain,
                champion: liveChampion,
                competition: liveCompetition,
                speakerCount: detectedSpeakers.count,
                speakerNames: names,
                transcript: transcriptEntries,
                training: training,
                questions: liveQuestions,
                docs: liveDocTopics.compactMap { $0.card },
                calendarEventId: meeting.calendarEventId,
                attendees: meeting.attendees
            )
            WebhookService.send(payload: payload, to: webhookURL)
        }

        // Auto-sync to Attio if configured
        if let meeting = currentMeeting, !meeting.attendees.isEmpty {
            autoSyncToAttio(meeting: meeting)
        }

        // Clear session and return to home
        clearCurrentSession()
        
        // Reset insights mode to standard for fresh start
        insightsMode = .standard
        selectedCalendarEvent = nil
    }

    /// Save the current meeting (stopping first if needed) and request the UI open it from history.
    func saveAndOpenCurrentMeeting() {
        pendingOpenSavedMeetingID = currentMeeting?.id
        if isRecording {
            shouldOpenMeetingAfterFinalization = true
            stopRecording()
            return
        }
        if isFinalizingMeeting {
            shouldOpenMeetingAfterFinalization = true
            return
        }
        goHome()
    }

    /// User-triggered repair for a degraded recording. Restarts capture in place and
    /// reconnects transcription without ending or creating a meeting.
    func retryRecordingHealth() {
        guard isRecording, let audioCaptureService else { return }
        recordingErrorMessage = nil
        applyAudioRecoveryState(.recovering)

        Task { @MainActor in
            audioCaptureService.stopCapture()
            do {
                audioCaptureService.onAudioBuffer = { [weak deepgramService] data in
                    deepgramService?.sendAudio(data)
                }
                try await audioCaptureService.startCapture(
                    microphone: captureMicrophone,
                    systemAudio: captureSystemAudio
                )

                deepgramReconnectTask?.cancel()
                deepgramReconnectTask = nil
                lastDeepgramReconnectScheduledAt = 0
                if deepgramService?.connectionState != .connected {
                    deepgramService?.disconnect()
                    scheduleDeepgramReconnect(reason: "manual retry")
                } else {
                    updateAudioRecoveryState()
                }
            } catch {
                recordingErrorMessage = "Audio could not restart. Check microphone permissions and your selected audio devices, then try again."
                applyAudioRecoveryState(.degraded)
                DebugLogger.shared.log(.app, "Manual recording repair FAILED: \(error.localizedDescription)")
            }
        }
    }

    func dismissRecordingError() {
        recordingErrorMessage = nil
    }
    
    /// Discard current meeting without saving — deletes from SwiftData and clears session
    func discardCurrentMeeting() {
        if let eventId = selectedCalendarEvent?.id {
            dismissedAutoStartEventIDs.insert(eventId)
        }

        #if os(iOS)
        endLiveActivity()
        #endif

        activeMeetingSaveTask?.cancel()
        activeMeetingSaveTask = nil
        queuedMeetingSavePayload = nil
        
        if let meeting = currentMeeting, let modelContext {
            deletedMeetingIDs.insert(meeting.id)
            modelContext.delete(meeting)
            try? modelContext.save()
        }
        
        clearCurrentSession()
        insightsMode = .standard
    }

    /// Record that a saved meeting is about to be deleted from history. Insight, docs, and save
    /// work already in flight holds a strong reference to the model and writes into it after its
    /// awaits resolve, which would resurrect the row the user just deleted. Call this *before*
    /// `modelContext.delete(_:)`.
    func noteMeetingDeleted(_ meeting: Meeting) {
        deletedMeetingIDs.insert(meeting.id)
        finalizingInsightMeetingIDs.remove(meeting.id)
        if currentMeeting?.id == meeting.id {
            activeMeetingSaveTask?.cancel()
            activeMeetingSaveTask = nil
            queuedMeetingSavePayload = nil
        }
    }

    /// Whether a meeting was discarded or deleted during this app run. Async work that resumes
    /// after a suspension point must check this before touching the model again.
    func isMeetingDeleted(_ id: UUID) -> Bool {
        deletedMeetingIDs.contains(id)
    }
    
    /// Generate only the currently selected insight view for a saved meeting.
    func generateInsightsForMeeting(_ meeting: Meeting) async {
        if insightsMode == .training {
            return
        }
        if insightsMode == .docs {
            await refreshDocsTopics(for: meeting)
            return
        }

        let canGenerate: Bool
        if appMode == .managed {
            canGenerate = minitiAPIService != nil
        } else {
            canGenerate = insightsService != nil && !openaiApiKey.isEmpty
        }
        guard canGenerate else { return }

        // Snapshot everything read across the awaits below: the user can delete this meeting from
        // history mid-generation, after which touching the model is unsafe and writing to it
        // resurrects the row.
        let meetingID = meeting.id
        let transcript = meeting.fullTranscript
        let language = meeting.language
        let requestedMode = insightsMode
        guard isInsightModeEnabled(requestedMode) else { return }
        let summaryForContext = meeting.summaryText
        guard !transcript.isEmpty else { return }
        
        isGeneratingInsights = true
        defer { isGeneratingInsights = false }
        let model = OpenAIModel.gpt5Mini
        
        if requestedMode == .standard {
            do {
                if appMode == .managed, let minitiAPIService {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await minitiAPIService.generateInsights(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: nil, existingTitle: nil,
                        mode: InsightsMode.standard.rawValue, model: model.rawValue,
                        language: language
                    )
                    guard !isMeetingDeleted(meetingID) else { return }
                    let insights = response.toLiveInsights()
                    meeting.summaryText = insights.summary
                    meeting.actionItems = insights.actionItems
                    meeting.topics = insights.topics
                    meeting.discussionFlow = insights.discussionFlow
                } else {
                    let insights = try await insightsService!.generateInsights(
                        transcript: transcript,
                        model: model, apiKey: openaiApiKey, language: language
                    )
                    guard !isMeetingDeleted(meetingID) else { return }
                    meeting.summaryText = insights.summary
                    meeting.actionItems = insights.actionItems
                    meeting.keyDecisions = insights.decisions
                    meeting.topics = insights.topics
                }
                markInsightsUpdated(.standard, meeting: meeting)
            } catch {
                DebugLogger.shared.log(.app, "History insights FAILED (standard): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_history_standard_failed", category: .insights, level: .warning)
            }
        }
        
        if requestedMode == .meddpicc {
            do {
                let meddpiccInsights: InsightsService.LiveInsights
                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: summaryForContext, existingTitle: nil,
                        mode: InsightsMode.meddpicc.rawValue, model: model.rawValue,
                        language: language
                    )
                    meddpiccInsights = response.toLiveInsights()
                } else {
                    meddpiccInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcript, existingSummary: summaryForContext,
                        existingTitle: nil, mode: .meddpicc,
                        model: model, apiKey: openaiApiKey, language: language
                    )
                }
                guard !isMeetingDeleted(meetingID) else { return }
                meeting.meddpiccMetrics = meddpiccInsights.metrics
                meeting.meddpiccEconomicBuyer = meddpiccInsights.economicBuyer
                meeting.meddpiccDecisionCriteria = meddpiccInsights.decisionCriteria
                meeting.meddpiccDecisionProcess = meddpiccInsights.decisionProcess
                meeting.meddpiccPaperProcess = meddpiccInsights.paperProcess
                meeting.meddpiccIdentifiedPain = meddpiccInsights.identifiedPain
                meeting.meddpiccChampion = meddpiccInsights.champion
                meeting.meddpiccCompetition = meddpiccInsights.competition
                markInsightsUpdated(.meddpicc, meeting: meeting)
            } catch {
                DebugLogger.shared.log(.app, "History insights FAILED (meddpicc): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_history_meddpicc_failed", category: .insights, level: .warning)
            }
        }
        
        if requestedMode == .questions {
            do {
                let questionsInsights: InsightsService.LiveInsights
                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: nil, existingTitle: nil,
                        mode: InsightsMode.questions.rawValue, model: model.rawValue,
                        language: language
                    )
                    questionsInsights = response.toLiveInsights()
                } else {
                    questionsInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcript, existingSummary: nil,
                        existingTitle: nil, mode: .questions,
                        model: model, apiKey: openaiApiKey, language: language
                    )
                }
                guard !isMeetingDeleted(meetingID) else { return }
                meeting.suggestedQuestions = questionsInsights.questions
                markInsightsUpdated(.questions, meeting: meeting)
            } catch {
                DebugLogger.shared.log(.app, "History insights FAILED (questions): \(error.localizedDescription)")
            }
        }

        guard !isMeetingDeleted(meetingID) else { return }
        try? modelContext?.save()

        // Re-export markdown with updated insights
        #if os(macOS)
        if autoExportMarkdown {
            let markdown = meeting.fullMeetingAsMarkdown()
            exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        #endif

        // Fire webhook with updated meeting data
        if !webhookURL.isEmpty {
            let payload = WebhookService.payloadFromMeeting(meeting)
            WebhookService.send(payload: payload, to: webhookURL)
        }
    }

    @discardableResult
    func applyTranscriptTrim(_ operation: TranscriptTrimOperation, to meeting: Meeting) -> Bool {
        guard !operation.isEmpty else { return false }
        guard let modelContext else {
            DebugLogger.shared.log(.app, "Transcript trim skipped: no model context")
            return false
        }

        var didChange = false
        let deleteIDs = operation.segmentIDsToDelete
        if !deleteIDs.isEmpty {
            for segment in meeting.segments where deleteIDs.contains(segment.id) {
                modelContext.delete(segment)
            }
            let oldCount = meeting.segments.count
            meeting.segments.removeAll { deleteIDs.contains($0.id) }
            didChange = didChange || oldCount != meeting.segments.count
        }

        let selectionsBySegment = Dictionary(
            grouping: operation.textSelections.filter { selection in
                !selection.isEmpty && !deleteIDs.contains(selection.segmentID)
            },
            by: \.segmentID
        )

        for (segmentID, selections) in selectionsBySegment {
            guard let segment = meeting.segments.first(where: { $0.id == segmentID }) else { continue }
            let trimmed = Self.transcriptTextAfterDeletingSelections(selections, from: segment.text)
            guard trimmed != segment.text else { continue }
            if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelContext.delete(segment)
                meeting.segments.removeAll { $0.id == segmentID }
            } else {
                segment.text = trimmed
                segment.isFinal = true
            }
            didChange = true
        }

        guard didChange else { return false }
        meeting.markTranscriptEdited()

        do {
            try modelContext.save()
        } catch {
            DebugLogger.shared.log(.app, "Transcript trim save FAILED: \(error.localizedDescription)")
            return false
        }

        #if os(macOS)
        if autoExportMarkdown {
            exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
        }
        #endif

        if !webhookURL.isEmpty {
            WebhookService.send(payload: WebhookService.payloadFromMeeting(meeting), to: webhookURL)
        }

        DebugLogger.shared.log(.app, "Transcript trim applied: meeting=\(meeting.id), revision=\(meeting.transcriptRevision)")
        return true
    }

    @discardableResult
    func restoreTranscriptSnapshots(_ snapshots: [TranscriptSegmentSnapshot], to meeting: Meeting) -> Bool {
        guard !snapshots.isEmpty else { return false }
        guard let modelContext else {
            DebugLogger.shared.log(.app, "Transcript restore skipped: no model context")
            return false
        }

        for segment in meeting.segments {
            modelContext.delete(segment)
        }
        meeting.segments = snapshots
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                TranscriptSegment(
                    id: $0.id,
                    text: $0.text,
                    speaker: $0.speaker,
                    timestamp: $0.timestamp,
                    isFinal: $0.isFinal,
                    confidence: $0.confidence
                )
            }
        meeting.markTranscriptEdited()

        do {
            try modelContext.save()
        } catch {
            DebugLogger.shared.log(.app, "Transcript restore save FAILED: \(error.localizedDescription)")
            return false
        }

        #if os(macOS)
        if autoExportMarkdown {
            exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
        }
        #endif

        if !webhookURL.isEmpty {
            WebhookService.send(payload: WebhookService.payloadFromMeeting(meeting), to: webhookURL)
        }

        DebugLogger.shared.log(.app, "Transcript trim undone: meeting=\(meeting.id), revision=\(meeting.transcriptRevision)")
        return true
    }

    nonisolated static func transcriptTextAfterDeletingSelections(
        _ selections: [TranscriptTextSelection],
        from originalText: String
    ) -> String {
        guard !selections.isEmpty, !originalText.isEmpty else { return originalText }
        var text = originalText
        let orderedSelections = selections
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.lowerUTF16Offset > rhs.lowerUTF16Offset
            }

        for selection in orderedSelections {
            let lower = max(0, min(selection.lowerUTF16Offset, text.utf16.count))
            let upper = max(lower, min(selection.upperUTF16Offset, text.utf16.count))
            guard lower < upper else { continue }
            let utf16Lower = text.utf16.index(text.utf16.startIndex, offsetBy: lower)
            let utf16Upper = text.utf16.index(text.utf16.startIndex, offsetBy: upper)
            guard let lowerIndex = String.Index(utf16Lower, within: text),
                  let upperIndex = String.Index(utf16Upper, within: text) else {
                continue
            }
            text.removeSubrange(lowerIndex..<upperIndex)
        }

        return normalizeTranscriptTrimWhitespace(text)
    }

    nonisolated private static func normalizeTranscriptTrimWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Restore an interrupted meeting (endTime == nil) from SwiftData on launch.
    /// Sets currentMeeting and rebuilds in-memory state so the UI shows the stopped-session view.
    func resumeInterruptedMeeting() {
        guard let modelContext else { return }
        guard currentMeeting == nil, !isRecording else { return }
        
        let descriptor = FetchDescriptor<Meeting>()
        guard let meetings = try? modelContext.fetch(descriptor) else { return }
        let now = Date()
        let interruptedMeetings = meetings
            .filter { $0.endTime == nil && !$0.segments.isEmpty }

        let staleInterruptedMeetings = interruptedMeetings
            .filter { Self.isInterruptedMeetingTooOldToAutoResume($0, now: now) }
        finalizeStaleInterruptedMeetings(staleInterruptedMeetings, now: now)

        guard let interrupted = interruptedMeetings
            .filter({ !Self.isInterruptedMeetingTooOldToAutoResume($0, now: now) })
            .max(by: { $0.startTime < $1.startTime })
        else { return }
        
        DebugLogger.shared.log(.app, "Resuming interrupted meeting: \(interrupted.title), segments=\(interrupted.segments.count)")
        
        currentMeeting = interrupted
        meetingLanguage = interrupted.language
        
        // Reconstruct liveSegments from persisted TranscriptSegments
        liveSegments = interrupted.segments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .map { seg in
                LiveSegment(
                    id: seg.id,
                    text: seg.text,
                    speaker: seg.speaker,
                    timestamp: seg.timestamp,
                    isFinal: seg.isFinal
                )
            }
        
        // Restore insights
        liveSummary = interrupted.summaryText ?? ""
        liveActionItems = interrupted.actionItems
        liveTopics = interrupted.topics
        liveDiscussionFlow = interrupted.discussionFlow
        liveNotes = interrupted.notes
        
        // Restore MEDDPICC
        liveMetrics = interrupted.meddpiccMetrics
        liveEconomicBuyer = interrupted.meddpiccEconomicBuyer
        liveDecisionCriteria = interrupted.meddpiccDecisionCriteria
        liveDecisionProcess = interrupted.meddpiccDecisionProcess
        livePaperProcess = interrupted.meddpiccPaperProcess
        liveIdentifiedPain = interrupted.meddpiccIdentifiedPain
        liveChampion = interrupted.meddpiccChampion
        liveCompetition = interrupted.meddpiccCompetition
        liveQuestions = interrupted.suggestedQuestions
        liveDocTopics = interrupted.docTopics
        liveSpeakerNames = interrupted.speakerNames
        liveSpeakerOverrides = interrupted.speakerOverrides
        liveSelfSpeakerIDs = interrupted.selfSpeakerIDs

        if salesInsightsEnabled, interrupted.hasMEDDPICC {
            insightsMode = .meddpicc
        }
        
        // Restore duration from last segment timestamp (actual recorded duration, not wall clock)
        if let lastSegment = liveSegments.last {
            recordingDuration = lastSegment.timestamp
            accumulatedRecordedDuration = recordingDuration
        }
        
        // Restore detected speakers
        detectedSpeakers = Set(liveSegments.map(\.speaker))
        
        // Restore title tracking (handles both old timestamp-prefixed and new clean titles)
        if let (_, suffix) = Self.parseMeetingTitle(interrupted.title) {
            currentTitleSuffix = suffix
        } else {
            currentTitleSuffix = interrupted.title
        }
        
        // Track segment counts so insight generation doesn't re-trigger unnecessarily
        let finalCount = liveSegments.count
        lastInsightSegmentCount = finalCount
        lastMEDDPICCSegmentCount = finalCount
        lastMEDDPICCRequestAt = Date()
        lastTitleUpdateCount = finalCount
        restoreManagedIncrementalTracking(finalCount: finalCount)
        
        hasUnsavedSession = true
        
        #if os(iOS)
        restorePausedLiveActivity()
        #endif
        
        // Report orphaned managed session usage to backend
        if appMode == .managed, let sessionId = interrupted.managedSessionId, !sessionId.isEmpty {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            let durationMinutes = recordingDuration / 60.0
            Task {
                let report = PendingSessionEndReport(
                    deviceId: deviceId,
                    sessionId: sessionId,
                    durationMinutes: durationMinutes,
                    meetingId: interrupted.id
                )
                await reportManagedSessionEnd(report, trigger: "orphaned resume")
            }
        }
        
        DebugLogger.shared.log(.app, "Interrupted session restored: segments=\(liveSegments.count), duration=\(formattedDuration)")
    }

    static let interruptedMeetingAutoResumeMaxAge: TimeInterval = 12 * 60 * 60

    /// Best estimate of the last moment the meeting was actively recording — the latest segment
    /// timestamp offset from `startTime`, clamped into the range `[startTime, now]`. Used as the
    /// reference for both the staleness check and the auto-finalised `endTime`, so a long-running
    /// but recently-active draft isn't misclassified as stale just because `startTime` is old.
    static func estimatedLastActivity(_ meeting: Meeting, now: Date = Date()) -> Date {
        let latestSegmentOffset = meeting.segments.map(\.timestamp).max() ?? 0
        let candidate = meeting.startTime.addingTimeInterval(max(0, latestSegmentOffset))
        return min(max(candidate, meeting.startTime), now)
    }

    static func isInterruptedMeetingTooOldToAutoResume(_ meeting: Meeting, now: Date = Date()) -> Bool {
        let lastActivity = estimatedLastActivity(meeting, now: now)
        return now.timeIntervalSince(lastActivity) > interruptedMeetingAutoResumeMaxAge
    }

    private func finalizeStaleInterruptedMeetings(_ meetings: [Meeting], now: Date) {
        guard !meetings.isEmpty else { return }

        var pendingReports: [PendingSessionEndReport] = []
        for meeting in meetings {
            let endTime = Self.estimatedLastActivity(meeting, now: now)
            meeting.endTime = endTime

            if appMode == .managed, let sessionId = meeting.managedSessionId, !sessionId.isEmpty {
                pendingReports.append(
                    PendingSessionEndReport(
                        deviceId: DeviceIdentifier.getOrCreateDeviceId(),
                        sessionId: sessionId,
                        durationMinutes: max(0, endTime.timeIntervalSince(meeting.startTime)) / 60.0,
                        meetingId: meeting.id
                    )
                )
            }
        }

        try? modelContext?.save()
        DebugLogger.shared.log(.app, "Finalized stale interrupted meetings: count=\(meetings.count)")

        for report in pendingReports {
            Task {
                await reportManagedSessionEnd(report, trigger: "stale interrupted resume")
            }
        }
    }
    
    func switchInsightsMode(to mode: InsightsMode) {
        if mode.isSpecialist {
            setInsightModeEnabled(mode, enabled: true)
        }
        insightsMode = mode

        if mode == .training {
            scheduleTrainingMetricsRecompute()
        }
        // Populate the docs-topic list on first visit to the tab so it's ready
        // without waiting for the next cadence tick. Auto-lookup (Pro/BYOK) then
        // follows from the merge inside refreshDocsTopics.
        if mode == .docs, validatedDocsMCPURL != nil, liveDocTopics.isEmpty, currentDocsTranscript() != nil {
            Task { @MainActor in await refreshDocsTopics() }
        }
    }
    
    /// Recompute training metrics from current live segments
    func recomputeTrainingMetrics() {
        trainingMetricsTask?.cancel()
        let segments = liveSegments.map {
            TrainingMetrics.Segment(
                text: $0.text,
                speaker: $0.speaker,
                isFinal: $0.isFinal,
                timestamp: $0.timestamp
            )
        }
        trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage, names: liveSpeakerNames, selfIDs: liveSelfSpeakerIDs)
    }

    private func scheduleTrainingMetricsRecompute() {
        trainingMetricsTask?.cancel()
        let revision = liveTranscriptRevision
        let segments = liveSegments.map {
            TrainingMetrics.Segment(
                text: $0.text,
                speaker: $0.speaker,
                isFinal: $0.isFinal,
                timestamp: $0.timestamp
            )
        }
        let duration = recordingDuration
        let language = meetingLanguage
        let names = liveSpeakerNames
        let selfIDs = liveSelfSpeakerIDs

        trainingMetricsTask = Task { [weak self] in
            let metrics = await Task.detached(priority: .utility) {
                TrainingMetrics.compute(
                    from: segments,
                    duration: duration,
                    language: language,
                    names: names,
                    selfIDs: selfIDs
                )
            }.value
            guard !Task.isCancelled, let self,
                  self.liveTranscriptRevision == revision,
                  self.insightsMode == .training else { return }
            self.trainingMetrics = metrics
        }
    }

    /// Save current meeting to SwiftData if it has transcript content.
    /// Called periodically during recording, on background transition, and on goHome/stopRecording.
    /// Does NOT set endTime — callers (stopRecording, goHome) set it explicitly so that
    /// meetings with endTime == nil can be identified as interrupted and resumed on next launch.
    func saveCurrentMeetingIfNeeded(onlyIfChanged: Bool = false) {
        let fingerprint = periodicSaveFingerprint()
        if onlyIfChanged, lastPeriodicSaveRequestedFingerprint == fingerprint {
            return
        }
        guard let payload = makeMeetingSavePayload(
            periodicFingerprint: onlyIfChanged ? fingerprint : nil
        ) else { return }
        if onlyIfChanged {
            lastPeriodicSaveRequestedFingerprint = fingerprint
        }
        enqueueMeetingSave(payload)
    }

    private func periodicSaveFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(currentMeeting?.id)
        hasher.combine(liveTranscriptRevision)
        hasher.combine(liveSummary)
        hasher.combine(liveActionItems)
        hasher.combine(liveTopics)
        hasher.combine(liveDiscussionFlow)
        hasher.combine(liveNotes)
        hasher.combine(liveMetrics)
        hasher.combine(liveEconomicBuyer)
        hasher.combine(liveDecisionCriteria)
        hasher.combine(liveDecisionProcess)
        hasher.combine(livePaperProcess)
        hasher.combine(liveIdentifiedPain)
        hasher.combine(liveChampion)
        hasher.combine(liveCompetition)
        for question in liveQuestions {
            hasher.combine(question.question)
            hasher.combine(question.type)
            hasher.combine(question.context)
            hasher.combine(question.priority)
        }
        if let topicsData = try? JSONEncoder().encode(liveDocTopics) {
            hasher.combine(topicsData)
        }
        for pair in liveSpeakerNames.sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        for value in liveSpeakerOverrides.sorted() { hasher.combine(value) }
        for value in liveSelfSpeakerIDs.sorted() { hasher.combine(value) }
        return hasher.finalize()
    }

    private func makeMeetingSavePayload(periodicFingerprint: Int?) -> MeetingSavePayload? {
        guard let meeting = currentMeeting else { return nil }

        let finalSegments = cachedSaveSegments

        guard !finalSegments.isEmpty else { return nil }

        return MeetingSavePayload(
            meeting: meeting,
            periodicFingerprint: periodicFingerprint,
            finalSegments: finalSegments,
            summary: liveSummary,
            actionItems: liveActionItems,
            topics: liveTopics,
            discussionFlow: liveDiscussionFlow,
            notes: liveNotes,
            meddpiccMetrics: liveMetrics,
            meddpiccEconomicBuyer: liveEconomicBuyer,
            meddpiccDecisionCriteria: liveDecisionCriteria,
            meddpiccDecisionProcess: liveDecisionProcess,
            meddpiccPaperProcess: livePaperProcess,
            meddpiccIdentifiedPain: liveIdentifiedPain,
            meddpiccChampion: liveChampion,
            meddpiccCompetition: liveCompetition,
            suggestedQuestions: liveQuestions,
            docTopics: liveDocTopics,
            speakerNames: liveSpeakerNames,
            speakerOverrides: liveSpeakerOverrides,
            selfSpeakerIDs: liveSelfSpeakerIDs
        )
    }

    private func enqueueMeetingSave(_ payload: MeetingSavePayload) {
        if activeMeetingSaveTask != nil {
            queuedMeetingSavePayload = payload
            return
        }

        activeMeetingSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var nextPayload: MeetingSavePayload? = payload
            while let payloadToPersist = nextPayload {
                await self.persistMeetingSavePayload(payloadToPersist)
                if let queued = self.queuedMeetingSavePayload {
                    self.queuedMeetingSavePayload = nil
                    nextPayload = queued
                } else {
                    nextPayload = nil
                }
            }
            self.activeMeetingSaveTask = nil
        }
    }

    private func persistMeetingSavePayload(_ payload: MeetingSavePayload) async {
        guard let modelContext else {
            DebugLogger.shared.log(.app, "Save skipped: no model context")
            clearPeriodicSaveFingerprintIfCurrent(payload.periodicFingerprint)
            return
        }

        // Read before the suspension point below: after it, the meeting may have been deleted,
        // and reading any property of a dead model traps.
        let meetingID = payload.meeting.id
        let existingSnapshots = payload.meeting.segments.map {
            PersistedSegmentSnapshot(
                id: $0.id,
                text: $0.text,
                speaker: $0.speaker,
                timestamp: $0.timestamp
            )
        }
        let finalSegmentSnapshots = payload.finalSegments

        let planSignpostID = OSSignpostID(log: appStatePerformanceLog)
        os_signpost(
            .begin,
            log: appStatePerformanceLog,
            name: "MeetingSavePlan",
            signpostID: planSignpostID,
            "desired=%{public}d existing=%{public}d",
            finalSegmentSnapshots.count,
            existingSnapshots.count
        )
        let syncPlan = await Task.detached(priority: .utility) {
            Self.buildSegmentSyncPlan(
                finalSegments: finalSegmentSnapshots,
                existingSegments: existingSnapshots
            )
        }.value
        os_signpost(
            .end,
            log: appStatePerformanceLog,
            name: "MeetingSavePlan",
            signpostID: planSignpostID,
            "upserts=%{public}d deletes=%{public}d",
            syncPlan.upserts.count,
            syncPlan.deleteIDs.count
        )

        // The off-main diff above is a suspension point, so the meeting can be discarded while we
        // are suspended. Re-check before writing: the insert below would otherwise resurrect a
        // meeting the user already deleted.
        guard !Task.isCancelled, !isMeetingDeleted(meetingID) else {
            clearPeriodicSaveFingerprintIfCurrent(payload.periodicFingerprint)
            return
        }

        let applySignpostID = OSSignpostID(log: appStatePerformanceLog)
        os_signpost(
            .begin,
            log: appStatePerformanceLog,
            name: "MeetingSaveApply",
            signpostID: applySignpostID,
            "upserts=%{public}d deletes=%{public}d",
            syncPlan.upserts.count,
            syncPlan.deleteIDs.count
        )
        applySegmentSyncPlan(syncPlan, to: payload.meeting, modelContext: modelContext)

        if !payload.summary.isEmpty {
            payload.meeting.summaryText = payload.summary
            payload.meeting.actionItems = payload.actionItems
            payload.meeting.topics = payload.topics
            payload.meeting.discussionFlow = payload.discussionFlow
        }

        payload.meeting.notes = payload.notes
        payload.meeting.meddpiccMetrics = payload.meddpiccMetrics
        payload.meeting.meddpiccEconomicBuyer = payload.meddpiccEconomicBuyer
        payload.meeting.meddpiccDecisionCriteria = payload.meddpiccDecisionCriteria
        payload.meeting.meddpiccDecisionProcess = payload.meddpiccDecisionProcess
        payload.meeting.meddpiccPaperProcess = payload.meddpiccPaperProcess
        payload.meeting.meddpiccIdentifiedPain = payload.meddpiccIdentifiedPain
        payload.meeting.meddpiccChampion = payload.meddpiccChampion
        payload.meeting.meddpiccCompetition = payload.meddpiccCompetition
        payload.meeting.suggestedQuestions = payload.suggestedQuestions
        payload.meeting.docTopics = payload.docTopics
        payload.meeting.speakerNames = payload.speakerNames
        payload.meeting.speakerOverrides = payload.speakerOverrides
        payload.meeting.selfSpeakerIDs = payload.selfSpeakerIDs

        if payload.meeting.modelContext == nil {
            modelContext.insert(payload.meeting)
        }
        os_signpost(
            .end,
            log: appStatePerformanceLog,
            name: "MeetingSaveApply",
            signpostID: applySignpostID
        )

        let commitSignpostID = OSSignpostID(log: appStatePerformanceLog)
        os_signpost(
            .begin,
            log: appStatePerformanceLog,
            name: "MeetingStoreCommit",
            signpostID: commitSignpostID
        )
        do {
            try modelContext.save()
            hasUnsavedSession = false
        } catch {
            clearPeriodicSaveFingerprintIfCurrent(payload.periodicFingerprint)
            DebugLogger.shared.log(.app, "Save FAILED: \(error.localizedDescription)")
        }
        os_signpost(
            .end,
            log: appStatePerformanceLog,
            name: "MeetingStoreCommit",
            signpostID: commitSignpostID
        )
    }

    private func clearPeriodicSaveFingerprintIfCurrent(_ fingerprint: Int?) {
        guard let fingerprint, lastPeriodicSaveRequestedFingerprint == fingerprint else { return }
        lastPeriodicSaveRequestedFingerprint = nil
    }

    nonisolated static func buildSegmentSyncPlan(
        finalSegments: [LiveSegmentSaveSnapshot],
        existingSegments: [PersistedSegmentSnapshot]
    ) -> SegmentSyncPlan {
        let desiredIDs = Set(finalSegments.map(\.id))
        let deleteIDs = existingSegments
            .map(\.id)
            .filter { !desiredIDs.contains($0) }

        let existingByID = existingSegments.reduce(into: [UUID: PersistedSegmentSnapshot]()) { partial, segment in
            partial[segment.id] = segment
        }
        let upserts = finalSegments.filter { segment in
            guard let existing = existingByID[segment.id] else { return true }
            return existing.text != segment.text ||
                existing.speaker != segment.speaker ||
                abs(existing.timestamp - segment.timestamp) > 0.001
        }

        return SegmentSyncPlan(deleteIDs: deleteIDs, upserts: upserts)
    }

    private func applySegmentSyncPlan(
        _ plan: SegmentSyncPlan,
        to meeting: Meeting,
        modelContext: ModelContext
    ) {
        if !plan.deleteIDs.isEmpty {
            let deleteSet = Set(plan.deleteIDs)
            for segment in meeting.segments where deleteSet.contains(segment.id) {
                modelContext.delete(segment)
            }
            meeting.segments.removeAll { deleteSet.contains($0.id) }
        }

        var existingByID = meeting.segments.reduce(into: [UUID: TranscriptSegment]()) { partial, segment in
            partial[segment.id] = segment
        }
        var insertedSegments: [TranscriptSegment] = []
        insertedSegments.reserveCapacity(plan.upserts.count)
        for upsert in plan.upserts {
            if let existing = existingByID[upsert.id] {
                existing.text = upsert.text
                existing.speaker = upsert.speaker
                existing.timestamp = upsert.timestamp
                existing.isFinal = true
            } else {
                let newSegment = TranscriptSegment(
                    id: upsert.id,
                    text: upsert.text,
                    speaker: upsert.speaker,
                    timestamp: upsert.timestamp,
                    isFinal: true
                )
                insertedSegments.append(newSegment)
                existingByID[upsert.id] = newSegment
            }
        }
        // Publish one relationship mutation after a long meeting save. Appending each
        // segment individually can invalidate the historical transcript hundreds of
        // times while the detail view is already visible.
        if !insertedSegments.isEmpty {
            meeting.segments.append(contentsOf: insertedSegments)
        }
    }
    
    // MARK: - Audio Monitoring (home screen pre-flight check)
    
    func startAudioMonitoring() {
        guard let audioCaptureService else { return }
        guard !isRecording else { return }
        
        isMonitoring = true
        
        // Monitor only - don't send data to Deepgram
        audioCaptureService.onAudioBuffer = nil
        
        Task {
            do {
                try await audioCaptureService.startCapture(
                    microphone: captureMicrophone,
                    systemAudio: captureSystemAudio
                )
            } catch {
                DebugLogger.shared.log(.app, "Audio monitoring FAILED: \(error.localizedDescription)")
            }
        }
    }
    
    func stopAudioMonitoring() {
        guard isMonitoring else { return }
        audioCaptureService?.stopCapture()
        isMonitoring = false
        audioLevels.reset()
        lastAudioActivityAt = 0
    }
    
    /// Restart monitoring after toggling an audio source
    func restartAudioMonitoring() {
        guard isMonitoring else { return }
        stopAudioMonitoring()
        startAudioMonitoring()
    }
    
    func startRecording() {
        guard let audioCaptureService, let deepgramService else { return }

        guard !isFinalizingMeeting else {
            DebugLogger.shared.log(.app, "startRecording blocked: meeting finalization in progress")
            return
        }

        guard !isCurrentMeetingGeneratingFinalInsights else {
            DebugLogger.shared.log(.app, "startRecording blocked: final insights are still being applied to this meeting")
            return
        }

        guard hasAcceptedTerms else {
            DebugLogger.shared.log(.app, "startRecording blocked: terms not accepted")
            return
        }
        
        DebugLogger.shared.log(.app, "startRecording (mode=\(appMode.rawValue), mic=\(captureMicrophone), sys=\(captureSystemAudio))")
        recordingErrorMessage = nil
        finalizationStatusText = ""
        isStartingMeeting = false
        isResumingRecording = false
        currentMeeting?.endTime = nil
        
        // In managed mode, if the JWT is missing/expired (e.g. resuming after stop),
        // request a fresh /api/session before connecting to Deepgram.
        if appMode == .managed && !hasFreshManagedDeepgramCredential {
            isResumingRecording = true
            Task { await startManagedRecording() }
            return
        }
        
        // Stop monitoring if active (clean transition)
        if isMonitoring {
            stopAudioMonitoring()
        }
        
        isRecording = true
        pendingAudioRecoveryTransitionTask?.cancel()
        pendingAudioRecoveryTransitionTask = nil
        trainingMetricsTask?.cancel()
        trainingMetricsTask = nil
        lastPeriodicSaveRequestedFingerprint = nil
        audioRecoveryState = .healthy
        desiredAudioRecoveryState = .healthy
        systemAudioInactiveSince = 0
        deepgramReconnectTask?.cancel()
        deepgramReconnectTask = nil
        deepgramReconnectGeneration += 1
        lastDeepgramReconnectScheduledAt = 0
        lastTranscriptReceivedAt = CFAbsoluteTimeGetCurrent()
        lastTranscriptStarvationRecoveryAt = 0
        consecutiveTranscriptRecoveries = 0
        lastTranscriptHealthDebugLogAt = 0
        lastAudioActivityAt = 0
        startTranscriptHealthMonitoring()
        
        configureDeepgramServiceCredential()
        
        #if os(macOS)
        let useMultichannel = captureMicrophone && captureSystemAudio
        if useMultichannel {
            resetEchoReconciliation(flushPending: true)
            // Multichannel attributes mic via channel 0 — no energy-based sourceLookup.
            audioCaptureService.resetSourceTracking()
            deepgramService.sourceLookup = nil
        } else {
            deepgramService.sourceLookup = nil
        }
        #else
        let useMultichannel = false
        deepgramService.sourceLookup = nil
        #endif
        
        deepgramService.connect(
            language: meetingLanguage,
            personalDictionaryTerms: PersonalDictionaryPreferences.currentTerms(),
            sessionKeyterms: deepgramSessionKeyterms(),
            multichannel: useMultichannel
        )

        // Configure audio capture
        audioCaptureService.onAudioBuffer = { [weak deepgramService] data in
            deepgramService?.sendAudio(data)
        }
        
        // Start capturing
        Task {
            do {
                try await audioCaptureService.startCapture(
                    microphone: captureMicrophone,
                    systemAudio: captureSystemAudio
                )
            } catch {
                DebugLogger.shared.log(.app, "Audio capture FAILED in startRecording: \(error.localizedDescription)")
                recordingErrorMessage = "Recording could not start. Check microphone and system-audio permissions, then try again."
                stopRecording()
            }
        }
        
        // Exclude paused time by anchoring to the already-recorded active duration.
        recordingStartDate = Date().addingTimeInterval(-accumulatedRecordedDuration)
        let startDate = recordingStartDate!
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(startDate)
            }
        }
        
        // Periodic dirty-save every 60s. Explicit background/stop/home saves remain immediate.
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentMeetingIfNeeded(onlyIfChanged: true)
            }
        }
        
        // Insights cadence: 30s per mode (steady-state only, after warmup)
        startInsightsCadenceTask()
        
        // Auto-stop if no transcript activity for configured duration
        startAutoStopMonitoring()
        
        // Start Live Activity
        #if os(iOS)
        startLiveActivity()
        #endif
    }
    
    /// Managed mode: request a Deepgram JWT from backend, then start recording.
    private func startManagedRecording() async {
        guard hasAcceptedTerms else {
            isStartingMeeting = false
            isResumingRecording = false
            return
        }

        let obtained = await refreshManagedDeepgramCredential(trigger: "start")
        guard obtained else { return }

        recordingErrorMessage = nil
        
        managedSessionStartRecordedDuration = accumulatedRecordedDuration
        await flushPendingSessionEndReports(trigger: "session started")
        
        // Now start recording with the managed JWT
        startRecording()
    }
    
    /// Stores managed session fields from `/api/session`.
    private func applyManagedSession(_ session: MinitiAPIService.SessionResponse) {
        currentSessionId = session.sessionId
        managedDeepgramAccessToken = session.accessToken
        managedDeepgramTokenExpiresAt = session.expiresAt
        managedDeepgramTokenType = session.tokenType.isEmpty ? "Bearer" : session.tokenType
        currentMeeting?.managedSessionId = session.sessionId
    }
    
    private func clearManagedDeepgramCredential() {
        managedDeepgramAccessToken = nil
        managedDeepgramTokenExpiresAt = nil
        managedDeepgramTokenType = "Bearer"
    }
    
    /// Configures Deepgram from the current mode's credential (no network).
    private func configureDeepgramServiceCredential() {
        guard let deepgramService else { return }
        if appMode == .managed, let token = managedDeepgramAccessToken, !token.isEmpty {
            // Managed grant tokens must use Bearer — Deepgram rejects JWT + Token.
            deepgramService.configure(credential: token, authorizationScheme: .bearer)
        } else {
            deepgramService.configure(credential: deepgramApiKey, authorizationScheme: .token)
        }
    }
    
    /// Ensures managed JWT is fresh (refreshing via `/api/session` if needed), then configures Deepgram.
    /// - Returns: `false` when managed mode cannot obtain a usable credential.
    @discardableResult
    private func configureDeepgramCredentialForConnect() async -> Bool {
        if appMode == .managed {
            let ok = await refreshManagedDeepgramCredentialIfNeeded(trigger: "reconnect")
            guard ok else { return false }
        }
        configureDeepgramServiceCredential()
        return true
    }
    
    /// Refreshes `/api/session` only when the managed JWT is missing or near expiry.
    @discardableResult
    private func refreshManagedDeepgramCredentialIfNeeded(trigger: String) async -> Bool {
        if hasFreshManagedDeepgramCredential { return true }
        return await refreshManagedDeepgramCredential(trigger: trigger)
    }
    
    /// Always requests a new managed session JWT from the backend.
    @discardableResult
    private func refreshManagedDeepgramCredential(trigger: String) async -> Bool {
        guard appMode == .managed else { return true }
        guard let minitiAPIService else {
            managedSessionError = "Service not available"
            recordingErrorMessage = "Miniti could not reach the transcription service. Check your connection and try again."
            isStartingMeeting = false
            isResumingRecording = false
            return false
        }
        
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        
        do {
            let session = try await minitiAPIService.requestSession(deviceId: deviceId, model: "nova-3")
            applyManagedSession(session)
            DebugLogger.shared.log(
                .app,
                "Managed Deepgram credential refreshed (\(trigger)): sessionId=\(session.sessionId), expiresAt=\(session.expiresAt)"
            )
            return true
        } catch let error as MinitiAPIService.ServiceError {
            if trigger == "start" {
                managedSessionStartRecordedDuration = nil
                isStartingMeeting = false
                isResumingRecording = false
            }
            switch error {
            case .limitReached(_, _):
                await refreshUsage()
                #if os(iOS)
                if hasActiveAppStoreSubscription {
                    managedSessionError = "Pro is active, but usage sync is still catching up. Please try again in a moment."
                } else {
                    managedSessionError = error.localizedDescription
                }
                #else
                managedSessionError = error.localizedDescription
                #endif
            case .deviceDisabled:
                isDeviceDisabled = true
                managedSessionError = error.localizedDescription
            default:
                managedSessionError = error.localizedDescription
            }
            DebugLogger.shared.log(.app, "Managed session FAILED (\(trigger)): \(error.localizedDescription)")
            recordingErrorMessage = managedSessionError
            return false
        } catch {
            if trigger == "start" {
                managedSessionStartRecordedDuration = nil
                isStartingMeeting = false
                isResumingRecording = false
            }
            managedSessionError = "Failed to connect: \(error.localizedDescription)"
            recordingErrorMessage = "Miniti could not start transcription. Check your connection and try again."
            DebugLogger.shared.log(.app, "Managed session FAILED (\(trigger)): \(error.localizedDescription)")
            return false
        }
    }
    
    func stopRecording() {
        guard !isFinalizingMeeting else {
            DebugLogger.shared.log(.app, "stopRecording ignored: finalization already in progress")
            return
        }
        DebugLogger.shared.log(.app, "stopRecording (duration=\(formattedDuration))")
        if let startDate = recordingStartDate {
            recordingDuration = Date().timeIntervalSince(startDate)
            accumulatedRecordedDuration = recordingDuration
        }

        // Snapshot text the user can currently see. On short meetings (or after a socket failure)
        // Deepgram may not have promoted this interim to a final segment before Stop is pressed.
        let stoppedInterimText = interimText
        let stoppedInterimSpeaker = interimSpeaker ?? currentSpeaker
        let stoppedInterimTimestamp = recordingDuration
        
        isRecording = false
        pendingAudioRecoveryTransitionTask?.cancel()
        pendingAudioRecoveryTransitionTask = nil
        audioRecoveryState = .healthy
        desiredAudioRecoveryState = .healthy
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartDate = nil
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
        insightsCadenceTask?.cancel()
        insightsCadenceTask = nil
        stopTranscriptHealthMonitoring()
        stopAutoStopMonitoring()
        deepgramReconnectTask?.cancel()
        deepgramReconnectTask = nil
        deepgramReconnectGeneration += 1
        lastDeepgramReconnectScheduledAt = 0
        lastTranscriptHealthDebugLogAt = 0
        systemAudioInactiveSince = 0
        
        // Update Live Activity to show paused state (keep it alive for resume)
        #if os(iOS)
        updateLiveActivityState(isRecording: false)
        #endif
        
        audioCaptureService?.stopCapture()
        Task { await flushClientEvents(trigger: "stop recording") }

        // Report usage to backend in managed mode
        if appMode == .managed, let sessionId = currentSessionId {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            let sessionStart = managedSessionStartRecordedDuration ?? 0
            let sessionDuration = max(0, recordingDuration - sessionStart)
            let durationMinutes = sessionDuration / 60.0
            let meetingId = currentMeeting?.id
            let report = PendingSessionEndReport(
                deviceId: deviceId,
                sessionId: sessionId,
                durationMinutes: durationMinutes,
                meetingId: meetingId
            )
            Task {
                await reportManagedSessionEnd(report, trigger: "stop recording")
            }
            clearManagedDeepgramCredential()
            managedSessionStartRecordedDuration = nil
        }

        // Gracefully close Deepgram (wait for final transcripts) then generate insights
        if let meeting = currentMeeting {
            let meetingIDAtStop = meeting.id
            meeting.endTime = Date()

            var hasContent = !liveSegments.isEmpty ||
                !stoppedInterimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            #if os(macOS)
            hasContent = hasContent || !pendingMicSegments.isEmpty
            #endif

            if hasContent {
                // Persist any finals already in memory immediately. A second save after graceful
                // shutdown captures its last final result or the visible-interim fallback.
                saveCurrentMeetingIfNeeded()
                isGeneratingInsights = true
                isFinalizingMeeting = true
                finalizationStatusText = "Finishing transcript…"
                Task {
                    await deepgramService?.gracefulDisconnect()
                    guard currentMeeting?.id == meetingIDAtStop,
                          !isMeetingDeleted(meetingIDAtStop) else {
                        // The meeting was discarded/deleted mid-finalization. clearCurrentSession
                        // usually resets these already; do it here too so no abandonment path can
                        // leave the app stuck reporting insights generation or finalization.
                        isGeneratingInsights = false
                        isFinalizingMeeting = false
                        finalizationStatusText = ""
                        shouldOpenMeetingAfterFinalization = false
                        DebugLogger.shared.log(.app, "Dropping stop finalization after meeting changed/discarded")
                        return
                    }
                    preserveStoppedInterimTranscript(
                        stoppedInterimText,
                        speaker: stoppedInterimSpeaker,
                        timestamp: stoppedInterimTimestamp
                    )
                    #if os(macOS)
                    flushAllPendingMicSegments()
                    #endif
                    // Make the transcript durable before slower, failure-prone AI requests.
                    saveCurrentMeetingIfNeeded()
                    if let saveTask = activeMeetingSaveTask {
                        await saveTask.value
                    }
                    let finalSegments = liveSegments
                        .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .sorted { $0.timestamp < $1.timestamp }
                    let finalTranscript = transcriptText(from: finalSegments)
                    let finalLanguage = meetingLanguage
                    let finalTitleContext = currentTitleSuffix
                    let shouldGenerateSales = salesInsightsEnabled

                    // From here on, insight generation is scoped to the saved Meeting rather than
                    // the live session. This lets the user return home and record another meeting
                    // without an older response writing into the new meeting's state.
                    finalizingInsightMeetingIDs.insert(meetingIDAtStop)
                    isGeneratingInsights = false
                    completeMeetingFinalization()
                    await generateFinalInsightsAndSave(
                        for: meeting,
                        transcript: finalTranscript,
                        language: finalLanguage,
                        existingTitle: finalTitleContext,
                        includeSales: shouldGenerateSales
                    )
                    finalizingInsightMeetingIDs.remove(meetingIDAtStop)
                    if currentMeeting?.id == meetingIDAtStop, !isRecording {
                        finalizationStatusText = "Saved automatically"
                    }
                }
            } else {
                deepgramService?.disconnect()
                saveCurrentMeetingIfNeeded()
                finalizationStatusText = "Saved automatically"
            }
        } else {
            deepgramService?.disconnect()
        }
    }

    private func preserveStoppedInterimTranscript(
        _ text: String,
        speaker: Int,
        timestamp: TimeInterval
    ) {
        var updated = liveSegments
        guard let result = Self.mergeStoppedInterimTranscript(
            text,
            speaker: speaker,
            timestamp: timestamp,
            into: &updated
        ) else { return }

        switch result {
        case .appended, .replacedSuperset:
            liveSegments = updated
            detectedSpeakers.insert(speaker)
            DebugLogger.shared.log(.app, "Preserved visible interim transcript during stop")
        case .skippedExactDuplicate, .skippedContainedDuplicate:
            break
        }
        interimText = ""
        interimSpeaker = nil
    }
    
    /// Clears current session state (moves meeting to history)
    private func clearCurrentSession() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
        insightsCadenceTask?.cancel()
        insightsCadenceTask = nil
        stopTranscriptHealthMonitoring()
        stopAutoStopMonitoring()
        deepgramReconnectTask?.cancel()
        deepgramReconnectTask = nil
        deepgramReconnectGeneration += 1
        lastDeepgramReconnectScheduledAt = 0
        lastTranscriptHealthDebugLogAt = 0
        pendingAudioRecoveryTransitionTask?.cancel()
        pendingAudioRecoveryTransitionTask = nil
        #if os(macOS)
        resetEchoReconciliation()
        #endif
        isGeneratingInsights = false
        isFinalizingMeeting = false
        finalizationStatusText = ""
        shouldOpenMeetingAfterFinalization = false
        recordingErrorMessage = nil
        currentMeeting = nil
        isStartingMeeting = false
        isResumingRecording = false
        liveSegments = []
        interimText = ""
        currentSpeaker = 0
        interimSpeaker = nil
        detectedSpeakers = []
        recordingDuration = 0
        recordingStartDate = nil
        accumulatedRecordedDuration = 0
        audioRecoveryState = .healthy
        desiredAudioRecoveryState = .healthy
        systemAudioInactiveSince = 0
        hasUnsavedSession = false
        
        // Reset live notes and insights
        liveNotes = ""
        liveSummary = ""
        liveActionItems = []
        liveTopics = []
        liveDiscussionFlow = []
        lastStandardSummaryContext = ""
        lastMeddpiccSummaryContext = ""
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        lastMEDDPICCRequestAt = nil
        resetManagedIncrementalTracking()
        
        // Reset training metrics
        trainingMetrics = nil
        
        // Reset MEDDPICC fields
        liveMetrics = nil
        liveEconomicBuyer = nil
        liveDecisionCriteria = nil
        liveDecisionProcess = nil
        livePaperProcess = nil
        liveIdentifiedPain = nil
        liveChampion = nil
        liveCompetition = nil
        
        // Reset questions
        liveQuestions = []
        notifiedQuestionIDs = []
        lastQuestionNotificationAt = nil
        resetZonedOutState()
        resetNudgeState()
        lastQuestionsSegmentCount = 0
        lastQuestionsRequestAt = nil
        questionsSuccessCount = 0
        questionsCadenceAnchor = nil
        questionsLastFiredSegmentCount = 0

        // Reset docs topics
        liveDocTopics = []
        docsSuccessCount = 0
        docsRequestSeq = 0
        docsLookupError = nil
        isExtractingDocsTopics = false
        docsLookupInFlight = []
        lastDocsTopicsRequestAt = nil
        docsTopicsLastFiredSegmentCount = 0

        // Reset speaker names
        liveSpeakerNames = [:]
        liveSpeakerOverrides = []
        liveSelfSpeakerIDs = []
        lastSpeakerNamesSegmentCount = 0
        lastSpeakerNamesRequestAt = nil
        isGeneratingSpeakerNames = false
        
        // Reset title tracking
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
        
        // Reset language to default for next meeting
        meetingLanguage = defaultLanguage
        
        // Reset managed session state
        currentSessionId = nil
        clearManagedDeepgramCredential()
        managedSessionStartRecordedDuration = nil
        managedSessionError = nil
    }

    private func completeMeetingFinalization() {
        isFinalizingMeeting = false
        finalizationStatusText = "Saved automatically"
        guard !isRecording else {
            // Defensive only: startRecording() rejects this transition while finalizing, but never
            // let completion from an older stop clear a recording if another entry point regresses.
            shouldOpenMeetingAfterFinalization = false
            DebugLogger.shared.log(.app, "Finalization completed while recording; preserving active session")
            return
        }
        guard shouldOpenMeetingAfterFinalization else { return }
        shouldOpenMeetingAfterFinalization = false
        goHome()
    }

    private func generateFinalInsightsAndSave(
        for meeting: Meeting,
        transcript: String,
        language: String,
        existingTitle: String,
        includeSales: Bool
    ) async {
        let meetingIDAtRequest = meeting.id
        let transcriptRevisionAtRequest = meeting.transcriptRevision
        let requestAppMode = appMode
        let requestAPIKey = openaiApiKey

        // Check if we can generate insights (mode-aware)
        let canGenerate: Bool
        if requestAppMode == .managed {
            canGenerate = minitiAPIService != nil
        } else {
            canGenerate = insightsService != nil && !requestAPIKey.isEmpty
        }
        
        guard canGenerate else {
            try? modelContext?.save()
            return
        }

        guard !transcript.isEmpty else {
            try? modelContext?.save()
            return
        }

        func isFinalInsightsRequestStillCurrent() -> Bool {
            !isMeetingDeleted(meetingIDAtRequest) &&
                meeting.transcriptRevision == transcriptRevisionAtRequest
        }
        
        DebugLogger.shared.log(.app, "Generating final insights before save")
        
        let model = OpenAIModel.gpt5Mini
        
        // Generate standard insights first
        do {
            DebugLogger.shared.log(.app, "Generating final standard insights")
            let insights: InsightsService.LiveInsights
            
            if requestAppMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: model.rawValue,
                    language: language
                )
                insights = response.toLiveInsights()
            } else {
                insights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: nil, existingTitle: nil,
                    mode: .standard, model: model, apiKey: requestAPIKey, language: language
                )
            }
            
            guard isFinalInsightsRequestStillCurrent() else {
                DebugLogger.shared.log(
                    .app,
                    "Dropping stale final standard insights response (meeting changed/resumed/segments advanced)"
                )
                return
            }

            meeting.summaryText = insights.summary
            meeting.actionItems = insights.actionItems
            meeting.topics = insights.topics
            meeting.discussionFlow = insights.discussionFlow
            markInsightsUpdated(.standard, meeting: meeting)

            if currentMeeting?.id == meetingIDAtRequest {
                liveSummary = insights.summary
                liveActionItems = insights.actionItems
                liveTopics = insights.topics
                liveDiscussionFlow = insights.discussionFlow
            }
            
            if let suggestedTitle = insights.suggestedTitle,
               !suggestedTitle.isEmpty {
                meeting.title = suggestedTitle
                if currentMeeting?.id == meetingIDAtRequest {
                    currentTitleSuffix = suggestedTitle
                }
                DebugLogger.shared.log(.app, "Final title updated: \(meeting.title)")
                #if os(iOS)
                if currentMeeting?.id == meetingIDAtRequest {
                    updateLiveActivityState(isRecording: isRecording)
                }
                #endif
            }
            try? modelContext?.save()
        } catch {
            DebugLogger.shared.log(.app, "Final insights FAILED (standard): \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_final_standard_failed", category: .insights, level: .warning)
        }
        
        // Sales qualification is specialist functionality: don't spend a request on it unless
        // the person has explicitly enabled the Sales view.
        if includeSales {
            do {
                guard isFinalInsightsRequestStillCurrent() else {
                    DebugLogger.shared.log(
                        .app,
                        "Skipping final meddpicc insights request (meeting changed/resumed/segments advanced)"
                    )
                    return
                }

                DebugLogger.shared.log(.app, "Generating final meddpicc insights")
                let meddpiccInsights: InsightsService.LiveInsights

                if requestAppMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: meeting.summaryText, existingTitle: existingTitle,
                        mode: InsightsMode.meddpicc.rawValue, model: model.rawValue,
                        language: language
                    )
                    meddpiccInsights = response.toLiveInsights()
                } else {
                    meddpiccInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcript, existingSummary: meeting.summaryText,
                        existingTitle: existingTitle, mode: .meddpicc,
                        model: model, apiKey: requestAPIKey, language: language
                    )
                }

                guard isFinalInsightsRequestStillCurrent() else {
                    DebugLogger.shared.log(
                        .app,
                        "Dropping stale final meddpicc insights response (meeting changed/resumed/segments advanced)"
                    )
                    return
                }

                meeting.meddpiccMetrics = meddpiccInsights.metrics
                meeting.meddpiccEconomicBuyer = meddpiccInsights.economicBuyer
                meeting.meddpiccDecisionCriteria = meddpiccInsights.decisionCriteria
                meeting.meddpiccDecisionProcess = meddpiccInsights.decisionProcess
                meeting.meddpiccPaperProcess = meddpiccInsights.paperProcess
                meeting.meddpiccIdentifiedPain = meddpiccInsights.identifiedPain
                meeting.meddpiccChampion = meddpiccInsights.champion
                meeting.meddpiccCompetition = meddpiccInsights.competition
                markInsightsUpdated(.meddpicc, meeting: meeting)
                if currentMeeting?.id == meetingIDAtRequest {
                    liveMetrics = meddpiccInsights.metrics
                    liveEconomicBuyer = meddpiccInsights.economicBuyer
                    liveDecisionCriteria = meddpiccInsights.decisionCriteria
                    liveDecisionProcess = meddpiccInsights.decisionProcess
                    livePaperProcess = meddpiccInsights.paperProcess
                    liveIdentifiedPain = meddpiccInsights.identifiedPain
                    liveChampion = meddpiccInsights.champion
                    liveCompetition = meddpiccInsights.competition
                }
                try? modelContext?.save()
                DebugLogger.shared.log(.app, "Final insights complete (meddpicc)")
            } catch {
                DebugLogger.shared.log(.app, "Final insights FAILED (meddpicc): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_final_meddpicc_failed", category: .insights, level: .warning)
            }
        }
        
        // Questions complete as part of the meeting-scoped background work.
        do {
            let questionsInsights: InsightsService.LiveInsights
            
            if requestAppMode == .managed, minitiAPIService != nil {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await generateManagedInsightsWithRetry(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: nil, existingTitle: existingTitle,
                    mode: InsightsMode.questions.rawValue, model: model.rawValue,
                    language: language
                )
                questionsInsights = response.toLiveInsights()
            } else {
                questionsInsights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: nil,
                    existingTitle: existingTitle, mode: .questions,
                    model: model, apiKey: requestAPIKey, language: language
                )
            }
            
            guard isFinalInsightsRequestStillCurrent() else {
                DebugLogger.shared.log(.app, "Dropping stale final questions insights response")
                return
            }
            
            meeting.suggestedQuestions = questionsInsights.questions
            markInsightsUpdated(.questions, meeting: meeting)
            if currentMeeting?.id == meetingIDAtRequest {
                liveQuestions = questionsInsights.questions
            }
            try? modelContext?.save()
            DebugLogger.shared.log(.app, "Final insights complete (questions): count=\(questionsInsights.questions.count)")
        } catch {
            DebugLogger.shared.log(.app, "Final insights FAILED (questions): \(error.localizedDescription)")
        }

        guard isFinalInsightsRequestStillCurrent() else { return }
        try? modelContext?.save()

        #if os(macOS)
        if autoExportMarkdown {
            exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
        }
        #endif

        if !webhookURL.isEmpty, currentMeeting?.id != meetingIDAtRequest {
            WebhookService.send(payload: WebhookService.payloadFromMeeting(meeting), to: webhookURL)
        }
    }
    
    func generateInsights() async {
        guard let meeting = currentMeeting else { return }

        if insightsMode == .training {
            recomputeTrainingMetrics()
            return
        }

        if insightsMode == .docs {
            await refreshDocsTopics()
            return
        }

        if isRecording, appMode == .managed {
            let requestedMode = insightsMode
            if requestedMode == .standard {
                resetCadenceAnchors()
                await updateLiveInsights(standardOnly: true)
                return
            }

            let finalSegments = liveSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
            let transcript = transcriptText(from: finalSegments)
            guard !transcript.isEmpty, let meetingID = currentMeeting?.id else { return }

            if requestedMode == .meddpicc, salesInsightsEnabled {
                await updateMeddpiccInBackground(
                    transcript: transcript,
                    finalSegments: finalSegments,
                    segmentCount: finalSegments.count,
                    existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                    meetingID: meetingID
                )
            } else if requestedMode == .questions {
                await updateQuestionsInBackground(
                    transcript: transcript,
                    finalSegments: finalSegments,
                    segmentCount: finalSegments.count,
                    meetingID: meetingID
                )
            }
            return
        }

        let liveFinalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        let liveTranscript = transcriptText(from: liveFinalSegments)
        let persistedTranscript = meeting.fullTranscript
        let transcriptForRequest = liveTranscript.count > persistedTranscript.count ? liveTranscript : persistedTranscript
        guard !transcriptForRequest.isEmpty else { return }
        let usingLiveTranscript = liveTranscript.count > persistedTranscript.count
        let existingSummaryContext: String? = {
            if usingLiveTranscript {
                let live = liveSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !live.isEmpty { return live }
            }
            let persisted = meeting.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return persisted.isEmpty ? nil : persisted
        }()
        
        // Mode-aware capability check
        let canGenerate: Bool
        if appMode == .managed {
            canGenerate = minitiAPIService != nil
        } else {
            canGenerate = insightsService != nil && !openaiApiKey.isEmpty
        }
        guard canGenerate else { return }
        
        isGeneratingInsights = true
        
        do {
            let requestedMode: InsightsMode = (insightsMode == .training) ? .standard : insightsMode
            guard isInsightModeEnabled(requestedMode) else {
                isGeneratingInsights = false
                return
            }
            let model = OpenAIModel.gpt5Mini

            if requestedMode == .questions {
                let questionsInsights: InsightsService.LiveInsights
                
                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId,
                        transcript: transcriptForRequest,
                        existingSummary: nil,
                        existingTitle: nil,
                        mode: InsightsMode.questions.rawValue,
                        model: model.rawValue,
                        language: meetingLanguage
                    )
                    questionsInsights = response.toLiveInsights()
                } else {
                    questionsInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcriptForRequest,
                        existingSummary: nil,
                        existingTitle: nil,
                        mode: .questions,
                        model: model,
                        apiKey: openaiApiKey,
                        language: meetingLanguage
                    )
                }
                
                liveQuestions = questionsInsights.questions
                meeting.suggestedQuestions = questionsInsights.questions
                markInsightsUpdated(.questions, meeting: meeting)
            } else if requestedMode == .meddpicc {
                let meddpiccInsights: InsightsService.LiveInsights
                
                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId,
                        transcript: transcriptForRequest,
                        existingSummary: existingSummaryContext,
                        existingTitle: nil,
                        mode: InsightsMode.meddpicc.rawValue,
                        model: model.rawValue,
                        language: meetingLanguage
                    )
                    meddpiccInsights = response.toLiveInsights()
                } else {
                    meddpiccInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcriptForRequest,
                        existingSummary: existingSummaryContext,
                        existingTitle: nil,
                        mode: .meddpicc,
                        model: model,
                        apiKey: openaiApiKey,
                        language: meetingLanguage
                    )
                }
                
                meeting.meddpiccMetrics = meddpiccInsights.metrics
                meeting.meddpiccEconomicBuyer = meddpiccInsights.economicBuyer
                meeting.meddpiccDecisionCriteria = meddpiccInsights.decisionCriteria
                meeting.meddpiccDecisionProcess = meddpiccInsights.decisionProcess
                meeting.meddpiccPaperProcess = meddpiccInsights.paperProcess
                meeting.meddpiccIdentifiedPain = meddpiccInsights.identifiedPain
                meeting.meddpiccChampion = meddpiccInsights.champion
                meeting.meddpiccCompetition = meddpiccInsights.competition
                liveMetrics = meddpiccInsights.metrics
                liveEconomicBuyer = meddpiccInsights.economicBuyer
                liveDecisionCriteria = meddpiccInsights.decisionCriteria
                liveDecisionProcess = meddpiccInsights.decisionProcess
                livePaperProcess = meddpiccInsights.paperProcess
                liveIdentifiedPain = meddpiccInsights.identifiedPain
                liveChampion = meddpiccInsights.champion
                liveCompetition = meddpiccInsights.competition
                lastMeddpiccSummaryContext = meddpiccInsights.summary
                markInsightsUpdated(.meddpicc, meeting: meeting)
            } else if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: transcriptForRequest,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: model.rawValue,
                    language: meetingLanguage
                )
                let insights = response.toLiveInsights()
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.topics = insights.topics
                meeting.discussionFlow = insights.discussionFlow
                liveSummary = insights.summary
                liveActionItems = insights.actionItems
                liveTopics = insights.topics
                liveDiscussionFlow = insights.discussionFlow
                lastStandardSummaryContext = insights.summary
                markInsightsUpdated(.standard, meeting: meeting)
            } else {
                let insights = try await insightsService!.generateInsights(
                    transcript: transcriptForRequest,
                    model: model,
                    apiKey: openaiApiKey
                )
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.keyDecisions = insights.decisions
                meeting.topics = insights.topics
                liveSummary = insights.summary
                liveActionItems = insights.actionItems
                liveTopics = insights.topics
                markInsightsUpdated(.standard, meeting: meeting)
            }
            
            try? modelContext?.save()
        } catch {
            DebugLogger.shared.log(.app, "Generate insights FAILED: \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_generate_failed", category: .insights, level: .warning)
        }
        
        isGeneratingInsights = false
    }

    nonisolated static func parseMeetingTitle(_ title: String) -> (String, String)? {
        for separator in [" - ", " — "] {
            guard let range = title.range(of: separator) else { continue }
            let timestamp = String(title[..<range.lowerBound])
            let suffix = String(title[range.upperBound...])
            return (timestamp, suffix)
        }
        return nil
    }

    private func generateManagedInsightsWithRetry(
        deviceId: String,
        transcript: String,
        existingSummary: String?,
        existingTitle: String?,
        mode: String,
        model: String,
        incrementalPayload: MinitiAPIService.IncrementalInsightsPayload? = nil,
        requestSeq: Int? = nil,
        maxAttempts: Int = 2,
        language: String = "en",
        attendees: [[String: String]]? = nil
    ) async throws -> ManagedInsightsResponse {
        guard let minitiAPIService else {
            throw MinitiAPIService.ServiceError.invalidResponse
        }
        DebugLogger.shared.log(
            .app,
            "Managed insights request with retry: mode=\(mode), model=\(model), transcriptChars=\(transcript.count), maxAttempts=\(maxAttempts), language=\(language)"
        )

        var attempt = 1
        while true {
            do {
                return try await minitiAPIService.generateInsights(
                    deviceId: deviceId,
                    transcript: transcript,
                    existingSummary: existingSummary,
                    existingTitle: existingTitle,
                    mode: mode,
                    model: model,
                    incrementalPayload: incrementalPayload,
                    requestSeq: requestSeq,
                    language: language,
                    attendees: attendees
                )
            } catch {
                let shouldRetry = attempt < maxAttempts && Self.isTransientInsightsError(error)
                if !shouldRetry {
                    throw error
                }

                DebugLogger.shared.log(.app, "Insights transient error (attempt \(attempt)/\(maxAttempts)); retrying: \(error.localizedDescription)")
                attempt += 1
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    nonisolated static func isTransientInsightsError(_ error: Error) -> Bool {
        if let serviceError = error as? MinitiAPIService.ServiceError {
            switch serviceError {
            case .serverError(let message):
                let normalized = message.lowercased()
                if normalized.contains("504") || normalized.contains("gateway timeout") {
                    return true
                }
            case .networkError(let wrappedError):
                return isTransientInsightsError(wrappedError)
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return true
            default:
                break
            }
        }

        return false
    }
    
    // MARK: - Diagnostics Events

    private func enqueueDiagnosticEvent(
        _ name: String,
        category: MinitiAPIService.ClientEventPayload.EventCategory,
        level: MinitiAPIService.ClientEventPayload.EventLevel = .info,
        details: [String: String] = [:]
    ) {
        guard shareDiagnostics else { return }
        guard appMode == .managed else { return }
        guard minitiAPIService != nil else { return }

        let cappedDetails = details.reduce(into: [String: String]()) { partial, pair in
            guard partial.count < 20 else { return }
            let key = String(pair.key.prefix(40))
            let value = String(pair.value.prefix(240))
            partial[key] = value
        }

        let event = MinitiAPIService.ClientEventPayload(
            name: String(name.prefix(60)),
            category: category,
            level: level,
            occurredAt: Date(),
            diagnosticsSessionId: diagnosticsSessionId,
            appMode: appMode.rawValue,
            meetingId: currentMeeting?.id.uuidString,
            details: cappedDetails.isEmpty ? nil : cappedDetails
        )
        pendingClientEvents.append(event)
        if pendingClientEvents.count > 200 {
            pendingClientEvents.removeFirst(pendingClientEvents.count - 200)
        }
        persistPendingClientEvents()
        scheduleClientEventsFlush()
    }

    private func scheduleClientEventsFlush() {
        guard shareDiagnostics, appMode == .managed else { return }
        guard !pendingClientEvents.isEmpty else { return }
        guard clientEventsFlushTask == nil else { return }

        clientEventsFlushTask = Task { @MainActor [weak self] in
            defer { self?.clientEventsFlushTask = nil }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushClientEvents(trigger: "debounced")
        }
    }

    private func flushClientEvents(trigger: String) async {
        guard shareDiagnostics else { return }
        guard appMode == .managed else { return }
        guard let minitiAPIService else { return }
        guard !pendingClientEvents.isEmpty else { return }

        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        var remaining = pendingClientEvents
        var sentCount = 0

        while !remaining.isEmpty {
            let batch = Array(remaining.prefix(25))
            do {
                try await minitiAPIService.sendClientEvents(
                    deviceId: deviceId,
                    events: batch
                )
                sentCount += batch.count
                remaining.removeFirst(batch.count)
            } catch {
                DebugLogger.shared.log(
                    .app,
                    "Client events flush FAILED (\(trigger)): \(error.localizedDescription)"
                )
                break
            }
        }

        pendingClientEvents = remaining
        persistPendingClientEvents()
        if sentCount > 0 {
            DebugLogger.shared.log(
                .app,
                "Client events flushed (\(trigger)): sent=\(sentCount), pending=\(pendingClientEvents.count)"
            )
        }
    }

    private func persistPendingClientEvents() {
        do {
            let data = try JSONEncoder().encode(pendingClientEvents)
            UserDefaults.standard.set(data, forKey: pendingClientEventsDefaultsKey)
        } catch {
            DebugLogger.shared.log(.app, "Persist client events FAILED: \(error.localizedDescription)")
        }
    }

    private func loadPendingClientEvents() -> [MinitiAPIService.ClientEventPayload] {
        guard let data = UserDefaults.standard.data(forKey: pendingClientEventsDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MinitiAPIService.ClientEventPayload].self, from: data)
        } catch {
            DebugLogger.shared.log(.app, "Load client events FAILED: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Managed Session End Durability
    
    private func reportManagedSessionEnd(_ report: PendingSessionEndReport, trigger: String) async {
        guard appMode == .managed else { return }
        guard let minitiAPIService else {
            enqueuePendingSessionEndReport(report, reason: "\(trigger): service unavailable")
            return
        }
        
        do {
            let result = try await minitiAPIService.endSession(
                deviceId: report.deviceId,
                sessionId: report.sessionId,
                durationMinutes: report.durationMinutes
            )
            DebugLogger.shared.log(
                .app,
                "Managed session end reported (\(trigger)): id=\(report.sessionId), used=\(result.minutesUsed)m, remaining=\(result.minutesRemaining)m"
            )
            clearManagedSessionReference(sessionId: report.sessionId, meetingId: report.meetingId)
            await refreshUsage()
            await flushPendingSessionEndReports(trigger: "post-success")
        } catch {
            DebugLogger.shared.log(.app, "Managed session end report FAILED (\(trigger)): \(error.localizedDescription)")
            enqueuePendingSessionEndReport(report, reason: "\(trigger): request failed")
        }
    }
    
    private func enqueuePendingSessionEndReport(_ report: PendingSessionEndReport, reason: String) {
        if let existingIndex = pendingSessionEndReports.firstIndex(
            where: { $0.sessionId == report.sessionId && $0.deviceId == report.deviceId }
        ) {
            var existing = pendingSessionEndReports[existingIndex]
            existing.retryCount = max(existing.retryCount + 1, report.retryCount + 1)
            existing.meetingId = existing.meetingId ?? report.meetingId
            pendingSessionEndReports[existingIndex] = existing
        } else {
            var queued = report
            queued.retryCount += 1
            pendingSessionEndReports.append(queued)
        }
        persistPendingSessionEndReports()
        clearManagedSessionReference(sessionId: report.sessionId, meetingId: report.meetingId)
        DebugLogger.shared.log(
            .app,
            "Queued pending managed session end: id=\(report.sessionId), reason=\(reason), pending=\(pendingSessionEndReports.count)"
        )
    }
    
    private func flushPendingSessionEndReports(trigger: String) async {
        guard appMode == .managed else { return }
        guard !isFlushingPendingSessionReports else { return }
        guard !pendingSessionEndReports.isEmpty else { return }
        guard let minitiAPIService else { return }
        
        isFlushingPendingSessionReports = true
        defer { isFlushingPendingSessionReports = false }
        
        DebugLogger.shared.log(
            .app,
            "Flushing pending managed session reports (\(trigger)): count=\(pendingSessionEndReports.count)"
        )
        
        var nextPending: [PendingSessionEndReport] = []
        var hadSuccess = false
        
        for report in pendingSessionEndReports {
            var attemptReport = report
            do {
                let result = try await minitiAPIService.endSession(
                    deviceId: attemptReport.deviceId,
                    sessionId: attemptReport.sessionId,
                    durationMinutes: attemptReport.durationMinutes
                )
                hadSuccess = true
                DebugLogger.shared.log(
                    .app,
                    "Flushed pending session end: id=\(attemptReport.sessionId), used=\(result.minutesUsed)m, remaining=\(result.minutesRemaining)m"
                )
                clearManagedSessionReference(sessionId: attemptReport.sessionId, meetingId: attemptReport.meetingId)
            } catch {
                attemptReport.retryCount += 1
                nextPending.append(attemptReport)
                DebugLogger.shared.log(
                    .app,
                    "Pending session end flush FAILED: id=\(attemptReport.sessionId), retries=\(attemptReport.retryCount), error=\(error.localizedDescription)"
                )
            }
        }
        
        pendingSessionEndReports = nextPending
        persistPendingSessionEndReports()
        
        if hadSuccess {
            await refreshUsage()
        }
    }
    
    private func clearManagedSessionReference(sessionId: String, meetingId: UUID?) {
        if currentSessionId == sessionId {
            currentSessionId = nil
        }
        
        if currentMeeting?.managedSessionId == sessionId || currentMeeting?.id == meetingId {
            currentMeeting?.managedSessionId = nil
        }
        
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Meeting>()
        guard let meetings = try? modelContext.fetch(descriptor) else { return }
        if let targetID = meetingId,
           let target = meetings.first(where: { $0.id == targetID }) {
            target.managedSessionId = nil
            try? modelContext.save()
            return
        }
        
        if let fallback = meetings.first(where: { $0.managedSessionId == sessionId }) {
            fallback.managedSessionId = nil
            try? modelContext.save()
        }
    }
    
    private func loadPendingSessionEndReports() -> [PendingSessionEndReport] {
        guard let data = UserDefaults.standard.data(forKey: pendingSessionReportsDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PendingSessionEndReport].self, from: data)
        } catch {
            DebugLogger.shared.log(.app, "Failed to decode pending session-end reports: \(error.localizedDescription)")
            return []
        }
    }
    
    private func persistPendingSessionEndReports() {
        do {
            let data = try JSONEncoder().encode(pendingSessionEndReports)
            UserDefaults.standard.set(data, forKey: pendingSessionReportsDefaultsKey)
        } catch {
            DebugLogger.shared.log(.app, "Failed to persist pending session-end reports: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Update Check
    
    /// Check if a newer version is available. Runs on launch for all modes.
    /// Also sends device ID and current mode so the backend can track BYOK devices.
    func checkForUpdates() async {
        guard let minitiAPIService else { return }
        
        do {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            let versionInfo = try await minitiAPIService.checkVersion(deviceId: deviceId, appMode: appMode.rawValue)
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if let minVersion = versionInfo.minVersion, Self.isNewer(remote: minVersion, than: currentVersion) {
                requiresForceUpdate = true
                availableUpdate = versionInfo
                DebugLogger.shared.log(.app, "Force update required: min=\(minVersion), current=\(currentVersion)")
            } else if Self.isNewer(remote: versionInfo.latestVersion, than: currentVersion) {
                availableUpdate = versionInfo
                DebugLogger.shared.log(.app, "Update available: latest=\(versionInfo.latestVersion), current=\(currentVersion)")
            }
        } catch {
            // Silent failure — update check is non-critical
            DebugLogger.shared.log(.app, "Version check FAILED: \(error.localizedDescription)")
        }
    }
    
    /// Simple semver comparison: returns true if `remote` is newer than `local`.
    nonisolated static func isNewer(remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
    
    // MARK: - Google Calendar
    
    func refreshGoogleCalendarStatus() async {
        guard googleCalendarEnabled, let minitiAPIService else {
            applyGoogleCalendarDisconnectedState()
            return
        }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let status = try await minitiAPIService.googleStatus(deviceId: deviceId)
            isGoogleCalendarConnected = status.connected
            googleCalendarEmail = status.email
            if status.connected {
                await fetchUpcomingEvents()
            } else {
                applyGoogleCalendarDisconnectedState()
            }
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar status check failed: \(error.localizedDescription)")
        }
    }
    
    func fetchUpcomingEvents() async {
        guard googleCalendarEnabled, isGoogleCalendarConnected, let minitiAPIService else {
            DebugLogger.shared.log(.app, "Google Calendar events fetch skipped: enabled=\(googleCalendarEnabled) connected=\(isGoogleCalendarConnected) service=\(minitiAPIService != nil)")
            return
        }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let events = try await minitiAPIService.googleEvents(deviceId: deviceId)
            DebugLogger.shared.log(.app, "Google Calendar fetched \(events.count) events")
            upcomingEvents = events
            rescheduleMeetingReminders()
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar events fetch failed: \(error)")
            if case MinitiAPIService.ServiceError.serverError(let msg) = error, msg.contains("google_not_connected") {
                applyGoogleCalendarDisconnectedState()
            }
        }
    }
    
    func startCalendarRefreshTimer() {
        calendarRefreshTimer?.invalidate()
        guard googleCalendarEnabled, isGoogleCalendarConnected else { return }
        calendarRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchUpcomingEvents()
            }
        }
    }
    
    func stopCalendarRefreshTimer() {
        calendarRefreshTimer?.invalidate()
        calendarRefreshTimer = nil
    }
    
    func startMeetingFromEvent(_ event: MinitiAPIService.CalendarEvent) {
        cancelAutoStartCountdown()
        selectedCalendarEvent = event
        
        startNewMeeting()
        
        guard let meeting = currentMeeting else { return }
        meeting.title = event.title
        meeting.calendarEventId = event.id
        meeting.attendees = event.attendees.map { $0.toMeetingAttendee() }
        currentTitleSuffix = event.title
    }
    
    // MARK: - Auto-start from Calendar
    
    func startAutoStartMonitoring() {
        autoStartCheckTimer?.invalidate()
        guard autoStartFromCalendar, googleCalendarEnabled, isGoogleCalendarConnected else { return }
        autoStartCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAutoStart()
            }
        }
    }
    
    func stopAutoStartMonitoring() {
        autoStartCheckTimer?.invalidate()
        autoStartCheckTimer = nil
        cancelAutoStartCountdown()
    }
    
    private func checkAutoStart() {
        guard autoStartFromCalendar, googleCalendarEnabled, isGoogleCalendarConnected else { return }
        guard currentMeeting == nil, !isStartingMeeting else { return }
        guard pendingAutoStartEvent == nil else { return }
        
        let now = Date()
        for event in upcomingEvents {
            guard let start = event.startDate else { continue }
            guard !dismissedAutoStartEventIDs.contains(event.id) else { continue }
            
            let secsUntilStart = start.timeIntervalSince(now)
            if secsUntilStart > 0 && secsUntilStart <= 16 {
                let countdownSecs = max(1, Int(ceil(secsUntilStart)))
                beginAutoStartCountdown(for: event, seconds: countdownSecs)
                return
            }
            if secsUntilStart <= 0 && secsUntilStart >= -120 {
                DebugLogger.shared.log(.app, "Auto-start: event \(event.title) already started, launching immediately")
                dismissedAutoStartEventIDs.insert(event.id)
                startMeetingFromEvent(event)
                return
            }
        }
    }
    
    private func beginAutoStartCountdown(for event: MinitiAPIService.CalendarEvent, seconds: Int) {
        pendingAutoStartEvent = event
        autoStartCountdown = seconds
        DebugLogger.shared.log(.app, "Auto-start countdown: \(event.title) in \(seconds)s")
        
        autoStartCountdownTimer?.invalidate()
        autoStartCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pendingAutoStartEvent != nil else { return }
                self.autoStartCountdown -= 1
                if self.autoStartCountdown <= 0 {
                    self.executeAutoStart()
                }
            }
        }
    }
    
    private func executeAutoStart() {
        guard let event = pendingAutoStartEvent else { return }
        DebugLogger.shared.log(.app, "Auto-start: starting meeting from calendar event \(event.title)")
        dismissedAutoStartEventIDs.insert(event.id)
        autoStartCountdownTimer?.invalidate()
        autoStartCountdownTimer = nil
        pendingAutoStartEvent = nil
        autoStartCountdown = 0
        startMeetingFromEvent(event)
    }
    
    func dismissAutoStart() {
        guard let event = pendingAutoStartEvent else { return }
        dismissedAutoStartEventIDs.insert(event.id)
        DebugLogger.shared.log(.app, "Auto-start dismissed: \(event.title)")
        cancelAutoStartCountdown()
    }
    
    func cancelAutoStartCountdown() {
        autoStartCountdownTimer?.invalidate()
        autoStartCountdownTimer = nil
        pendingAutoStartEvent = nil
        autoStartCountdown = 0
    }

    /// True when the home-screen calendar nudge card should be visible.
    /// Conditions: calendar not connected, user hasn't permanently dismissed,
    /// and any snooze window has elapsed.
    var shouldShowCalendarNudge: Bool {
        if isGoogleCalendarConnected { return false }
        if calendarNudgeDismissedUntil > Date().timeIntervalSince1970 { return false }
        return true
    }

    /// Snooze the calendar nudge for ~30 days.
    func snoozeCalendarNudge() {
        calendarNudgeDismissedUntil = Date().addingTimeInterval(30 * 24 * 3600).timeIntervalSince1970
    }

    /// Permanently dismiss the calendar nudge (10 years).
    func dismissCalendarNudgeForever() {
        calendarNudgeDismissedUntil = Date().addingTimeInterval(10 * 365 * 24 * 3600).timeIntervalSince1970
    }

    /// Enable the integration and kick off OAuth. Used by the nudge card.
    func startCalendarConnectFromNudge() {
        googleCalendarEnabled = true
        Task { await googleConnect() }
    }

    func googleConnect() async {
        guard let minitiAPIService else { return }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let response = try await minitiAPIService.googleConnectStart(deviceId: deviceId)
            guard response.callbackScheme.lowercased() == "miniti-google" else {
                DebugLogger.shared.log(.app, "Google Calendar connect start unexpected callback scheme: \(response.callbackScheme)")
                return
            }
            guard let url = URL(string: response.authURL) else {
                DebugLogger.shared.log(.app, "Google Calendar connect start invalid auth URL")
                return
            }
            #if os(macOS)
            guard NSWorkspace.shared.open(url) else {
                DebugLogger.shared.log(.app, "Google Calendar connect browser open failed")
                return
            }
            #elseif os(iOS)
            let opened = await UIApplication.shared.open(url)
            guard opened else {
                DebugLogger.shared.log(.app, "Google Calendar connect browser open failed")
                return
            }
            #endif
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar connect start failed: \(error.localizedDescription)")
        }
    }
    
    func googleDisconnect() async {
        if let minitiAPIService {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            do {
                _ = try await minitiAPIService.googleDisconnect(deviceId: deviceId)
            } catch {
                DebugLogger.shared.log(.app, "Google Calendar disconnect failed: \(error.localizedDescription)")
            }
        }
        applyGoogleCalendarDisconnectedState()
    }

    func applyGoogleCalendarDisconnectedState() {
        isGoogleCalendarConnected = false
        googleCalendarEmail = nil
        upcomingEvents = []
        stopCalendarRefreshTimer()
        stopAutoStartMonitoring()
        rescheduleMeetingReminders()
    }
    
    func autoSyncToAttio(meeting: Meeting) {
        guard autoAttioSync, googleCalendarEnabled, isGoogleCalendarConnected else { return }
        let attendees = meeting.attendees
        let externalDomains = Set(attendees.filter { !$0.isSelf }.map(\.domain).filter { !$0.isEmpty })
        guard !externalDomains.isEmpty else { return }
        guard let service = minitiAPIService else { return }
        
        let payload = AttioMeetingPayload.from(meeting: meeting)
        let domainsCopy = externalDomains
        
        Task.detached {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            do {
                var allMatches: [MinitiAPIService.AttioSearchRecord] = []
                for domain in domainsCopy {
                    let results = try await service.attioSearch(
                        deviceId: deviceId, query: domain, objects: ["companies", "people"]
                    )
                    allMatches.append(contentsOf: results)
                }
                
                guard allMatches.count == 1 else {
                    DebugLogger.shared.log(.app, "Auto Attio sync: \(allMatches.count) matches for domains \(domainsCopy) — skipping (need exactly 1)")
                    return
                }
                
                let match = allMatches[0]
                _ = try await service.attioSendMeeting(
                    deviceId: deviceId,
                    meetingPayload: payload,
                    targetObject: match.objectSlug,
                    targetRecordID: match.idPayload.recordID,
                    createTasksFromActionItems: false
                )
                DebugLogger.shared.log(.app, "Auto Attio sync: sent to \(match.objectSlug) \(match.recordText)")
            } catch {
                DebugLogger.shared.log(.app, "Auto Attio sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    func handleGoogleOAuthCallback(_ url: URL) async {
        guard let payload = Self.parseGoogleOAuthCallback(url) else {
            DebugLogger.shared.log(.app, "Ignoring invalid Google Calendar OAuth callback: \(url.absoluteString)")
            return
        }
        
        if payload.status == "success" {
            DebugLogger.shared.log(.app, "Google Calendar OAuth success")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshGoogleCalendarStatus()
            if !isGoogleCalendarConnected {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await refreshGoogleCalendarStatus()
            }
            startCalendarRefreshTimer()
            startAutoStartMonitoring()
        } else {
            DebugLogger.shared.log(.app, "Google Calendar OAuth failed: \(payload.message ?? "unknown")")
        }
    }

    nonisolated static func parseGoogleOAuthCallback(_ url: URL) -> GoogleOAuthCallbackPayload? {
        guard url.scheme?.lowercased() == "miniti-google" else { return nil }
        guard url.host?.lowercased() == "oauth-callback" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let status = components.queryItems?.first(where: { $0.name == "status" })?.value
        let message = components.queryItems?.first(where: { $0.name == "message" })?.value
        return GoogleOAuthCallbackPayload(status: status, message: message)
    }
    
    // MARK: - Managed Mode Usage
    
    /// Fetch latest usage info from backend. Call on launch, mode switch, and after sessions.
    func refreshUsage() async {
        guard appMode == .managed, let minitiAPIService else { return }
        
        isLoadingUsage = true
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        
        do {
            usageInfo = try await minitiAPIService.checkUsage(deviceId: deviceId)
            isDeviceDisabled = false
        } catch MinitiAPIService.ServiceError.deviceDisabled {
            isDeviceDisabled = true
            DebugLogger.shared.log(.app, "Device disabled in managed mode")
        } catch {
            DebugLogger.shared.log(.app, "Usage check FAILED: \(error.localizedDescription)")
        }
        
        isLoadingUsage = false
    }
    
    /// Retry any managed session-end reports that were queued due transient failures.
    func retryPendingSessionEndReports() async {
        await flushPendingSessionEndReports(trigger: "manual retry")
    }
    
    // MARK: - Subscription
    
    /// Start upgrade flow: StoreKit purchase on iOS, Polar checkout on macOS.
    func openSubscribePage() async {
        #if os(iOS)
        _ = await purchaseProSubscription()
        #else
        guard let minitiAPIService else { return }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let url = try await minitiAPIService.getSubscribeURL(deviceId: deviceId)
            NSWorkspace.shared.open(url)
        } catch {
            DebugLogger.shared.log(.app, "Subscribe URL FAILED: \(error.localizedDescription)")
        }
        #endif
    }
    
    /// Open subscription management: Apple subscriptions on iOS, Polar portal on macOS.
    func openManageSubscriptionPage() async {
        #if os(iOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
        #else
        guard let minitiAPIService else { return }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let url = try await minitiAPIService.getPortalURL(deviceId: deviceId)
            NSWorkspace.shared.open(url)
        } catch {
            DebugLogger.shared.log(.app, "Portal URL FAILED: \(error.localizedDescription)")
        }
        #endif
    }
    
    #if os(iOS)
    /// Purchase the App Store Pro monthly subscription.
    func purchaseProSubscription() async -> Bool {
        guard let storeKitService else { return false }
        let purchased = await storeKitService.purchaseProMonthly()
        guard purchased else { return false }
        return await syncAppleEntitlementToBackend()
    }
    
    /// Restore App Store purchases on this device.
    func restoreAppStorePurchases() async -> Bool {
        guard let storeKitService else { return false }
        let restored = await storeKitService.restorePurchases()
        guard restored else { return false }
        return await syncAppleEntitlementToBackend()
    }
    
    /// Send the current verified App Store entitlement to backend for server-side usage enforcement.
    private func syncAppleEntitlementToBackend() async -> Bool {
        guard let storeKitService, let minitiAPIService else { return false }
        let signedJWS: String?
        if let cachedJWS = storeKitService.lastVerifiedTransactionJWS {
            signedJWS = cachedJWS
        } else {
            signedJWS = await storeKitService.activeProTransactionJWS()
        }
        
        guard let signedJWS else {
            storeKitService.purchaseErrorMessage = "No active App Store subscription found."
            return false
        }
        
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            _ = try await minitiAPIService.verifyAppleSubscription(
                deviceId: deviceId,
                signedTransactionJWS: signedJWS
            )
            await refreshUsage()
            return true
        } catch {
            storeKitService.purchaseErrorMessage = "Purchase verified by Apple, but backend sync failed. Please try Restore Purchases."
            DebugLogger.shared.log(.app, "Apple verify FAILED: \(error.localizedDescription)")
            return false
        }
    }
    #endif
    
    /// Restore a subscription using a Polar license key.
    func restoreSubscription(licenseKey: String) async -> Bool {
        guard let minitiAPIService else { return false }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let result = try await minitiAPIService.restoreSubscription(deviceId: deviceId, licenseKey: licenseKey)
            if result.success {
                await refreshUsage()
                return true
            }
        } catch {
            DebugLogger.shared.log(.app, "Restore subscription FAILED: \(error.localizedDescription)")
        }
        return false
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Live Activity
    
    #if os(iOS)
    private func startLiveActivity() {
        guard let meeting = currentMeeting else { return }
        let meetingID = meeting.id.uuidString
        let meetingTitle = meeting.displayTitle
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replaceLiveActivity(
                meetingID: meetingID,
                meetingTitle: meetingTitle,
                isRecording: true,
                transcript: "",
                elapsedSeconds: nil,
                reason: "started"
            )
        }
    }
    
    private func updateLiveActivityState(isRecording: Bool) {
        guard let activity = resolveCurrentActivity() else { return }
        let state = RecordingActivityAttributes.ContentState(
            meetingTitle: currentMeeting?.displayTitle ?? "",
            isRecording: isRecording,
            currentTranscript: LiveActivityPreferences.presentedTranscript(currentTranscriptLine),
            elapsedSeconds: isRecording ? nil : Int(recordingDuration)
        )
        lastLiveActivityUpdate = Date()
        nonisolated(unsafe) let sendableActivity = activity
        Task {
            await sendableActivity.update(.init(state: state, staleDate: nil))
        }
    }
    
    /// Push transcript text to the Live Activity, throttled to avoid exceeding update budget.
    private func updateLiveActivityTranscript() {
        guard resolveCurrentActivity() != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityUpdate) >= liveActivityUpdateInterval else { return }
        updateLiveActivityState(isRecording: isRecording)
    }

    /// Applies a Live Activity privacy preference change immediately rather than
    /// waiting for the next throttled transcript update.
    func refreshLiveActivityPrivacySetting() {
        updateLiveActivityState(isRecording: isRecording)
    }
    
    /// The most recent transcript line — interim text if available, otherwise the last finalized segment.
    private var currentTranscriptLine: String {
        if !interimText.isEmpty {
            return interimText
        }
        if let last = liveSegments.last {
            return last.text
        }
        return ""
    }
    
    private func endLiveActivity() {
        let finalState = RecordingActivityAttributes.ContentState(
            meetingTitle: currentMeeting?.displayTitle ?? "",
            isRecording: false,
            currentTranscript: "",
            elapsedSeconds: Int(recordingDuration)
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.endAllLiveActivities(finalState: finalState)
        }
    }
    
    /// On launch, if we have no session but Live Activities exist, the app was killed while recording.
    /// End those orphaned activities and inform the user.
    func cleanupOrphanedLiveActivities() async {
        let activities = Activity<RecordingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        guard currentMeeting == nil, !isRecording else { return }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        DebugLogger.shared.log(.app, "Cleaned up orphaned Live Activities: count=\(activities.count)")
    }
    
    private func restorePausedLiveActivity() {
        guard let meeting = currentMeeting else { return }
        let meetingID = meeting.id.uuidString
        let meetingTitle = meeting.displayTitle
        Task { @MainActor [weak self] in
            guard let self, self.currentMeeting != nil else { return }
            await self.replaceLiveActivity(
                meetingID: meetingID,
                meetingTitle: meetingTitle,
                isRecording: false,
                transcript: LiveActivityPreferences.presentedTranscript(self.currentTranscriptLine),
                elapsedSeconds: Int(self.recordingDuration),
                reason: "restored paused session"
            )
        }
    }
    
    private func resolveCurrentActivity() -> Activity<RecordingActivityAttributes>? {
        if let currentActivity {
            return currentActivity
        }
        guard let meetingID = currentMeeting?.id.uuidString else { return nil }
        let resolved = Activity<RecordingActivityAttributes>.activities.first {
            $0.attributes.meetingID == meetingID
        }
        currentActivity = resolved
        return resolved
    }
    
    /// Takes the meeting's ID and title as plain values rather than reading them off
    /// `currentMeeting`: callers hop through a `Task` to get here, and the meeting can be deleted
    /// (or its context torn down) in the meantime, which makes any SwiftData property access trap.
    private func replaceLiveActivity(
        meetingID: String,
        meetingTitle: String,
        isRecording: Bool,
        transcript: String,
        elapsedSeconds: Int?,
        reason: String
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            currentActivity = nil
            DebugLogger.shared.log(.app, "Live Activities not enabled")
            return
        }
        guard currentMeeting != nil else {
            await endAllLiveActivities(finalState: nil)
            return
        }
        
        let state = RecordingActivityAttributes.ContentState(
            meetingTitle: meetingTitle,
            isRecording: isRecording,
            currentTranscript: LiveActivityPreferences.presentedTranscript(transcript),
            elapsedSeconds: elapsedSeconds
        )
        await endAllLiveActivities(finalState: nil)
        
        let attributes = RecordingActivityAttributes(
            meetingID: meetingID,
            startTime: recordingStartDate ?? Date()
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            lastLiveActivityUpdate = Date()
            DebugLogger.shared.log(.app, "Live Activity \(reason)")
        } catch {
            currentActivity = nil
            DebugLogger.shared.log(.app, "Live Activity replace FAILED: \(error.localizedDescription)")
        }
    }
    
    private func endAllLiveActivities(finalState: RecordingActivityAttributes.ContentState?) async {
        let activities = Activity<RecordingActivityAttributes>.activities
        for activity in activities {
            if let finalState {
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        if !activities.isEmpty {
            DebugLogger.shared.log(.app, "Live Activity ended: count=\(activities.count)")
        }
    }
    #endif
    
    // MARK: - Markdown Export
    
    func transcriptAsMarkdown() -> String {
        var md = "## Transcript\n\n"
        
        let finalSegments = liveSegments.filter { 
            $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
        }
        
        var currentKey: String? = nil
        let names = liveSpeakerNames.isEmpty ? nil : liveSpeakerNames
        for segment in finalSegments {
            let key = SelectableAttributed.displayGroupKey(speaker: segment.speaker, names: names, selfIDs: liveSelfSpeakerIDs)
            if key != currentKey {
                currentKey = key
                md += "\n**\(resolvedSpeakerLabel(for: segment.speaker, names: names, selfIDs: liveSelfSpeakerIDs)):**\n"
            }
            md += "\(segment.text) "
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func insightsAsMarkdown() -> String {
        var md = "## Insights\n\n"
        
        if !liveSummary.isEmpty {
            md += "### Summary\n\n\(liveSummary)\n\n"
        }
        
        if !liveDiscussionFlow.isEmpty {
            md += "### Discussion Flow\n\n"
            for (index, item) in liveDiscussionFlow.enumerated() {
                md += "\(index + 1). \(item)\n"
            }
            md += "\n"
        }
        
        if !liveActionItems.isEmpty {
            md += "### Action Items\n\n"
            for item in liveActionItems {
                md += "- [ ] \(item)\n"
            }
            md += "\n"
        }
        
        if !liveTopics.isEmpty {
            md += "### Topics\n\n"
            for topic in liveTopics {
                md += "- \(topic)\n"
            }
            md += "\n"
        }
        
        // MEDDPICC if available (always include in markdown export, not gated by mode)
        let meddpiccFields: [(String, String?)] = [
            ("Metrics", liveMetrics),
            ("Economic Buyer", liveEconomicBuyer),
            ("Decision Criteria", liveDecisionCriteria),
            ("Decision Process", liveDecisionProcess),
            ("Paper Process", livePaperProcess),
            ("Identified Pain", liveIdentifiedPain),
            ("Champion", liveChampion),
            ("Competition", liveCompetition)
        ]

        let hasAnyMeddpicc = meddpiccFields.contains { $0.1 != nil && !($0.1?.isEmpty ?? true) }
        if hasAnyMeddpicc {
            md += "### MEDDPICC\n\n"
            for (label, value) in meddpiccFields {
                if let value = value, !value.isEmpty {
                    md += "**\(label):** \(value)\n\n"
                }
            }
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trainingMetricsAsMarkdown() -> String {
        guard let metrics = trainingMetrics, !metrics.speakers.isEmpty else { return "" }

        var md = "## Training\n\n"
        md += "**Duration:** \(String(format: "%.1f", metrics.durationMinutes)) min"
        if let you = metrics.speakers.first(where: { $0.isLocalMic }) {
            let totalWords = metrics.speakers.reduce(0) { $0 + $1.wordCount }
            let ratio = totalWords > 0 ? Int(Double(you.wordCount) / Double(totalWords) * 100) : 0
            md += " | **Talk Ratio (You):** \(ratio)%"
        }
        md += "\n\n"

        for speaker in metrics.speakers {
            md += "### \(speaker.speakerLabel)\n"
            md += "- Pace: \(Int(speaker.wordsPerMinute)) wpm\n"
            md += "- Fillers: \(String(format: "%.1f", speaker.fillersPerMinute))/min"
            if !speaker.fillers.isEmpty {
                let top = speaker.fillers.prefix(5).map { "\($0.word): \($0.count)" }.joined(separator: ", ")
                md += " (\(top))"
            }
            md += "\n"
            md += "- Longest monologue: \(speaker.longestMonologueWords) words\n"
            md += "- Questions asked: \(speaker.questionsAsked)\n"
            md += "- Clarity: \(Int(speaker.avgWordsPerTurn)) words/turn\n\n"
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fullMeetingAsMarkdown() -> String {
        let startDate = currentMeeting?.startTime ?? Date()
        var md = "# \(currentMeeting?.displayTitle ?? "Meeting")\n\n"
        md += "_\(startDate.formatted(date: .long, time: .shortened))_\n\n"
        md += "---\n\n"
        if !liveNotes.isEmpty {
            md += "## Notes\n\n\(liveNotes)\n\n---\n\n"
        }
        md += insightsAsMarkdown()
        let training = trainingMetricsAsMarkdown()
        if !training.isEmpty {
            md += "\n\n---\n\n"
            md += training
        }
        md += "\n\n---\n\n"
        md += transcriptAsMarkdown()
        return md
    }

    // MARK: - Markdown File Export (macOS)

    #if os(macOS)
    private var resolvedExportFolderPath: String {
        if markdownExportFolderPath.isEmpty {
            return NSString("~/Documents/miniti").expandingTildeInPath
        }
        return markdownExportFolderPath
    }

    /// Save a security-scoped bookmark for the export folder so sandboxed writes work across sessions.
    func saveExportFolderBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            markdownExportBookmarkData = bookmark
            markdownExportFolderPath = url.path
            DebugLogger.shared.log(.app, "Export folder bookmark saved: \(url.path)")
        } catch {
            DebugLogger.shared.log(.app, "Export folder bookmark FAILED: \(error.localizedDescription)")
            markdownExportFolderPath = url.path
        }
    }

    /// Resolve the bookmark and start accessing the security-scoped resource. Caller must call `stopAccessingSecurityScopedResource()` on the returned URL when done.
    private func resolveExportFolderURL() -> URL? {
        if !markdownExportBookmarkData.isEmpty {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: markdownExportBookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    // Re-save bookmark
                    if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        markdownExportBookmarkData = fresh
                    }
                }
                if url.startAccessingSecurityScopedResource() {
                    return url
                }
            }
        }
        // Fallback: default ~/Documents/miniti (inside user home, no bookmark needed)
        let fallback = URL(fileURLWithPath: NSString("~/Documents/miniti").expandingTildeInPath)
        let fm = FileManager.default
        if !fm.fileExists(atPath: fallback.path) {
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        }
        return fallback
    }

    nonisolated static func sanitizeFilename(from title: String) -> String {
        let lowered = title.lowercased()
        // Replace any non-alphanumeric character (except dash) with a dash
        let sanitized = lowered.unicodeScalars.map { char -> String in
            if CharacterSet.alphanumerics.contains(char) || char == "-" {
                return String(char)
            }
            return "-"
        }.joined()
        // Collapse consecutive dashes and strip leading/trailing dashes
        let collapsed = sanitized.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func exportFilename(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let datePrefix = formatter.string(from: meeting.startTime)

        // Strip timestamp prefix from title if present (e.g. "20260310-003102 - My Meeting" → "My Meeting")
        var title = meeting.title
        for separator in [" - ", " — "] {
            if let range = title.range(of: separator) {
                let prefix = String(title[..<range.lowerBound])
                if prefix.allSatisfy({ $0.isNumber || $0 == "-" }) {
                    title = String(title[range.upperBound...])
                    break
                }
            }
        }

        let titleSlug = sanitizeFilename(from: title)
        return titleSlug.isEmpty ? "\(datePrefix).md" : "\(datePrefix)-\(titleSlug).md"
    }

    func exportMeetingAsMarkdownFile(markdown: String, meeting: Meeting) {
        guard let folderURL = resolveExportFolderURL() else {
            DebugLogger.shared.log(.app, "Markdown export FAILED — could not resolve export folder")
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default

        // Create directory if needed
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folderURL.path, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                DebugLogger.shared.log(.app, "Markdown export: created folder \(folderURL.path)")
            } catch {
                DebugLogger.shared.log(.app, "Markdown export FAILED — could not create folder '\(folderURL.path)': \(error.localizedDescription)")
                return
            }
        }

        let filename = Self.exportFilename(for: meeting)
        let fileURL = folderURL.appendingPathComponent(filename)

        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            DebugLogger.shared.log(.app, "Markdown exported: \(filename)")
        } catch {
            DebugLogger.shared.log(.app, "Markdown export FAILED '\(filename)' to '\(folderURL.path)': \(error.localizedDescription)")
            return
        }

        if generateAgentsMd {
            updateAgentsMdIndex()
        }
    }

    func updateAgentsMdIndex() {
        guard let folderURL = resolveExportFolderURL() else { return }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: folderURL.path) else { return }

        let mdFiles = files
            .filter { file in
                guard file.hasSuffix(".md") && file != "AGENTS.md" else { return false }
                let name = String(file.dropLast(3))
                let parts = name.split(separator: "-", maxSplits: 4)
                return parts.count >= 4
                    && parts[0].count == 4
                    && parts[1].count == 2
                    && parts[2].count == 2
                    && parts[3].count == 4
            }
            .sorted()

        var index = "# Miniti Meeting Notes\n\n"
        index += "This folder contains auto-exported meeting notes from [Miniti](https://miniti.app).\n\n"
        index += "Each file contains notes, AI-generated insights (summary, discussion flow, action items, topics, MEDDPICC analysis), "
        index += "training metrics (filler words, pace, talk ratio, clarity), and the full transcript.\n\n"
        index += "## Meetings\n\n"

        for file in mdFiles {
            // Parse date from filename: yyyy-MM-dd-HHmm-title.md
            let name = String(file.dropLast(3)) // strip .md
            let parts = name.split(separator: "-", maxSplits: 4)
            if parts.count >= 4 {
                let year = parts[0], month = parts[1], day = parts[2]
                let dateStr = "\(year)-\(month)-\(day)"
                let titlePart = parts.count > 4 ? String(parts[4]).replacingOccurrences(of: "-", with: " ") : name
                index += "- [\(file)](\(file)) — \(dateStr) — \(titlePart)\n"
            } else {
                index += "- [\(file)](\(file))\n"
            }
        }

        let agentsMdURL = folderURL.appendingPathComponent("AGENTS.md")
        try? index.write(to: agentsMdURL, atomically: true, encoding: .utf8)
        DebugLogger.shared.log(.app, "AGENTS.md index updated: \(mdFiles.count) meetings")
    }
    #endif

    // MARK: - Incisive Question Notifications

    func requestQuestionNotificationPermission(completion: (@Sendable (Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    private func isAppInForeground() -> Bool {
        #if os(macOS)
        return NSApplication.shared.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }

    private func notifyNewHighPriorityQuestions(_ questions: [SuggestedQuestion]) {
        guard notifyOnIncisiveQuestions else { return }
        guard isRecording else { return }

        // Don't notify when the user is already looking at the app.
        if isAppInForeground() { return }

        let newHighs = questions.filter { $0.isHighPriority && !notifiedQuestionIDs.contains($0.id) }
        guard let question = newHighs.first else { return }

        if let last = lastQuestionNotificationAt,
           Date().timeIntervalSince(last) < Self.questionNotificationMinInterval {
            // Still mark as seen so we don't surface them later once the cooldown lifts.
            for q in newHighs { notifiedQuestionIDs.insert(q.id) }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "incisive question"
        content.body = question.question
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "miniti.question.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DebugLogger.shared.log(.app, "Question notification failed: \(error.localizedDescription)")
            }
        }

        lastQuestionNotificationAt = Date()
        for q in newHighs { notifiedQuestionIDs.insert(q.id) }
        DebugLogger.shared.log(.app, "Question notification fired: \(question.question.prefix(60))")
    }

    // MARK: - Upcoming Meeting Reminders

    /// Schedules local notifications ~60s before each upcoming calendar event.
    /// Always cancels previously-scheduled reminders first, so cancelled/rescheduled
    /// events don't fire stale notifications. Safe to call whenever `upcomingEvents`
    /// changes or the toggle flips.
    func rescheduleMeetingReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] pending in
            let staleIDs = pending
                .filter { $0.identifier.hasPrefix("miniti.meeting-reminder.") }
                .map { $0.identifier }
            if !staleIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            Task { @MainActor [weak self] in
                self?.scheduleMeetingRemindersIfEnabled()
            }
        }
    }

    private func scheduleMeetingRemindersIfEnabled() {
        guard notifyOnUpcomingMeeting else { return }
        guard googleCalendarEnabled, isGoogleCalendarConnected else { return }

        let now = Date()
        let center = UNUserNotificationCenter.current()
        for event in upcomingEvents {
            guard let start = event.startDate else { continue }
            let fireAt = start.addingTimeInterval(-60)
            let interval = fireAt.timeIntervalSince(now)
            guard interval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "meeting in 1 minute"
            content.body = event.title
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: "miniti.meeting-reminder.\(event.id)",
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                if let error {
                    DebugLogger.shared.log(.app, "Meeting reminder schedule failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Real-time Nudges (monologue + filler rate)

    /// Permission request shared between question notifications and nudges.
    func requestNudgeNotificationPermission(completion: (@Sendable (Bool) -> Void)? = nil) {
        requestQuestionNotificationPermission(completion: completion)
    }

    func resetNudgeState() {
        lastMonologueNudgeAt = nil
        lastFillerNudgeAt = nil
        monologueNudgedForRun = false
        lastEvaluatedFinalSegmentID = nil
        cachedFillerTokensLanguage = nil
        cachedFillerTokens = []
    }

    /// Returns the tokenized filler phrases for the given language, rebuilding the
    /// cache only when the language changes. Cache is cleared in `resetNudgeState()`
    /// so mid-meeting filler list edits are picked up on the next meeting.
    private func fillerTokens(for language: String) -> [[String]] {
        if cachedFillerTokensLanguage == language {
            return cachedFillerTokens
        }
        let tokens = TrainingFillerPreferences.currentFillers(for: language)
            .map { TrainingMetrics.tokenize($0) }
            .filter { !$0.isEmpty }
        cachedFillerTokensLanguage = language
        cachedFillerTokens = tokens
        return tokens
    }

    /// Called from the transcript finalization hot path after a new batch of final segments lands.
    /// Short-circuits aggressively — most calls return within a couple of property reads.
    func evaluateRealtimeNudges() {
        // Global gates
        guard isRecording else { return }
        guard notifyOnMonologue || notifyOnHighFillerRate else { return }

        // Find the most recent final segment to avoid re-evaluating the same batch twice.
        guard let lastFinal = liveSegments.last(where: { $0.isFinal }) else { return }
        guard lastFinal.id != lastEvaluatedFinalSegmentID else { return }
        lastEvaluatedFinalSegmentID = lastFinal.id

        // Don't interrupt when the user is looking at the app — nudges are for when attention is elsewhere.
        if isAppInForeground() { return }

        guard let targetSpeakerIDs = Self.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: lastFinal.speaker,
            effectiveSelfSpeakerIDs: effectiveLiveSelfSpeakerIDs,
            explicitSelfSpeakerIDs: liveSelfSpeakerIDs,
            detectedSpeakers: detectedSpeakers,
            prefersSingleSpeakerFallback: Self.realtimeNudgesPreferSingleSpeakerFallback
        ) else {
            monologueNudgedForRun = false
            return
        }

        if notifyOnMonologue {
            evaluateMonologueNudge(targetSpeakers: targetSpeakerIDs)
        }
        if notifyOnHighFillerRate {
            evaluateFillerRateNudge(targetSpeakers: targetSpeakerIDs)
        }
    }

    private func evaluateMonologueNudge(targetSpeakers: Set<Int>) {
        if let last = lastMonologueNudgeAt,
           Date().timeIntervalSince(last) < Self.monologueNudgeMinInterval {
            return
        }

        // Walk backwards over liveSegments; accumulate contiguous target-speaker run.
        // Skip interim (non-final) segments; break on the first final from a different speaker.
        // This avoids allocating a filtered copy of `liveSegments` every new segment.
        var runWordCount = 0
        var runStartTimestamp: TimeInterval?
        var runEndTimestamp: TimeInterval?
        for seg in liveSegments.reversed() {
            guard seg.isFinal else { continue }
            if targetSpeakers.contains(seg.speaker) {
                let words = TrainingMetrics.tokenize(seg.text).count
                runWordCount += words
                runStartTimestamp = seg.timestamp
                if runEndTimestamp == nil { runEndTimestamp = seg.timestamp }
            } else {
                break
            }
        }

        guard let start = runStartTimestamp, let end = runEndTimestamp else {
            monologueNudgedForRun = false
            return
        }

        // Use recordingDuration as the right edge so we account for the time that has
        // elapsed since the last You segment finalized (still inside the same run).
        let runSeconds = max(recordingDuration - start, end - start)

        // Drop the latch as soon as the current contiguous run falls back below the
        // nudge threshold. This lets future speaker turns trigger again without
        // requiring platform-specific reset logic.
        if !Self.isEligibleMonologueRun(wordCount: runWordCount, runSeconds: runSeconds) {
            monologueNudgedForRun = false
            return
        }
        guard !monologueNudgedForRun else { return }

        sendLocalNudge(
            identifier: "miniti.nudge.monologue.\(UUID().uuidString)",
            title: "heads up",
            body: "you've been talking for a while — consider pausing to check in."
        )
        lastMonologueNudgeAt = Date()
        monologueNudgedForRun = true
        DebugLogger.shared.log(.app, "Monologue nudge fired: words=\(runWordCount) seconds=\(Int(runSeconds))")
    }

    private func evaluateFillerRateNudge(targetSpeakers: Set<Int>) {
        if let last = lastFillerNudgeAt,
           Date().timeIntervalSince(last) < Self.fillerNudgeMinInterval {
            return
        }

        let windowEnd = recordingDuration
        let windowStart = max(0, windowEnd - Self.fillerWindowSeconds)

        // Walk backwards over liveSegments and break out as soon as we cross the
        // window boundary — avoids filtering the whole segment array.
        let fillers = fillerTokens(for: meetingLanguage)
        var youWordCount = 0
        var fillerCount = 0
        var sawAnyWindowSegment = false
        for seg in liveSegments.reversed() {
            guard seg.isFinal else { continue }
            if seg.timestamp < windowStart { break }
            if seg.timestamp > windowEnd { continue }
            if !targetSpeakers.contains(seg.speaker) { continue }
            sawAnyWindowSegment = true
            let tokens = TrainingMetrics.tokenize(seg.text)
            youWordCount += tokens.count
            for phraseTokens in fillers {
                fillerCount += TrainingMetrics.countPhraseOccurrences(of: phraseTokens, in: tokens)
            }
        }
        guard sawAnyWindowSegment else { return }

        guard youWordCount >= Self.fillerWindowMinYouWords else { return }
        let windowMinutes = max(Self.fillerWindowSeconds / 60.0, 0.01)
        let fillersPerMinute = Double(fillerCount) / windowMinutes
        guard fillersPerMinute >= Self.fillerNudgeMinFillersPerMinute else { return }

        sendLocalNudge(
            identifier: "miniti.nudge.filler.\(UUID().uuidString)",
            title: "heads up",
            body: "you've used a lot of filler words recently (\(Int(fillersPerMinute.rounded()))/min)."
        )
        lastFillerNudgeAt = Date()
        DebugLogger.shared.log(.app, "Filler nudge fired: fillers=\(fillerCount) words=\(youWordCount) rate=\(String(format: "%.1f", fillersPerMinute))/min")
    }

    private func sendLocalNudge(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DebugLogger.shared.log(.app, "Nudge notification failed: \(error.localizedDescription)")
            }
        }
    }

    #if os(iOS)
    nonisolated static let realtimeNudgesPreferSingleSpeakerFallback = true
    #else
    nonisolated static let realtimeNudgesPreferSingleSpeakerFallback = false
    #endif

    nonisolated static func realtimeNudgeTargetSpeakerIDs(
        lastFinalSpeaker: Int,
        effectiveSelfSpeakerIDs: Set<Int>,
        explicitSelfSpeakerIDs: Set<Int>,
        detectedSpeakers: Set<Int>,
        prefersSingleSpeakerFallback: Bool
    ) -> Set<Int>? {
        if effectiveSelfSpeakerIDs.contains(lastFinalSpeaker) {
            return effectiveSelfSpeakerIDs
        }

        guard prefersSingleSpeakerFallback else { return nil }
        guard explicitSelfSpeakerIDs.isEmpty else { return nil }
        guard detectedSpeakers.count <= 1 else { return nil }
        return [lastFinalSpeaker]
    }

    nonisolated static func isEligibleMonologueRun(wordCount: Int, runSeconds: TimeInterval) -> Bool {
        wordCount >= monologueMinWords && runSeconds >= monologueMinSeconds
    }

    nonisolated static func isFinalNonEmptyLiveSegment(_ segment: LiveSegment) -> Bool {
        segment.isFinal && !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func finalizedLiveSegmentCount(in liveSegments: [LiveSegment]) -> Int {
        liveSegments.lazy.filter(Self.isFinalNonEmptyLiveSegment).count
    }

    nonisolated static func finalizedLiveSegments(from liveSegments: [LiveSegment]) -> [LiveSegment] {
        liveSegments
            .lazy
            .filter(Self.isFinalNonEmptyLiveSegment)
            .sorted { $0.timestamp < $1.timestamp }
    }
}

#if os(iOS)
@MainActor
final class AppStoreSubscriptionService: ObservableObject {
    enum PurchaseState {
        case idle
        case purchasing
        case pending
        case purchased
        case failed
    }
    
    static let proMonthlyProductID = "com.miniti.mobile.pro.monthlysub"
    
    @Published private(set) var proMonthlyProduct: Product?
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var lastVerifiedTransactionJWS: String?
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published var purchaseErrorMessage: String?
    
    private var updatesTask: Task<Void, Never>?
    
    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        
        Task {
            await loadProducts()
            await refreshEntitlementStatus()
        }
    }
    
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyProductID])
            proMonthlyProduct = products.first
            if proMonthlyProduct != nil {
                DebugLogger.shared.log(.app, "StoreKit product loaded: \(Self.proMonthlyProductID)")
            } else {
                DebugLogger.shared.log(.app, "StoreKit product NOT FOUND: \(Self.proMonthlyProductID) (returned \(products.count) products)")
            }
        } catch {
            purchaseErrorMessage = "Failed to load subscriptions."
            purchaseState = .failed
            DebugLogger.shared.log(.app, "StoreKit products load FAILED: \(error.localizedDescription)")
        }
    }
    
    func purchaseProMonthly() async -> Bool {
        purchaseErrorMessage = nil
        purchaseState = .purchasing
        
        if proMonthlyProduct == nil {
            DebugLogger.shared.log(.app, "StoreKit product nil at purchase time, reloading...")
            await loadProducts()
        }
        
        guard let proMonthlyProduct else {
            purchaseState = .failed
            purchaseErrorMessage = "Pro subscription is unavailable right now."
            DebugLogger.shared.log(.app, "StoreKit purchase aborted: product still nil after reload")
            return false
        }
        
        do {
            let result = try await proMonthlyProduct.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseState = .failed
                    purchaseErrorMessage = "Purchase verification failed."
                    return false
                }
                lastVerifiedTransactionJWS = verification.jwsRepresentation
                await transaction.finish()
                await refreshEntitlementStatus()
                if hasActiveSubscription {
                    purchaseState = .purchased
                    return true
                } else {
                    purchaseState = .failed
                    purchaseErrorMessage = "Purchase completed, but entitlement is not active yet."
                    return false
                }
            case .pending:
                purchaseState = .pending
                return false
            case .userCancelled:
                purchaseState = .idle
                return false
            @unknown default:
                purchaseState = .failed
                purchaseErrorMessage = "Unknown purchase result."
                return false
            }
        } catch {
            purchaseState = .failed
            purchaseErrorMessage = error.localizedDescription
            DebugLogger.shared.log(.app, "StoreKit purchase FAILED: \(error.localizedDescription)")
            return false
        }
    }
    
    func restorePurchases() async -> Bool {
        purchaseErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlementStatus()
            return hasActiveSubscription
        } catch {
            purchaseErrorMessage = "Restore failed. Please try again."
            purchaseState = .failed
            DebugLogger.shared.log(.app, "StoreKit restore FAILED: \(error.localizedDescription)")
            return false
        }
    }
    
    func refreshEntitlementStatus() async {
        let now = Date()
        var active = false
        var activeJWS: String?
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.proMonthlyProductID else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                continue
            }
            active = true
            activeJWS = result.jwsRepresentation
            break
        }
        
        hasActiveSubscription = active
        lastVerifiedTransactionJWS = activeJWS
    }
    
    /// Returns the active verified App Store entitlement JWS for Pro, if present.
    func activeProTransactionJWS() async -> String? {
        await refreshEntitlementStatus()
        return lastVerifiedTransactionJWS
    }
    
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlementStatus()
        }
    }
}
#endif
