import Foundation
import SwiftUI
import SwiftData
import Combine

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
    @Published var showHistory = false
    @Published var selectedTab: Tab = .transcript
    @Published var isGeneratingInsights = false
    @Published var audioLevel: Float = 0  // Real-time audio level for visualization
    
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
    
    // MARK: - Services
    var audioCaptureService: AudioCaptureService?
    var deepgramService: DeepgramService?
    var insightsService: InsightsService?
    
    // MARK: - Settings (persisted via @AppStorage)
    @AppStorage("deepgramApiKey") var deepgramApiKey: String = ""
    @AppStorage("openaiApiKey") var openaiApiKey: String = ""
    @AppStorage("captureSystemAudio") var captureSystemAudio: Bool = true
    @AppStorage("captureMicrophone") var captureMicrophone: Bool = true
    @AppStorage("deepgramModel") var deepgramModel: String = DeepgramModel.nova3.rawValue
    @AppStorage("openaiModel") var openaiModel: String = OpenAIModel.gpt5Mini.rawValue
    
    private var recordingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
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
        
        var speakerLabel: String {
            "Speaker \(speaker + 1)"
        }
    }
    
    init() {
        setupServices()
    }
    
    private func setupServices() {
        audioCaptureService = AudioCaptureService()
        deepgramService = DeepgramService()
        insightsService = InsightsService()
        
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
        
        // Subscribe to audio levels for visualization
        if let audioService = audioCaptureService {
            audioService.$microphoneLevel
                .combineLatest(audioService.$systemAudioLevel)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] micLevel, sysLevel in
                    // Use the higher of the two levels
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
        }
    }
    
    private func handleSpeakerSegments(_ segments: [DeepgramService.SpeakerSegment]) {
        // Only process final segments
        let finalSegments = segments.filter { $0.isFinal }
        guard !finalSegments.isEmpty else { return }
        
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
            
            // Remove interim segments
            liveSegments.removeAll { !$0.isFinal }
            
            // Check for duplicates (same speaker and very similar text)
            let isDuplicate = liveSegments.suffix(3).contains { existing in
                existing.isFinal && 
                existing.speaker == segment.speaker &&
                (existing.text == text || existing.text.contains(text) || text.contains(existing.text))
            }
            
            if !isDuplicate {
                liveSegments.append(liveSegment)
                print("[AppState] Added segment - Speaker \(segment.speaker): \"\(text.prefix(50))...\"")
            }
        }
        
        // Clear interim
        interimText = ""
        interimSpeaker = nil
        
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
        guard let insightsService, !openaiApiKey.isEmpty else { return }
        guard !isGeneratingInsights else { return } // Don't overlap requests
        
        // Build transcript from final segments
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        let transcript = finalSegments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[S\($0.speaker + 1)] \($0.text)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else { return }
        
        // Check if we should request a title update (less frequent than insights)
        let segmentCount = finalSegments.count
        let shouldUpdateTitle = segmentCount >= lastTitleUpdateCount + titleUpdateThreshold
        
        isGeneratingInsights = true
        
        do {
            // Only ask for title if we're due for an update
            let existingTitle = shouldUpdateTitle ? nil : currentTitleSuffix
            
            let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
            let insights = try await insightsService.generateLiveInsights(
                transcript: transcript,
                existingSummary: liveSummary.isEmpty ? nil : liveSummary,
                existingTitle: existingTitle.flatMap { $0.isEmpty ? nil : $0 },
                mode: insightsMode,
                model: selectedModel,
                apiKey: openaiApiKey
            )
            
            // Update live insights
            liveSummary = insights.summary
            liveActionItems = insights.actionItems
            liveTopics = insights.topics
            liveDiscussionFlow = insights.discussionFlow
            
            // Update MEDDPICC fields
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
                // Always keep timestamp prefix, update the suffix
                let newSuffix = suggestedTitle.trimmingCharacters(in: .whitespaces)
                
                // Only update if the title actually changed meaningfully
                if newSuffix != currentTitleSuffix {
                    currentTitleSuffix = newSuffix
                    meeting.title = "\(meetingTimestamp) - \(newSuffix)"
                    lastTitleUpdateCount = segmentCount
                    print("[AppState] Updated meeting title to: \(meeting.title)")
                }
            }
        } catch {
            print("Live insights error: \(error)")
        }
        
        isGeneratingInsights = false
    }
    
    func startNewMeeting() {
        guard !deepgramApiKey.isEmpty else {
            showSettings = true
            return
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
        
        // Reset live notes and insights
        liveNotes = ""
        liveSummary = ""
        liveActionItems = []
        liveTopics = []
        liveDiscussionFlow = []
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        
        startRecording()
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
        guard let insightsService, !openaiApiKey.isEmpty else { return }
        guard !isGeneratingInsights else { return }
        
        // Build transcript from final segments
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        let transcript = finalSegments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[S\($0.speaker + 1)] \($0.text)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else { return }
        
        isGeneratingInsights = true
        
        do {
            let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
            let insights = try await insightsService.generateLiveInsights(
                transcript: transcript,
                existingSummary: nil, // Fresh analysis
                existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix,
                mode: .meddpicc,
                model: selectedModel,
                apiKey: openaiApiKey
            )
            
            // Update all insights
            liveSummary = insights.summary
            liveActionItems = insights.actionItems
            liveTopics = insights.topics
            liveDiscussionFlow = insights.discussionFlow
            
            // Update MEDDPICC fields
            liveMetrics = insights.metrics
            liveEconomicBuyer = insights.economicBuyer
            liveDecisionCriteria = insights.decisionCriteria
            liveDecisionProcess = insights.decisionProcess
            livePaperProcess = insights.paperProcess
            liveIdentifiedPain = insights.identifiedPain
            liveChampion = insights.champion
            liveCompetition = insights.competition
            
            // Track that we've analyzed this content with MEDDPICC
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
        
        // Add segments to meeting if not already done
        if meeting.segments.isEmpty {
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
    
    func startRecording() {
        guard let audioCaptureService, let deepgramService else { return }
        
        isRecording = true
        
        // Configure and start Deepgram with selected model
        let selectedModel = DeepgramModel(rawValue: deepgramModel) ?? .nova3
        deepgramService.configure(apiKey: deepgramApiKey)
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
        
        // Start duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 1
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioCaptureService?.stopCapture()
        deepgramService?.disconnect()
        
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
    }
    
    private func generateFinalInsightsAndSave() async {
        guard let insightsService, !openaiApiKey.isEmpty else {
            saveCurrentMeetingIfNeeded()
            return
        }
        
        // Build transcript
        let transcript = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[S\($0.speaker + 1)] \($0.text)" }
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
            let insights = try await insightsService.generateLiveInsights(
                transcript: transcript,
                existingSummary: nil,
                existingTitle: nil,
                mode: .standard,
                model: selectedModel,
                apiKey: openaiApiKey
            )
            
            // Update standard insights
            liveSummary = insights.summary
            liveActionItems = insights.actionItems
            liveTopics = insights.topics
            liveDiscussionFlow = insights.discussionFlow
            
            // Update title if we got one
            if let suggestedTitle = insights.suggestedTitle,
               !suggestedTitle.isEmpty,
               let meeting = currentMeeting {
                currentTitleSuffix = suggestedTitle
                meeting.title = "\(meetingTimestamp) - \(suggestedTitle)"
                print("[AppState] Final title: \(meeting.title)")
            }
        } catch {
            print("[AppState] Failed to generate standard insights: \(error)")
        }
        
        // Also generate MEDDPICC insights
        do {
            print("[AppState] Generating MEDDPICC insights...")
            let meddpiccInsights = try await insightsService.generateLiveInsights(
                transcript: transcript,
                existingSummary: liveSummary,
                existingTitle: currentTitleSuffix,
                mode: .meddpicc,
                model: selectedModel,
                apiKey: openaiApiKey
            )
            
            // Update MEDDPICC fields
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
        guard let meeting = currentMeeting,
              let insightsService,
              !openaiApiKey.isEmpty else { return }
        
        isGeneratingInsights = true
        
        do {
            let selectedModel = OpenAIModel(rawValue: openaiModel) ?? .gpt5Mini
            let insights = try await insightsService.generateInsights(
                transcript: meeting.fullTranscript,
                model: selectedModel,
                apiKey: openaiApiKey
            )
            
            meeting.summaryText = insights.summary
            meeting.actionItems = insights.actionItems
            meeting.keyDecisions = insights.decisions
            meeting.topics = insights.topics
        } catch {
            print("Failed to generate insights: \(error)")
        }
        
        isGeneratingInsights = false
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
                md += "\n**Speaker \(segment.speaker + 1):**\n"
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
