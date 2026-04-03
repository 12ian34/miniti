import Foundation
import SwiftUI
import SwiftData
import Combine
#if os(iOS)
import ActivityKit
import StoreKit
#endif

@MainActor
final class AudioLevelsState: ObservableObject {
    @Published var combinedLevel: Float = 0
    @Published var microphoneLevel: Float = 0
    @Published var systemAudioLevel: Float = 0

    func reset() {
        combinedLevel = 0
        microphoneLevel = 0
        systemAudioLevel = 0
    }
}

@MainActor
final class TranscriptRuntimeState: ObservableObject {
    @Published var interimText: String = ""
    @Published var currentSpeaker: Int = 0
    @Published var interimSpeaker: Int? = nil

    func clear() {
        interimText = ""
        currentSpeaker = 0
        interimSpeaker = nil
    }
}

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

    private struct MeetingSavePayload {
        let meeting: Meeting
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
    }
    
    // MARK: - Recording State
    @Published var isRecording = false
    @Published var isStartingMeeting = false
    @Published var isResumingRecording = false
    @Published var currentMeeting: Meeting?
    @Published var pendingOpenSavedMeetingID: UUID?
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Session Management
    var modelContext: ModelContext?
    @Published var hasUnsavedSession = false
    let audioLevels = AudioLevelsState()
    let transcriptRuntime = TranscriptRuntimeState()
    
    // MARK: - Live Transcript
    @Published var liveSegments: [LiveSegment] = []
    @Published var detectedSpeakers: Set<Int> = []  // Track unique speakers
    
    // MARK: - UI State
    @Published var showSettings = false
    @Published var selectedTab: Tab = .transcript
    @Published var isGeneratingInsights = false
    @Published var isLiveInsightsCollapsed = false
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
        get { audioLevels.combinedLevel }
        set { audioLevels.combinedLevel = newValue }
    }

    var microphoneLevel: Float {
        get { audioLevels.microphoneLevel }
        set { audioLevels.microphoneLevel = newValue }
    }

    var systemAudioLevel: Float {
        get { audioLevels.systemAudioLevel }
        set { audioLevels.systemAudioLevel = newValue }
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
    
    private var lastInsightSegmentCount = 0
    private let firstInsightThreshold = 3 // First insight after 3 sentences
    private let insightUpdateThreshold = 8 // Subsequent updates every 8 sentences
    
    // MARK: - MEDDPICC Tracking
    private var lastMEDDPICCSegmentCount = 0 // Track when we last analyzed with MEDDPICC
    private var lastMEDDPICCRequestAt: Date? = nil
    private let firstMEDDPICCInsightThreshold = 6
    private let meddpiccInsightUpdateThreshold = 12
    private let meddpiccMinUpdateInterval: TimeInterval = 60
    
    // MARK: - Title Updates
    private var lastTitleUpdateCount = 0
    private let titleUpdateThreshold = 15 // Update title less often (every 15 segments)
    private var currentTitleSuffix: String = ""
    private var lastStandardSummaryContext: String = ""
    private var lastMeddpiccSummaryContext: String = ""
    private let managedIncrementalRecentWindowChars = 10_000
    private var managedStandardAckedSegmentCount = 0
    private var managedMeddpiccAckedSegmentCount = 0
    private var standardRequestSeq = 0
    private var meddpiccRequestSeq = 0
    private var lastAppliedStandardSeq = -1
    private var lastAppliedMeddpiccSeq = -1
    private var standardSuccessCount = 0
    private var meddpiccSuccessCount = 0
    private var standardCadenceAnchor: Date?
    private var meddpiccCadenceAnchor: Date?
    private var standardLastFiredSegmentCount = 0
    private var meddpiccLastFiredSegmentCount = 0
    private var insightsCadenceTask: Task<Void, Never>?
    private let insightsCadenceInterval: TimeInterval = 30
    private let meddpiccCadenceStagger: TimeInterval = 15
    
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
    @AppStorage("generateClaudeMd") var generateClaudeMd: Bool = false
    #endif

    // MARK: - Update Check
    @Published var availableUpdate: MinitiAPIService.VersionInfo?
    
    // MARK: - Managed Mode State
    @Published var usageInfo: MinitiAPIService.UsageInfo?
    @Published var isLoadingUsage = false
    @Published var managedSessionError: String?
    @Published var isDeviceDisabled = false
    #if os(iOS)
    @Published var hasActiveAppStoreSubscription = false
    #endif
    private var currentSessionId: String?
    private var tempDeepgramKey: String?
    private var managedSessionStartRecordedDuration: TimeInterval?
    
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
    @AppStorage("autoStopMinutes") var autoStopMinutes: Int = 5
    @AppStorage("googleCalendarEnabled") var googleCalendarEnabled: Bool = false
    @AppStorage("autoAttioSync") var autoAttioSync: Bool = false
    @AppStorage("autoStartFromCalendar") var autoStartFromCalendar: Bool = false
    @AppStorage("autoStopFromCalendar") var autoStopFromCalendar: Bool = false
    
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
    @Published var selectedSettingsTab: String = "general"
    
    private var recordingTimer: Timer?
    private var periodicSaveTimer: Timer?
    private var transcriptHealthTimer: Timer?
    private var autoStopTimer: Timer?
    private var lastTranscriptReceivedAt: CFAbsoluteTime = 0
    private var lastTranscriptStarvationRecoveryAt: CFAbsoluteTime = 0
    private var deepgramReconnectTask: Task<Void, Never>?
    private var deepgramReconnectGeneration = 0
    private var lastDeepgramReconnectScheduledAt: CFAbsoluteTime = 0
    private var pendingAudioRecoveryTransitionTask: Task<Void, Never>?
    private var desiredAudioRecoveryState: AudioRecoveryState = .healthy
    private var isGeneratingFinalInsights = false
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
    
    init() {
        // One-time migration from legacy boolean acceptance storage.
        if acceptedTermsVersion == 0, legacyHasAcceptedTerms {
            acceptedTermsVersion = 1
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
        
        // Subscribe to audio levels for visualization (separate + combined)
        if let audioService = audioCaptureService {
            audioService.$microphoneLevel
                .receive(on: DispatchQueue.main)
                .sink { [weak self] level in
                    self?.microphoneLevel = level
                }
                .store(in: &cancellables)
            
            audioService.$systemAudioLevel
                .receive(on: DispatchQueue.main)
                .sink { [weak self] level in
                    self?.systemAudioLevel = level
                }
                .store(in: &cancellables)
            
            audioService.$microphoneLevel
                .combineLatest(audioService.$systemAudioLevel)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] micLevel, sysLevel in
                    self?.audioLevel = max(micLevel, sysLevel)
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
            interimText = ""
            interimSpeaker = nil
        } else {
            // Interim result - show live typing
            interimText = update.text
            let candidateSpeaker = update.speaker
            let lastFinalSpeaker = liveSegments.last(where: \.isFinal)?.speaker
            // Interim gating: avoid jumping to never-confirmed speakers too early.
            let canUseCandidateSpeaker =
                detectedSpeakers.isEmpty ||
                detectedSpeakers.contains(candidateSpeaker) ||
                candidateSpeaker == lastFinalSpeaker ||
                candidateSpeaker == currentSpeaker
            
            if canUseCandidateSpeaker {
                currentSpeaker = candidateSpeaker
                interimSpeaker = candidateSpeaker
            } else {
                interimSpeaker = currentSpeaker
            }
            
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
                deepgramService.connect(language: self.meetingLanguage)
                
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
    
    private func checkAutoStop() {
        guard isRecording, lastTranscriptReceivedAt > 0 else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        let gap = now - lastTranscriptReceivedAt
        
        // Calendar-aware auto-stop: after event end time, use 2-min silence threshold
        if autoStopFromCalendar,
           let event = selectedCalendarEvent,
           let endDate = event.endDate,
           Date() > endDate {
            if !calendarEventEndedWhileRecording {
                calendarEventEndedWhileRecording = true
                DebugLogger.shared.log(.app, "Calendar event ended — using 2-min silence threshold")
            }
            if gap >= 120 {
                DebugLogger.shared.log(.app, "Auto-stop: calendar event ended + 2 min silence")
                wasAutoStopped = true
                stopRecording()
                return
            }
        }
        
        // Normal silence-based auto-stop
        guard autoStopMinutes > 0 else { return }
        let threshold = Double(autoStopMinutes) * 60.0
        if gap >= threshold {
            DebugLogger.shared.log(.app, "Auto-stop: no transcript activity for \(autoStopMinutes) min")
            wasAutoStopped = true
            stopRecording()
        }
    }
    
    private func checkTranscriptHealth() {
        guard isRecording else { return }
        guard let deepgramService else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        let speechLikely = microphoneLevel > 0.008 || (captureSystemAudio && systemAudioLevel > 0.006)
        if speechLikely {
            let transcriptGap = now - lastTranscriptReceivedAt
            if transcriptGap > 20.0,
               now - lastTranscriptStarvationRecoveryAt > 30.0,
               deepgramService.connectionState == .connected {
                lastTranscriptStarvationRecoveryAt = now
                DebugLogger.shared.log(
                    .app,
                    "Transcript starvation detected (\(String(format: "%.1f", transcriptGap))s gap with active audio) — reconnecting Deepgram"
                )
                enqueueDiagnosticEvent(
                    "transcript_starvation_detected",
                    category: .deepgram,
                    level: .warning,
                    details: [
                        "gap_seconds": String(format: "%.1f", transcriptGap),
                        "mic_level": String(format: "%.4f", microphoneLevel),
                        "system_level": String(format: "%.4f", systemAudioLevel)
                    ]
                )
                scheduleDeepgramReconnect(reason: "transcript starvation")
            }
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
        // Only process final segments
        let finalSegments = segments.filter { $0.isFinal }
        guard !finalSegments.isEmpty else { return }
        
        // Build new array state atomically to avoid multiple @Published mutations.
        // Previously, removeAll + append fired per iteration, causing SwiftUI's
        // AttributeGraph to see intermediate states and corrupt weak references
        // during ForEach diffing (EXC_BAD_ACCESS in AGGraphGetWeakValue).
        var updated = liveSegments.filter { $0.isFinal } // Strip interims once
        
        for segment in finalSegments {
            // Skip empty segments
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            
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
            
            // Check for duplicates (same speaker and very similar text)
            let isDuplicate = updated.suffix(3).contains { existing in
                existing.isFinal && 
                existing.speaker == segment.speaker &&
                (existing.text == text || existing.text.contains(text) || text.contains(existing.text))
            }
            
            if !isDuplicate {
                updated.append(liveSegment)
                print("[AppState] Added segment - Speaker \(segment.speaker): \"\(text.prefix(50))...\"")
            }
        }
        
        // Single atomic mutation — one @Published change instead of N
        liveSegments = updated
        interimText = ""
        interimSpeaker = nil
        
        // Push final segment to Live Activity (throttled)
        #if os(iOS)
        updateLiveActivityTranscript()
        #endif
        
        // Update training metrics if in training mode
        if insightsMode == .training {
            recomputeTrainingMetrics()
        }
        
        // Warmup: fire first request when we have 4 segments (standard) or 6 (MEDDPICC).
        // Steady-state: cadence task handles 30s intervals.
        let finalCount = liveSegments.filter {
            $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let standardWarmup = standardSuccessCount < 2 && finalCount >= 4
        let meddpiccWarmup = meddpiccSuccessCount < 2 && finalCount >= 6
        let shouldTrigger = (standardWarmup || meddpiccWarmup) && finalCount > lastInsightSegmentCount
        if shouldTrigger {
            lastInsightSegmentCount = finalCount
            Task { await updateLiveInsights() }
        }
    }
    
    private var isGeneratingMeddpiccInsights = false
    
    private func startInsightsCadenceTask() {
        insightsCadenceTask?.cancel()
        insightsCadenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, isRecording {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, isRecording else { break }
                let finalCount = liveSegments.filter {
                    $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }.count
                let now = Date()
                if standardSuccessCount >= 2,
                   let anchor = standardCadenceAnchor,
                   now.timeIntervalSince(anchor) >= insightsCadenceInterval,
                   finalCount > standardLastFiredSegmentCount {
                    await updateLiveInsights(standardOnly: true)
                }
                if meddpiccSuccessCount >= 2 {
                    let anchor = meddpiccCadenceAnchor ?? standardCadenceAnchor?.addingTimeInterval(meddpiccCadenceStagger) ?? recordingStartDate ?? now
                    let interval: TimeInterval = meddpiccCadenceAnchor == nil ? meddpiccCadenceStagger : insightsCadenceInterval
                    if now.timeIntervalSince(anchor) >= interval,
                       finalCount > meddpiccLastFiredSegmentCount {
                        let finalSegments = liveSegments
                            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .sorted { $0.timestamp < $1.timestamp }
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
            }
        }
    }

    private func resetCadenceAnchors() {
        standardCadenceAnchor = Date()
        meddpiccCadenceAnchor = Date()
    }

    private func updateLiveInsights(standardOnly: Bool = false) async {
        guard !isGeneratingInsights else {
            DebugLogger.shared.log(.app, "Live insights skipped: request already in flight")
            return
        }
        
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        
        let transcript = transcriptText(from: finalSegments)
        
        guard !transcript.isEmpty else { return }
        guard let meetingIDAtRequest = currentMeeting?.id else { return }
        
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
    }
    
    private func updateMeddpiccInBackground(
        transcript: String,
        finalSegments: [LiveSegment],
        segmentCount: Int,
        existingTitle: String?,
        meetingID: UUID
    ) async {
        guard !isGeneratingMeddpiccInsights else { return }
        guard currentMeeting?.id == meetingID else { return }
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
            var usedIncrementalPayload = false
            
            if appMode == .managed, let minitiAPIService {
                let requestPlan = makeManagedInsightsRequestPlan(
                    mode: mode,
                    finalSegments: finalSegments,
                    fullTranscript: transcript
                )
                usedIncrementalPayload = requestPlan.usesIncrementalPayload
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
                case .training:
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
                    "Live insights request: mode=\(mode.rawValue), model=\(model.rawValue), transcriptChars=\(transcript.count)"
                )
                guard let insightsService, !openaiApiKey.isEmpty else { return nil }
                insights = try await insightsService.generateLiveInsights(
                    transcript: transcript, existingSummary: existingSummary,
                    existingTitle: existingTitle, mode: mode,
                    model: model, apiKey: openaiApiKey, language: meetingLanguage
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
        let successCount = mode == .standard ? standardSuccessCount : meddpiccSuccessCount
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
            case .training: return 0
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
            case .training:
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
                meddpicc: nil
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
                meddpicc: meddpicc
            )
        case .training:
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
        Self.transcriptText(from: segments)
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
        guard appMode == .managed else { return }

        switch mode {
        case .standard:
            managedStandardAckedSegmentCount = max(managedStandardAckedSegmentCount, segmentCount)
        case .meddpicc:
            managedMeddpiccAckedSegmentCount = max(managedMeddpiccAckedSegmentCount, segmentCount)
        case .training:
            return
        }

        if usedIncrementalPayload {
            DebugLogger.shared.log(.app, "Live insights incremental cursor advanced: mode=\(mode.rawValue), ackedSegments=\(segmentCount)")
        }
    }

    private func resetManagedIncrementalTracking() {
        managedStandardAckedSegmentCount = 0
        managedMeddpiccAckedSegmentCount = 0
        standardRequestSeq = 0
        meddpiccRequestSeq = 0
        lastAppliedStandardSeq = -1
        lastAppliedMeddpiccSeq = -1
        standardSuccessCount = 0
        meddpiccSuccessCount = 0
    }

    private func restoreManagedIncrementalTracking(finalCount: Int) {
        managedStandardAckedSegmentCount = finalCount
        managedMeddpiccAckedSegmentCount = finalCount
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
    }
    
    func startNewMeeting() {
        DebugLogger.shared.log(.app, "startNewMeeting (mode=\(appMode.rawValue))")
        updateLogRedaction()

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
        calendarEventEndedWhileRecording = false
        
        // Save previous meeting if exists and has content
        saveCurrentMeetingIfNeeded()
        
        let meeting = Meeting(title: "untitled")
        meeting.language = meetingLanguage
        currentMeeting = meeting
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
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
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        lastMEDDPICCRequestAt = nil
        resetManagedIncrementalTracking()
        
        if appMode == .managed {
            // Managed mode: request temp key first, then start recording
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
        wasAutoStopped = false
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
                trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage)
            }
            let markdown = fullMeetingAsMarkdown()
            exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        #endif

        // Fire webhook with live in-memory state before clearing
        if !webhookURL.isEmpty, let meeting = currentMeeting {
            let transcriptEntries = liveSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
                .map { seg in
                    WebhookService.MeetingPayload.TranscriptEntry(
                        speaker: seg.speakerLabel,
                        text: seg.text,
                        timestamp: seg.timestamp
                    )
                }
            if trainingMetrics == nil {
                let segs = liveSegments.map {
                    TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal, timestamp: $0.timestamp)
                }
                trainingMetrics = TrainingMetrics.compute(from: segs, duration: recordingDuration, language: meetingLanguage)
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
                transcript: transcriptEntries,
                training: training,
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
            stopRecording()
        }
        goHome()
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
            modelContext.delete(meeting)
            try? modelContext.save()
        }
        
        clearCurrentSession()
        insightsMode = .standard
    }
    
    /// Generate standard + MEDDPICC insights for a saved meeting (used from history detail)
    func generateInsightsForMeeting(_ meeting: Meeting) async {
        if insightsMode == .training {
            return
        }

        let canGenerate: Bool
        if appMode == .managed {
            canGenerate = minitiAPIService != nil
        } else {
            canGenerate = insightsService != nil && !openaiApiKey.isEmpty
        }
        guard canGenerate else { return }
        guard !meeting.fullTranscript.isEmpty else { return }
        
        isGeneratingInsights = true
        let model = OpenAIModel.gpt5Mini
        
        // Generate standard insights
        do {
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: meeting.fullTranscript,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: model.rawValue,
                    language: meeting.language
                )
                let insights = response.toLiveInsights()
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.topics = insights.topics
                meeting.discussionFlow = insights.discussionFlow
            } else {
                let insights = try await insightsService!.generateInsights(
                    transcript: meeting.fullTranscript,
                    model: model, apiKey: openaiApiKey, language: meeting.language
                )
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.keyDecisions = insights.decisions
                meeting.topics = insights.topics
            }
        } catch {
            DebugLogger.shared.log(.app, "History insights FAILED (standard): \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_history_standard_failed", category: .insights, level: .warning)
        }
        
        // Generate MEDDPICC insights
        do {
            let meddpiccInsights: InsightsService.LiveInsights
            if appMode == .managed, minitiAPIService != nil {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await generateManagedInsightsWithRetry(
                    deviceId: deviceId, transcript: meeting.fullTranscript,
                    existingSummary: meeting.summaryText, existingTitle: nil,
                    mode: InsightsMode.meddpicc.rawValue, model: model.rawValue,
                    language: meeting.language
                )
                meddpiccInsights = response.toLiveInsights()
            } else {
                meddpiccInsights = try await insightsService!.generateLiveInsights(
                    transcript: meeting.fullTranscript, existingSummary: meeting.summaryText,
                    existingTitle: nil, mode: .meddpicc,
                    model: model, apiKey: openaiApiKey, language: meeting.language
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
        } catch {
            DebugLogger.shared.log(.app, "History insights FAILED (meddpicc): \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_history_meddpicc_failed", category: .insights, level: .warning)
        }
        
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

        isGeneratingInsights = false
    }

    /// Restore an interrupted meeting (endTime == nil) from SwiftData on launch.
    /// Sets currentMeeting and rebuilds in-memory state so the UI shows the stopped-session view.
    func resumeInterruptedMeeting() {
        guard let modelContext else { return }
        guard currentMeeting == nil, !isRecording else { return }
        
        let descriptor = FetchDescriptor<Meeting>()
        guard let meetings = try? modelContext.fetch(descriptor) else { return }
        guard let interrupted = meetings
            .filter({ $0.endTime == nil && !$0.segments.isEmpty })
            .max(by: { $0.startTime < $1.startTime })
        else { return }
        
        DebugLogger.shared.log(.app, "Resuming interrupted meeting: \(interrupted.title), segments=\(interrupted.segments.count)")
        
        currentMeeting = interrupted
        meetingLanguage = interrupted.language
        
        // Reconstruct liveSegments from persisted TranscriptSegments
        liveSegments = interrupted.segments
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
        
        if interrupted.hasMEDDPICC {
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
        let finalCount = liveSegments.filter { $0.isFinal && !$0.text.isEmpty }.count
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
    
    func switchInsightsMode(to mode: InsightsMode) {
        insightsMode = mode
        
        if mode == .training {
            recomputeTrainingMetrics()
        }
    }
    
    /// Recompute training metrics from current live segments
    func recomputeTrainingMetrics() {
        let segments = liveSegments.map {
            TrainingMetrics.Segment(
                text: $0.text,
                speaker: $0.speaker,
                isFinal: $0.isFinal,
                timestamp: $0.timestamp
            )
        }
        trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage)
    }
    
    /// Save current meeting to SwiftData if it has transcript content.
    /// Called periodically during recording, on background transition, and on goHome/stopRecording.
    /// Does NOT set endTime — callers (stopRecording, goHome) set it explicitly so that
    /// meetings with endTime == nil can be identified as interrupted and resumed on next launch.
    func saveCurrentMeetingIfNeeded() {
        guard let payload = makeMeetingSavePayload() else { return }
        enqueueMeetingSave(payload)
    }

    private func makeMeetingSavePayload() -> MeetingSavePayload? {
        guard let meeting = currentMeeting else { return nil }

        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                LiveSegmentSaveSnapshot(
                    id: $0.id,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    speaker: $0.speaker,
                    timestamp: $0.timestamp
                )
            }
            .filter { !$0.text.isEmpty }

        guard !finalSegments.isEmpty else { return nil }

        return MeetingSavePayload(
            meeting: meeting,
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
            meddpiccCompetition: liveCompetition
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
            return
        }

        let existingSnapshots = payload.meeting.segments.map {
            PersistedSegmentSnapshot(
                id: $0.id,
                text: $0.text,
                speaker: $0.speaker,
                timestamp: $0.timestamp
            )
        }
        let finalSegmentSnapshots = payload.finalSegments

        let syncPlan = await Task.detached(priority: .utility) {
            Self.buildSegmentSyncPlan(
                finalSegments: finalSegmentSnapshots,
                existingSegments: existingSnapshots
            )
        }.value

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

        if payload.meeting.modelContext == nil {
            modelContext.insert(payload.meeting)
        }

        do {
            try modelContext.save()
            hasUnsavedSession = false
        } catch {
            DebugLogger.shared.log(.app, "Save FAILED: \(error.localizedDescription)")
        }
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
                meeting.segments.append(newSegment)
                existingByID[upsert.id] = newSegment
            }
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
        microphoneLevel = 0
        systemAudioLevel = 0
        audioLevel = 0
    }
    
    /// Restart monitoring after toggling an audio source
    func restartAudioMonitoring() {
        guard isMonitoring else { return }
        stopAudioMonitoring()
        startAudioMonitoring()
    }
    
    func startRecording() {
        guard let audioCaptureService, let deepgramService else { return }

        guard hasAcceptedTerms else {
            DebugLogger.shared.log(.app, "startRecording blocked: terms not accepted")
            return
        }
        
        DebugLogger.shared.log(.app, "startRecording (mode=\(appMode.rawValue), mic=\(captureMicrophone), sys=\(captureSystemAudio))")
        isStartingMeeting = false
        isResumingRecording = false
        currentMeeting?.endTime = nil
        
        // In managed mode, if we don't have a temp key (e.g. resuming after stop),
        // we must request a new one before connecting to Deepgram.
        if appMode == .managed && tempDeepgramKey == nil {
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
        audioRecoveryState = .healthy
        desiredAudioRecoveryState = .healthy
        systemAudioInactiveSince = 0
        deepgramReconnectTask?.cancel()
        deepgramReconnectTask = nil
        deepgramReconnectGeneration += 1
        lastDeepgramReconnectScheduledAt = 0
        lastTranscriptReceivedAt = CFAbsoluteTimeGetCurrent()
        lastTranscriptStarvationRecoveryAt = 0
        startTranscriptHealthMonitoring()
        
        // Determine which API key to use
        let apiKey: String
        if appMode == .managed, let tempKey = tempDeepgramKey {
            apiKey = tempKey
        } else {
            apiKey = deepgramApiKey
        }
        
        deepgramService.configure(apiKey: apiKey)
        
        #if os(macOS)
        if captureMicrophone && captureSystemAudio {
            audioCaptureService.resetSourceTracking()
            deepgramService.sourceLookup = { [weak audioCaptureService] start, end in
                audioCaptureService?.dominantSource(from: start, to: end) ?? .unknown
            }
        } else {
            deepgramService.sourceLookup = nil
        }
        #else
        deepgramService.sourceLookup = nil
        #endif
        
        deepgramService.connect(language: meetingLanguage)
        
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
                stopRecording()
            }
        }
        
        // Exclude paused time by anchoring to the already-recorded active duration.
        recordingStartDate = Date().addingTimeInterval(-accumulatedRecordedDuration)
        let startDate = recordingStartDate!
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(startDate)
            }
        }
        
        // Periodic auto-save every 30s so transcript is preserved if app is killed
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentMeetingIfNeeded()
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
    
    /// Managed mode: request a temp Deepgram key from backend, then start recording.
    private func startManagedRecording() async {
        guard hasAcceptedTerms else {
            isStartingMeeting = false
            isResumingRecording = false
            return
        }

        guard let minitiAPIService else {
            managedSessionError = "Service not available"
            isStartingMeeting = false
            isResumingRecording = false
            return
        }
        
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        
        do {
            let session = try await minitiAPIService.requestSession(deviceId: deviceId, model: "nova-3")
            currentSessionId = session.sessionId
            tempDeepgramKey = session.tempApiKey
            managedSessionStartRecordedDuration = accumulatedRecordedDuration
            currentMeeting?.managedSessionId = session.sessionId
            DebugLogger.shared.log(.app, "Managed session started: sessionId=\(session.sessionId)")
            await flushPendingSessionEndReports(trigger: "session started")
            
            // Now start recording with the temp key
            startRecording()
        } catch let error as MinitiAPIService.ServiceError {
            managedSessionStartRecordedDuration = nil
            isStartingMeeting = false
            isResumingRecording = false
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
            DebugLogger.shared.log(.app, "Managed session FAILED: \(error.localizedDescription)")
        } catch {
            managedSessionStartRecordedDuration = nil
            isStartingMeeting = false
            isResumingRecording = false
            managedSessionError = "Failed to connect: \(error.localizedDescription)"
            DebugLogger.shared.log(.app, "Managed session FAILED: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        DebugLogger.shared.log(.app, "stopRecording (duration=\(formattedDuration))")
        if let startDate = recordingStartDate {
            recordingDuration = Date().timeIntervalSince(startDate)
            accumulatedRecordedDuration = recordingDuration
        }
        
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
            tempDeepgramKey = nil
            managedSessionStartRecordedDuration = nil
        }

        // Gracefully close Deepgram (wait for final transcripts) then generate insights
        if let meeting = currentMeeting {
            meeting.endTime = Date()

            let hasContent = !liveSegments.filter {
                $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.isEmpty

            if hasContent {
                isGeneratingInsights = true
                Task {
                    await deepgramService?.gracefulDisconnect()
                    await generateFinalInsightsAndSave()
                }
            } else {
                deepgramService?.disconnect()
                saveCurrentMeetingIfNeeded()
            }
        } else {
            deepgramService?.disconnect()
        }
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
        pendingAudioRecoveryTransitionTask?.cancel()
        pendingAudioRecoveryTransitionTask = nil
        isGeneratingFinalInsights = false
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
        
        // Reset title tracking
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
        
        // Reset language to default for next meeting
        meetingLanguage = defaultLanguage
        
        // Reset managed session state
        currentSessionId = nil
        tempDeepgramKey = nil
        managedSessionStartRecordedDuration = nil
        managedSessionError = nil
    }
    
    private func generateFinalInsightsAndSave() async {
        guard !isGeneratingFinalInsights else {
            DebugLogger.shared.log(.app, "Skipping duplicate final insights request")
            return
        }
        isGeneratingFinalInsights = true
        defer { isGeneratingFinalInsights = false }
        
        // Check if we can generate insights (mode-aware)
        let canGenerate: Bool
        if appMode == .managed {
            canGenerate = minitiAPIService != nil
        } else {
            canGenerate = insightsService != nil && !openaiApiKey.isEmpty
        }
        
        guard canGenerate else {
            saveCurrentMeetingIfNeeded()
            return
        }

        guard let meetingIDAtRequest = currentMeeting?.id else {
            return
        }

        let requestFinalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        let requestFinalSegmentCount = requestFinalSegments.count
        let transcript = transcriptText(from: requestFinalSegments)

        guard !transcript.isEmpty else {
            saveCurrentMeetingIfNeeded()
            return
        }

        func isFinalInsightsRequestStillCurrent() -> Bool {
            guard let meeting = currentMeeting, meeting.id == meetingIDAtRequest else {
                return false
            }
            guard !isRecording, meeting.endTime != nil else {
                return false
            }
            let currentFinalSegmentCount = liveSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
            return currentFinalSegmentCount == requestFinalSegmentCount
        }
        
        DebugLogger.shared.log(.app, "Generating final insights before save")
        isGeneratingInsights = true
        defer { isGeneratingInsights = false }
        
        let model = OpenAIModel.gpt5Mini
        
        // Generate standard insights first
        do {
            DebugLogger.shared.log(.app, "Generating final standard insights")
            let insights: InsightsService.LiveInsights
            
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: model.rawValue,
                    language: meetingLanguage
                )
                insights = response.toLiveInsights()
            } else {
                insights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: nil, existingTitle: nil,
                    mode: .standard, model: model, apiKey: openaiApiKey, language: meetingLanguage
                )
            }
            
            guard isFinalInsightsRequestStillCurrent() else {
                DebugLogger.shared.log(
                    .app,
                    "Dropping stale final standard insights response (meeting changed/resumed/segments advanced)"
                )
                saveCurrentMeetingIfNeeded()
                return
            }

            liveSummary = insights.summary
            liveActionItems = insights.actionItems
            liveTopics = insights.topics
            liveDiscussionFlow = insights.discussionFlow
            
            if let suggestedTitle = insights.suggestedTitle,
               !suggestedTitle.isEmpty,
               let meeting = currentMeeting {
                currentTitleSuffix = suggestedTitle
                meeting.title = suggestedTitle
                DebugLogger.shared.log(.app, "Final title updated: \(meeting.title)")
                #if os(iOS)
                updateLiveActivityState(isRecording: isRecording)
                #endif
            }
        } catch {
            DebugLogger.shared.log(.app, "Final insights FAILED (standard): \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_final_standard_failed", category: .insights, level: .warning)
        }
        
        // Also generate MEDDPICC insights
        do {
            guard isFinalInsightsRequestStillCurrent() else {
                DebugLogger.shared.log(
                    .app,
                    "Skipping final meddpicc insights request (meeting changed/resumed/segments advanced)"
                )
                saveCurrentMeetingIfNeeded()
                return
            }

            DebugLogger.shared.log(.app, "Generating final meddpicc insights")
            let meddpiccInsights: InsightsService.LiveInsights
            
            if appMode == .managed, minitiAPIService != nil {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await generateManagedInsightsWithRetry(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: liveSummary, existingTitle: currentTitleSuffix,
                    mode: InsightsMode.meddpicc.rawValue, model: model.rawValue,
                    language: meetingLanguage
                )
                meddpiccInsights = response.toLiveInsights()
            } else {
                meddpiccInsights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: liveSummary,
                    existingTitle: currentTitleSuffix, mode: .meddpicc,
                    model: model, apiKey: openaiApiKey, language: meetingLanguage
                )
            }
            
            guard isFinalInsightsRequestStillCurrent() else {
                DebugLogger.shared.log(
                    .app,
                    "Dropping stale final meddpicc insights response (meeting changed/resumed/segments advanced)"
                )
                saveCurrentMeetingIfNeeded()
                return
            }

            liveMetrics = meddpiccInsights.metrics
            liveEconomicBuyer = meddpiccInsights.economicBuyer
            liveDecisionCriteria = meddpiccInsights.decisionCriteria
            liveDecisionProcess = meddpiccInsights.decisionProcess
            livePaperProcess = meddpiccInsights.paperProcess
            liveIdentifiedPain = meddpiccInsights.identifiedPain
            liveChampion = meddpiccInsights.champion
            liveCompetition = meddpiccInsights.competition
            DebugLogger.shared.log(.app, "Final insights complete (meddpicc)")
        } catch {
            DebugLogger.shared.log(.app, "Final insights FAILED (meddpicc): \(error.localizedDescription)")
            enqueueDiagnosticEvent("insights_final_meddpicc_failed", category: .insights, level: .warning)
        }
        
        saveCurrentMeetingIfNeeded()
    }
    
    func generateInsights() async {
        guard let meeting = currentMeeting else { return }

        if insightsMode == .training {
            recomputeTrainingMetrics()
            return
        }

        if isRecording, appMode == .managed {
            resetCadenceAnchors()
            await updateLiveInsights(standardOnly: true)
            let finalSegments = liveSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
            let transcript = transcriptText(from: finalSegments)
            if !transcript.isEmpty, let meetingID = currentMeeting?.id {
                await updateMeddpiccInBackground(
                    transcript: transcript,
                    finalSegments: finalSegments,
                    segmentCount: finalSegments.count,
                    existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
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
            let requestedMode: InsightsMode = insightsMode == .training ? .standard : insightsMode
            let model = OpenAIModel.gpt5Mini
            
            if requestedMode == .meddpicc {
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
            
            if Self.isNewer(remote: versionInfo.latestVersion, than: currentVersion) {
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
            isGoogleCalendarConnected = false
            googleCalendarEmail = nil
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
                upcomingEvents = []
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
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar events fetch failed: \(error)")
            if case MinitiAPIService.ServiceError.serverError(let msg) = error, msg.contains("google_not_connected") {
                isGoogleCalendarConnected = false
                googleCalendarEmail = nil
                upcomingEvents = []
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
    
    func googleConnect() async {
        guard let minitiAPIService else { return }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let response = try await minitiAPIService.googleConnectStart(deviceId: deviceId)
            guard let url = URL(string: response.authURL) else { return }
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(response.authURL, forType: .string)
            NSWorkspace.shared.open(url)
            #endif
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar connect start failed: \(error.localizedDescription)")
        }
    }
    
    func googleDisconnect() async {
        guard let minitiAPIService else { return }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            _ = try await minitiAPIService.googleDisconnect(deviceId: deviceId)
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar disconnect failed: \(error.localizedDescription)")
        }
        isGoogleCalendarConnected = false
        googleCalendarEmail = nil
        upcomingEvents = []
        stopCalendarRefreshTimer()
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let status = components.queryItems?.first(where: { $0.name == "status" })?.value
        let message = components.queryItems?.first(where: { $0.name == "message" })?.value
        
        if status == "success" {
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
            DebugLogger.shared.log(.app, "Google Calendar OAuth failed: \(message ?? "unknown")")
        }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replaceLiveActivity(
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
            currentTranscript: currentTranscriptLine,
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
    
    /// The most recent transcript line — interim text if available, otherwise the last finalized segment.
    private var currentTranscriptLine: String {
        if !interimText.isEmpty {
            return interimText
        }
        if let last = liveSegments.last(where: { $0.isFinal && !$0.text.isEmpty }) {
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
        Task { @MainActor [weak self] in
            guard let self, self.currentMeeting != nil else { return }
            await self.replaceLiveActivity(
                isRecording: false,
                transcript: self.currentTranscriptLine,
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
    
    private func replaceLiveActivity(
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
        guard let meeting = currentMeeting else {
            await endAllLiveActivities(finalState: nil)
            return
        }
        
        let state = RecordingActivityAttributes.ContentState(
            meetingTitle: meeting.displayTitle,
            isRecording: isRecording,
            currentTranscript: transcript,
            elapsedSeconds: elapsedSeconds
        )
        await endAllLiveActivities(finalState: nil)
        
        let attributes = RecordingActivityAttributes(
            meetingID: meeting.id.uuidString,
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
        
        var currentSpeaker: Int? = nil
        for segment in finalSegments {
            if segment.speaker != currentSpeaker {
                currentSpeaker = segment.speaker
                md += "\n**\(segment.speakerLabel):**\n"
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

        if generateClaudeMd {
            updateClaudeMdIndex()
        }
    }

    func updateClaudeMdIndex() {
        guard let folderURL = resolveExportFolderURL() else { return }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: folderURL.path) else { return }

        let mdFiles = files
            .filter { $0.hasSuffix(".md") && $0 != "CLAUDE.md" }
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

        let claudeMdURL = folderURL.appendingPathComponent("CLAUDE.md")
        try? index.write(to: claudeMdURL, atomically: true, encoding: .utf8)
        DebugLogger.shared.log(.app, "CLAUDE.md index updated: \(mdFiles.count) meetings")
    }
    #endif
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
