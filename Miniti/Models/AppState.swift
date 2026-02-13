import Foundation
import SwiftUI
import SwiftData
import Combine
#if os(iOS)
import ActivityKit
#endif

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
    // MARK: - Recording State
    @Published var isRecording = false
    @Published var currentMeeting: Meeting?
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Session Management
    var modelContext: ModelContext?
    @Published var hasUnsavedSession = false
    
    // MARK: - Live Transcript
    @Published var liveSegments: [LiveSegment] = []
    @Published var interimText: String = ""
    @Published var currentSpeaker: Int = 0
    @Published var interimSpeaker: Int? = nil
    @Published var detectedSpeakers: Set<Int> = []  // Track unique speakers
    
    // MARK: - UI State
    @Published var showSettings = false
    @Published var selectedTab: Tab = .transcript
    @Published var isGeneratingInsights = false
    @Published var audioLevel: Float = 0  // Combined audio level for visualization
    @Published var microphoneLevel: Float = 0  // Mic-only level
    @Published var systemAudioLevel: Float = 0  // System audio-only level
    @Published var isMonitoring = false  // Audio monitoring active (home screen)
    
    // MARK: - Insights Mode
    @Published var insightsMode: InsightsMode = .standard
    
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
    private let insightUpdateThreshold = 5 // Subsequent updates every 5 sentences
    
    // MARK: - MEDDPICC Tracking
    private var lastMEDDPICCSegmentCount = 0 // Track when we last analyzed with MEDDPICC
    
    // MARK: - Title Updates
    private var lastTitleUpdateCount = 0
    private let titleUpdateThreshold = 15 // Update title less often (every 15 segments)
    private var currentTitleSuffix: String = "" // Track the descriptive part of title
    private var meetingTimestamp: String = "" // Store the ISO timestamp prefix
    
    // MARK: - App Mode (persisted)
    /// Raw storage — use `appMode` computed property for type-safe access.
    @AppStorage("appMode") var appModeRaw: String = AppMode.managed.rawValue
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    /// Type-safe app mode. Changing this is a pure routing toggle — doesn't reset anything.
    var appMode: AppMode {
        get { AppMode(rawValue: appModeRaw) ?? .managed }
        set { appModeRaw = newValue.rawValue }
    }
    
    // MARK: - Update Check
    @Published var availableUpdate: MinitiAPIService.VersionInfo?
    
    // MARK: - Managed Mode State
    @Published var usageInfo: MinitiAPIService.UsageInfo?
    @Published var isLoadingUsage = false
    @Published var managedSessionError: String?
    private var currentSessionId: String?
    private var tempDeepgramKey: String?
    
    /// Whether managed mode is at its limit (500 min).
    var isLimitReached: Bool {
        guard appMode == .managed else { return false }
        return usageInfo?.isLimitReached ?? false
    }
    
    /// Whether the app can start recording right now.
    var canStartRecording: Bool {
        switch appMode {
        case .byok:
            return !deepgramApiKey.isEmpty
        case .managed:
            return !(usageInfo?.isLimitReached ?? false)
        }
    }
    
    // MARK: - Services
    var audioCaptureService: AudioCaptureService?
    var deepgramService: DeepgramService?
    var insightsService: InsightsService?
    var minitiAPIService: MinitiAPIService?
    
    // MARK: - Settings (persisted via @AppStorage)
    @AppStorage("deepgramApiKey") var deepgramApiKey: String = ""
    @AppStorage("openaiApiKey") var openaiApiKey: String = ""
    @AppStorage("captureSystemAudio") var captureSystemAudio: Bool = true
    @AppStorage("captureMicrophone") var captureMicrophone: Bool = true
    @AppStorage("deepgramModel") var deepgramModel: String = DeepgramModel.nova3.rawValue
    @AppStorage("openaiModel") var openaiModel: String = OpenAIModel.gpt5Mini.rawValue
    
    private var recordingTimer: Timer?
    private var recordingStartDate: Date?
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
        
        // Load usage info for managed mode
        if appMode == .managed {
            Task { await refreshUsage() }
        }
        
        // Check for app updates (all modes)
        Task { await checkForUpdates() }
    }
    
    private func setupServices() {
        audioCaptureService = AudioCaptureService()
        deepgramService = DeepgramService()
        insightsService = InsightsService()
        minitiAPIService = MinitiAPIService()
        
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
        }
    }
    
    private func handleTranscriptUpdate(_ update: DeepgramService.TranscriptUpdate) {
        // Skip empty updates
        guard !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if update.isFinal {
            // Final result - will be handled by speaker segments for better accuracy
            interimText = ""
            interimSpeaker = nil
        } else {
            // Interim result - show live typing
            interimText = update.text
            currentSpeaker = update.speaker
            interimSpeaker = update.speaker
            
            // Track detected speakers
            detectedSpeakers.insert(update.speaker)
            
            // Push to Live Activity (throttled)
            #if os(iOS)
            updateLiveActivityTranscript()
            #endif
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
        
        // Check if we should update live insights
        let finalCount = liveSegments.filter { 
            $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
        }.count
        
        // Use lower threshold for first insight, then normal threshold after
        let threshold = lastInsightSegmentCount == 0 ? firstInsightThreshold : insightUpdateThreshold
        
        if finalCount >= lastInsightSegmentCount + threshold {
            lastInsightSegmentCount = finalCount
            Task {
                await updateLiveInsights()
            }
        }
    }
    
    private func updateLiveInsights() async {
        guard !isGeneratingInsights else { return } // Don't overlap requests
        
        // Build transcript from final segments
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        let transcript = finalSegments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\($0.speakerLabel)] \($0.text)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else { return }
        
        // Check if we should request a title update (less frequent than insights)
        let segmentCount = finalSegments.count
        let shouldUpdateTitle = segmentCount >= lastTitleUpdateCount + titleUpdateThreshold
        let existingTitle = shouldUpdateTitle ? nil : currentTitleSuffix
        
        isGeneratingInsights = true
        
        do {
            let insights: InsightsService.LiveInsights
            
            if appMode == .managed, let minitiAPIService {
                // Managed mode: proxy through backend
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId,
                    transcript: transcript,
                    existingSummary: liveSummary.isEmpty ? nil : liveSummary,
                    existingTitle: existingTitle.flatMap { $0.isEmpty ? nil : $0 },
                    mode: insightsMode.rawValue,
                    model: (OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini).rawValue
                )
                insights = response.toLiveInsights()
            } else {
                // BYOK mode: call OpenAI directly
                guard let insightsService, !openaiApiKey.isEmpty else {
                    isGeneratingInsights = false
                    return
                }
                let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
                insights = try await insightsService.generateLiveInsights(
                    transcript: transcript,
                    existingSummary: liveSummary.isEmpty ? nil : liveSummary,
                    existingTitle: existingTitle.flatMap { $0.isEmpty ? nil : $0 },
                    mode: insightsMode,
                    model: selectedModel,
                    apiKey: openaiApiKey
                )
            }
            
            // Apply insights (same for both modes)
            applyInsights(insights, segmentCount: segmentCount)
        } catch {
            print("Live insights error: \(error)")
        }
        
        isGeneratingInsights = false
    }
    
    /// Apply insights from either BYOK or managed mode to the live state.
    private func applyInsights(_ insights: InsightsService.LiveInsights, segmentCount: Int) {
        liveSummary = insights.summary
        liveActionItems = insights.actionItems
        liveTopics = insights.topics
        liveDiscussionFlow = insights.discussionFlow
        
        // MEDDPICC fields
        liveMetrics = insights.metrics
        liveEconomicBuyer = insights.economicBuyer
        liveDecisionCriteria = insights.decisionCriteria
        liveDecisionProcess = insights.decisionProcess
        livePaperProcess = insights.paperProcess
        liveIdentifiedPain = insights.identifiedPain
        liveChampion = insights.champion
        liveCompetition = insights.competition
        
        // Update meeting title if we got a suggestion
        if let suggestedTitle = insights.suggestedTitle,
           !suggestedTitle.isEmpty,
           let meeting = currentMeeting {
            let newSuffix = suggestedTitle.trimmingCharacters(in: .whitespaces)
            if newSuffix != currentTitleSuffix {
                currentTitleSuffix = newSuffix
                meeting.title = "\(meetingTimestamp) - \(newSuffix)"
                lastTitleUpdateCount = segmentCount
                print("[AppState] Updated meeting title to: \(meeting.title)")
                #if os(iOS)
                updateLiveActivityState(isRecording: isRecording)
                #endif
            }
        }
    }
    
    func startNewMeeting() {
        // Mode-aware guard
        switch appMode {
        case .byok:
            guard !deepgramApiKey.isEmpty else {
                showSettings = true
                return
            }
        case .managed:
            guard !isLimitReached else {
                // Limit reached — UI should already show LimitReachedView
                return
            }
        }
        
        // Save previous meeting if exists and has content
        saveCurrentMeetingIfNeeded()
        
        // Create new meeting with ISO timestamp
        meetingTimestamp = generateMeetingTitle()
        let meeting = Meeting(title: meetingTimestamp)
        currentMeeting = meeting
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
        liveSegments = []
        interimText = ""
        interimSpeaker = nil
        detectedSpeakers = []
        recordingDuration = 0
        hasUnsavedSession = true
        managedSessionError = nil
        
        // Reset live notes and insights
        liveNotes = ""
        liveSummary = ""
        liveActionItems = []
        liveTopics = []
        liveDiscussionFlow = []
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        
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
            // Save and clear if not recording
            saveCurrentMeetingIfNeeded()
            clearCurrentSession()
        }
    }
    
    /// Go back to home screen (clears current session after saving)
    func goHome() {
        // End Live Activity
        #if os(iOS)
        endLiveActivity()
        #endif
        
        // Save current meeting if there's content
        saveCurrentMeetingIfNeeded()
        
        // Clear session and return to home
        clearCurrentSession()
        
        // Reset insights mode to standard for fresh start
        insightsMode = .standard
    }
    
    /// Switch insights mode and re-analyze transcript if switching to MEDDPICC
    func switchInsightsMode(to mode: InsightsMode) {
        let previousMode = insightsMode
        insightsMode = mode
        
        // If switching to MEDDPICC and we have transcript content, check if re-analysis needed
        if mode == .meddpicc && previousMode != .meddpicc {
            let currentSegmentCount = liveSegments.filter({ $0.isFinal && !$0.text.isEmpty }).count
            
            // Only re-analyze if we have new content since last MEDDPICC analysis
            if currentSegmentCount > lastMEDDPICCSegmentCount {
                Task {
                    await reanalyzeWithMEDDPICC()
                }
            }
        }
    }
    
    /// Re-analyze the current transcript with MEDDPICC framework
    private func reanalyzeWithMEDDPICC() async {
        guard !isGeneratingInsights else { return }
        
        // Build transcript from final segments
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        let transcript = finalSegments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\($0.speakerLabel)] \($0.text)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else { return }
        
        isGeneratingInsights = true
        
        do {
            let insights: InsightsService.LiveInsights
            
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId,
                    transcript: transcript,
                    existingSummary: nil,
                    existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                    mode: InsightsMode.meddpicc.rawValue,
                    model: (OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini).rawValue
                )
                insights = response.toLiveInsights()
            } else {
                guard let insightsService, !openaiApiKey.isEmpty else {
                    isGeneratingInsights = false
                    return
                }
                let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
                insights = try await insightsService.generateLiveInsights(
                    transcript: transcript,
                    existingSummary: nil,
                    existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                    mode: .meddpicc,
                    model: selectedModel,
                    apiKey: openaiApiKey
                )
            }
            
            applyInsights(insights, segmentCount: finalSegments.count)
            lastMEDDPICCSegmentCount = finalSegments.count
            print("[AppState] Re-analyzed with MEDDPICC framework (\(finalSegments.count) segments)")
        } catch {
            print("MEDDPICC re-analysis error: \(error)")
        }
        
        isGeneratingInsights = false
    }
    
    private func saveCurrentMeetingIfNeeded() {
        guard let meeting = currentMeeting,
              let modelContext = modelContext else {
            print("[Save] No meeting or context to save")
            return
        }
        
        // Only save if there's actual content
        let finalSegments = liveSegments.filter { 
            $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
        }
        
        guard !finalSegments.isEmpty else {
            print("[Save] No content to save")
            return
        }
        
        print("[Save] Saving meeting: \(meeting.title) with \(finalSegments.count) segments")
        
        // Sync all live segments to meeting (handles resumed sessions adding new segments)
        if finalSegments.count != meeting.segments.count {
            // Clear stale persisted segments
            for existingSeg in meeting.segments {
                modelContext.delete(existingSeg)
            }
            meeting.segments.removeAll()
            
            for segment in finalSegments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                
                let persistentSegment = TranscriptSegment(
                    text: text,
                    speaker: segment.speaker,
                    timestamp: segment.timestamp,
                    isFinal: true
                )
                meeting.segments.append(persistentSegment)
            }
        }
        
        // Save live insights to meeting
        if !liveSummary.isEmpty {
            meeting.summaryText = liveSummary
            meeting.actionItems = liveActionItems
            meeting.topics = liveTopics
            meeting.discussionFlow = liveDiscussionFlow
        }
        
        // Save notes
        meeting.notes = liveNotes
        
        // Save MEDDPICC fields
        meeting.meddpiccMetrics = liveMetrics
        meeting.meddpiccEconomicBuyer = liveEconomicBuyer
        meeting.meddpiccDecisionCriteria = liveDecisionCriteria
        meeting.meddpiccDecisionProcess = liveDecisionProcess
        meeting.meddpiccPaperProcess = livePaperProcess
        meeting.meddpiccIdentifiedPain = liveIdentifiedPain
        meeting.meddpiccChampion = liveChampion
        meeting.meddpiccCompetition = liveCompetition
        
        meeting.endTime = meeting.endTime ?? Date()
        
        // Insert into context (SwiftData handles if already inserted)
        modelContext.insert(meeting)
        
        do {
            try modelContext.save()
            print("[Save] Session saved successfully: \(meeting.title)")
            hasUnsavedSession = false
        } catch {
            print("[Save] Failed to save session: \(error)")
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
                print("Audio monitoring failed: \(error)")
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
        
        // In managed mode, if we don't have a temp key (e.g. resuming after stop),
        // we must request a new one before connecting to Deepgram.
        if appMode == .managed && tempDeepgramKey == nil {
            Task { await startManagedRecording() }
            return
        }
        
        // Stop monitoring if active (clean transition)
        if isMonitoring {
            stopAudioMonitoring()
        }
        
        isRecording = true
        
        // Determine which API key to use
        let apiKey: String
        if appMode == .managed, let tempKey = tempDeepgramKey {
            apiKey = tempKey
        } else {
            apiKey = deepgramApiKey
        }
        
        // Configure and start Deepgram with selected model
        let selectedModel = DeepgramModel(rawValue: deepgramModel) ?? .nova3
        deepgramService.configure(apiKey: apiKey)
        
        // Wire up source dominance tracking so Deepgram can separate mic vs system speakers.
        // Only active when both mic and system audio are enabled.
        if captureMicrophone && captureSystemAudio {
            audioCaptureService.resetSourceTracking()
            deepgramService.sourceLookup = { [weak audioCaptureService] start, end in
                audioCaptureService?.dominantSource(from: start, to: end) ?? .unknown
            }
        } else {
            deepgramService.sourceLookup = nil
        }
        
        deepgramService.connect(model: selectedModel)
        
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
                print("Failed to start audio capture: \(error)")
                stopRecording()
            }
        }
        
        // Start duration timer (date-based for reliable background timing)
        if recordingStartDate == nil {
            recordingStartDate = Date()
        }
        let startDate = recordingStartDate!
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(startDate)
            }
        }
        
        // Start Live Activity
        #if os(iOS)
        startLiveActivity()
        #endif
    }
    
    /// Managed mode: request a temp Deepgram key from backend, then start recording.
    private func startManagedRecording() async {
        guard let minitiAPIService else {
            managedSessionError = "Service not available"
            return
        }
        
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        let model = deepgramModel
        
        do {
            let session = try await minitiAPIService.requestSession(deviceId: deviceId, model: model)
            currentSessionId = session.sessionId
            tempDeepgramKey = session.tempApiKey
            print("[AppState] Got temp key for managed session: \(session.sessionId)")
            
            // Now start recording with the temp key
            startRecording()
        } catch let error as MinitiAPIService.ServiceError {
            switch error {
            case .limitReached(_, _):
                // Refresh usage to get current state
                await refreshUsage()
                managedSessionError = error.localizedDescription
            default:
                managedSessionError = error.localizedDescription
            }
            print("[AppState] Managed session failed: \(error)")
        } catch {
            managedSessionError = "Failed to connect: \(error.localizedDescription)"
            print("[AppState] Managed session failed: \(error)")
        }
    }
    
    func stopRecording() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Update Live Activity to show paused state (keep it alive for resume)
        #if os(iOS)
        updateLiveActivityState(isRecording: false)
        #endif
        
        audioCaptureService?.stopCapture()
        deepgramService?.disconnect()
        
        // Report usage to backend in managed mode
        if appMode == .managed, let sessionId = currentSessionId {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            let durationMinutes = recordingDuration / 60.0
            Task {
                do {
                    let result = try await minitiAPIService?.endSession(
                        deviceId: deviceId,
                        sessionId: sessionId,
                        durationMinutes: durationMinutes
                    )
                    if let result {
                        print("[AppState] Session ended. Used: \(result.minutesUsed)m, Remaining: \(result.minutesRemaining)m")
                    }
                    // Refresh usage info
                    await refreshUsage()
                } catch {
                    print("[AppState] Failed to report session end: \(error)")
                }
            }
            currentSessionId = nil
            tempDeepgramKey = nil
        }
        
        // Finalize meeting (but keep as current session so user can resume)
        if let meeting = currentMeeting {
            meeting.endTime = Date()
            
            // If we have content but no insights yet, generate them before saving
            let hasContent = !liveSegments.filter { 
                $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            }.isEmpty
            
            if hasContent && liveSummary.isEmpty {
                // Generate final insights then save
                Task {
                    await generateFinalInsightsAndSave()
                }
            } else {
                saveCurrentMeetingIfNeeded()
            }
        }
    }
    
    /// Clears current session state (moves meeting to history)
    private func clearCurrentSession() {
        currentMeeting = nil
        liveSegments = []
        interimText = ""
        interimSpeaker = nil
        detectedSpeakers = []
        recordingDuration = 0
        recordingStartDate = nil
        hasUnsavedSession = false
        
        // Reset live notes and insights
        liveNotes = ""
        liveSummary = ""
        liveActionItems = []
        liveTopics = []
        liveDiscussionFlow = []
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        
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
        meetingTimestamp = ""
        currentTitleSuffix = ""
        lastTitleUpdateCount = 0
        
        // Reset managed session state
        currentSessionId = nil
        tempDeepgramKey = nil
        managedSessionError = nil
    }
    
    private func generateFinalInsightsAndSave() async {
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
        
        // Build transcript
        let transcript = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\($0.speakerLabel)] \($0.text)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else {
            saveCurrentMeetingIfNeeded()
            return
        }
        
        print("[AppState] Generating final insights before save...")
        isGeneratingInsights = true
        
        let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
        
        // Generate standard insights first
        do {
            print("[AppState] Generating standard insights...")
            let insights: InsightsService.LiveInsights
            
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: selectedModel.rawValue
                )
                insights = response.toLiveInsights()
            } else {
                insights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: nil, existingTitle: nil,
                    mode: .standard, model: selectedModel, apiKey: openaiApiKey
                )
            }
            
            liveSummary = insights.summary
            liveActionItems = insights.actionItems
            liveTopics = insights.topics
            liveDiscussionFlow = insights.discussionFlow
            
            if let suggestedTitle = insights.suggestedTitle,
               !suggestedTitle.isEmpty,
               let meeting = currentMeeting {
                currentTitleSuffix = suggestedTitle
                meeting.title = "\(meetingTimestamp) - \(suggestedTitle)"
                print("[AppState] Final title: \(meeting.title)")
                #if os(iOS)
                updateLiveActivityState(isRecording: isRecording)
                #endif
            }
        } catch {
            print("[AppState] Failed to generate standard insights: \(error)")
        }
        
        // Also generate MEDDPICC insights
        do {
            print("[AppState] Generating MEDDPICC insights...")
            let meddpiccInsights: InsightsService.LiveInsights
            
            if appMode == .managed, let minitiAPIService {
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: transcript,
                    existingSummary: liveSummary, existingTitle: currentTitleSuffix,
                    mode: InsightsMode.meddpicc.rawValue, model: selectedModel.rawValue
                )
                meddpiccInsights = response.toLiveInsights()
            } else {
                meddpiccInsights = try await insightsService!.generateLiveInsights(
                    transcript: transcript, existingSummary: liveSummary,
                    existingTitle: currentTitleSuffix, mode: .meddpicc,
                    model: selectedModel, apiKey: openaiApiKey
                )
            }
            
            liveMetrics = meddpiccInsights.metrics
            liveEconomicBuyer = meddpiccInsights.economicBuyer
            liveDecisionCriteria = meddpiccInsights.decisionCriteria
            liveDecisionProcess = meddpiccInsights.decisionProcess
            livePaperProcess = meddpiccInsights.paperProcess
            liveIdentifiedPain = meddpiccInsights.identifiedPain
            liveChampion = meddpiccInsights.champion
            liveCompetition = meddpiccInsights.competition
            print("[AppState] MEDDPICC insights generated")
        } catch {
            print("[AppState] Failed to generate MEDDPICC insights: \(error)")
        }
        
        isGeneratingInsights = false
        saveCurrentMeetingIfNeeded()
    }
    
    func generateInsights() async {
        guard let meeting = currentMeeting else { return }
        
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
            let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
            
            if appMode == .managed, let minitiAPIService {
                // Managed mode: proxy through backend
                let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                let response = try await minitiAPIService.generateInsights(
                    deviceId: deviceId, transcript: meeting.fullTranscript,
                    existingSummary: nil, existingTitle: nil,
                    mode: InsightsMode.standard.rawValue, model: selectedModel.rawValue
                )
                let insights = response.toLiveInsights()
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.topics = insights.topics
            } else {
                // BYOK mode: direct OpenAI call
                let insights = try await insightsService!.generateInsights(
                    transcript: meeting.fullTranscript,
                    model: selectedModel,
                    apiKey: openaiApiKey
                )
                meeting.summaryText = insights.summary
                meeting.actionItems = insights.actionItems
                meeting.keyDecisions = insights.decisions
                meeting.topics = insights.topics
            }
        } catch {
            print("Failed to generate insights: \(error)")
        }
        
        isGeneratingInsights = false
    }
    
    // MARK: - Update Check
    
    /// Check if a newer version is available. Runs on launch for all modes.
    func checkForUpdates() async {
        guard let minitiAPIService else { return }
        
        do {
            let versionInfo = try await minitiAPIService.checkVersion()
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if Self.isNewer(remote: versionInfo.latestVersion, than: currentVersion) {
                availableUpdate = versionInfo
                print("[AppState] Update available: \(versionInfo.latestVersion) (current: \(currentVersion))")
            } else {
                print("[AppState] App is up to date (\(currentVersion))")
            }
        } catch {
            // Silent failure — update check is non-critical
            print("[AppState] Version check failed: \(error)")
        }
    }
    
    /// Simple semver comparison: returns true if `remote` is newer than `local`.
    private static func isNewer(remote: String, than local: String) -> Bool {
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
    
    // MARK: - Managed Mode Usage
    
    /// Fetch latest usage info from backend. Call on launch, mode switch, and after sessions.
    func refreshUsage() async {
        guard appMode == .managed, let minitiAPIService else { return }
        
        isLoadingUsage = true
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        
        do {
            usageInfo = try await minitiAPIService.checkUsage(deviceId: deviceId)
            print("[AppState] Usage: \(usageInfo?.minutesUsed ?? 0)/\(usageInfo?.minutesLimit ?? 0) min")
        } catch {
            print("[AppState] Failed to check usage: \(error)")
            // Don't block usage on network errors — allow recording and let backend reject if needed
        }
        
        isLoadingUsage = false
    }
    
    private func generateMeetingTitle() -> String {
        // Compact format: 20260203-232804
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Live Activity
    
    #if os(iOS)
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[AppState] Live Activities not enabled")
            return
        }
        
        // End any existing activity first
        if let existing = currentActivity {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
        
        let startTime = recordingStartDate ?? Date()
        let attributes = RecordingActivityAttributes(startTime: startTime)
        let state = RecordingActivityAttributes.ContentState(
            meetingTitle: currentMeeting?.title ?? "",
            isRecording: true,
            currentTranscript: ""
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            print("[AppState] Live Activity started")
        } catch {
            print("[AppState] Failed to start Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivityState(isRecording: Bool) {
        guard let activity = currentActivity else { return }
        let state = RecordingActivityAttributes.ContentState(
            meetingTitle: currentMeeting?.title ?? "",
            isRecording: isRecording,
            currentTranscript: currentTranscriptLine
        )
        lastLiveActivityUpdate = Date()
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    
    /// Push transcript text to the Live Activity, throttled to avoid exceeding update budget.
    private func updateLiveActivityTranscript() {
        guard currentActivity != nil else { return }
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
        guard let activity = currentActivity else { return }
        let finalState = RecordingActivityAttributes.ContentState(
            meetingTitle: currentMeeting?.title ?? "",
            isRecording: false,
            currentTranscript: ""
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
        print("[AppState] Live Activity ended")
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
        
        // MEDDPICC if available
        if insightsMode == .meddpicc {
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
        }
        
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func fullMeetingAsMarkdown() -> String {
        var md = "# \(currentMeeting?.title ?? "Meeting")\n\n"
        md += "_\(Date().formatted(date: .long, time: .shortened))_\n\n"
        md += "---\n\n"
        md += transcriptAsMarkdown()
        md += "\n\n---\n\n"
        if !liveNotes.isEmpty {
            md += "## Notes\n\n\(liveNotes)\n\n---\n\n"
        }
        md += insightsAsMarkdown()
        return md
    }
}
