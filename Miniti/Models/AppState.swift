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

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case account
    case recording
    case language
    case ai
    case templates
    case notifications
    case calendar
    case crm
    case webhooks
    case docsMCP
    case dataExport
    case privacySupport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .account: return "Account & Plan"
        case .recording: return "Recording & Audio"
        case .language: return "Language"
        case .ai: return "AI & Models"
        case .templates: return "Templates"
        case .notifications: return "Notifications"
        case .calendar: return "Calendar & Meetings"
        case .crm: return "CRM"
        case .webhooks: return "Webhooks"
        case .docsMCP: return "Docs MCP"
        case .dataExport: return "Data & Export"
        case .privacySupport: return "Privacy & Support"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup and appearance"
        case .account: return "Subscription, usage, API mode, and keys"
        case .recording: return "Audio sources, permissions, and recording behavior"
        case .language: return "Transcription language and vocabulary"
        case .ai: return "Transcription and insight models"
        case .templates: return "Built-in and your own insight templates"
        case .notifications: return "Meeting reminders and coaching nudges"
        case .calendar: return "Google Calendar and meeting automation"
        case .crm: return "Attio and Twenty connections"
        case .webhooks: return "Send meeting data to other tools"
        case .docsMCP: return "Ground Playbook answers in your documentation"
        case .dataExport: return "Import meetings and export your data"
        case .privacySupport: return "Diagnostics, app information, and help"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.crop.circle"
        case .recording: return "waveform"
        case .language: return "character.book.closed"
        case .ai: return "sparkles"
        case .templates: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .calendar: return "calendar"
        case .crm: return "person.2"
        case .webhooks: return "arrow.triangle.branch"
        case .docsMCP: return "books.vertical"
        case .dataExport: return "tray.and.arrow.down"
        case .privacySupport: return "hand.raised"
        }
    }

    static func fromLegacyID(_ id: String) -> SettingsDestination {
        switch id {
        case "account", "apikeys": return .account
        case "audio", "recording": return .recording
        case "language": return .language
        case "ai", "models": return .ai
        case "templates": return .templates
        case "notifications": return .notifications
        case "integrations", "calendar": return .calendar
        case "crm": return .crm
        case "webhook", "webhooks": return .webhooks
        case "mcp", "docsMCP": return .docsMCP
        case "data", "dataExport": return .dataExport
        case "about", "privacySupport": return .privacySupport
        default: return .general
        }
    }
}

enum SettingsPlatform: Hashable {
    case macOS
    case iOS
}

extension SettingsDestination {
    static func available(on platform: SettingsPlatform) -> [SettingsDestination] {
        allCases.filter { destination in
            destination != .crm || platform == .macOS
        }
    }
}

struct SettingsSearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let section: String
    let destination: SettingsDestination
    let keywords: [String]
    let platforms: Set<SettingsPlatform>
    let requiresBYOK: Bool

    init(
        _ id: String,
        _ title: String,
        section: String,
        destination: SettingsDestination,
        keywords: [String] = [],
        platforms: Set<SettingsPlatform> = [.macOS, .iOS],
        requiresBYOK: Bool = false
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.destination = destination
        self.keywords = keywords
        self.platforms = platforms
        self.requiresBYOK = requiresBYOK
    }

    var breadcrumb: String { "\(destination.title) › \(section)" }

    func isAvailable(on platform: SettingsPlatform, appMode: AppMode) -> Bool {
        platforms.contains(platform) && (!requiresBYOK || appMode == .byok)
    }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = ([title, section, destination.title, destination.subtitle] + keywords)
            .joined(separator: " ")
        return terms.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }
}

enum SettingsSearchCatalog {
    static let items: [SettingsSearchItem] = [
        .init("general.launchAtLogin", "Launch at Login", section: "Startup", destination: .general, keywords: ["open automatically", "startup"], platforms: [.macOS]),
        .init("general.showInMenuBar", "Show in Menu Bar", section: "Appearance", destination: .general, keywords: ["status item", "menu icon"], platforms: [.macOS]),
        .init("general.recordingIndicator", "Show Recording Indicator", section: "Appearance", destination: .general, keywords: ["floating", "panel", "overlay", "REC"], platforms: [.macOS]),
        .init("general.interfaceScale", "Interface Scale", section: "Appearance", destination: .general, keywords: ["compact", "standard", "large", "text size"]),

        .init("account.subscription", "Subscription", section: "Plan", destination: .account, keywords: ["free", "pro", "upgrade", "manage", "restore"]),
        .init("account.usage", "Usage", section: "Plan", destination: .account, keywords: ["minutes", "limit", "remaining"]),
        .init("account.apiMode", "API Mode", section: "Mode", destination: .account, keywords: ["managed", "BYOK", "bring your own keys"]),
        .init("account.deepgramKey", "Deepgram API Key", section: "API Keys", destination: .account, keywords: ["transcription key"], requiresBYOK: true),
        .init("account.openAIKey", "OpenAI API Key", section: "API Keys", destination: .account, keywords: ["insights key"], requiresBYOK: true),
        .init("account.deviceID", "Device ID", section: "Device", destination: .account, keywords: ["identifier", "UUID"]),

        .init("recording.microphone", "Capture Microphone", section: "Audio Sources", destination: .recording, keywords: ["mic", "audio input"], platforms: [.macOS]),
        .init("recording.systemAudio", "Capture System Audio", section: "Audio Sources", destination: .recording, keywords: ["screen audio", "video calls"], platforms: [.macOS]),
        .init("recording.permissions", "Audio Permissions", section: "Permissions", destination: .recording, keywords: ["microphone access", "system settings"]),
        .init("recording.autoStop", "Auto-stop After Silence", section: "Recording", destination: .recording, keywords: ["quiet", "inactivity", "3 minutes", "5 minutes", "fallback"]),
        .init("recording.autoNameSpeakers", "Auto-name Speakers", section: "Recording", destination: .recording, keywords: ["diarization", "speaker names"]),
        .init("recording.onDeviceSpeakers", "On-device Speaker Separation", section: "Recording", destination: .recording, keywords: ["diarization", "nemotron", "beta", "privacy", "speakers", "local"]),
        .init("recording.liveActivityTranscript", "Show Transcript on Lock Screen", section: "Live Activity", destination: .recording, keywords: ["Dynamic Island", "privacy"], platforms: [.iOS]),

        .init("templates.list", "Templates", section: "Templates", destination: .templates, keywords: ["BANT", "SPIN", "interview", "stand-up", "1:1", "check-in", "specialist view", "sections"]),
        .init("templates.custom", "Your Templates", section: "Templates", destination: .templates, keywords: ["custom", "new template", "edit", "import", "export", "duplicate", "preview"]),

        .init("language.default", "Default Language", section: "Language", destination: .language, keywords: ["transcription language"]),
        .init("language.dictionary", "Personal Dictionary", section: "Language", destination: .language, keywords: ["vocabulary", "names", "acronyms", "correction", "replace"]),
        .init("language.fillers", "Filler Detection", section: "Language", destination: .language, keywords: ["um", "uh", "coaching"]),
        .init("ai.models", "AI Models", section: "Models", destination: .ai, keywords: ["Nova-3", "GPT", "Deepgram", "OpenAI", "BYOK", "managed"]),
        .init("ai.investigations", "OpenAI Investigations", section: "Meeting Investigations", destination: .ai, keywords: ["research", "web", "codebase", "folder", "investigate"]),

        .init("notifications.questions", "Incisive Question Notifications", section: "Meeting Nudges", destination: .notifications, keywords: ["questions", "alert"]),
        .init("notifications.monologue", "Monologue Nudges", section: "Meeting Nudges", destination: .notifications, keywords: ["talking too long", "coaching"]),
        .init("notifications.fillers", "Filler Word Nudges", section: "Meeting Nudges", destination: .notifications, keywords: ["um", "uh", "coaching"]),
        .init("notifications.salesDetection", "Sales Conversation Suggestions", section: "Meeting Nudges", destination: .notifications, keywords: ["MEDDPICC", "sales", "detect", "suggest"]),
        .init("notifications.upcomingMeeting", "Upcoming Meeting Reminders", section: "Calendar Reminders", destination: .notifications, keywords: ["1 minute", "calendar", "alert"]),

        .init("integrations.smartMeetings", "Smart Meetings", section: "Meeting Automation", destination: .calendar, keywords: ["meeting ended", "handoff", "transition", "call detection", "zoom", "call ended"]),
        .init("integrations.googleCalendar", "Google Calendar", section: "Google Calendar", destination: .calendar, keywords: ["connect", "disconnect", "events"]),
        .init("integrations.autoStart", "Auto-start Recording", section: "Meeting Automation", destination: .calendar, keywords: ["countdown", "calendar"]),
        .init("integrations.meetingFilters", "Meeting Filters", section: "Meeting Filters", destination: .calendar, keywords: ["out of office", "ooo", "focus time", "all-day", "declined", "skip", "preview", "filter", "pto", "holiday"]),
        .init("integrations.calendarAutoStop", "Auto-stop After Meeting Ends", section: "Meeting Automation", destination: .calendar, keywords: ["calendar", "quiet"]),
        .init("integrations.attio", "Attio CRM", section: "CRM Connections", destination: .crm, keywords: ["sync", "companies"], platforms: [.macOS]),
        .init("integrations.twenty", "Twenty CRM", section: "CRM Connections", destination: .crm, keywords: ["sync", "companies"], platforms: [.macOS]),
        .init("integrations.webhook", "Webhook URL", section: "Webhooks", destination: .webhooks, keywords: ["Zapier", "Make", "n8n", "POST"]),
        .init("integrations.docsMCP", "Docs MCP", section: "Connection", destination: .docsMCP, keywords: ["playbook", "documentation", "server"]),

        .init("data.granola", "Import from Granola", section: "Import", destination: .dataExport, keywords: ["CSV", "meetings"]),
        .init("data.markdownFolder", "Markdown Export Folder", section: "Markdown Export", destination: .dataExport, keywords: ["Obsidian", "files"], platforms: [.macOS]),
        .init("data.autoExport", "Auto-export Meetings as Markdown", section: "Markdown Export", destination: .dataExport, keywords: ["Obsidian", "AGENTS.md"], platforms: [.macOS]),
        .init("data.exportAll", "Export All Meetings", section: "Markdown Export", destination: .dataExport, keywords: ["backup", "markdown"], platforms: [.macOS]),

        .init("account.recoveryKey", "Recovery Key", section: "Account", destination: .account, keywords: ["account", "restore", "backup", "another device", "sign in"]),
        .init("account.devices", "Devices on This Account", section: "Account", destination: .account, keywords: ["remove device", "sign out", "linked"]),
        .init("account.delete", "Delete Account", section: "Account", destination: .account, keywords: ["erase", "remove account", "privacy"]),

        .init("privacy.diagnostics", "Share Diagnostics", section: "Privacy", destination: .privacySupport, keywords: ["reliability", "errors", "telemetry"]),
        .init("privacy.version", "Version", section: "About", destination: .privacySupport, keywords: ["build", "update"]),
        .init("privacy.acknowledgements", "Acknowledgements", section: "About", destination: .privacySupport, keywords: ["licenses", "licences", "open source", "nemotron", "fluidaudio", "sparkle", "credits"]),
        .init("privacy.docs", "Miniti Docs", section: "Help", destination: .privacySupport, keywords: ["documentation", "learn"]),
        .init("privacy.support", "Support", section: "Help", destination: .privacySupport, keywords: ["help", "contact"]),
        .init("privacy.legal", "Privacy & Terms", section: "About", destination: .privacySupport, keywords: ["policy", "legal"])
    ]

    static func availableItems(on platform: SettingsPlatform, appMode: AppMode) -> [SettingsSearchItem] {
        items.filter { $0.isAvailable(on: platform, appMode: appMode) }
    }
}

@MainActor
final class AppState: ObservableObject {
    struct CalendarPrepNote: Codable, Equatable {
        let eventID: String
        var text: String
        var eventStart: Date?
        var updatedAt: Date
    }

    struct InvestigationSuggestion: Identifiable, Equatable {
        let id: UUID
        let focus: String
    }

    struct CodebaseSnapshot: Sendable, Equatable {
        let context: String
        let files: [String]
    }

    struct SmartMeetingPrompt: Identifiable, Equatable {
        enum Kind: Equatable {
            case quiet
            case calendar
            /// A recognized call app held the mic while no recording existed: offer notes.
            case callStart
            /// The associated call ended but the session is too short/empty for automatic
            /// ending (or no countdown surface is visible): ask instead.
            case callEnd
            /// A different recognized call app became active during the recording.
            case callTransition
        }

        let id: String
        let kind: Kind
        let title: String
        let message: String
        let eventID: String?
        var countdown: Int?
    }

    struct RecordingNudge: Identifiable, Equatable {
        enum Kind: Equatable {
            case question
            case monologue
            case fillerRate
            case salesDetected
        }

        let id: String
        let kind: Kind
        let title: String
        let message: String
    }

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
        case callEnded

        var label: String {
            switch self {
            case .silence: return "auto-stopped — no speech detected"
            case .stalledPipeline: return "auto-stopped — live transcription stopped responding"
            case .callEnded: return "ended automatically — call ended"
            }
        }

        var icon: String {
            switch self {
            case .silence: return "moon.zzz.fill"
            case .stalledPipeline: return "wifi.exclamationmark"
            case .callEnded: return "phone.down.fill"
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
        var sourceRaw: String? = nil
    }

    struct PersistedSegmentSnapshot: Sendable {
        let id: UUID
        let text: String
        let speaker: Int
        let timestamp: TimeInterval
        var sourceRaw: String? = nil
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

    private struct PendingOrderedFinalSegment {
        let segment: DeepgramService.SpeakerSegment
        let timelineOffset: TimeInterval
        let arrivalSequence: UInt64
        let deadline: Date
    }

    private struct MeetingSavePayload {
        let meeting: Meeting
        let meetingID: UUID
        let stateFingerprint: Int
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
        let insightTemplateID: String?
        let templateSections: [String: String]
        let speakerNames: [String: String]
        let speakerOverrides: Set<String>
        let selfSpeakerIDs: Set<Int>
    }

    private struct PendingMeetingSave {
        var payload: MeetingSavePayload
        var revision: UInt64
    }

    private struct MeetingSaveFence {
        let meetingID: UUID
        let revision: UInt64
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

    private enum PendingMeetingCompletion {
        case none
        case returnHome
        case startUnscheduled
        case startCalendar(MinitiAPIService.CalendarEvent, openJoinLink: Bool)
    }

    private var pendingMeetingCompletion: PendingMeetingCompletion = .none

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
    /// Distinct app speaker IDs confirmed on the microphone source this session.
    /// Drives the implicit-"You" rule: once a second mic speaker exists, nobody
    /// is assumed to be the user.
    @Published var liveMicSpeakerIDs: Set<Int> = []
    /// Internal, diagnostic-only inferred meeting environment. Never a user-facing
    /// choice or badge; never changes capture routing, meeting boundaries,
    /// persistence rules, usage reporting, or transcript content.
    private(set) var inferredMeetingEnvironment: InferredMeetingEnvironment = .unknown
    private var environmentEvidence = MeetingEnvironmentEvidence()
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

    // MARK: - Meeting Prep + Investigations
    @Published private(set) var calendarPrepNotes: [String: CalendarPrepNote] = [:]
    @Published private(set) var investigationSuggestion: InvestigationSuggestion?
    @Published private(set) var investigationResult: InvestigationResult?
    @Published private(set) var investigationError: String?
    @Published private(set) var isGeneratingInvestigation = false
    @Published var isInvestigationPresented = false
    @Published private(set) var activeInvestigationScope: InvestigationScope = .web
    @Published private(set) var activeInvestigationFocus = ""
    #if os(macOS)
    @AppStorage("investigationCodebaseBookmark") private var investigationCodebaseBookmark: Data = Data()
    #endif
    private static let calendarPrepNotesDefaultsKey = "calendarPrepNotes.v1"
    private var lastInvestigationEvaluatedFinalSegmentID: UUID?
    private var dismissedInvestigationSuggestionIDs: Set<UUID> = []
    private var activeInvestigationTask: Task<Void, Never>?
    private var investigationRequestID: UUID?
    
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
    // Templates specialist view: the template in use for this meeting and its filled
    // sections (section key -> text). `liveTemplateID` is nil until the view is enabled.
    @Published var liveTemplateID: String? = nil
    @Published var liveTemplateSections: [String: String] = [:]
    /// The person's own templates (roadmap P2.1), loaded once and persisted on every change.
    @Published private(set) var customInsightTemplates: [InsightTemplate] = CustomInsightTemplates.load()
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

    // MARK: - Template Tracking
    private var lastTemplateSegmentCount = 0
    private var lastTemplateRequestAt: Date? = nil
    private let firstTemplateInsightThreshold = 6
    private let templateInsightUpdateThreshold = 12
    private let templateMinUpdateInterval: TimeInterval = 60
    private var isGeneratingTemplateInsights = false

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
    private var templateRequestSeq = 0
    private var lastAppliedTemplateSeq = -1
    private var standardSuccessCount = 0
    private var meddpiccSuccessCount = 0
    private var questionsSuccessCount = 0
    private var templateSuccessCount = 0
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
    private var templateCadenceAnchor: Date?
    private var standardLastAttemptAt: Date?
    private var meddpiccLastAttemptAt: Date?
    private var questionsLastAttemptAt: Date?
    private var templateLastAttemptAt: Date?
    private var lastWarmupInsightsAttemptAt: Date?
    private var standardLastFiredSegmentCount = 0
    private var meddpiccLastFiredSegmentCount = 0
    private var questionsLastFiredSegmentCount = 0
    private var templateLastFiredSegmentCount = 0
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
    private let templateCadencePolicy = LiveInsightCadencePolicy(
        minimumInterval: 90,
        minimumSegmentDelta: 8,
        maximumInterval: 180
    )
    private let warmupInsightsRetryInterval: TimeInterval = 30
    private let meddpiccCadenceStagger: TimeInterval = 15
    private let questionsCadenceStagger: TimeInterval = 22
    private let templateCadenceStagger: TimeInterval = 30
    
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
    /// Last markdown filename written per meeting, so a re-export after an AI title change
    /// removes the stale file instead of leaving two exports for one meeting. In-memory only.
    var lastExportedMarkdownFilenames: [UUID: String] = [:]
    #endif

    // MARK: - Update Check
    @Published var availableUpdate: MinitiAPIService.VersionInfo?
    @Published var requiresForceUpdate = false
    
    // MARK: - Managed Mode State
    @Published var usageInfo: MinitiAPIService.UsageInfo?
    // Device-bound authorization (managed mode). The account is an anonymous recovery key;
    // see Miniti/Services/ClientAuth.swift. Screenshot mode fakes an enrolled state.
    @Published var clientAuthStatus: ClientAuthStatus = ClientAuthManager.shared.status
    @Published private(set) var isEnrollingManagedDevice = false
    @Published private(set) var managedEnrollmentError: String?
    /// Show the "save your recovery key" nudge: enrolled, key never acknowledged, not snoozed this launch.
    @Published private(set) var showRecoveryKeyNotice = false
    @Published private(set) var managedDevices: [ClientAuthDevice] = []
    @Published private(set) var managedDevicesError: String?
    /// Set when the on-disk meeting store could not be opened at launch (roadmap P0.2).
    /// Settings uses it to disable export/import; the recovery screen owns the rest.
    @Published private(set) var persistentStoreFailure: PersistentStoreOpenFailure?
    /// The most recent save or load that did not persist (roadmap P0.3). Rendered once at the
    /// app root by `PersistenceIssueBanner`; cleared by dismiss, a successful retry, or the
    /// next successful commit of the same operation. See `AppState+Persistence.swift`.
    @Published private(set) var persistenceIssue: PersistenceIssue?
    /// Re-runs the failed commit. Nil when the operation is not safely repeatable.
    var persistenceRetryAction: (() -> Void)?
    /// Seams so tests can inject failures. Production keeps the plain SwiftData calls.
    var persistenceSaveHandler: (ModelContext) throws -> Void = { try $0.save() }
    var persistenceFetchHandler: (ModelContext, FetchDescriptor<Meeting>) throws -> [Meeting] = { try $0.fetch($1) }
    /// Sees every diagnostics event before the share/mode guards; tests assert through it.
    var diagnosticEventObserver: ((String, [String: String]) -> Void)?
    private var recoveryKeyNoticeSnoozed = false
    private var enrollmentTask: Task<Bool, Never>?
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

    #if DEBUG
    /// Screenshot mode: the seeded live meeting already "received" every kind of insight,
    /// so the first-response warm-up placeholders must not render above the content.
    func markAllInsightsReceivedForScreenshots() {
        standardSuccessCount = 2
        meddpiccSuccessCount = 2
        questionsSuccessCount = 2
        templateSuccessCount = 2
    }
    #endif

    /// True after first non-degraded standard insights response (for warmup placeholder).
    var hasReceivedStandardInsights: Bool { standardSuccessCount > 0 }
    /// True after first non-degraded MEDDPICC insights response (for warmup placeholder).
    var hasReceivedMeddpiccInsights: Bool { meddpiccSuccessCount > 0 }
    var hasReceivedQuestionsInsights: Bool { questionsSuccessCount > 0 }
    var hasReceivedDocsInsights: Bool { docsSuccessCount > 0 }
    var hasReceivedTemplateInsights: Bool { templateSuccessCount > 0 }

    /// The template the Templates view uses for new meetings (and the live one when set).
    var selectedInsightTemplate: InsightTemplate {
        insightTemplate(id: insightTemplateID)
            ?? InsightTemplate.builtIn(id: InsightTemplate.defaultID)
            ?? InsightTemplate.builtIn[0]
    }

    /// The template attached to the live meeting, falling back to the selected default.
    var liveTemplate: InsightTemplate {
        insightTemplate(id: liveTemplateID) ?? selectedInsightTemplate
    }

    /// Built-in first, then the person's own (roadmap P2.1).
    func insightTemplate(id: String?) -> InsightTemplate? {
        guard let id else { return nil }
        return InsightTemplate.builtIn(id: id) ?? customInsightTemplates.first { $0.id == id }
    }

    /// What the Templates submenu lists.
    var availableInsightTemplates: [InsightTemplate] {
        InsightTemplate.builtIn + customInsightTemplates
    }

    // MARK: Custom templates

    /// Add or replace one of the person's templates and persist the list.
    func saveCustomInsightTemplate(_ template: InsightTemplate) {
        guard template.isCustom else { return }
        if let index = customInsightTemplates.firstIndex(where: { $0.id == template.id }) {
            customInsightTemplates[index] = template
        } else {
            customInsightTemplates.append(template)
        }
        CustomInsightTemplates.save(customInsightTemplates)
        DebugLogger.shared.log(.app, "Custom template saved: sections=\(template.sections.count)")
        if liveTemplateID == template.id { liveTemplateSections = liveTemplateSections.filter { section in template.sections.contains { $0.key == section.key } } }
    }

    /// Delete one of the person's templates. Meetings that used it keep their own copy.
    func deleteCustomInsightTemplate(id: String) {
        customInsightTemplates.removeAll { $0.id == id }
        CustomInsightTemplates.save(customInsightTemplates)
        if insightTemplateID == id { insightTemplateID = InsightTemplate.defaultID }
        if liveTemplateID == id { liveTemplateID = nil }
        DebugLogger.shared.log(.app, "Custom template deleted")
    }

    @discardableResult
    func duplicateInsightTemplate(_ template: InsightTemplate) -> InsightTemplate {
        let copy = CustomInsightTemplates.duplicate(template)
        saveCustomInsightTemplate(copy)
        return copy
    }

    /// Re-read the stored list; screenshot mode installs its seeded template after init.
    func reloadCustomInsightTemplates() {
        customInsightTemplates = CustomInsightTemplates.load()
    }

    var canAddCustomInsightTemplate: Bool {
        customInsightTemplates.count < InsightTemplate.maxCustomTemplates
    }

    /// Fill `template` from a saved meeting's transcript without touching the meeting. Used by
    /// the editor's preview so people see what a template produces before using it live.
    func previewInsightTemplate(_ template: InsightTemplate, using meeting: Meeting) async throws -> [String: String] {
        let transcript = meeting.fullTranscript
        let language = meeting.language
        guard !transcript.isEmpty else { return [:] }
        let model = OpenAIModel.gpt5Mini
        if appMode == .managed, minitiAPIService != nil {
            let response = try await generateManagedInsightsWithRetry(
                deviceId: DeviceIdentifier.getOrCreateDeviceId(), transcript: transcript,
                existingSummary: nil, existingTitle: nil,
                mode: InsightsMode.template.rawValue, model: model.rawValue,
                language: language, template: template
            )
            return response.toLiveInsights(template: template).templateSections
        }
        guard let insightsService, !openaiApiKey.isEmpty else {
            throw MinitiAPIService.ServiceError.serverError("add an OpenAI key in Settings → Account to preview templates")
        }
        return try await insightsService.generateLiveInsights(
            transcript: transcript, existingSummary: nil, existingTitle: nil,
            mode: .template, model: model, apiKey: openaiApiKey, language: language, template: template
        ).templateSections
    }

    var hasLiveTemplateContent: Bool {
        !liveTemplate.orderedSections(from: liveTemplateSections).isEmpty
    }

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
        case .template:
            return templateInsightsEnabled
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
        case .template:
            templateInsightsEnabled = enabled
            if enabled, liveTemplateID == nil, currentMeeting != nil {
                liveTemplateID = selectedInsightTemplate.id
            }
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
    /// On by default in managed mode (2.8.0). Structured reliability events only; the
    /// backend stores a bounded window and nothing here carries transcript or audio.
    /// A person who switched it off keeps it off: the default applies only to an unset key.
    @AppStorage("shareDiagnostics") var shareDiagnostics: Bool = true {
        didSet {
            if !shareDiagnostics {
                pendingClientEvents.removeAll()
                persistPendingClientEvents()
            } else {
                Task { await flushClientEvents(trigger: "setting enabled") }
            }
        }
    }
    @AppStorage("webhookURL") var webhookURL: String = "" {
        didSet { updateLogRedaction() }
    }
    @AppStorage("salesInsightsEnabled") var salesInsightsEnabled: Bool = false
    @AppStorage("playbookInsightsEnabled") var playbookInsightsEnabled: Bool = false
    @AppStorage("templateInsightsEnabled") var templateInsightsEnabled: Bool = false
    /// Built-in template id used for new meetings once the Templates view is enabled.
    @AppStorage("insightTemplateID") var insightTemplateID: String = InsightTemplate.defaultID
    @AppStorage("docsMCPURL") var docsMCPURL: String = "" {
        didSet {
            if validatedDocsMCPURL != nil {
                playbookInsightsEnabled = true
            } else {
                setInsightModeEnabled(.docs, enabled: false)
            }
        }
    }
    @AppStorage("autoStopMinutes") var autoStopMinutes: Int = 5 {
        didSet { restartMeetingAutomationMonitoring() }
    }
    @AppStorage("smartMeetingsEnabled") var smartMeetingsEnabled: Bool = true {
        didSet {
            if !smartMeetingsEnabled {
                clearSmartMeetingPrompt()
                #if os(macOS)
                // A pending automatic-end countdown belongs to the feature being turned
                // off: cancel it and resume the recording rather than letting it finish.
                cancelEndingGrace(reason: .smartMeetingsDisabled)
                #endif
            }
            restartMeetingAutomationMonitoring()
            #if os(macOS)
            updateCallActivityMonitoringState()
            #endif
        }
    }
    @AppStorage("googleCalendarEnabled") var googleCalendarEnabled: Bool = false
    @AppStorage("autoAttioSync") var autoAttioSync: Bool = false
    @AppStorage("autoTwentySync") var autoTwentySync: Bool = false
    @AppStorage("autoStartFromCalendar") var autoStartFromCalendar: Bool = false {
        didSet { restartMeetingAutomationMonitoring() }
    }
    @AppStorage("autoStopFromCalendar") var autoStopFromCalendar: Bool = false {
        didSet { restartMeetingAutomationMonitoring() }
    }
    #if os(macOS)
    /// Floating recording indicator visibility. Independent of Smart meetings and the menu
    /// bar item: hiding the strip must not disable lifecycle automation or vice versa.
    @AppStorage("showRecordingIndicator") var showRecordingIndicator: Bool = true
    #endif
    @AppStorage("notifyOnIncisiveQuestions") var notifyOnIncisiveQuestions: Bool = false
    @AppStorage("notifyOnMonologue") var notifyOnMonologue: Bool = false
    @AppStorage("notifyOnHighFillerRate") var notifyOnHighFillerRate: Bool = false
    /// Suggest enabling Sales (MEDDPICC) analysis when a live meeting sounds like a
    /// sales conversation. Default-on because it fires at most once per meeting and
    /// only while Sales analysis is off.
    @AppStorage("notifyOnSalesDetection") var notifyOnSalesDetection: Bool = true
    @AppStorage("notifyOnUpcomingMeeting") var notifyOnUpcomingMeeting: Bool = false
    @AppStorage("autoInferSpeakerNames") var autoInferSpeakerNames: Bool = true
    /// Separate speakers with the on-device Nemotron model instead of Deepgram's diarizer.
    /// Default off (beta). When the model is loaded, new sessions open the Deepgram socket
    /// without the diarization add-on and take speaker numbers from the on-device timeline.
    @AppStorage("onDeviceSpeakerSeparation") var onDeviceSpeakerSeparationEnabled: Bool = false
    /// On-device diarization (Nemotron-3 via FluidAudio). Always constructed; does nothing
    /// until `onDeviceSpeakerSeparationEnabled` prepares its models.
    let onDeviceDiarization = OnDeviceDiarizationService()
    /// Timestamp (TimeInterval since 1970) after which the calendar nudge card on the
    /// home screen should stop being hidden. 0 = never dismissed. `.infinity` (or any
    /// value > 10 years from now) = permanently dismissed via the `×` button.
    @AppStorage("calendarNudgeDismissedUntil") var calendarNudgeDismissedUntil: Double = 0

    private var notifiedQuestionIDs: Set<String> = []
    private var lastQuestionNotificationAt: Date?
    private static let questionNotificationMinInterval: TimeInterval = 120 // 2 minutes
    /// Cached local dictionary corrector. Rebuilt when corrections are saved.
    /// Nil when the store is empty so existing users pay nothing.
    private var transcriptCorrector: TranscriptCorrector? = TranscriptCorrector(
        corrections: PersonalDictionaryPreferences.currentCorrections()
    )
    #if os(macOS)
    /// Transient live guidance shown by the floating recording surface while Miniti is
    /// frontmost. When the app is behind another app (or the surface is disabled), the
    /// same guidance is delivered through Notification Center instead.
    @Published private(set) var recordingNudge: RecordingNudge?
    private var recordingNudgeDismissTask: Task<Void, Never>?
    nonisolated static let recordingNudgeDuration: TimeInterval = 10
    #endif

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

    // Sales-conversation detection (local keyword heuristic, no LLM). Distinct signal
    // phrases accumulate across finalized segments; one suggestion per meeting at most.
    private var salesDetectionSignalsSeen: Set<String> = []
    private var salesDetectionNudgeFired = false
    nonisolated static let salesDetectionMinDistinctSignals = 3
    /// Deliberately commercial-only vocabulary: generic meeting words ("decision",
    /// "timeline") are excluded so ordinary planning meetings don't trigger this.
    nonisolated static let salesSignalPhrases: [String] = [
        "pricing", "price point", "budget", "contract", "procurement", "renewal",
        "discount", "quote", "proposal", "decision maker", "purchase order",
        "licensing", "per seat", "annual plan", "sales cycle", "close the deal"
    ]

    /// Which sales-signal phrases occur in `text` (case-insensitive, word-boundary
    /// tokens so "contract" doesn't match "contractor").
    nonisolated static func salesSignalMatches(in text: String) -> Set<String> {
        let tokens = TrainingMetrics.tokenize(text)
        guard !tokens.isEmpty else { return [] }
        var matches: Set<String> = []
        for phrase in salesSignalPhrases {
            let phraseTokens = TrainingMetrics.tokenize(phrase)
            guard !phraseTokens.isEmpty else { continue }
            if TrainingMetrics.countPhraseOccurrences(of: phraseTokens, in: tokens) > 0 {
                matches.insert(phrase)
            }
        }
        return matches
    }
    
    @Published var isGoogleCalendarConnected: Bool = false
    @Published var googleCalendarEmail: String?
    @Published var upcomingEvents: [MinitiAPIService.CalendarEvent] = []
    /// Every non-cancelled event from the last calendar fetch, before the meeting
    /// filters. `upcomingEvents` is this list minus what the filters skip, so a
    /// filter change re-applies without another network call.
    private var fetchedCalendarEvents: [MinitiAPIService.CalendarEvent] = []
    /// Which calendar events count as meetings (Settings → Calendar → Meeting filters).
    @Published var calendarMeetingFilters = MinitiAPIService.CalendarMeetingFilterPreferences.load() {
        didSet {
            guard calendarMeetingFilters != oldValue else { return }
            calendarMeetingFilters.save()
            applyCalendarMeetingFilters()
        }
    }

    /// One row of the "next 7 days" preview in Settings.
    struct CalendarFilterPreviewRow: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date?
        let isAllDay: Bool
        let skipReason: MinitiAPIService.CalendarMeetingSkipReason?
    }
    @Published var selectedCalendarEvent: MinitiAPIService.CalendarEvent?

    var upcomingMeetingEvents: [MinitiAPIService.CalendarEvent] {
        let now = Date()
        return upcomingEvents
            .filter { event in
                guard !event.isAllDay,
                      event.status.lowercased() != "cancelled",
                      let end = event.endDate else { return false }
                return end > now
            }
            .sorted {
                ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
            }
    }

    var todayEvents: [MinitiAPIService.CalendarEvent] {
        let calendar = Calendar.current
        return upcomingMeetingEvents.filter { event in
            guard let start = event.startDate else { return false }
            return calendar.isDateInToday(start)
        }
    }

    var nextEvent: MinitiAPIService.CalendarEvent? {
        todayEvents.first
    }
    @Published var pendingAutoStartEvent: MinitiAPIService.CalendarEvent?
    @Published var autoStartCountdown: Int = 0
    @Published var calendarEventEndedWhileRecording: Bool = false
    @Published private(set) var smartMeetingPrompt: SmartMeetingPrompt?
    private var calendarRefreshTimer: Timer?
    private var autoStartCheckTimer: Timer?
    /// Bounded retry for a launch-time (or wake-time) calendar status check that could not
    /// reach the backend. A thrown check is "unknown", never "disconnected": after a reboot
    /// the app often starts before the network does, and treating that as signed-out left
    /// people reconnecting Google Calendar by hand every morning (2026-09-25).
    private var calendarStatusRetryTask: Task<Void, Never>?
    private var calendarStatusRetryAttempt = 0
    private var lastCalendarStatusRecheckAt: Date?
    /// Set once the launch-time status check has returned, so an activation recheck
    /// cannot run a second check (and a second events fetch) during a normal cold start.
    private var calendarLaunchCheckCompleted = false
    private var autoStartCountdownTimer: Timer?
    private var dismissedAutoStartEventIDs: Set<String> = []
    /// One browser/tab open per calendar event for a given meeting start. Cleared with
    /// other per-meeting state so a later explicit rejoin (live header) can reopen.
    private var openedJoinLinkEventIDs: Set<String> = []
    /// Reminder tapped before the first calendar refresh of this launch; consumed once.
    private var pendingReminderJoinEventID: String?
    /// Test seam: when set, `openMeetingLink` uses this instead of the system browser.
    var testOpenURLHandler: ((URL) -> Bool)?
    /// Test seam for reminder "not now" routing.
    var testingDismissedAutoStartEventIDs: Set<String> { dismissedAutoStartEventIDs }
    private var smartMeetingCountdownTimer: Timer?
    private var smartMeetingSnoozedUntilByEventID: [String: Date] = [:]
    private var smartMeetingSuppressedUntil: Date?
    private var smartQuietEpisodePrompted = false

    // MARK: - Call lifecycle (macOS)
    #if os(macOS)
    private var callActivityMonitor: CallActivityMonitor?
    private(set) var callLifecycleEngine = CallLifecycleEngine()
    private(set) var latestCallSnapshot: CallActivitySnapshot?
    /// Reversible pre-finalization countdown after a strong call end. A deferred stop:
    /// while non-nil, sending is suspended, the Deepgram socket stays open on KeepAlive,
    /// and none of the finalization path has run. See the call-lifecycle plan §4.
    @Published private(set) var endingGrace: EndingGraceState?
    private var endingGraceTimer: Timer?
    /// Wall-clock moment sending was suspended; restores the Deepgram timeline offset on resume.
    private var endingGraceSuspendedAt: Date?
    /// Set by the start-notes prompt so the next startRecording associates with that app.
    private var pendingCallAssociationApp: ActiveCallApplication?
    /// App backing the visible call-start prompt.
    private var startPromptApp: ActiveCallApplication?
    /// After `Keep recording` during grace or a call-end ask, hold off automatic ending for a
    /// while. Deliberately not cleared by speech: an in-person continuation should not re-arm
    /// the countdown the person just cancelled.
    private var suppressAutoCallEndUntil: Date?
    private var sleepWakeObserversInstalled = false
    /// The grace deadline lapsed while the Mac was asleep (or sleep interrupted it):
    /// finalize on wake, when async save/report work can actually run.
    private var finalizeGraceOnWake = false
    static let endingGraceDuration: TimeInterval = 10
    #endif
    
    @Published var wasAutoStopped = false
    @Published var autoStopReason: AutoStopReason?
    @Published var selectedSettingsTab: String = UserDefaults.standard.string(forKey: "selectedSettingsDestination") ?? "general" {
        didSet {
            UserDefaults.standard.set(SettingsDestination.fromLegacyID(selectedSettingsTab).rawValue, forKey: "selectedSettingsDestination")
        }
    }
    @Published var pendingSettingsSearchTarget: String?
    
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
    /// Last `SpeechStarted` from Deepgram's VAD this recording (0 = none yet). Feeds the
    /// quiet-prompt audio gap while transcription is healthy, so room noise cannot keep
    /// the "has this meeting ended?" question from ever appearing (2026-09-25).
    private var lastSpeechDetectedAt: CFAbsoluteTime = 0
    static let speechMicLevelThreshold: Float = 0.008
    static let speechSystemLevelThreshold: Float = 0.006
    private var deepgramReconnectTask: Task<Void, Never>?
    private var deepgramReconnectGeneration = 0
    private var lastDeepgramReconnectScheduledAt: CFAbsoluteTime = 0
    private var pendingMicSegments: [PendingMicSegment] = []
    private var recentSystemSegments: [BufferedSystemSegment] = []
    private var pendingMicFlushTask: Task<Void, Never>?
    private var pendingOrderedFinalSegments: [PendingOrderedFinalSegment] = []
    private var pendingOrderedFinalFlushTask: Task<Void, Never>?
    private var nextOrderedFinalArrivalSequence: UInt64 = 0
    /// Deepgram word times restart at zero for every WebSocket. Add this offset to place the
    /// current socket's precise word clock on the meeting's accumulated recording timeline.
    private var deepgramTimelineOffset: TimeInterval = 0
    private let micEchoReconciliationDelay: TimeInterval = 4
    private let echoSystemHistoryWindow: TimeInterval = 8
    private let dualChannelOrderingDelay: TimeInterval = 0.35
    private var pendingAudioRecoveryTransitionTask: Task<Void, Never>?
    private var desiredAudioRecoveryState: AudioRecoveryState = .healthy
    private var systemAudioInactiveSince: CFAbsoluteTime = 0
    private let pendingSessionReportsDefaultsKey = "pendingSessionEndReports"
    private var pendingSessionEndReports: [PendingSessionEndReport] = []
    private let pendingClientEventsDefaultsKey = "pendingClientEvents"
    private(set) var pendingClientEvents: [MinitiAPIService.ClientEventPayload] = []
    private var clientEventsFlushTask: Task<Void, Never>?
    private let diagnosticsSessionId = UUID().uuidString
    private var isFlushingPendingSessionReports = false
    private var recordingStartDate: Date?
    /// The published duration advances on a UI timer. Ordering reconnect epochs from the wall
    /// clock avoids up to one second of overlap between the old and new Deepgram timelines.
    private var preciseCurrentRecordingDuration: TimeInterval {
        guard let recordingStartDate else { return recordingDuration }
        return max(recordingDuration, Date().timeIntervalSince(recordingStartDate))
    }
    private var accumulatedRecordedDuration: TimeInterval = 0
    private var activeMeetingSaveTask: Task<Void, Never>?
    private var pendingMeetingSaves: [UUID: PendingMeetingSave] = [:]
    private var pendingMeetingSaveOrder: [UUID] = []
    private var nextMeetingSaveRevision: UInt64 = 0
    private var latestMeetingSaveRevision: [UUID: UInt64] = [:]
    private var successfulMeetingSaveRevision: [UUID: UInt64] = [:]
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
        /// Explicit capture source. Nil for legacy segments recorded before
        /// source tracking; those fall back to the reserved mic ID range.
        var source: TranscriptSource? = nil

        /// Whether this segment came from the local microphone (vs system/remote audio).
        /// Reads the explicit source; the ID-range check only covers legacy data.
        var isLocalMic: Bool {
            if let source { return source == .microphone }
            return DeepgramService.isMicAppSpeakerID(speaker)
        }

        /// Stable per-segment label used for LLM-facing transcripts. Not for UI —
        /// views resolve names/self marks via `resolvedSpeakerLabel`.
        var speakerLabel: String {
            if isLocalMic {
                return speaker == DeepgramService.micSpeakerID
                    ? "You"
                    : "Speaker \(speaker - DeepgramService.micSpeakerID + 1) (mic)"
            }
            return "Speaker \(speaker + 1)"
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
        let suffixStart = max(0, segments.count - duplicateSearchSuffix)
        // A mic segment can be held briefly for echo reconciliation. Include the nearby timeline
        // window as well as the legacy suffix so a late chronological insertion still merges a
        // cumulative Deepgram final instead of duplicating it.
        let delayedFinalSearchWindow: TimeInterval = 8
        let timelineStart = chronologicalInsertionIndex(
            for: newSegment.timestamp - delayedFinalSearchWindow,
            in: segments
        )
        let searchStart = min(suffixStart, timelineStart)
        var containedMatchIndex: Int?

        for index in searchStart..<segments.count {
            let existing = segments[index]
            let isInSuffix = index >= suffixStart
            if !isInSuffix,
               existing.timestamp > newSegment.timestamp + delayedFinalSearchWindow { continue }
            guard existing.isFinal else { continue }
            let sameSpeaker = existing.speaker == newSegment.speaker
            // Mic diarization can flip a cumulative Deepgram final to a
            // different mic speaker between passes. Allow cross-speaker dedup
            // only for mic-source segments that are near-simultaneous and
            // substantial enough that a coincidental short repeat ("Yeah.",
            // "Thank you.") from another person in the room cannot be
            // swallowed — a genuinely flipped cumulative final spans at least
            // a full speaker-change run (4+ words).
            let crossSpeakerMicMatch = !sameSpeaker
                && existing.isLocalMic && newSegment.isLocalMic
                && abs(existing.timestamp - newSegment.timestamp) <= 1.5
                && newSegment.text.split(separator: " ").count >= 4
            guard sameSpeaker || crossSpeakerMicMatch else { continue }
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
                isFinal: true,
                source: existing.source ?? newSegment.source
            )
            return .replacedSuperset
        }

        let insertionIndex = chronologicalInsertionIndex(for: newSegment.timestamp, in: segments)
        segments.insert(newSegment, at: insertionIndex)
        return .appended
    }

    nonisolated static func transcriptTimelineTimestamp(
        streamStart: TimeInterval,
        timelineOffset: TimeInterval
    ) -> TimeInterval {
        max(0, timelineOffset + streamStart)
    }

    /// Persist a total ordering without adding a SwiftData migration. Deepgram can emit two
    /// channel segments with the same sample timestamp; a microsecond tie-break remains invisible
    /// to users while surviving save/reload where relationship iteration order is unspecified.
    nonisolated static func collisionFreeTranscriptTimestamp(
        proposed: TimeInterval,
        in segments: [LiveSegment]
    ) -> TimeInterval {
        let step: TimeInterval = 0.000_001
        var candidate = max(0, proposed)
        while true {
            let index = chronologicalInsertionIndex(for: candidate, in: segments)
            let collidesWithPrevious = index > 0
                && abs(segments[index - 1].timestamp - candidate) < step / 2
            let collidesWithNext = index < segments.count
                && abs(segments[index].timestamp - candidate) < step / 2
            guard collidesWithPrevious || collidesWithNext else { return candidate }
            candidate += step
        }
    }

    nonisolated static func chronologicalInsertionIndex(
        for timestamp: TimeInterval,
        in segments: [LiveSegment]
    ) -> Int {
        guard let last = segments.last, last.timestamp > timestamp else { return segments.count }
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if segments[middle].timestamp <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    /// Preserve transcript text that was visible as an interim when a recording stopped but the
    /// streaming socket could not deliver a final result. The normal final-segment merge keeps
    /// this fallback from duplicating a final that arrived during graceful shutdown.
    @discardableResult
    nonisolated static func mergeStoppedInterimTranscript(
        _ text: String,
        speaker: Int,
        timestamp: TimeInterval,
        source: TranscriptSource? = nil,
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
                isFinal: true,
                source: source
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

        calendarPrepNotes = Self.decodeCalendarPrepNotes(
            UserDefaults.standard.data(forKey: Self.calendarPrepNotesDefaultsKey)
        )
        pruneExpiredCalendarPrepNotes()

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

        // Screenshot mode renders from seeded state and must stay offline: skip the
        // launch-time network work and fill the published state the scene needs.
        if ScreenshotMode.isActive {
            ScreenshotMode.apply(to: self)
            return
        }

        // The unit-test host constructs AppState hundreds of times; none of those launches may
        // refresh usage, check for updates, poll the calendar, or flush queued events against
        // production. Tests that need a network path inject a stubbed service explicitly.
        if Self.isRunningUnderXCTest {
            return
        }
        
        // Load usage info for managed mode. Enrollment (silent migration for existing
        // installs, otherwise a fresh anonymous account) runs first because every managed
        // request is device-bound.
        if appMode == .managed {
            isLoadingUsage = true
            Task {
                await refreshUsage()
                // The calendar status call needs the device-auth enrollment that
                // refreshUsage establishes; running it in parallel could throw
                // notEnrolled on a fresh install and look like a disconnect.
                await refreshGoogleCalendarStatus()
                startCalendarRefreshTimer()
                startAutoStartMonitoring()
                await flushPendingSessionEndReports(trigger: "launch")
                await flushClientEvents(trigger: "launch")
            }
        } else {
            // Check Google Calendar connection and fetch events
            Task {
                await refreshGoogleCalendarStatus()
                startCalendarRefreshTimer()
                startAutoStartMonitoring()
            }
        }
        
        // Check for app updates (all modes)
        Task { await checkForUpdates() }
        
        #if os(iOS)
        // Clean up orphaned Live Activities (app was killed while recording, state lost)
        Task { await cleanupOrphanedLiveActivities() }
        #endif
    }
    
    private func updateLogRedaction() {
        // The webhook URL is a secret too: hook URLs embed their token in the path.
        // WebhookService never logs it, but URLError text can, so redact it everywhere.
        DebugLogger.shared.setRedactPatterns([deepgramApiKey, openaiApiKey, webhookURL])
    }
    
    private func setupServices() {
        audioCaptureService = AudioCaptureService()
        deepgramService = DeepgramService()
        refreshOnDeviceDiarizationAvailability()
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

        // Deepgram's own speech detection: the quiet prompt's "speech-like audio" signal
        // while the pipeline is healthy. It stamps a timestamp only; prompts are cleared
        // by transcript, not by a VAD blip.
        deepgramService?.$lastSpeechStartedAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] at in
                guard at > 0 else { return }
                self?.lastSpeechDetectedAt = at
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
                        self.noteSmartMeetingActivity(source: .audioLevel)
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

        #if os(macOS)
        setupCallLifecycleMonitoring()
        #endif
    }

    private func handleTranscriptUpdate(_ update: DeepgramService.TranscriptUpdate) {
        // Skip empty updates
        guard !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastTranscriptReceivedAt = CFAbsoluteTimeGetCurrent()
        noteSmartMeetingActivity(source: .transcript)
        
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
            let interim = transcriptCorrector?.apply(to: update.text) ?? update.text
            transcriptRuntime.update(
                interimText: interim,
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
                let monoSource: TranscriptSource = self.captureMicrophone ? .microphone : .system
                #else
                let useMultichannel = false
                let monoSource: TranscriptSource = .microphone
                #endif
                let configured = await self.configureDeepgramCredentialForConnect()
                guard configured else {
                    DebugLogger.shared.log(.app, "Deepgram reconnect skipped attempt \(idx + 1): credential unavailable")
                    continue
                }
                // A new Deepgram socket resets word timestamps to zero. Anchor that new clock at
                // the active meeting duration so post-reconnect segments remain chronological.
                self.deepgramTimelineOffset = self.preciseCurrentRecordingDuration
                deepgramService.connect(
                    language: self.meetingLanguage,
                    personalDictionaryTerms: PersonalDictionaryPreferences.currentTerms(),
                    sessionKeyterms: self.deepgramSessionKeyterms(),
                    multichannel: useMultichannel,
                    monoSource: monoSource,
                    preserveSpeakerIdentities: true,
                    onDeviceSpeakerTimeline: self.onDeviceDiarization.activeTimeline
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
        guard autoStopMinutes > 0 || hasCalendarAutoStop || smartMeetingsEnabled else { return }
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMeetingSilencePolicies()
            }
        }
    }
    
    private func stopAutoStopMonitoring() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
    }

    private func restartMeetingAutomationMonitoring() {
        if isRecording {
            startAutoStopMonitoring()
        }
        if googleCalendarEnabled, isGoogleCalendarConnected {
            startAutoStartMonitoring()
        }
    }

    private func checkMeetingSilencePolicies() {
        #if os(macOS)
        // The deferred-stop grace owns the ending decision; silence policies stand down.
        guard endingGrace == nil else { return }
        #endif
        checkSmartQuietMeetingPrompt()
        checkAutoStop()
    }

    private func checkSmartQuietMeetingPrompt() {
        // The quiet fallback applies to calendar-linked and non-calendar meetings alike
        // (call-lifecycle plan, weak fallback signals). It only stands down while another
        // prompt or countdown — calendar transition, call end, call start — is on screen.
        guard smartMeetingsEnabled,
              isRecording,
              smartMeetingPrompt == nil,
              lastTranscriptReceivedAt > 0 else { return }

        let nowAbsolute = CFAbsoluteTimeGetCurrent()
        let now = Date()
        let transcriptGap = nowAbsolute - lastTranscriptReceivedAt
        // Speech-like audio: Deepgram's VAD while the pipeline is healthy (room noise is
        // not speech), the raw capture level otherwise. Hard stops keep the raw level.
        let audioGap = Self.smartMeetingSpeechGap(
            pipelineHealthy: audioRecoveryState == .healthy,
            speechGap: lastSpeechDetectedAt > 0 ? nowAbsolute - lastSpeechDetectedAt : nil,
            levelGap: audioActivityGap(at: nowAbsolute)
        )
        let jointQuietGap = min(transcriptGap, audioGap)
        let crossedBoundary = Self.quietPeriodCrossedCommonMeetingBoundary(
            quietStartedAt: now.addingTimeInterval(-jointQuietGap),
            now: now,
            recordingDuration: recordingDuration
        )
        let isSuppressed = smartMeetingSuppressedUntil.map { $0 > now } ?? false
        let hasMeaningfulTranscript = liveSegments.contains {
            $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Supporting signal, independent of the calendar auto-stop setting: past the
        // event's end the question comes sooner. It is an ask, never a stop.
        let calendarEventEnded = selectedCalendarEvent?.endDate.map { $0 < now } ?? false

        guard Self.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: hasMeaningfulTranscript,
            transcriptGap: transcriptGap,
            audioGap: audioGap,
            autoStopMinutes: autoStopMinutes,
            crossedCommonBoundary: crossedBoundary,
            calendarEventEnded: calendarEventEnded,
            alreadyPromptedThisQuietEpisode: smartQuietEpisodePrompted,
            isSuppressed: isSuppressed
        ) else { return }

        smartQuietEpisodePrompted = true
        let quietMinutes = max(1, Int(transcriptGap / 60))
        presentSmartMeetingPrompt(
            SmartMeetingPrompt(
                id: "quiet-\(currentMeeting?.id.uuidString ?? UUID().uuidString)",
                kind: .quiet,
                title: "Has this meeting ended?",
                message: "No speech for \(quietMinutes) minute\(quietMinutes == 1 ? "" : "s").",
                eventID: nil,
                countdown: nil
            )
        )
    }

    enum SmartMeetingActivitySource {
        /// Interim or final words arrived: someone is talking.
        case transcript
        /// The capture level crossed the speech threshold: could be talking, could be a fan.
        case audioLevel
    }

    /// While transcription is healthy, words are the evidence of speech and the raw level
    /// is not: a noise burst must not dismiss the "has this meeting ended?" question or
    /// forget a "Keep recording" answer. With the pipeline down, the level is all there is.
    nonisolated static func audioLevelActivityResetsQuietEpisode(pipelineHealthy: Bool) -> Bool {
        !pipelineHealthy
    }

    private func noteSmartMeetingActivity(source: SmartMeetingActivitySource) {
        if source == .audioLevel,
           !Self.audioLevelActivityResetsQuietEpisode(pipelineHealthy: audioRecoveryState == .healthy) {
            // Conservative exception: speech-like audio still cancels an automatic
            // calendar handoff countdown, which is a silent split.
            if let prompt = smartMeetingPrompt, prompt.kind == .calendar, prompt.countdown != nil {
                cancelSmartMeetingCountdown(keepPrompt: true)
            }
            return
        }
        smartMeetingSuppressedUntil = nil
        smartQuietEpisodePrompted = false
        guard let prompt = smartMeetingPrompt else { return }
        switch prompt.kind {
        case .quiet:
            clearSmartMeetingPrompt()
        case .calendar:
            if prompt.countdown != nil {
                cancelSmartMeetingCountdown(keepPrompt: true)
            }
        case .callEnd:
            // Speech resumed after the call ended: treat like the quiet ask. If quiet
            // returns, the fallback prompt machinery re-raises the question later.
            clearSmartMeetingPrompt()
        case .callStart, .callTransition:
            // Driven by another app's lifecycle, not by our audio activity.
            break
        }
    }

    private func presentSmartMeetingPrompt(_ prompt: SmartMeetingPrompt) {
        guard smartMeetingPrompt != prompt else { return }
        #if os(macOS)
        clearRecordingNudge()
        #endif
        clearSmartMeetingNotification()
        smartMeetingPrompt = prompt
        sendSmartMeetingNotificationIfNeeded(prompt)
    }

    func clearSmartMeetingPrompt() {
        smartMeetingCountdownTimer?.invalidate()
        smartMeetingCountdownTimer = nil
        smartMeetingPrompt = nil
        clearSmartMeetingNotification()
    }

    func keepRecordingFromSmartMeetingPrompt() {
        guard let prompt = smartMeetingPrompt else { return }
        if let eventID = prompt.eventID {
            dismissedAutoStartEventIDs.insert(eventID)
        } else {
            smartMeetingSuppressedUntil = Date().addingTimeInterval(5 * 60)
        }
        #if os(macOS)
        if prompt.kind == .callEnd || prompt.kind == .callTransition {
            // Keeping after a call-end ask also holds off the automatic call-end path,
            // and deliberately survives resumed speech.
            suppressAutoCallEndUntil = Date().addingTimeInterval(5 * 60)
        }
        #endif
        clearSmartMeetingPrompt()
    }

    func remindSmartMeetingPromptInTwoMinutes() {
        guard let eventID = smartMeetingPrompt?.eventID else { return }
        smartMeetingSnoozedUntilByEventID[eventID] = Date().addingTimeInterval(2 * 60)
        clearSmartMeetingPrompt()
    }

    func endMeetingFromSmartPrompt() {
        clearSmartMeetingPrompt()
        finishCurrentMeeting(then: .returnHome)
    }

    // MARK: - Call lifecycle detection (macOS)
    #if os(macOS)

    private func setupCallLifecycleMonitoring() {
        if callActivityMonitor == nil {
            let monitor = CallActivityMonitor()
            monitor.onSnapshot = { [weak self] snapshot in
                self?.handleCallActivitySnapshot(snapshot)
            }
            callActivityMonitor = monitor
        }
        installSleepWakeObserversIfNeeded()
        updateCallActivityMonitoringState()
    }

    private func updateCallActivityMonitoringState() {
        guard let monitor = callActivityMonitor else { return }
        if smartMeetingsEnabled {
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    private func installSleepWakeObserversIfNeeded() {
        guard !sleepWakeObserversInstalled else { return }
        sleepWakeObserversInstalled = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSystemWillSleep() }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSystemDidWake() }
        }
    }

    private func handleSystemWillSleep() {
        // Sleep ends the deliberation, but macOS may suspend async save/report work started
        // now — so record the decision and run the actual finalization on wake, when the
        // durable transaction can complete. The monitor pauses so a sleeping Mac takes no
        // HAL wakeups.
        if endingGrace != nil {
            endingGraceTimer?.invalidate()
            endingGraceTimer = nil
            finalizeGraceOnWake = true
            DebugLogger.shared.log(.app, "ending_grace_deferred_to_wake")
        }
        callActivityMonitor?.stop()
    }

    private func handleSystemDidWake() {
        updateCallActivityMonitoringState()
        recheckGoogleCalendarStatusIfNeeded(trigger: "wake")
        if finalizeGraceOnWake {
            finalizeGraceOnWake = false
            finalizeEndingGrace(trigger: "wake_after_sleep", markAutoStopped: true)
        }
    }

    private func handleCallActivitySnapshot(_ snapshot: CallActivitySnapshot) {
        let previous = latestCallSnapshot
        latestCallSnapshot = snapshot
        if previous == nil || !snapshot.hasSameCalls(as: previous!) {
            // Known-app display names only — bounded by the directory, never raw bundle IDs.
            let names = snapshot.activeCalls.map(\.displayName).joined(separator: ", ")
            DebugLogger.shared.log(.app, "call_activity_changed [\(names)]")
        }
        guard smartMeetingsEnabled else { return }

        let nowAbsolute = CFAbsoluteTimeGetCurrent()
        let transcriptGap = lastTranscriptReceivedAt > 0
            ? nowAbsolute - lastTranscriptReceivedAt
            : .infinity
        let context = CallLifecycleContext(
            isRecording: isRecording,
            smartMeetingsEnabled: smartMeetingsEnabled,
            hasMeaningfulContent: !liveSegments.isEmpty,
            recordingDuration: recordingDuration,
            transcriptGap: transcriptGap,
            audioGap: audioActivityGap(at: nowAbsolute),
            isInEndingGrace: endingGrace != nil
        )
        let events = callLifecycleEngine.ingest(snapshot: snapshot, context: context)
        for event in events {
            handleCallLifecycleEvent(event)
        }
    }

    private func handleCallLifecycleEvent(_ event: CallLifecycleEvent) {
        switch event {
        case .offerStartPrompt(let app):
            guard currentMeeting == nil, !isRecording, !requiresForceUpdate, hasAcceptedTerms,
                  pendingAutoStartEvent == nil else {
                // Not showable right now (stopped session open, terms gate, calendar start
                // pending…). Un-mark it so the same call is offered once the gate clears.
                callLifecycleEngine.noteStartPromptNotShown(bundleID: app.bundleID)
                return
            }
            startPromptApp = app
            DebugLogger.shared.log(.app, "supported_call_started (\(app.displayName))")
            presentSmartMeetingPrompt(
                SmartMeetingPrompt(
                    id: "call-start-\(app.bundleID)",
                    kind: .callStart,
                    title: "Meeting detected",
                    message: "Take notes with Miniti",
                    eventID: nil,
                    countdown: nil
                )
            )

        case .clearStartPrompt:
            if smartMeetingPrompt?.kind == .callStart {
                clearSmartMeetingPrompt()
            }
            startPromptApp = nil
            DebugLogger.shared.log(.app, "start_prompt_cleared")

        case .beginEndingGrace(let app, let askOnly):
            guard isRecording, endingGrace == nil, !isFinalizingMeeting else { return }
            if let until = suppressAutoCallEndUntil, until > Date() { return }
            DebugLogger.shared.log(.app, "associated_call_missing (\(app.displayName), askOnly=\(askOnly))")
            if askOnly {
                presentCallEndAskPrompt(app: app)
            } else {
                requestEndingGrace(app: app)
            }

        case .cancelEndCandidate:
            DebugLogger.shared.log(.app, "end_candidate_cancelled_reactivated")

        case .reactivateDuringGrace:
            cancelEndingGrace(reason: .reactivated)

        case .adoptExpectedCall(let app):
            // Join / calendar-link start, or a plain start followed by a call within the
            // inferred window: the call that appeared is this recording's own call.
            // Nothing to show; end detection now tracks it (inferred: ask-only).
            let inferred = callLifecycleEngine.associationSource == .adoptedInferred
            DebugLogger.shared.log(.app, inferred ? "inferred_call_adopted (\(app.displayName))" : "expected_call_adopted (\(app.displayName))")
            refreshEnvironmentContextEvidence()

        case .offerTransition(let app):
            guard isRecording, endingGrace == nil, smartMeetingPrompt == nil else { return }
            DebugLogger.shared.log(.app, "transition_candidate (\(app.displayName))")
            presentSmartMeetingPrompt(
                SmartMeetingPrompt(
                    id: "call-transition-\(app.bundleID)",
                    kind: .callTransition,
                    title: "New meeting detected",
                    message: "End the current meeting and start a new one?",
                    eventID: nil,
                    countdown: nil
                )
            )
        }
    }

    /// `Take notes` from the call-start prompt: applies an unambiguous nearby calendar
    /// event's context before transcription connects and associates the recording with
    /// the detected application.
    func startMeetingFromDetectedCall() {
        guard let app = startPromptApp else {
            clearSmartMeetingPrompt()
            return
        }
        clearSmartMeetingPrompt()
        startPromptApp = nil
        pendingCallAssociationApp = app
        let event = unambiguousCurrentCalendarEvent()
        DebugLogger.shared.log(.app, "start_prompt_accepted (\(app.displayName), calendar=\(event != nil))")
        if let event {
            _ = startNewMeeting(calendarEvent: event)
        } else {
            _ = startNewMeeting()
        }
    }

    /// `Not now` from the call-start prompt: suppress until this uninterrupted call ends.
    func dismissDetectedCallStartPrompt() {
        if let app = startPromptApp {
            callLifecycleEngine.noteStartPromptDismissed(bundleID: app.bundleID)
        }
        startPromptApp = nil
        DebugLogger.shared.log(.app, "start_prompt_dismissed")
        clearSmartMeetingPrompt()
    }

    /// Exactly one calendar event whose window (5 minutes early through its end) contains
    /// now; anything ambiguous returns nil and the meeting starts without calendar context.
    private func unambiguousCurrentCalendarEvent(now: Date = Date()) -> MinitiAPIService.CalendarEvent? {
        let candidates = todayEvents.filter { event in
            guard let start = event.startDate, let end = event.endDate else { return false }
            return start.addingTimeInterval(-5 * 60) <= now && now < end
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private func presentCallEndAskPrompt(app: ActiveCallApplication) {
        guard smartMeetingPrompt?.kind != .callEnd else { return }
        presentSmartMeetingPrompt(
            SmartMeetingPrompt(
                id: "call-end-\(app.bundleID)",
                kind: .callEnd,
                title: app.confidence == .browser
                    ? "Browser call ended"
                    : "\(app.displayName) call ended",
                message: "Has this meeting finished?",
                eventID: nil,
                countdown: nil
            )
        )
    }

    // MARK: - Ending grace (deferred stop)

    /// Visibility rule: the countdown must be visible somewhere, or the automatic end
    /// degrades to an ask-first prompt. `NSApp.isActive` is not proof — only Settings may
    /// be open — so the main-window check looks for the identified main window itself.
    /// Menu bar and floating indicator preferences are stored by their owning surfaces;
    /// absent keys mean their default-on state.
    private func graceCountdownHasVisibleSurface() -> Bool {
        let mainWindowVisible = NSApp.windows.contains {
            $0.identifier == AppDelegate.mainWindowIdentifier && $0.isVisible && !$0.isMiniaturized
        }
        if mainWindowVisible { return true }
        let defaults = UserDefaults.standard
        let menuBarVisible = defaults.object(forKey: "showInMenuBar") == nil
            ? true : defaults.bool(forKey: "showInMenuBar")
        let indicatorVisible = defaults.object(forKey: "showRecordingIndicator") == nil
            ? true : defaults.bool(forKey: "showRecordingIndicator")
        return menuBarVisible || indicatorVisible
    }

    private func requestEndingGrace(app: ActiveCallApplication) {
        if graceCountdownHasVisibleSurface() {
            startEndingGrace(app: app)
            return
        }
        // No countdown surface. A notification can carry the countdown, but only when the
        // app is inactive — foreground notifications are suppressed by default, so a
        // technically-active app with no visible countdown must ask instead of auto-ending.
        guard !isAppInForeground() else {
            DebugLogger.shared.log(.app, "ending_grace_degraded_to_ask (no visible surface)")
            presentCallEndAskPrompt(app: app)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in
                guard let self else { return }
                if authorized {
                    self.startEndingGrace(app: app)
                } else {
                    DebugLogger.shared.log(.app, "ending_grace_degraded_to_ask (no visible surface)")
                    self.presentCallEndAskPrompt(app: app)
                }
            }
        }
    }

    private func startEndingGrace(app: ActiveCallApplication) {
        guard isRecording, endingGrace == nil, !isFinalizingMeeting else { return }
        if let until = suppressAutoCallEndUntil, until > Date() { return }
        clearRecordingNudge()
        audioCaptureService?.suspendSending()
        endingGraceSuspendedAt = Date()
        let deadline = Date().addingTimeInterval(Self.endingGraceDuration)
        endingGrace = EndingGraceState(
            appBundleID: app.bundleID,
            appDisplayName: app.displayName,
            deadline: deadline,
            remainingSeconds: Int(Self.endingGraceDuration)
        )
        // Grace supersedes any pending quiet/transition prompt.
        clearSmartMeetingPrompt()
        endingGraceTimer?.invalidate()
        endingGraceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickEndingGrace()
            }
        }
        DebugLogger.shared.log(.app, "ending_grace_started (\(app.displayName))")
        sendEndingGraceNotificationIfNeeded(app: app)
    }

    private func tickEndingGrace() {
        guard var grace = endingGrace else { return }
        let remaining = grace.deadline.timeIntervalSinceNow
        if remaining <= 0 {
            finalizeEndingGrace(trigger: "timeout", markAutoStopped: true)
        } else {
            grace.remainingSeconds = Int(remaining.rounded(.up))
            endingGrace = grace
        }
    }

    /// `Keep recording` during grace: resume on the same socket and hold off automatic
    /// ending for a while so the countdown the person just cancelled does not re-arm.
    func keepRecordingFromEndingGrace() {
        cancelEndingGrace(reason: .kept)
    }

    /// `End now` during grace: run the normal finish immediately, without the auto-stop banner.
    func endEndingGraceNow() {
        finalizeEndingGrace(trigger: "end_now", markAutoStopped: false)
    }

    enum EndingGraceCancelReason {
        case kept
        case reactivated
        case smartMeetingsDisabled
    }

    func cancelEndingGrace(reason: EndingGraceCancelReason) {
        guard endingGrace != nil else { return }
        endingGraceTimer?.invalidate()
        endingGraceTimer = nil
        endingGrace = nil
        finalizeGraceOnWake = false
        clearEndingGraceNotification()
        // Deepgram's clock is driven by received samples and paused with them; keep the
        // socket-to-meeting timeline offset honest about the wall-clock gap.
        if let suspendedAt = endingGraceSuspendedAt {
            deepgramTimelineOffset += Date().timeIntervalSince(suspendedAt)
        }
        endingGraceSuspendedAt = nil
        audioCaptureService?.resumeSending()
        switch reason {
        case .kept:
            suppressAutoCallEndUntil = Date().addingTimeInterval(5 * 60)
            DebugLogger.shared.log(.app, "ending_grace_kept")
        case .reactivated:
            DebugLogger.shared.log(.app, "end_candidate_cancelled_reactivated")
        case .smartMeetingsDisabled:
            DebugLogger.shared.log(.app, "ending_grace_cancelled_smart_meetings_off")
        }
    }

    private func finalizeEndingGrace(trigger: String, markAutoStopped: Bool) {
        guard endingGrace != nil else { return }
        endingGraceTimer?.invalidate()
        endingGraceTimer = nil
        endingGrace = nil
        endingGraceSuspendedAt = nil
        finalizeGraceOnWake = false
        clearEndingGraceNotification()
        callLifecycleEngine.noteRecordingEnded()
        if markAutoStopped {
            wasAutoStopped = true
            autoStopReason = .callEnded
        }
        DebugLogger.shared.log(.app, "ending_grace_completed (trigger=\(trigger))")
        // stopCapture inside stopRecording resets the send suspension; the existing durable
        // finish/save/finalization transaction runs exactly once from here.
        stopRecording()
    }

    private static let endingGraceNotificationIdentifier = "miniti.smart-meeting.call-grace"

    private func sendEndingGraceNotificationIfNeeded(app: ActiveCallApplication) {
        guard MacNotificationRoutingPolicy.shouldMirrorToSystem(
            isAppActive: isAppInForeground(),
            recordingIndicatorEnabled: showRecordingIndicator
        ) else { return }
        let title = app.confidence == .browser
            ? "Browser call ended"
            : "\(app.displayName) call ended"
        let body = "Finishing in \(Int(Self.endingGraceDuration))s — Keep recording to continue."
        // Hoisted out of the @Sendable closure: these are main-actor-isolated statics.
        let category = Self.smartMeetingNotificationCategory + ".call-grace"
        let identifier = Self.endingGraceNotificationIdentifier
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = category
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: nil
                )
            ) { error in
                if let error {
                    DebugLogger.shared.log(.app, "Ending grace notification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func clearEndingGraceNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.endingGraceNotificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.endingGraceNotificationIdentifier])
    }

    #endif


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

    /// Smart meetings prompts before the existing silence auto-stop point, while keeping enough
    /// quiet time to avoid interrupting ordinary pauses in conversation.
    nonisolated static func smartMeetingQuietThreshold(autoStopMinutes: Int) -> TimeInterval {
        switch autoStopMinutes {
        case 3: return 2 * 60
        case 5: return 3 * 60
        case 10, 15: return 5 * 60
        default: return 5 * 60
        }
    }

    /// A common half-hour boundary can bring the prompt forward, but only for an established
    /// meeting and a quiet period that began before the boundary.
    nonisolated static func quietPeriodCrossedCommonMeetingBoundary(
        quietStartedAt: Date,
        now: Date,
        recordingDuration: TimeInterval,
        calendar: Calendar = .current
    ) -> Bool {
        guard recordingDuration >= 15 * 60,
              now.timeIntervalSince(quietStartedAt) >= 2 * 60 else { return false }

        var boundary = calendar.dateInterval(of: .hour, for: quietStartedAt)?.start ?? quietStartedAt
        if boundary <= quietStartedAt {
            boundary = calendar.date(byAdding: .minute, value: 30, to: boundary) ?? boundary
        }
        while boundary <= now {
            let minute = calendar.component(.minute, from: boundary)
            if (minute == 0 || minute == 30), boundary > quietStartedAt {
                return true
            }
            boundary = calendar.date(byAdding: .minute, value: 30, to: boundary) ?? now.addingTimeInterval(1)
        }
        return false
    }

    /// Which "speech-like audio" gap the quiet prompt should trust. Deepgram's VAD is
    /// speech-specific; the capture level counts fans, keyboards and traffic as activity
    /// and kept the prompt from ever maturing in a normal room. The VAD only exists while
    /// the socket is alive and delivering, so a degraded pipeline falls back to the level.
    nonisolated static func smartMeetingSpeechGap(
        pipelineHealthy: Bool,
        speechGap: TimeInterval?,
        levelGap: TimeInterval
    ) -> TimeInterval {
        guard pipelineHealthy, let speechGap else { return levelGap }
        return speechGap
    }

    /// Quiet threshold once the meeting's calendar event has ended: the same two minutes
    /// the calendar-aware auto-stop uses, applied to the ask.
    nonisolated static let smartMeetingCalendarEndedQuietThreshold: TimeInterval = 2 * 60

    nonisolated static func shouldOfferSmartQuietPrompt(
        hasMeaningfulTranscript: Bool,
        transcriptGap: TimeInterval,
        audioGap: TimeInterval,
        autoStopMinutes: Int,
        crossedCommonBoundary: Bool,
        calendarEventEnded: Bool = false,
        alreadyPromptedThisQuietEpisode: Bool,
        isSuppressed: Bool
    ) -> Bool {
        guard hasMeaningfulTranscript,
              !alreadyPromptedThisQuietEpisode,
              !isSuppressed else { return false }
        var threshold = crossedCommonBoundary
            ? 2 * 60
            : smartMeetingQuietThreshold(autoStopMinutes: autoStopMinutes)
        if calendarEventEnded {
            threshold = min(threshold, smartMeetingCalendarEndedQuietThreshold)
        }
        return transcriptGap >= threshold && audioGap >= threshold
    }

    nonisolated static func canAutomaticallyHandoffCalendarMeeting(
        currentEventEnd: Date?,
        nextEventStart: Date?,
        now: Date,
        transcriptGap: TimeInterval,
        audioGap: TimeInterval,
        autoStartEnabled: Bool,
        calendarAutoStopEnabled: Bool,
        eventsOverlap: Bool
    ) -> Bool {
        guard autoStartEnabled,
              calendarAutoStopEnabled,
              !eventsOverlap,
              let currentEventEnd,
              let nextEventStart,
              currentEventEnd <= now,
              nextEventStart >= currentEventEnd,
              nextEventStart.timeIntervalSince(currentEventEnd) <= 15 * 60,
              transcriptGap >= 2 * 60,
              audioGap >= 2 * 60 else { return false }
        return true
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
        if let smartMeetingSuppressedUntil, smartMeetingSuppressedUntil > Date() {
            return
        }

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
        #if os(macOS)
        // Sending is deliberately suspended during ending grace; a transcript gap is expected
        // and must not trigger a starvation reconnect.
        guard endingGrace == nil else { return }
        #endif
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
        if ScreenshotMode.isActive {
            audioRecoveryState = .healthy
            return
        }
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
            enqueueOrderedFinalSegments(systemSegments)
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
            enqueueOrderedFinalSegments(immediateMic)
        }
        if !unclassified.isEmpty {
            // Defensive fallback for malformed multichannel results. Never drop
            // transcript content merely because Deepgram omitted channel_index.
            enqueueOrderedFinalSegments(unclassified)
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
        enqueueOrderedFinalSegments(covered.map(\.segment))
    }

    /// Keep the common dual-channel case append-only by allowing nearby mic/system final callbacks
    /// to rendezvous briefly on Deepgram's precise stream clock. Interim text remains immediate.
    private func enqueueOrderedFinalSegments(
        _ segments: [DeepgramService.SpeakerSegment],
        now: Date = Date()
    ) {
        guard !segments.isEmpty else { return }
        for segment in segments {
            nextOrderedFinalArrivalSequence &+= 1
            pendingOrderedFinalSegments.append(
                PendingOrderedFinalSegment(
                    segment: segment,
                    timelineOffset: deepgramTimelineOffset,
                    arrivalSequence: nextOrderedFinalArrivalSequence,
                    deadline: now.addingTimeInterval(dualChannelOrderingDelay)
                )
            )
        }
        scheduleOrderedFinalFlush()
    }

    private func scheduleOrderedFinalFlush() {
        pendingOrderedFinalFlushTask?.cancel()
        pendingOrderedFinalFlushTask = nil
        guard let deadline = pendingOrderedFinalSegments.map(\.deadline).min() else { return }

        let delay = max(0, deadline.timeIntervalSinceNow)
        pendingOrderedFinalFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.flushDueOrderedFinalSegments()
        }
    }

    private func flushDueOrderedFinalSegments(now: Date = Date()) {
        let due = pendingOrderedFinalSegments.filter { $0.deadline <= now }
        pendingOrderedFinalSegments.removeAll { $0.deadline <= now }
        commitOrderedFinalSegments(due)
        scheduleOrderedFinalFlush()
    }

    private func flushAllPendingOrderedFinalSegments() {
        pendingOrderedFinalFlushTask?.cancel()
        pendingOrderedFinalFlushTask = nil
        let remaining = pendingOrderedFinalSegments
        pendingOrderedFinalSegments.removeAll()
        commitOrderedFinalSegments(remaining)
    }

    private func commitOrderedFinalSegments(_ pending: [PendingOrderedFinalSegment]) {
        guard !pending.isEmpty else { return }
        let ordered = pending.sorted { lhs, rhs in
            let lhsTime = Self.transcriptTimelineTimestamp(
                streamStart: lhs.segment.startTime,
                timelineOffset: lhs.timelineOffset
            )
            let rhsTime = Self.transcriptTimelineTimestamp(
                streamStart: rhs.segment.startTime,
                timelineOffset: rhs.timelineOffset
            )
            if lhsTime != rhsTime { return lhsTime < rhsTime }
            return lhs.arrivalSequence < rhs.arrivalSequence
        }

        // A reconnect flushes the old socket before installing the new offset, so all entries in
        // a normal batch share one timeline offset. Keep a defensive grouping path to avoid ever
        // applying a new socket's offset to an older segment.
        var batch: [DeepgramService.SpeakerSegment] = []
        var batchOffset: TimeInterval?
        for item in ordered {
            if let batchOffset, batchOffset != item.timelineOffset {
                commitFinalSpeakerSegments(batch, timelineOffset: batchOffset)
                batch.removeAll(keepingCapacity: true)
            }
            batchOffset = item.timelineOffset
            batch.append(item.segment)
        }
        if let batchOffset, !batch.isEmpty {
            commitFinalSpeakerSegments(batch, timelineOffset: batchOffset)
        }
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
            enqueueOrderedFinalSegments(due, now: now)
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
            enqueueOrderedFinalSegments(remaining)
        }
    }

    private func resetEchoReconciliation(flushPending: Bool = false) {
        if flushPending {
            flushAllPendingMicSegments()
            flushAllPendingOrderedFinalSegments()
        } else {
            pendingMicFlushTask?.cancel()
            pendingMicFlushTask = nil
            pendingMicSegments.removeAll()
            pendingOrderedFinalFlushTask?.cancel()
            pendingOrderedFinalFlushTask = nil
            pendingOrderedFinalSegments.removeAll()
            nextOrderedFinalArrivalSequence = 0
            deepgramTimelineOffset = 0
        }
        recentSystemSegments.removeAll()
    }
    #endif

    private func commitFinalSpeakerSegments(
        _ finalSegments: [DeepgramService.SpeakerSegment],
        timelineOffset: TimeInterval? = nil
    ) {
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
            let rawText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { continue }
            let text = transcriptCorrector?.apply(to: rawText) ?? rawText
            receivedTranscriptContent = true

            // Track this speaker
            detectedSpeakers.insert(segment.speaker)

            // Create live segment
            let proposedTimestamp = timelineOffset.map {
                Self.transcriptTimelineTimestamp(
                    streamStart: segment.startTime,
                    timelineOffset: $0
                )
            } ?? recordingDuration
            let timestamp = Self.collisionFreeTranscriptTimestamp(
                proposed: proposedTimestamp,
                in: updated
            )
            let liveSegment = LiveSegment(
                id: segment.id,
                text: text,
                speaker: segment.speaker,
                timestamp: timestamp,
                isFinal: true,
                source: segment.source
            )

            let mergeResult = Self.mergeFinalSegment(liveSegment, into: &updated)
            // Duplicate/cumulative re-emissions must not accumulate evidence twice:
            // mic-speaker confirmation, environment durations, and sales-vocabulary
            // hits only count for genuinely new transcript content.
            if mergeResult == .appended {
                if segment.source == .microphone {
                    liveMicSpeakerIDs.insert(segment.speaker)
                }
                recordEnvironmentEvidence(for: segment)
                evaluateSalesDetection(for: text)
            }
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
            noteSmartMeetingActivity(source: .transcript)
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
        let templateWarmup = templateInsightsEnabled && templateSuccessCount < 2 && finalCount >= 6
        let now = Date()
        let warmupRetryReady = lastWarmupInsightsAttemptAt.map {
            now.timeIntervalSince($0) >= warmupInsightsRetryInterval
        } ?? true
        let shouldTrigger = (standardWarmup || meddpiccWarmup || questionsWarmup || templateWarmup)
            && finalCount > lastInsightSegmentCount
            && warmupRetryReady
        if shouldTrigger {
            lastInsightSegmentCount = finalCount
            lastWarmupInsightsAttemptAt = now
            Task { await updateLiveInsights() }
        }

        evaluateRealtimeNudges()
        evaluateInvestigationSuggestion()
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
                        if let meetingID = currentMeeting?.id, !transcript.isEmpty {
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
                        if let meetingID = currentMeeting?.id, !transcript.isEmpty {
                            await updateQuestionsInBackground(
                                transcript: transcript,
                                finalSegments: finalSegments,
                                segmentCount: finalCount,
                                meetingID: meetingID
                            )
                        }
                    }
                }
                if templateInsightsEnabled, templateSuccessCount >= 2 {
                    let anchor = templateCadenceAnchor
                        ?? standardCadenceAnchor?.addingTimeInterval(templateCadenceStagger)
                        ?? recordingStartDate
                    if Self.shouldFireLiveInsightCadence(
                        now: now,
                        lastSuccessAt: anchor,
                        lastAttemptAt: templateLastAttemptAt,
                        lastSuccessfulSegmentCount: templateLastFiredSegmentCount,
                        currentSegmentCount: finalCount,
                        policy: templateCadencePolicy
                    ) {
                        templateLastAttemptAt = now
                        let finalSegments = finalizedSegments()
                        let transcript = transcriptText(from: finalSegments)
                        if let meetingID = currentMeeting?.id, !transcript.isEmpty {
                            await updateTemplateInBackground(
                                transcript: transcript,
                                finalSegments: finalSegments,
                                segmentCount: finalCount,
                                meetingID: meetingID
                            )
                        }
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
        templateCadenceAnchor = Date()
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

        let shouldRunTemplate: Bool = {
            guard templateInsightsEnabled else { return false }
            guard !isGeneratingTemplateInsights else { return false }
            let meetsSegmentThreshold = segmentCount >= lastTemplateSegmentCount + (
                lastTemplateSegmentCount == 0 ? firstTemplateInsightThreshold : templateInsightUpdateThreshold
            )
            let meetsTimeThreshold = lastTemplateRequestAt.map {
                Date().timeIntervalSince($0) >= templateMinUpdateInterval
            } ?? true
            return meetsSegmentThreshold && meetsTimeThreshold
        }()

        if shouldRunTemplate {
            Task {
                await self.updateTemplateInBackground(
                    transcript: transcript,
                    finalSegments: finalSegments,
                    segmentCount: segmentCount,
                    meetingID: meetingIDAtRequest
                )
            }
        }

    }

    /// Template sections run as their own background request, like Sales: they never block
    /// standard insights, and a template chosen mid-meeting can fill straight away.
    private func updateTemplateInBackground(
        transcript: String,
        finalSegments: [LiveSegment],
        segmentCount: Int,
        meetingID: UUID
    ) async {
        guard templateInsightsEnabled else { return }
        guard !isGeneratingTemplateInsights else { return }
        guard currentMeeting?.id == meetingID else { return }
        templateLastAttemptAt = Date()
        isGeneratingTemplateInsights = true
        defer { isGeneratingTemplateInsights = false }

        let template = liveTemplate
        if liveTemplateID == nil { liveTemplateID = template.id }

        if let templateResult = await fetchLiveInsights(
            mode: .template,
            transcript: transcript,
            finalSegments: finalSegments,
            existingSummary: nil,
            existingTitle: currentTitleSuffix.isEmpty ? nil : currentTitleSuffix
        ) {
            guard currentMeeting?.id == meetingID, liveTemplateID == template.id else {
                DebugLogger.shared.log(.app, "Dropping stale template insights response (meeting or template changed)")
                return
            }
            let isDegraded = templateResult.meta?.degraded ?? false
            if !isDegraded {
                if let seq = templateResult.meta?.requestSeq {
                    lastAppliedTemplateSeq = seq
                }
                templateCadenceAnchor = Date()
                templateLastFiredSegmentCount = segmentCount
                lastTemplateRequestAt = Date()
                applyInsights(templateResult.insights, segmentCount: segmentCount, mode: .template)
                lastTemplateSegmentCount = segmentCount
                templateSuccessCount += 1
                DebugLogger.shared.log(.app, "Live template applied: template=\(template.id), sections=\(liveTemplateSections.count), segmentCount=\(segmentCount)")
            } else {
                DebugLogger.shared.log(.app, "Template insights degraded — not advancing cursor")
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
        commit(.docsTopics)

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
        commit(.docsLookup)

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

    /// When the calendar has exactly one non-self named attendee and the
    /// transcript has exactly one confirmed system-channel speaker with enough
    /// speech, name that speaker after the attendee without an API request.
    /// Returns true when a name was applied.
    @discardableResult
    private func applyOneToOneCalendarSpeakerName(finalSegments: [LiveSegment]) -> Bool {
        let candidates = speakerNameCandidates()
        guard candidates.count == 1, let attendeeName = candidates.first else { return false }

        var systemSpeakerCounts: [Int: Int] = [:]
        for segment in finalSegments where segment.isFinal {
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let source = segment.source
            let isSystem: Bool
            if let source {
                isSystem = source == .system
            } else {
                // Legacy rows without source are not treated as system.
                isSystem = false
            }
            guard isSystem, !DeepgramService.isMicAppSpeakerID(segment.speaker) else { continue }
            systemSpeakerCounts[segment.speaker, default: 0] += 1
        }
        guard systemSpeakerCounts.count == 1,
              let (speakerID, count) = systemSpeakerCounts.first,
              count >= 5 else {
            return false
        }

        let key = String(speakerID)
        guard !liveSpeakerOverrides.contains(key) else { return false }
        if liveSpeakerNames[key] == attendeeName { return false }

        var merged = liveSpeakerNames
        merged[key] = attendeeName
        liveSpeakerNames = merged
        if let meeting = currentMeeting {
            meeting.speakerNames = merged
            saveCurrentMeetingIfNeeded()
        }
        DebugLogger.shared.log(
            .app,
            "Speaker-names 1:1 shortcut: id=\(speakerID) -> \(attendeeName)"
        )
        return true
    }

    /// True when some non-self speaker with at least three words of speech has no
    /// inferred or user-given name yet. Shared by the cadence, 1:1 shortcut, and
    /// end-of-meeting paths so they agree on "nothing left to name".
    private func hasUnnamedNonSelfSpeaker(in finalSegments: [LiveSegment]) -> Bool {
        let selfIDs = effectiveLiveSelfSpeakerIDs
        var meaningfulSpeakers: Set<Int> = []
        for segment in finalSegments where !selfIDs.contains(segment.speaker) {
            if segment.text.split(separator: " ").count >= 3 {
                meaningfulSpeakers.insert(segment.speaker)
            }
        }
        return meaningfulSpeakers.contains { id in
            (liveSpeakerNames[String(id)] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        // Local free 1:1 shortcut: one non-self calendar attendee + one system
        // speaker with enough speech. Never applies to mic IDs. User overrides win.
        if applyOneToOneCalendarSpeakerName(finalSegments: finalSegments) {
            lastSpeakerNamesRequestAt = Date()
            lastSpeakerNamesSegmentCount = segmentCount
            if !hasUnnamedNonSelfSpeaker(in: finalSegments) {
                DebugLogger.shared.log(.app, "Speaker-names: 1:1 calendar shortcut named every speaker, skipping request")
                return
            }
        }

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

            let supported = Self.transcriptSupportedSpeakerNames(
                inferred,
                finalSegments: finalSegments,
                calendarAttendeeNames: candidates
            )
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

    /// Mark every confirmed mic speaker as self in one action. Display grouping
    /// already collapses self IDs, so no segment rewrite is needed.
    func markAllLiveMicSpeakersAsSelf() {
        let micIDs = liveMicSpeakerIDs
        guard micIDs.count > 1 else { return }
        for id in micIDs.sorted() {
            setLiveSelfSpeaker(id: id, isSelf: true)
        }
    }

    /// Whether the implicit "the primary mic speaker is You" default applies.
    /// Dual-source only. Withdrawn when several mic speakers exist unless the
    /// meeting is remote-likely (diarizer clones on a solo headset call).
    private var liveImplicitSelfAllowed: Bool {
        #if os(macOS)
        let dualSource = captureMicrophone && captureSystemAudio
        #else
        let dualSource = false
        #endif
        return ImplicitSelfPolicy.allowed(
            micSpeakerCount: liveMicSpeakerIDs.count,
            hasDualSourceOrLegacy: dualSource,
            environment: inferredMeetingEnvironment
        )
    }

    /// The effective self-speaker set during the live session, for membership checks —
    /// explicit markings win; otherwise the primary mic speaker (1000) is implicitly
    /// "You" only in a dual-source session with at most one detected microphone
    /// speaker. Once several people share the microphone, or in mic-only capture,
    /// no one is assumed to be the user (rename / `mark as you` correct it).
    var effectiveLiveSelfSpeakerIDs: Set<Int> {
        if !liveSelfSpeakerIDs.isEmpty { return liveSelfSpeakerIDs }
        return liveImplicitSelfAllowed ? [DeepgramService.micSpeakerID] : []
    }

    /// Live-session self context for label/metrics resolution. Nil = no marks and the
    /// implicit mic default applies (resolver applies it *after* inferred names);
    /// empty = no implicit "You" at all.
    var liveSpeakerLabelSelfIDs: Set<Int>? {
        if !liveSelfSpeakerIDs.isEmpty { return liveSelfSpeakerIDs }
        return liveImplicitSelfAllowed ? nil : []
    }

    // MARK: - Automatic environment inference (internal, diagnostic only)

    /// Update the evidence snapshot from one meaningful finalized segment, then
    /// re-evaluate the inferred environment. Reads call-lifecycle and calendar
    /// context lazily so this stays decoupled from monitor callbacks. Must never
    /// perform any action beyond logging, diagnostics, and optional metadata.
    private func recordEnvironmentEvidence(for segment: DeepgramService.SpeakerSegment) {
        let wordCount = segment.text.split(separator: " ").count
        guard wordCount >= MeetingEnvironmentInferenceEngine.meaningfulFinalMinimumWordCount else { return }

        refreshEnvironmentContextEvidence()

        switch segment.source {
        case .microphone:
            environmentEvidence.hasMeaningfulMicFinal = true
            let seconds = max(0, segment.endTime - segment.startTime)
            environmentEvidence.meaningfulMicSpeechSeconds += seconds
            if segment.speaker != DeepgramService.micSpeakerID {
                environmentEvidence.additionalMicSpeakerSpeechSeconds += seconds
            }
            environmentEvidence.confirmedMicSpeakerCount = liveMicSpeakerIDs.count
        case .system:
            environmentEvidence.hasMeaningfulSystemFinal = true
            if environmentEvidence.hasAssociatedCallApp
                || environmentEvidence.recognizedCallAppActive
                || environmentEvidence.calendarEventHasConferenceURL == true {
                environmentEvidence.systemFinalWithCallContext = true
            }
        case .unknown:
            break
        }
        evaluateEnvironmentInference()
    }

    /// Call-app and calendar context are known before any transcript arrives.
    /// Refreshing them at meeting start lets a calendar-linked call with an
    /// active call app be classified remote-likely (and the mic promotion policy
    /// set to strict) before the first response, instead of after the first
    /// system final.
    private func refreshEnvironmentContextEvidence() {
        #if os(macOS)
        // Monitor unreliability is "no information", never in-room evidence.
        let snapshot = latestCallSnapshot
        let monitorReliable = snapshot?.isReliable ?? false
        environmentEvidence.hasAssociatedCallApp = callLifecycleEngine.associatedAppForEnvironmentEvidence != nil
        environmentEvidence.recognizedCallAppActive =
            monitorReliable && !(snapshot?.activeCalls.isEmpty ?? true)
        #endif
        if let event = selectedCalendarEvent {
            environmentEvidence.calendarEventHasConferenceURL = event.joinURL != nil
        }
    }

    /// Reconstruct the minimal evidence consistent with a persisted conclusion so a
    /// resumed meeting keeps its environment (and promotion policy, and implicit
    /// "You") instead of dropping to `unknown` until the next final.
    private func restoreEnvironmentInference(from meeting: Meeting) {
        resetEnvironmentInference()
        guard let raw = meeting.inferredEnvironmentRaw,
              let restored = InferredMeetingEnvironment(rawValue: raw),
              restored != .unknown else { return }
        refreshEnvironmentContextEvidence()
        environmentEvidence.confirmedMicSpeakerCount = liveMicSpeakerIDs.count
        switch restored {
        case .remoteLikely:
            environmentEvidence.systemFinalWithCallContext = true
        case .inRoomLikely:
            environmentEvidence.hasMeaningfulMicFinal = true
            environmentEvidence.meaningfulMicSpeechSeconds =
                MeetingEnvironmentInferenceEngine.inRoomObservationWindowSeconds
        case .hybridLikely:
            environmentEvidence.systemFinalWithCallContext = true
            environmentEvidence.hasMeaningfulMicFinal = true
            environmentEvidence.meaningfulMicSpeechSeconds =
                MeetingEnvironmentInferenceEngine.inRoomObservationWindowSeconds
            environmentEvidence.additionalMicSpeakerSpeechSeconds =
                MeetingEnvironmentInferenceEngine.hybridSecondaryMicSpeechSeconds
        case .unknown:
            break
        }
        evaluateEnvironmentInference()
    }

    private func evaluateEnvironmentInference() {
        let next = MeetingEnvironmentInferenceEngine.infer(environmentEvidence)
        guard next != inferredMeetingEnvironment else { return }
        let previous = inferredMeetingEnvironment
        inferredMeetingEnvironment = next
        DebugLogger.shared.log(
            .app,
            "Environment inference: \(previous.rawValue) -> \(next.rawValue) (micSpeakers=\(environmentEvidence.confirmedMicSpeakerCount), systemFinal=\(environmentEvidence.hasMeaningfulSystemFinal), callApp=\(environmentEvidence.hasAssociatedCallApp), micSpeech=\(Int(environmentEvidence.meaningfulMicSpeechSeconds))s)"
        )
        // Privacy-safe counter: state names only — no transcript, titles,
        // attendee names, URLs, or bundle IDs.
        enqueueDiagnosticEvent(
            "environment_inference_transition",
            category: .app,
            details: ["from": previous.rawValue, "to": next.rawValue]
        )
        // Optional metadata for recovery/diagnostics. Old meetings stay nil and
        // decode as unknown; no migration required.
        currentMeeting?.inferredEnvironmentRaw = next == .unknown ? nil : next.rawValue

        // B2: tighten additional-mic promotion only while remote-likely so a
        // solo headset call does not mint clones. Shared-mic rooms stay standard.
        let nextPolicy: DeepgramService.MicSpeakerPromotionPolicy =
            next == .remoteLikely ? .strict : .standard
        if deepgramService?.micSpeakerPromotionPolicy != nextPolicy {
            deepgramService?.micSpeakerPromotionPolicy = nextPolicy
            DebugLogger.shared.log(
                .deepgram,
                "Mic speaker promotion policy: \(nextPolicy.rawValue) (environment=\(next.rawValue))"
            )
        }
    }

    private func resetEnvironmentInference() {
        environmentEvidence = MeetingEnvironmentEvidence()
        inferredMeetingEnvironment = .unknown
        deepgramService?.micSpeakerPromotionPolicy = .standard
    }

    /// App speaker IDs allocated to earlier sockets stay valid after a reconnect —
    /// the identity allocator hands the new socket fresh, collision-free IDs (with
    /// single-mic continuity for the primary `1000` identity), so names, overrides,
    /// and self marks attached to existing segments must be preserved. Only the
    /// naming-request pacing resets so inference re-runs for the new identities.
    /// Capture sources this platform diarizes on device.
    private var onDeviceDiarizationSources: Set<TranscriptSource> {
        #if os(macOS)
        return [.microphone, .system]
        #else
        return [.microphone]
        #endif
    }

    /// Load or drop the on-device diarization models to match the setting. Called at
    /// launch and whenever the setting changes. Never touches an active session.
    func refreshOnDeviceDiarizationAvailability() {
        guard !ScreenshotMode.isActive else { return }
        if onDeviceSpeakerSeparationEnabled {
            onDeviceDiarization.prepare(sources: onDeviceDiarizationSources)
        } else {
            onDeviceDiarization.unload()
        }
    }

    /// Start an on-device diarization session for the sources this recording captures, or
    /// nil (Deepgram diarizes) when the setting is off or the models are not ready.
    private func beginOnDeviceDiarizationSession(multichannel: Bool, monoSource: TranscriptSource) -> OnDeviceSpeakerTimeline? {
        guard onDeviceSpeakerSeparationEnabled else { return nil }
        let sources: Set<TranscriptSource> = multichannel ? [.microphone, .system] : [monoSource]
        return onDeviceDiarization.beginSession(sources: sources)
    }

    /// Audio callback that feeds the on-device diarizer (when a session is active) and then
    /// Deepgram. Order matters: the diarizer clock advances before the socket sees the packet.
    private func makeAudioBufferHandler(multichannel: Bool, monoSource: TranscriptSource) -> @Sendable (Data) -> Void {
        let diarization = onDeviceDiarization
        return { [weak deepgramService] data in
            diarization.ingest(data, multichannel: multichannel, monoSource: monoSource)
            deepgramService?.sendAudio(data)
        }
    }

    func resetSpeakerIdentityForDeepgramReconnect() {
        lastSpeakerNamesSegmentCount = 0
        lastSpeakerNamesRequestAt = nil
        DebugLogger.shared.log(
            .app,
            "Deepgram reconnect: speaker identities preserved (names=\(liveSpeakerNames.count), overrides=\(liveSpeakerOverrides.count), self=\(liveSelfSpeakerIDs.count)); naming pacing reset"
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
        // Template requests carry their definition and, after the first fill, the current
        // sections as a stability baseline (the backend's lightweight incremental mode).
        let requestTemplate: InsightTemplate? = mode == .template ? liveTemplate : nil
        let requestPreviousTemplateSections: [String: String]? =
            mode == .template && templateSuccessCount > 0 && !liveTemplateSections.isEmpty ? liveTemplateSections : nil
        
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
                case .template:
                    templateRequestSeq += 1
                    seq = templateRequestSeq
                    lastApplied = lastAppliedTemplateSeq
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
                        attendees: attendeesPayload,
                        template: requestTemplate,
                        previousTemplateSections: requestPreviousTemplateSections
                    )
                }
                if let responseSeq = response.meta?.requestSeq, responseSeq < lastApplied {
                    DebugLogger.shared.log(.app, "Dropping stale insights response: mode=\(mode.rawValue), responseSeq=\(responseSeq) < lastApplied=\(lastApplied)")
                    return nil
                }
                insights = response.toLiveInsights(template: requestTemplate)
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
                    incrementalPayload: requestPlan.incrementalPayload,
                    template: requestTemplate,
                    previousTemplateSections: requestPreviousTemplateSections
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
            case .training, .docs, .template: return 0
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
            case .training, .docs, .template: return 0
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
            case .training, .docs, .template:
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
        case .training, .docs, .template:
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
            timestamp: segment.timestamp,
            sourceRaw: segment.source?.rawValue
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
        finalSegments: [LiveSegment],
        calendarAttendeeNames: [String] = []
    ) -> [String: String] {
        let sanitized = SpeakerNamesResponse.sanitize(inferred)
        guard !sanitized.isEmpty else { return [:] }
        let calendarNameKeys = Set(
            calendarAttendeeNames
                .map { speakerNameTokens($0).joined(separator: " ") }
                .filter { !$0.isEmpty }
        )

        var supported: [String: String] = [:]
        for (key, name) in sanitized {
            guard let speaker = Int(key) else { continue }
            let nameKey = speakerNameTokens(name).joined(separator: " ")
            let isCalendarAttendee = !nameKey.isEmpty && calendarNameKeys.contains(nameKey)
            guard speakerNameHasTranscriptEvidence(
                name: name,
                speaker: speaker,
                segments: finalSegments,
                adjacentWindow: isCalendarAttendee ? 3 : 1
            ) else {
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
        segments: [LiveSegment],
        adjacentWindow: Int = 1
    ) -> Bool {
        let nameTokens = speakerNameTokens(name)
        guard let firstName = nameTokens.first else { return false }

        for segment in segments where segment.speaker == speaker {
            if textHasSelfIdentification(segment.text, firstName: firstName) {
                return true
            }
        }

        let window = max(1, adjacentWindow)
        for index in segments.indices where segments[index].speaker != speaker {
            guard textContainsNameToken(segments[index].text, firstName) else { continue }
            let start = segments.index(index, offsetBy: -window, limitedBy: segments.startIndex) ?? segments.startIndex
            let endExclusive = segments.index(index, offsetBy: window + 1, limitedBy: segments.endIndex) ?? segments.endIndex
            var neighbor = start
            while neighbor < endExclusive {
                if neighbor != index, segments[neighbor].speaker == speaker {
                    return true
                }
                neighbor = segments.index(after: neighbor)
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
        case .training, .docs, .template:
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
        templateSuccessCount = 0
        docsSuccessCount = 0
        templateRequestSeq = 0
        lastAppliedTemplateSeq = -1
        standardCadenceAnchor = nil
        meddpiccCadenceAnchor = nil
        questionsCadenceAnchor = nil
        templateCadenceAnchor = nil
        standardLastAttemptAt = nil
        meddpiccLastAttemptAt = nil
        questionsLastAttemptAt = nil
        templateLastAttemptAt = nil
        lastWarmupInsightsAttemptAt = nil
        standardLastFiredSegmentCount = 0
        meddpiccLastFiredSegmentCount = 0
        questionsLastFiredSegmentCount = 0
        templateLastFiredSegmentCount = 0
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
        } else if mode == .template {
            if let templateID = insights.templateID, templateID == liveTemplateID {
                // A fresh fill replaces the previous sections: the model already received them
                // as the baseline, so anything dropped was contradicted or resolved.
                if !insights.templateSections.isEmpty {
                    liveTemplateSections = insights.templateSections
                }
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
    
    @discardableResult
    func startNewMeeting() -> Bool {
        startNewMeeting(calendarEvent: nil)
    }

    @discardableResult
    private func startNewMeeting(calendarEvent: MinitiAPIService.CalendarEvent?) -> Bool {
        DebugLogger.shared.log(.app, "startNewMeeting (mode=\(appMode.rawValue))")
        updateLogRedaction()

        guard !isFinalizingMeeting else { return false }
        recordingErrorMessage = nil
        finalizationStatusText = ""
        shouldOpenMeetingAfterFinalization = false

        guard hasAcceptedTerms else {
            DebugLogger.shared.log(.app, "startNewMeeting blocked: terms not accepted")
            return false
        }
        
        switch appMode {
        case .byok:
            guard !deepgramApiKey.isEmpty else {
                showSettings = true
                return false
            }
        case .managed:
            guard !isLimitReached else {
                return false
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
        
        let preparedNotes = calendarEvent.map { prepNotes(for: $0) } ?? ""
        let meeting = Meeting(
            title: calendarEvent?.title ?? "untitled",
            notes: preparedNotes
        )
        meeting.language = meetingLanguage
        if let calendarEvent {
            meeting.calendarEventId = calendarEvent.id
            meeting.attendees = calendarEvent.attendees.map { $0.toMeetingAttendee() }
        }
        currentMeeting = meeting
        selectedCalendarEvent = calendarEvent
        currentTitleSuffix = calendarEvent?.title ?? ""
        lastTitleUpdateCount = 0
        #if os(macOS)
        resetEchoReconciliation()
        #endif
        liveSegments = []
        interimText = ""
        currentSpeaker = 0
        interimSpeaker = nil
        detectedSpeakers = []
        liveMicSpeakerIDs = []
        salesDetectionSignalsSeen = []
        salesDetectionNudgeFired = false
        resetEnvironmentInference()
        refreshEnvironmentContextEvidence()
        evaluateEnvironmentInference()
        recordingDuration = 0
        recordingStartDate = nil
        accumulatedRecordedDuration = 0
        hasUnsavedSession = true
        managedSessionError = nil
        
        // Reset live notes and insights
        liveNotes = preparedNotes
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
        liveTemplateSections = [:]
        liveTemplateID = templateInsightsEnabled ? selectedInsightTemplate.id : nil
        liveDocTopics = []
        liveSpeakerNames = [:]
        liveSpeakerOverrides = []
        liveSelfSpeakerIDs = []
        notifiedQuestionIDs = []
        lastQuestionNotificationAt = nil
        resetZonedOutState()
        resetNudgeState()
        resetInvestigationState()
        lastInsightSegmentCount = 0
        lastMEDDPICCSegmentCount = 0
        lastMEDDPICCRequestAt = nil
        lastQuestionsSegmentCount = 0
        lastQuestionsRequestAt = nil
        lastTemplateSegmentCount = 0
        lastTemplateRequestAt = nil
        lastSpeakerNamesSegmentCount = 0
        lastSpeakerNamesRequestAt = nil
        resetManagedIncrementalTracking()
        lastInsightsUpdatedAt = [:]
        
        if appMode == .managed {
            Task { await startManagedRecording() }
        } else {
            startRecording()
        }
        return true
    }
    
    func createNewSession() {
        if currentMeeting == nil {
            _ = startNewMeeting()
        } else {
            finishCurrentMeeting(then: .startUnscheduled)
        }
    }

    func endAndStartNewMeeting() {
        finishCurrentMeeting(then: .startUnscheduled)
    }

    func endAndStartCalendarMeeting(eventID: String) {
        guard let event = upcomingEvents.first(where: { $0.id == eventID }) else {
            recordingErrorMessage = "That calendar event is no longer available. Refresh your calendar and try again."
            return
        }
        finishCurrentMeeting(then: .startCalendar(event, openJoinLink: false))
    }

    /// End the current meeting and start the next calendar event, opening its join link
    /// after notes start. Explicit user action only — never used by timer paths.
    func joinAndEndAndStartCalendarMeeting(eventID: String) {
        guard let event = upcomingEvents.first(where: { $0.id == eventID }) else {
            recordingErrorMessage = "That calendar event is no longer available. Refresh your calendar and try again."
            return
        }
        finishCurrentMeeting(then: .startCalendar(event, openJoinLink: true))
    }

    /// Start taking notes for a calendar event, then open its Meet/Zoom/Teams link once.
    /// Starting is synchronous state setup; the browser takes focus afterward.
    func joinAndStartMeeting(from event: MinitiAPIService.CalendarEvent) {
        guard startMeetingFromEvent(event) else {
            // Terms, key, limit, or finalization refused the start. Opening the call
            // anyway would leave the user in a meeting miniti is not recording, and
            // would burn the one-shot guard for a start that never happened.
            DebugLogger.shared.log(.app, "Join skipped: meeting start was refused for \(event.title)")
            return
        }
        _ = openMeetingLink(for: event)
    }

    /// Open the event's conference URL. Returns false when there is no https link, the
    /// one-shot guard blocks a duplicate open for this meeting start, or the system
    /// opener fails. Never throws — join failures must not fail meeting start.
    /// - Parameter allowingRepeat: live-header rejoin after a drop; skips the one-shot set.
    @discardableResult
    func openMeetingLink(for event: MinitiAPIService.CalendarEvent, allowingRepeat: Bool = false) -> Bool {
        guard let url = event.joinURL else { return false }
        if !allowingRepeat, openedJoinLinkEventIDs.contains(event.id) {
            DebugLogger.shared.log(.app, "Join link already opened for event \(event.id); skipping duplicate")
            return false
        }
        let opened: Bool
        if let handler = testOpenURLHandler {
            opened = handler(url)
        } else {
            #if os(macOS)
            opened = NSWorkspace.shared.open(url)
            #elseif os(iOS)
            UIApplication.shared.open(url)
            opened = true
            #else
            opened = false
            #endif
        }
        if opened {
            // Record only successful opens, so a failed launch can be retried from
            // any join surface without waiting for the next meeting.
            openedJoinLinkEventIDs.insert(event.id)
            DebugLogger.shared.log(.app, "Opened join link for \(event.title)")
            #if os(macOS)
            // The browser or app that picks this link up is this meeting's call, not a
            // new meeting. Expect it, so the lifecycle engine adopts it instead of
            // prompting "End the current meeting and start a new one?".
            callLifecycleEngine.noteJoinLinkOpened()
            #endif
        } else {
            DebugLogger.shared.log(.app, "Join link open failed for \(event.title)")
        }
        return opened
    }

    private func finishCurrentMeeting(then completion: PendingMeetingCompletion) {
        guard canBeginFreshMeeting(for: completion) else { return }
        pendingMeetingCompletion = completion
        clearSmartMeetingPrompt()

        if isRecording {
            stopRecording()
        } else if isFinalizingMeeting {
            finalizationStatusText = "Saving before the next meeting…"
        } else {
            completeMeetingFinalization()
        }
    }

    private func canBeginFreshMeeting(for completion: PendingMeetingCompletion) -> Bool {
        if case .returnHome = completion { return true }
        guard hasAcceptedTerms else { return false }
        switch appMode {
        case .byok:
            guard !deepgramApiKey.isEmpty else {
                showSettings = true
                return false
            }
        case .managed:
            guard !isLimitReached, !isDeviceDisabled else { return false }
        }
        return true
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
                trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage, names: liveSpeakerNames, selfIDs: liveSpeakerLabelSelfIDs)
            }
            let markdown = fullMeetingAsMarkdown()
            exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        #endif

        // Fire webhook with live in-memory state before clearing
        if !webhookURL.isEmpty, let meeting = currentMeeting {
            let names = liveSpeakerNames
            let selfIDs = liveSpeakerLabelSelfIDs
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
                template: insightTemplate(id: liveTemplateID),
                templateSections: liveTemplateSections,
                calendarEventId: meeting.calendarEventId,
                attendees: meeting.attendees
            )
            WebhookService.send(payload: payload, to: webhookURL)
        }

        // Auto-sync to configured CRMs using calendar attendee domains.
        if let meeting = currentMeeting, !meeting.attendees.isEmpty {
            autoSyncToAttio(meeting: meeting)
            autoSyncToTwenty(meeting: meeting)
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
                #if os(macOS)
                let repairMultichannel = captureMicrophone && captureSystemAudio
                let repairMonoSource: TranscriptSource = captureMicrophone ? .microphone : .system
                #else
                let repairMultichannel = false
                let repairMonoSource: TranscriptSource = .microphone
                #endif
                audioCaptureService.onAudioBuffer = makeAudioBufferHandler(multichannel: repairMultichannel, monoSource: repairMonoSource)
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

        if let meeting = currentMeeting, let modelContext {
            // No revert: the delete stays pending in the context (never rolled back, see
            // AppState+Persistence.swift) and the retry or the next successful save commits it.
            commit(.discard, in: modelContext, mutate: { [self] in
                noteMeetingDeleted(meeting)
                modelContext.delete(meeting)
            })
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
        pendingMeetingSaves.removeValue(forKey: meeting.id)
        pendingMeetingSaveOrder.removeAll { $0 == meeting.id }
    }

    /// Set by `persistenceIssue` writers in the persistence extension; stored here because
    /// extensions cannot declare stored properties.
    func setPersistenceIssue(_ issue: PersistenceIssue?) {
        persistenceIssue = issue
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

        if requestedMode == .template {
            let template = meeting.insightTemplate ?? selectedInsightTemplate
            let baseline = meeting.insightTemplateID == template.id ? meeting.templateSections : [:]
            do {
                let templateInsights: InsightsService.LiveInsights
                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: nil, existingTitle: nil,
                        mode: InsightsMode.template.rawValue, model: model.rawValue,
                        language: language,
                        template: template,
                        previousTemplateSections: baseline.isEmpty ? nil : baseline
                    )
                    templateInsights = response.toLiveInsights(template: template)
                } else {
                    templateInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcript, existingSummary: nil,
                        existingTitle: nil, mode: .template,
                        model: model, apiKey: openaiApiKey, language: language,
                        template: template,
                        previousTemplateSections: baseline.isEmpty ? nil : baseline
                    )
                }
                guard !isMeetingDeleted(meetingID) else { return }
                meeting.applyInsightTemplate(template)
                meeting.templateSections = templateInsights.templateSections
                markInsightsUpdated(.template, meeting: meeting)
            } catch {
                DebugLogger.shared.log(.app, "History insights FAILED (template): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_history_template_failed", category: .insights, level: .warning)
            }
        }

        guard !isMeetingDeleted(meetingID) else { return }
        commit(.insightsRegeneration)

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

    /// Rebuild the cached corrector from UserDefaults. Call after Settings or
    /// live-transcript saves change the correction store.
    func reloadTranscriptCorrector() {
        transcriptCorrector = TranscriptCorrector(
            corrections: PersonalDictionaryPreferences.currentCorrections()
        )
    }

    /// What happened when a correction was saved from a transcript surface. Views
    /// show this instead of closing silently: a rejected pair, a full dictionary,
    /// or a save that matched no earlier text all looked identical to "nothing
    /// happened" in the field (Sasha, 2026-09-11).
    enum DictionaryCorrectionOutcome: Equatable {
        /// Pair stored. `rewroteEarlierMentions` is true when at least one existing
        /// segment changed; false when the fix applies to new text only.
        case saved(rewroteEarlierMentions: Bool)
        /// Empty side, or the replacement is exactly the heard text.
        case invalid
        /// The dictionary already holds the maximum number of corrections.
        case full
        /// Applied in memory, but the store did not accept the save (roadmap P0.3).
        case saveFailed

        var isSaved: Bool {
            if case .saved = self { return true }
            return false
        }

        /// One-line message for the editor. Nil when there is nothing to say.
        func message(heard: String, fixEarlierMentions: Bool) -> String? {
            switch self {
            case .invalid:
                return "that is the same word. type the spelling you want, capitals included"
            case .full:
                return "your dictionary already has \(PersonalDictionaryPreferences.maxCorrections) corrections. remove one in Settings → Language"
            case .saveFailed:
                return "correction didn't save. try again"
            case .saved(let rewrote):
                guard fixEarlierMentions, !rewrote else { return nil }
                return "saved for new mentions. no earlier “\(heard)” matched in this transcript"
            }
        }
    }

    /// Save a correction pair and optionally rewrite earlier mentions in the
    /// current live meeting. Never combined with a finals append in the same turn.
    /// After the meeting has stopped, a rewrite is also persisted straight away so
    /// the saved meeting, the minutes file, and any webhook resend carry it even if
    /// the app quits before Home.
    @discardableResult
    func saveDictionaryCorrection(
        heard: String,
        correct: String,
        fixEarlierMentions: Bool = true
    ) -> DictionaryCorrectionOutcome {
        let result = PersonalDictionaryPreferences.upsertCorrection(heard: heard, correct: correct)
        switch result {
        case .invalid:
            DebugLogger.shared.log(.app, "Dictionary correction not saved (invalid)")
            return .invalid
        case .full:
            DebugLogger.shared.log(.app, "Dictionary correction not saved (full)")
            return .full
        case .saved:
            break
        }
        reloadTranscriptCorrector()
        var rewrote = false
        if fixEarlierMentions {
            rewrote = applyRetroactiveCorrectionsToLiveTranscript()
            if rewrote, !isRecording, currentMeeting != nil {
                saveCurrentMeetingIfNeeded()
            }
        }
        DebugLogger.shared.log(
            .app,
            "Dictionary correction saved: '\(heard)' -> '\(correct)' (earlier mentions rewritten: \(rewrote), recording: \(isRecording))"
        )
        return .saved(rewroteEarlierMentions: rewrote)
    }

    /// One pass over liveSegments changing only matching text. Skips the assignment
    /// when nothing matched. Must not run inside handleSpeakerSegments.
    @discardableResult
    func applyRetroactiveCorrectionsToLiveTranscript() -> Bool {
        guard let corrector = transcriptCorrector else { return false }
        var changed = false
        let updated: [LiveSegment] = liveSegments.map { segment in
            let corrected = corrector.apply(to: segment.text)
            guard corrected != segment.text else { return segment }
            changed = true
            var copy = segment
            copy.text = corrected
            return copy
        }
        guard changed else { return false }
        liveSegments = updated
        return true
    }

    /// Apply corrections to a saved meeting's transcript without clearing insights.
    @discardableResult
    func applyDictionaryCorrection(
        heard: String,
        correct: String,
        to meeting: Meeting,
        fixEarlierMentions: Bool = true
    ) -> DictionaryCorrectionOutcome {
        let result = PersonalDictionaryPreferences.upsertCorrection(heard: heard, correct: correct)
        switch result {
        case .invalid:
            DebugLogger.shared.log(.app, "Dictionary correction not saved (invalid)")
            return .invalid
        case .full:
            DebugLogger.shared.log(.app, "Dictionary correction not saved (full)")
            return .full
        case .saved:
            break
        }
        reloadTranscriptCorrector()

        guard fixEarlierMentions, let corrector = transcriptCorrector else {
            return .saved(rewroteEarlierMentions: false)
        }
        var changed = false
        for segment in meeting.segments {
            let corrected = corrector.apply(to: segment.text)
            guard corrected != segment.text else { continue }
            segment.text = corrected
            changed = true
        }
        guard changed else { return .saved(rewroteEarlierMentions: false) }
        meeting.markTranscriptCorrected()
        guard commit(.correction) else { return .saveFailed }
        #if os(macOS)
        if autoExportMarkdown {
            let markdown = meeting.fullMeetingAsMarkdown()
            exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        #endif
        if !webhookURL.isEmpty {
            let payload = WebhookService.payloadFromMeeting(meeting)
            WebhookService.send(payload: payload, to: webhookURL)
        }
        return .saved(rewroteEarlierMentions: true)
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

        guard commit(.transcriptTrim, in: modelContext) else { return false }

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
                    confidence: $0.confidence,
                    sourceRaw: $0.sourceRaw
                )
            }
        meeting.markTranscriptEdited()

        guard commit(.transcriptRestore, in: modelContext) else { return false }

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
        guard !ScreenshotMode.isActive else { return }
        guard let modelContext else { return }
        guard currentMeeting == nil, !isRecording else { return }
        
        guard let meetings = fetchMeetings(.interruptedMeetingCheck, in: modelContext) else { return }
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
                    isFinal: seg.isFinal,
                    source: seg.source
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
        liveTemplateID = interrupted.insightTemplateID ?? (templateInsightsEnabled ? selectedInsightTemplate.id : nil)
        liveTemplateSections = interrupted.templateSections
        liveDocTopics = interrupted.docTopics
        liveSpeakerNames = interrupted.speakerNames
        liveSpeakerOverrides = interrupted.speakerOverrides
        liveSelfSpeakerIDs = interrupted.selfSpeakerIDs

        if salesInsightsEnabled, interrupted.hasMEDDPICC {
            insightsMode = .meddpicc
        } else if templateInsightsEnabled, interrupted.hasTemplateInsights {
            insightsMode = .template
        }
        
        // Restore duration from last segment timestamp (actual recorded duration, not wall clock)
        if let lastSegment = liveSegments.last {
            recordingDuration = lastSegment.timestamp
            accumulatedRecordedDuration = recordingDuration
        }
        
        // Restore detected speakers. Legacy segments without a source fall back to
        // the reserved mic ID range for the mic-speaker set.
        detectedSpeakers = Set(liveSegments.map(\.speaker))
        liveMicSpeakerIDs = Set(liveSegments.filter(\.isLocalMic).map(\.speaker))
        restoreEnvironmentInference(from: interrupted)
        
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

        guard commit(.staleMeetingFinalize) else {
            // Nothing is reported to the backend for a finalization that did not persist;
            // the next launch finds the same drafts and tries again.
            DebugLogger.shared.log(.app, "Stale interrupted meetings NOT finalized: count=\(meetings.count)", level: .warning)
            return
        }
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
        if mode == .template {
            requestTemplateFillIfNeeded()
        }
        // Populate the docs-topic list on first visit to the tab so it's ready
        // without waiting for the next cadence tick. Auto-lookup (Pro/BYOK) then
        // follows from the merge inside refreshDocsTopics.
        if mode == .docs, validatedDocsMCPURL != nil, liveDocTopics.isEmpty, currentDocsTranscript() != nil {
            Task { @MainActor in await refreshDocsTopics() }
        }
    }
    
    /// Choose the template for the live meeting (and as the default for new meetings), enable
    /// the Templates view, and show it. Changing the template mid-meeting discards the previous
    /// template's sections and fills the new one from the transcript so far.
    func selectInsightTemplate(_ id: String) {
        guard let template = insightTemplate(id: id) else { return }
        insightTemplateID = template.id
        let changed = liveTemplateID != template.id
        if changed {
            liveTemplateID = template.id
            liveTemplateSections = [:]
            lastTemplateSegmentCount = 0
            lastTemplateRequestAt = nil
            templateSuccessCount = 0
            templateCadenceAnchor = nil
            templateLastFiredSegmentCount = 0
        }
        switchInsightsMode(to: .template)
    }

    /// Choose the template for a saved meeting and fill it straight away. Picking a template is
    /// an explicit request for its notes, so this does not wait for a second tap on "update".
    func selectInsightTemplate(_ id: String, for meeting: Meeting) async {
        guard let template = insightTemplate(id: id) else { return }
        insightTemplateID = template.id
        setInsightModeEnabled(.template, enabled: true)
        insightsMode = .template
        if meeting.insightTemplateID != template.id {
            meeting.applyInsightTemplate(template)
            meeting.templateSections = [:]
            commit(.templateChange)
        }
        if currentMeeting?.id == meeting.id {
            liveTemplateID = template.id
            liveTemplateSections = meeting.templateSections
        }
        guard !meeting.hasTemplateInsights, !meeting.segments.isEmpty else { return }
        await generateInsightsForMeeting(meeting)
    }

    /// Fill the live template as soon as it is chosen, rather than waiting for the next
    /// cadence tick, when there is enough transcript to fill from.
    private func requestTemplateFillIfNeeded() {
        guard isRecording, templateInsightsEnabled, !isGeneratingTemplateInsights else { return }
        guard !hasLiveTemplateContent else { return }
        let finalSegments = liveSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        guard finalSegments.count >= firstTemplateInsightThreshold else { return }
        let transcript = transcriptText(from: finalSegments)
        guard !transcript.isEmpty, let meetingID = currentMeeting?.id else { return }
        if liveTemplateID == nil { liveTemplateID = selectedInsightTemplate.id }
        Task { @MainActor in
            await updateTemplateInBackground(
                transcript: transcript,
                finalSegments: finalSegments,
                segmentCount: finalSegments.count,
                meetingID: meetingID
            )
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
        trainingMetrics = TrainingMetrics.compute(from: segments, duration: recordingDuration, language: meetingLanguage, names: liveSpeakerNames, selfIDs: liveSpeakerLabelSelfIDs)
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
        let selfIDs = liveSpeakerLabelSelfIDs

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
            stateFingerprint: fingerprint,
            periodicFingerprint: onlyIfChanged ? fingerprint : nil
        ) else { return }
        if onlyIfChanged {
            lastPeriodicSaveRequestedFingerprint = fingerprint
        }
        _ = enqueueMeetingSave(payload)
    }

    /// Snapshots the current finalized transcript and waits until that exact revision (or a newer
    /// coalesced revision for the same meeting) reaches SwiftData. Lifecycle callers use this as a
    /// durability fence; it never blocks the main actor while the off-main diff is running.
    func saveCurrentMeetingAndWait() async -> Bool {
        let fingerprint = periodicSaveFingerprint()
        guard let payload = makeMeetingSavePayload(
            stateFingerprint: fingerprint,
            periodicFingerprint: nil
        ) else {
            return true
        }
        let fence = enqueueMeetingSave(payload)
        guard let task = activeMeetingSaveTask else {
            return isMeetingSaveFenceDurable(fence)
        }
        await task.value
        return isMeetingSaveFenceDurable(fence)
    }

    private func periodicSaveFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(currentMeeting?.id)
        hasher.combine(currentMeeting?.title)
        hasher.combine(currentMeeting?.startTime)
        hasher.combine(currentMeeting?.endTime)
        hasher.combine(currentMeeting?.language)
        hasher.combine(currentMeeting?.calendarEventId)
        hasher.combine(currentMeeting?.attendeesJSON)
        hasher.combine(currentMeeting?.managedSessionId)
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
        hasher.combine(liveTemplateID)
        hasher.combine(liveTemplateSections)
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

    private func makeMeetingSavePayload(
        stateFingerprint: Int,
        periodicFingerprint: Int?
    ) -> MeetingSavePayload? {
        guard let meeting = currentMeeting else { return nil }

        let finalSegments = cachedSaveSegments

        guard !finalSegments.isEmpty else { return nil }

        return MeetingSavePayload(
            meeting: meeting,
            meetingID: meeting.id,
            stateFingerprint: stateFingerprint,
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
            insightTemplateID: liveTemplateID,
            templateSections: liveTemplateSections,
            speakerNames: liveSpeakerNames,
            speakerOverrides: liveSpeakerOverrides,
            selfSpeakerIDs: liveSelfSpeakerIDs
        )
    }

    @discardableResult
    private func enqueueMeetingSave(_ payload: MeetingSavePayload) -> MeetingSaveFence {
        nextMeetingSaveRevision &+= 1
        let revision = nextMeetingSaveRevision
        latestMeetingSaveRevision[payload.meetingID] = revision
        let fence = MeetingSaveFence(meetingID: payload.meetingID, revision: revision)

        if activeMeetingSaveTask != nil {
            if pendingMeetingSaves[payload.meetingID] == nil {
                pendingMeetingSaveOrder.append(payload.meetingID)
            }
            pendingMeetingSaves[payload.meetingID] = PendingMeetingSave(
                payload: payload,
                revision: revision
            )
            return fence
        }

        activeMeetingSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var nextSave: PendingMeetingSave? = PendingMeetingSave(
                payload: payload,
                revision: revision
            )
            while let save = nextSave {
                let succeeded = await self.persistMeetingSavePayload(save.payload)
                if succeeded {
                    let priorRevision = self.successfulMeetingSaveRevision[save.payload.meetingID] ?? 0
                    self.successfulMeetingSaveRevision[save.payload.meetingID] = max(
                        priorRevision,
                        save.revision
                    )
                    if !self.isMeetingDeleted(save.payload.meetingID),
                       self.currentMeeting?.id == save.payload.meetingID,
                       self.latestMeetingSaveRevision[save.payload.meetingID] == save.revision,
                       self.periodicSaveFingerprint() == save.payload.stateFingerprint {
                        self.hasUnsavedSession = false
                    }
                }

                nextSave = self.dequeuePendingMeetingSave()
            }
            self.activeMeetingSaveTask = nil
        }
        return fence
    }

    private func dequeuePendingMeetingSave() -> PendingMeetingSave? {
        while !pendingMeetingSaveOrder.isEmpty {
            let meetingID = pendingMeetingSaveOrder.removeFirst()
            if let save = pendingMeetingSaves.removeValue(forKey: meetingID) {
                return save
            }
        }
        return nil
    }

    private func isMeetingSaveFenceDurable(_ fence: MeetingSaveFence) -> Bool {
        isMeetingDeleted(fence.meetingID)
            || (successfulMeetingSaveRevision[fence.meetingID] ?? 0) >= fence.revision
    }

    private func persistMeetingSavePayload(_ payload: MeetingSavePayload) async -> Bool {
        guard let modelContext else {
            DebugLogger.shared.log(.app, "Save skipped: no model context")
            clearPeriodicSaveFingerprintIfCurrent(payload.periodicFingerprint)
            return false
        }

        // The ID was snapshotted when the payload was built. Check it before any model access
        // because this payload may have waited behind another meeting, then check it again after
        // the detached diff below; reading a deleted SwiftData model traps.
        let meetingID = payload.meetingID
        guard !isMeetingDeleted(meetingID) else { return true }
        let existingSnapshots = payload.meeting.segments.map {
            PersistedSegmentSnapshot(
                id: $0.id,
                text: $0.text,
                speaker: $0.speaker,
                timestamp: $0.timestamp,
                sourceRaw: $0.sourceRaw
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
            return isMeetingDeleted(meetingID)
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
        if let templateID = payload.insightTemplateID {
            if let template = insightTemplate(id: templateID) {
                payload.meeting.applyInsightTemplate(template)
            } else {
                payload.meeting.insightTemplateID = templateID
            }
        }
        payload.meeting.templateSections = payload.templateSections
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
        let didSave: Bool
        do {
            try persistenceSaveHandler(modelContext)
            didSave = true
            clearPersistenceIssue(for: .liveTranscript)
        } catch {
            clearPeriodicSaveFingerprintIfCurrent(payload.periodicFingerprint)
            DebugLogger.shared.log(.app, "Save FAILED: \(error.localizedDescription)")
            // One banner per outage, not one per 60 s checkpoint; the queue keeps retrying.
            if persistenceIssue?.operation != .liveTranscript {
                reportPersistenceFailure(.liveTranscript, kind: .save, error: error, retry: nil)
            }
            didSave = false
        }
        os_signpost(
            .end,
            log: appStatePerformanceLog,
            name: "MeetingStoreCommit",
            signpostID: commitSignpostID,
            "success=%{public}d",
            didSave ? 1 : 0
        )
        return didSave
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
                existing.sourceRaw != segment.sourceRaw ||
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
                existing.sourceRaw = upsert.sourceRaw
            } else {
                let newSegment = TranscriptSegment(
                    id: upsert.id,
                    text: upsert.text,
                    speaker: upsert.speaker,
                    timestamp: upsert.timestamp,
                    isFinal: true,
                    sourceRaw: upsert.sourceRaw
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
        guard !ScreenshotMode.isActive else { return }
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
        lastSpeechDetectedAt = 0
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
        lastSpeechDetectedAt = 0
        #if os(macOS)
        // Association forms here: from the start prompt's app, or from exactly one
        // recognized call being active right now. Mid-recording calls never associate,
        // except the call a join-style start is waiting for (calendar event with a
        // conference link, or a join link the user opened): that one is adopted within
        // the engine's bounded window instead of being offered as a "new meeting".
        callLifecycleEngine.noteRecordingStarted(
            activeCalls: latestCallSnapshot?.activeCalls ?? [],
            startedFrom: pendingCallAssociationApp,
            expectsCall: selectedCalendarEvent?.joinURL != nil
        )
        pendingCallAssociationApp = nil
        suppressAutoCallEndUntil = nil
        #endif
        startTranscriptHealthMonitoring()
        
        configureDeepgramServiceCredential()
        
        #if os(macOS)
        let useMultichannel = captureMicrophone && captureSystemAudio
        // Mono capture attributes every response to the active source explicitly;
        // multichannel attributes by channel (0 mic, 1 system).
        let monoSource: TranscriptSource = captureMicrophone ? .microphone : .system
        if useMultichannel {
            resetEchoReconciliation(flushPending: true)
            audioCaptureService.resetSourceTracking()
        }
        #else
        let useMultichannel = false
        let monoSource: TranscriptSource = .microphone
        #endif

        // Initial and resumed sockets use the duration already accumulated before this active
        // recording interval. Deepgram's word clock begins at zero for the new connection.
        // Resumed sockets within one meeting keep the speaker identity allocation so app
        // speaker IDs never collide across sockets; a fresh meeting resets it.
        deepgramTimelineOffset = accumulatedRecordedDuration
        let isResumedSession = accumulatedRecordedDuration > 0
        if isResumedSession {
            // After an app relaunch the allocator is empty but restored segments
            // still hold their speaker IDs — seed so new allocations can't collide.
            deepgramService.seedRestoredSpeakerIdentities(Set(liveSegments.map(\.speaker)))
        }
        let onDeviceTimeline = beginOnDeviceDiarizationSession(multichannel: useMultichannel, monoSource: monoSource)
        deepgramService.connect(
            language: meetingLanguage,
            personalDictionaryTerms: PersonalDictionaryPreferences.currentTerms(),
            sessionKeyterms: deepgramSessionKeyterms(),
            multichannel: useMultichannel,
            monoSource: monoSource,
            preserveSpeakerIdentities: isResumedSession,
            onDeviceSpeakerTimeline: onDeviceTimeline
        )

        // Configure audio capture
        audioCaptureService.onAudioBuffer = makeAudioBufferHandler(multichannel: useMultichannel, monoSource: monoSource)
        
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
        guard await ensureManagedEnrollment(trigger: "start") else {
            recordingErrorMessage = managedEnrollmentError
                ?? "Miniti could not set up this device for managed mode. Check your connection and try again."
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
        // Screenshot scenes are seeded and offline; never surface a session error there.
        guard !ScreenshotMode.isActive else { return true }
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
        // The no-content stop branch never sets isFinalizingMeeting, so without this gate a
        // second stop (for example a late capture-failure cleanup racing a user stop) re-runs
        // the whole body — including a second managed session-end report.
        guard isRecording else {
            DebugLogger.shared.log(.app, "stopRecording ignored: not recording")
            return
        }
        #if os(macOS)
        // A direct user Stop during ending grace commits the end: clear the countdown
        // without resuming sending (capture is torn down just below either way).
        if endingGrace != nil {
            endingGraceTimer?.invalidate()
            endingGraceTimer = nil
            endingGrace = nil
            endingGraceSuspendedAt = nil
            finalizeGraceOnWake = false
            clearEndingGraceNotification()
        }
        callLifecycleEngine.noteRecordingEnded()
        #endif
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
        onDeviceDiarization.endSession()
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
            hasContent = hasContent ||
                !pendingMicSegments.isEmpty ||
                !pendingOrderedFinalSegments.isEmpty
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
                    flushAllPendingOrderedFinalSegments()
                    #endif
                    // Make the transcript durable before slower, failure-prone AI requests.
                    _ = await saveCurrentMeetingAndWait()
                    let finalSegments = liveSegments
                        .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .sorted { $0.timestamp < $1.timestamp }
                    let finalTranscript = transcriptText(from: finalSegments)
                    let finalLanguage = meetingLanguage
                    let finalTitleContext = currentTitleSuffix
                    let shouldGenerateSales = salesInsightsEnabled
                    let finalTemplate: InsightTemplate? = templateInsightsEnabled ? liveTemplate : nil

                    // End-of-meeting naming pass: one request with the full transcript
                    // when automatic naming is on and any non-self speaker still lacks a name.
                    // The pass is fenced by meeting ID inside updateSpeakerNamesInBackground and
                    // runs concurrently with final insights: naming must never delay the
                    // summary or the "finishing" state (plan B5 contract).
                    if autoInferSpeakerNames, hasUnnamedNonSelfSpeaker(in: finalSegments) {
                        let passSegments = finalSegments
                        // The enclosing stop task already holds self strongly; a weak inner
                        // capture changes nothing and trips Xcode 27's capture diagnostic.
                        Task { @MainActor in
                            await updateSpeakerNamesInBackground(
                                finalSegments: passSegments,
                                segmentCount: passSegments.count,
                                meetingID: meetingIDAtStop
                            )
                            saveCurrentMeetingIfNeeded()
                        }
                    }

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
                        includeSales: shouldGenerateSales,
                        template: finalTemplate
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
                completeMeetingFinalization()
            }
        } else {
            deepgramService?.disconnect()
            completeMeetingFinalization()
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
        clearSmartMeetingPrompt()
        smartMeetingSuppressedUntil = nil
        smartQuietEpisodePrompted = false
        #if os(macOS)
        endingGraceTimer?.invalidate()
        endingGraceTimer = nil
        endingGrace = nil
        endingGraceSuspendedAt = nil
        finalizeGraceOnWake = false
        suppressAutoCallEndUntil = nil
        startPromptApp = nil
        pendingCallAssociationApp = nil
        clearEndingGraceNotification()
        callLifecycleEngine.noteRecordingEnded()
        #endif
        recordingErrorMessage = nil
        currentMeeting = nil
        isStartingMeeting = false
        isResumingRecording = false
        liveSegments = []
        interimText = ""
        currentSpeaker = 0
        interimSpeaker = nil
        detectedSpeakers = []
        liveMicSpeakerIDs = []
        salesDetectionSignalsSeen = []
        salesDetectionNudgeFired = false
        resetEnvironmentInference()
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
        resetInvestigationState()
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
        openedJoinLinkEventIDs.removeAll()
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

        let completion = pendingMeetingCompletion
        pendingMeetingCompletion = .none
        switch completion {
        case .none:
            break
        case .returnHome:
            shouldOpenMeetingAfterFinalization = false
            goHome()
            return
        case .startUnscheduled:
            shouldOpenMeetingAfterFinalization = false
            goHome()
            _ = startNewMeeting()
            return
        case .startCalendar(let event, let openJoinLink):
            shouldOpenMeetingAfterFinalization = false
            goHome()
            if openJoinLink {
                joinAndStartMeeting(from: event)
            } else {
                _ = startNewMeeting(calendarEvent: event)
            }
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
        includeSales: Bool,
        template: InsightTemplate? = nil
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
            commit(.finalInsights)
            return
        }

        guard !transcript.isEmpty else {
            commit(.finalInsights)
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
            commit(.finalInsights)
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
                commit(.finalInsights)
                DebugLogger.shared.log(.app, "Final insights complete (meddpicc)")
            } catch {
                DebugLogger.shared.log(.app, "Final insights FAILED (meddpicc): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_final_meddpicc_failed", category: .insights, level: .warning)
            }
        }
        
        // Template sections are specialist functionality too: only when the person enabled
        // the Templates view for this meeting.
        if let template {
            do {
                guard isFinalInsightsRequestStillCurrent() else {
                    DebugLogger.shared.log(.app, "Skipping final template insights request (meeting changed/resumed/segments advanced)")
                    return
                }

                DebugLogger.shared.log(.app, "Generating final template insights: \(template.id)")
                let templateInsights: InsightsService.LiveInsights
                let baseline = meeting.insightTemplateID == template.id ? meeting.templateSections : [:]

                if requestAppMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId, transcript: transcript,
                        existingSummary: nil, existingTitle: existingTitle,
                        mode: InsightsMode.template.rawValue, model: model.rawValue,
                        language: language,
                        template: template,
                        previousTemplateSections: baseline.isEmpty ? nil : baseline
                    )
                    templateInsights = response.toLiveInsights(template: template)
                } else {
                    templateInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcript, existingSummary: nil,
                        existingTitle: existingTitle, mode: .template,
                        model: model, apiKey: requestAPIKey, language: language,
                        template: template,
                        previousTemplateSections: baseline.isEmpty ? nil : baseline
                    )
                }

                guard isFinalInsightsRequestStillCurrent() else {
                    DebugLogger.shared.log(.app, "Dropping stale final template insights response")
                    return
                }

                meeting.applyInsightTemplate(template)
                if !templateInsights.templateSections.isEmpty {
                    meeting.templateSections = templateInsights.templateSections
                }
                markInsightsUpdated(.template, meeting: meeting)
                if currentMeeting?.id == meetingIDAtRequest, liveTemplateID == template.id,
                   !templateInsights.templateSections.isEmpty {
                    liveTemplateSections = templateInsights.templateSections
                }
                commit(.finalInsights)
                DebugLogger.shared.log(.app, "Final insights complete (template): sections=\(templateInsights.templateSections.count)")
            } catch {
                DebugLogger.shared.log(.app, "Final insights FAILED (template): \(error.localizedDescription)")
                enqueueDiagnosticEvent("insights_final_template_failed", category: .insights, level: .warning)
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
            commit(.finalInsights)
            DebugLogger.shared.log(.app, "Final insights complete (questions): count=\(questionsInsights.questions.count)")
        } catch {
            DebugLogger.shared.log(.app, "Final insights FAILED (questions): \(error.localizedDescription)")
        }

        guard isFinalInsightsRequestStillCurrent() else { return }
        commit(.finalInsights)

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
            } else if requestedMode == .template, templateInsightsEnabled {
                await updateTemplateInBackground(
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
            } else if requestedMode == .template {
                let template = liveTemplate
                if liveTemplateID == nil { liveTemplateID = template.id }
                let baseline = liveTemplateSections.isEmpty ? nil : liveTemplateSections
                let templateInsights: InsightsService.LiveInsights

                if appMode == .managed, minitiAPIService != nil {
                    let deviceId = DeviceIdentifier.getOrCreateDeviceId()
                    let response = try await generateManagedInsightsWithRetry(
                        deviceId: deviceId,
                        transcript: transcriptForRequest,
                        existingSummary: nil,
                        existingTitle: nil,
                        mode: InsightsMode.template.rawValue,
                        model: model.rawValue,
                        language: meetingLanguage,
                        template: template,
                        previousTemplateSections: baseline
                    )
                    templateInsights = response.toLiveInsights(template: template)
                } else {
                    templateInsights = try await insightsService!.generateLiveInsights(
                        transcript: transcriptForRequest,
                        existingSummary: nil,
                        existingTitle: nil,
                        mode: .template,
                        model: model,
                        apiKey: openaiApiKey,
                        language: meetingLanguage,
                        template: template,
                        previousTemplateSections: baseline
                    )
                }

                if !templateInsights.templateSections.isEmpty {
                    liveTemplateSections = templateInsights.templateSections
                }
                meeting.applyInsightTemplate(template)
                meeting.templateSections = liveTemplateSections
                markInsightsUpdated(.template, meeting: meeting)
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
            
            commit(.insights)
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
        attendees: [[String: String]]? = nil,
        template: InsightTemplate? = nil,
        previousTemplateSections: [String: String]? = nil
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
                    attendees: attendees,
                    template: template,
                    previousTemplateSections: previousTemplateSections
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
    
    // MARK: - Persistent store outcome

    /// Record how the launch-time store open went. Emits one diagnostics event per distinct
    /// failure (no meeting content, only category/domain/code) and clears on a successful retry.
    func notePersistentStore(_ state: PersistentStoreState) {
        switch state {
        case .ready:
            if persistentStoreFailure != nil {
                DebugLogger.shared.log(.app, "Persistent store opened after recovery retry", level: .recovery)
            }
            persistentStoreFailure = nil
        case .failed(let failure, let readOnly):
            guard persistentStoreFailure != failure else { return }
            persistentStoreFailure = failure
            enqueueDiagnosticEvent(
                "persistent_store_open_failed",
                category: .app,
                level: .error,
                details: [
                    "category": failure.category.rawValue,
                    "domain": failure.domain,
                    "code": String(failure.code),
                    "read_only_open": readOnly == nil ? "failed" : "ok",
                ]
            )
        }
    }

    // MARK: - Diagnostics Events

    func enqueueDiagnosticEvent(
        _ name: String,
        category: MinitiAPIService.ClientEventPayload.EventCategory,
        level: MinitiAPIService.ClientEventPayload.EventLevel = .info,
        details: [String: String] = [:]
    ) {
        diagnosticEventObserver?(name, details)
        // The unit-test host shares this device's defaults and enrollment; it must never queue
        // events that would later flush to production as if a real session produced them.
        guard !Self.isRunningUnderXCTest else { return }
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
        guard let meetings = fetchMeetings(.sessionReference, in: modelContext) else { return }
        if let targetID = meetingId,
           let target = meetings.first(where: { $0.id == targetID }) {
            commit(.sessionReference, in: modelContext, mutate: { target.managedSessionId = nil })
            return
        }
        
        if let fallback = meetings.first(where: { $0.managedSessionId == sessionId }) {
            commit(.sessionReference, in: modelContext, mutate: { fallback.managedSessionId = nil })
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
        guard !ScreenshotMode.isActive else { return }
        guard let minitiAPIService else { return }
        
        do {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            let versionInfo = try await minitiAPIService.checkVersion(deviceId: deviceId, appMode: appMode.rawValue)
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if let minVersion = versionInfo.minVersion, Self.isNewer(remote: minVersion, than: currentVersion) {
                requiresForceUpdate = true
                availableUpdate = versionInfo
                DebugLogger.shared.log(.app, "Force update required: min=\(minVersion), current=\(currentVersion)")
            } else {
                requiresForceUpdate = false
                availableUpdate = nil
                DebugLogger.shared.log(.app, "Version supported: current=\(currentVersion)")
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

    func prepNotes(for event: MinitiAPIService.CalendarEvent) -> String {
        calendarPrepNotes[event.id]?.text ?? ""
    }

    func updatePrepNotes(_ notes: String, for event: MinitiAPIService.CalendarEvent) {
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            calendarPrepNotes[event.id] = nil
        } else {
            calendarPrepNotes[event.id] = CalendarPrepNote(
                eventID: event.id,
                text: notes,
                eventStart: event.startDate,
                updatedAt: Date()
            )
        }
        persistCalendarPrepNotes()
    }

    nonisolated static func decodeCalendarPrepNotes(_ data: Data?) -> [String: CalendarPrepNote] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: CalendarPrepNote].self, from: data)) ?? [:]
    }

    nonisolated static func encodeCalendarPrepNotes(_ notes: [String: CalendarPrepNote]) -> Data? {
        try? JSONEncoder().encode(notes)
    }

    private func persistCalendarPrepNotes() {
        guard let data = Self.encodeCalendarPrepNotes(calendarPrepNotes) else { return }
        UserDefaults.standard.set(data, forKey: Self.calendarPrepNotesDefaultsKey)
    }

    private func pruneExpiredCalendarPrepNotes(now: Date = Date()) {
        let retained = calendarPrepNotes.filter { _, note in
            if let eventStart = note.eventStart {
                return eventStart.addingTimeInterval(30 * 24 * 60 * 60) > now
            }
            return note.updatedAt.addingTimeInterval(180 * 24 * 60 * 60) > now
        }
        guard retained.count != calendarPrepNotes.count else { return }
        calendarPrepNotes = retained
        persistCalendarPrepNotes()
    }
    
    func refreshGoogleCalendarStatus() async {
        guard !ScreenshotMode.isActive else { return }
        guard googleCalendarEnabled, let minitiAPIService else {
            applyGoogleCalendarDisconnectedState()
            return
        }
        defer { calendarLaunchCheckCompleted = true }
        if DeviceIdentifier.isUsingSessionOnlyID {
            // The backend keys the Google connection by device ID; asking with a temporary
            // ID would answer "not connected" for a device that is. Unknown, retry later.
            DebugLogger.shared.log(.app, "Google Calendar status check deferred: session-only device ID")
            scheduleCalendarStatusRetry()
            return
        }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        let result: Result<MinitiAPIService.GoogleStatusResponse, any Error>
        do {
            result = .success(try await minitiAPIService.googleStatus(deviceId: deviceId))
        } catch {
            result = .failure(error)
        }
        switch Self.calendarStatusOutcome(from: result.map(\.connected)) {
        case .connected:
            cancelCalendarStatusRetry()
            let status = try? result.get()
            isGoogleCalendarConnected = true
            googleCalendarEmail = status?.email
            await fetchUpcomingEvents()
        case .disconnected:
            // The backend answered: this device really has no Google connection.
            cancelCalendarStatusRetry()
            applyGoogleCalendarDisconnectedState()
        case .unknown:
            // No answer (network not up yet, DNS, token refresh failed on the wire):
            // keep whatever state we had and try again shortly. Never treat silence
            // as a sign-out.
            if case .failure(let error) = result {
                DebugLogger.shared.log(.app, "Google Calendar status check failed: \(error.localizedDescription)")
                if case MinitiAPIService.ServiceError.notEnrolled = error, appMode != .managed {
                    // Nothing will enrol this install outside managed mode, so a retry
                    // ladder would only spin. Same end state as before: unconfirmed.
                    return
                }
            }
            scheduleCalendarStatusRetry()
        }
    }

    enum CalendarStatusOutcome: Equatable {
        case connected
        case disconnected
        case unknown
    }

    /// A thrown status check is no information about the connection.
    nonisolated static func calendarStatusOutcome(from result: Result<Bool, any Error>) -> CalendarStatusOutcome {
        switch result {
        case .success(true): return .connected
        case .success(false): return .disconnected
        case .failure: return .unknown
        }
    }

    /// Retry ladder for an unanswered status check: quick at first (the network usually
    /// arrives within a minute of login), then every five minutes for as long as the
    /// calendar is enabled and still unconfirmed.
    nonisolated static func calendarStatusRetryDelay(attempt: Int) -> TimeInterval {
        let ladder: [TimeInterval] = [5, 15, 45, 120]
        guard attempt >= 1 else { return ladder[0] }
        return attempt <= ladder.count ? ladder[attempt - 1] : 300
    }

    private func scheduleCalendarStatusRetry() {
        guard googleCalendarEnabled, !ScreenshotMode.isActive else { return }
        calendarStatusRetryTask?.cancel()
        calendarStatusRetryAttempt += 1
        let delay = Self.calendarStatusRetryDelay(attempt: calendarStatusRetryAttempt)
        DebugLogger.shared.log(.app, "calendar_status_retry_scheduled attempt=\(calendarStatusRetryAttempt) in=\(Int(delay))s")
        calendarStatusRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.googleCalendarEnabled, !self.isGoogleCalendarConnected else { return }
            await self.refreshGoogleCalendarStatus()
            if self.isGoogleCalendarConnected {
                DebugLogger.shared.log(.app, "calendar_status_retry_recovered attempt=\(self.calendarStatusRetryAttempt)")
                self.startCalendarRefreshTimer()
                self.startAutoStartMonitoring()
            }
        }
    }

    private func cancelCalendarStatusRetry() {
        calendarStatusRetryTask?.cancel()
        calendarStatusRetryTask = nil
        calendarStatusRetryAttempt = 0
    }

    /// The app became active or the Mac woke while the calendar is enabled but unconfirmed:
    /// ask again, at most once a minute. A deliberately disconnected person gets one
    /// cheap `connected: false` per activation and nothing changes for them.
    func recheckGoogleCalendarStatusIfNeeded(trigger: String) {
        guard !ScreenshotMode.isActive, googleCalendarEnabled, !isGoogleCalendarConnected else { return }
        // The launch Task owns the first check; an activation during a cold start must
        // not race it (managed enrollment may still be in flight).
        guard calendarLaunchCheckCompleted else { return }
        let now = Date()
        if let last = lastCalendarStatusRecheckAt, now.timeIntervalSince(last) < 60 { return }
        lastCalendarStatusRecheckAt = now
        DebugLogger.shared.log(.app, "calendar_status_recheck trigger=\(trigger)")
        Task { [weak self] in
            guard let self else { return }
            await self.refreshGoogleCalendarStatus()
            if self.isGoogleCalendarConnected {
                self.startCalendarRefreshTimer()
                self.startAutoStartMonitoring()
            }
        }
    }
    
    func fetchUpcomingEvents() async {
        guard googleCalendarEnabled, isGoogleCalendarConnected, let minitiAPIService else {
            DebugLogger.shared.log(.app, "Google Calendar events fetch skipped: enabled=\(googleCalendarEnabled) connected=\(isGoogleCalendarConnected) service=\(minitiAPIService != nil)")
            return
        }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        do {
            let events = try await minitiAPIService.googleEvents(deviceId: deviceId, maxResults: 40, includeFiltered: true)
            let withLink = events.reduce(into: 0) { $0 += $1.joinURL != nil ? 1 : 0 }
            let withRawLinkFields = events.reduce(into: 0) {
                $0 += ($1.meetLink != nil || $1.conferenceUrl != nil) ? 1 : 0
            }
            // Out of office, focus time, and similar blocks are not meetings: they must
            // never raise a reminder, an auto-start countdown, or "end and start next".
            // The fetch asks for the skipped events too so the person's own filter
            // settings decide, and a settings change re-applies without a refetch.
            fetchedCalendarEvents = events
            let meetings = Self.filterCalendarMeetings(events, preferences: calendarMeetingFilters)
            DebugLogger.shared.log(
                .app,
                "Google Calendar fetched \(events.count) events, \(withLink) with a join link (\(withRawLinkFields) carried raw link fields), \(events.count - meetings.count) skipped as non-meetings"
            )
            upcomingEvents = meetings
            rescheduleMeetingReminders()
            if let pendingID = pendingReminderJoinEventID {
                pendingReminderJoinEventID = nil
                if let event = events.first(where: { $0.id == pendingID }) {
                    joinAndStartMeeting(from: event)
                } else {
                    DebugLogger.shared.log(.app, "Deferred meeting reminder \(pendingID) no longer matches an upcoming event")
                }
            }
        } catch {
            DebugLogger.shared.log(.app, "Google Calendar events fetch failed: \(error)")
            if case MinitiAPIService.ServiceError.serverError(let msg) = error, msg.contains("google_not_connected") {
                applyGoogleCalendarDisconnectedState()
            }
        }
    }
    
    nonisolated static func filterCalendarMeetings(
        _ events: [MinitiAPIService.CalendarEvent],
        preferences: MinitiAPIService.CalendarMeetingFilterPreferences
    ) -> [MinitiAPIService.CalendarEvent] {
        events.filter { $0.skipReason(under: preferences) == nil }
    }

    /// Re-derive `upcomingEvents` from the last fetch after the filters changed.
    private func applyCalendarMeetingFilters() {
        guard !ScreenshotMode.isActive, !fetchedCalendarEvents.isEmpty else { return }
        let meetings = Self.filterCalendarMeetings(fetchedCalendarEvents, preferences: calendarMeetingFilters)
        guard meetings.map(\.id) != upcomingEvents.map(\.id) else { return }
        upcomingEvents = meetings
        rescheduleMeetingReminders()
    }

    /// Settings → Calendar → Meeting filters → "Preview next 7 days": every event
    /// in the coming week with the reason it would be skipped, or nil for a meeting.
    func previewCalendarMeetingFilters(days: Int = 7) async throws -> [CalendarFilterPreviewRow] {
        guard let minitiAPIService else { return [] }
        let deviceId = DeviceIdentifier.getOrCreateDeviceId()
        let formatter = ISO8601DateFormatter()
        let timeMax = formatter.string(from: Date().addingTimeInterval(TimeInterval(days) * 86_400))
        let events = try await minitiAPIService.googleEvents(
            deviceId: deviceId,
            timeMax: timeMax,
            maxResults: 50,
            includeFiltered: true
        )
        let preferences = calendarMeetingFilters
        return events.map { event in
            CalendarFilterPreviewRow(
                id: event.id,
                title: event.title,
                start: event.startDate,
                isAllDay: event.isAllDay,
                skipReason: event.skipReason(under: preferences)
            )
        }
    }

    func startCalendarRefreshTimer() {
        guard !ScreenshotMode.isActive else { return }
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
    
    @discardableResult
    func startMeetingFromEvent(_ event: MinitiAPIService.CalendarEvent) -> Bool {
        cancelAutoStartCountdown()
        clearSmartMeetingPrompt()
        return startNewMeeting(calendarEvent: event)
    }
    
    // MARK: - Auto-start from Calendar
    
    func startAutoStartMonitoring() {
        guard !ScreenshotMode.isActive else { return }
        autoStartCheckTimer?.invalidate()
        guard (autoStartFromCalendar || smartMeetingsEnabled),
              googleCalendarEnabled,
              isGoogleCalendarConnected else { return }
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
        guard googleCalendarEnabled, isGoogleCalendarConnected else { return }
        if currentMeeting != nil {
            if smartMeetingsEnabled {
                checkSmartCalendarTransition()
            }
            return
        }
        guard autoStartFromCalendar, !isStartingMeeting else { return }
        guard pendingAutoStartEvent == nil else { return }
        
        let now = Date()
        for event in upcomingEvents {
            guard let start = event.startDate else { continue }
            guard event.status.lowercased() != "cancelled" else { continue }
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

    private func checkSmartCalendarTransition() {
        guard smartMeetingsEnabled,
              isRecording || currentMeeting != nil,
              let currentMeeting else { return }

        let now = Date()
        guard let event = upcomingEvents.first(where: { candidate in
            guard candidate.id != currentMeeting.calendarEventId,
                  !candidate.isAllDay,
                  !dismissedAutoStartEventIDs.contains(candidate.id),
                  let start = candidate.startDate else { return false }
            let snoozedUntil = smartMeetingSnoozedUntilByEventID[candidate.id]
            return (snoozedUntil == nil || snoozedUntil! <= now)
                && start.timeIntervalSince(now) <= 60
                && start.timeIntervalSince(now) >= -120
        }) else { return }

        let startsIn = max(0, Int(ceil(event.startDate?.timeIntervalSince(now) ?? 0)))
        if smartMeetingPrompt?.eventID != event.id {
            let time = event.startDate?.formatted(date: .omitted, time: .shortened) ?? "soon"
            presentSmartMeetingPrompt(
                SmartMeetingPrompt(
                    id: "calendar-\(event.id)",
                    kind: .calendar,
                    title: "Next: \(event.title)",
                    message: "Starts at \(time). Is the current meeting over?",
                    eventID: event.id,
                    countdown: nil
                )
            )
        }

        guard isRecording,
              startsIn <= 15,
              smartMeetingPrompt?.countdown == nil,
              let currentEvent = selectedCalendarEvent,
              currentEvent.id == currentMeeting.calendarEventId else { return }

        let currentEnd = currentEvent.endDate
        let nextStart = event.startDate
        let eventsOverlap = {
            guard let currentEnd, let nextStart else { return true }
            return nextStart < currentEnd
        }()
        let nowAbsolute = CFAbsoluteTimeGetCurrent()
        guard Self.canAutomaticallyHandoffCalendarMeeting(
            currentEventEnd: currentEnd,
            nextEventStart: nextStart,
            now: now,
            transcriptGap: nowAbsolute - lastTranscriptReceivedAt,
            audioGap: audioActivityGap(at: nowAbsolute),
            autoStartEnabled: autoStartFromCalendar,
            calendarAutoStopEnabled: autoStopFromCalendar,
            eventsOverlap: eventsOverlap
        ) else { return }

        beginSmartMeetingCountdown(for: event, seconds: max(1, startsIn))
    }

    private func beginSmartMeetingCountdown(
        for event: MinitiAPIService.CalendarEvent,
        seconds: Int
    ) {
        guard var prompt = smartMeetingPrompt, prompt.eventID == event.id else { return }
        prompt.countdown = seconds
        smartMeetingPrompt = prompt
        smartMeetingCountdownTimer?.invalidate()
        smartMeetingCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      var prompt = self.smartMeetingPrompt,
                      prompt.eventID == event.id,
                      let countdown = prompt.countdown else { return }
                if countdown <= 1 {
                    self.smartMeetingCountdownTimer?.invalidate()
                    self.smartMeetingCountdownTimer = nil
                    self.endAndStartCalendarMeeting(eventID: event.id)
                } else {
                    prompt.countdown = countdown - 1
                    self.smartMeetingPrompt = prompt
                }
            }
        }
    }

    private func cancelSmartMeetingCountdown(keepPrompt: Bool) {
        smartMeetingCountdownTimer?.invalidate()
        smartMeetingCountdownTimer = nil
        guard keepPrompt, var prompt = smartMeetingPrompt else {
            smartMeetingPrompt = nil
            return
        }
        prompt.countdown = nil
        smartMeetingPrompt = prompt
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
        cancelCalendarStatusRetry()
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

    func autoSyncToTwenty(meeting: Meeting) {
        guard autoTwentySync, googleCalendarEnabled, isGoogleCalendarConnected else { return }
        let externalDomains = Set(meeting.attendees.filter { !$0.isSelf }.map(\.domain).filter { !$0.isEmpty })
        guard !externalDomains.isEmpty, let service = minitiAPIService else { return }

        let payload = AttioMeetingPayload.from(meeting: meeting)
        let domainsCopy = externalDomains
        Task.detached {
            let deviceId = DeviceIdentifier.getOrCreateDeviceId()
            do {
                var allMatches: [MinitiAPIService.AttioSearchRecord] = []
                for domain in domainsCopy {
                    let results = try await service.twentySearch(
                        deviceId: deviceId,
                        query: domain,
                        objects: ["companies"]
                    )
                    allMatches.append(contentsOf: results)
                }
                let uniqueMatches = Dictionary(
                    grouping: allMatches,
                    by: { "\($0.objectSlug):\($0.idPayload.recordID)" }
                ).compactMap(\.value.first)
                guard uniqueMatches.count == 1, let match = uniqueMatches.first else {
                    DebugLogger.shared.log(
                        .app,
                        "Auto Twenty sync: \(uniqueMatches.count) matches for domains \(domainsCopy) — skipping (need exactly 1)"
                    )
                    return
                }
                _ = try await service.twentySendMeeting(
                    deviceId: deviceId,
                    meetingPayload: payload,
                    targetObject: match.objectSlug,
                    targetRecordID: match.idPayload.recordID,
                    createTasksFromActionItems: false
                )
                DebugLogger.shared.log(.app, "Auto Twenty sync: sent to \(match.objectSlug) \(match.recordText)")
            } catch {
                DebugLogger.shared.log(.app, "Auto Twenty sync failed: \(error.localizedDescription)")
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
        guard !ScreenshotMode.isActive else { return }
        if appMode == .managed {
            guard await ensureManagedEnrollment(trigger: "usage") else {
                isLoadingUsage = false
                return
            }
        }
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
    // MARK: - Device-bound authorization (managed account)

    func refreshClientAuthStatus() {
        let status = ClientAuthManager.shared.status
        clientAuthStatus = status
        showRecoveryKeyNotice = status.isEnrolled && !status.recoveryKeyAcknowledged && !recoveryKeyNoticeSnoozed
    }

    /// Screenshot mode: derive the nudge from the faked status rather than the Keychain.
    func refreshClientAuthStatusForScreenshots() {
        showRecoveryKeyNotice = clientAuthStatus.isEnrolled && !clientAuthStatus.recoveryKeyAcknowledged
    }

    /// Make sure this installation holds device-bound credentials before a managed request.
    /// Existing installations migrate silently (their device record predates the backend
    /// cutoff); anything else gets a fresh anonymous account. Failures are retried on the
    /// next managed action rather than surfaced as a gate, since managed features need the
    /// network anyway. Concurrent callers share one attempt.
    /// Unit tests construct `AppState` inside the app host; they must never enroll a real
    /// device or create accounts on the production backend.
    nonisolated static let isRunningUnderXCTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
        || NSClassFromString("XCTestCase") != nil

    @discardableResult
    func ensureManagedEnrollment(trigger: String) async -> Bool {
        guard !ScreenshotMode.isActive else { return true }
        guard !Self.isRunningUnderXCTest else { return false }
        guard appMode == .managed else { return false }
        if ClientAuthManager.shared.isEnrolled {
            if !clientAuthStatus.isEnrolled { refreshClientAuthStatus() }
            return true
        }
        if DeviceIdentifier.isUsingSessionOnlyID {
            // The real device ID exists but the Keychain could not be read right now
            // (locked, prompting). Enrolling would bind a new account and stored
            // credentials to a temporary identity; wait for the next trigger instead.
            DebugLogger.shared.log(.app, "enrollment_deferred_session_only_device_id trigger=\(trigger)")
            return false
        }
        if let enrollmentTask { return await enrollmentTask.value }
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            defer { self.enrollmentTask = nil }
            return await self.performManagedEnrollment(trigger: trigger)
        }
        enrollmentTask = task
        return await task.value
    }

    private func performManagedEnrollment(trigger: String) async -> Bool {
        isEnrollingManagedDevice = true
        defer { isEnrollingManagedDevice = false }
        let manager = ClientAuthManager.shared
        let label = Self.managedDeviceLabel
        do {
            try await manager.migrateLegacyDevice(label: label)
            managedEnrollmentError = nil
            DebugLogger.shared.log(.app, "Managed enrollment: migrated existing device (trigger=\(trigger))")
            enqueueDiagnosticEvent("client_auth_migrated", category: .app, level: .info)
        } catch ClientAuthError.notEligibleForMigration {
            do {
                try await manager.createAccount(label: label)
                managedEnrollmentError = nil
                DebugLogger.shared.log(.app, "Managed enrollment: created anonymous account (trigger=\(trigger))")
                enqueueDiagnosticEvent("client_auth_created", category: .app, level: .info)
            } catch {
                managedEnrollmentError = error.localizedDescription
                DebugLogger.shared.log(.app, "Managed enrollment FAILED (create, trigger=\(trigger)): \(error.localizedDescription)")
                enqueueDiagnosticEvent("client_auth_enrollment_failed", category: .app, level: .warning, details: ["path": "create"])
            }
        } catch ClientAuthError.alreadyEnrolled {
            managedEnrollmentError = nil
        } catch {
            managedEnrollmentError = error.localizedDescription
            DebugLogger.shared.log(.app, "Managed enrollment FAILED (migrate, trigger=\(trigger)): \(error.localizedDescription)")
            enqueueDiagnosticEvent("client_auth_enrollment_failed", category: .app, level: .warning, details: ["path": "migrate"])
        }
        refreshClientAuthStatus()
        return manager.isEnrolled
    }

    /// Short, non-identifying label shown in the device list ("MacBook Pro", "iPhone").
    nonisolated static var managedDeviceLabel: String {
        #if os(iOS)
        return "iPhone or iPad"
        #else
        return "Mac"
        #endif
    }

    /// Attach this installation to an existing account with its recovery key.
    func restoreManagedAccount(recoveryKey: String) async -> Bool {
        guard !ScreenshotMode.isActive else { return true }
        managedEnrollmentError = nil
        isEnrollingManagedDevice = true
        defer { isEnrollingManagedDevice = false }
        let manager = ClientAuthManager.shared
        do {
            if manager.isEnrolled { try await manager.signOut() }
            manager.discardDraft()
            try await manager.restoreAccount(recoveryKeyInput: recoveryKey, label: Self.managedDeviceLabel)
            refreshClientAuthStatus()
            if appMode == .managed { await refreshUsage() }
            return true
        } catch {
            managedEnrollmentError = error.localizedDescription
            refreshClientAuthStatus()
            return false
        }
    }

    /// Move this enrolled device to another account with that account's recovery key.
    /// Unlike restore this never signs the device out: usage, integrations, and the device
    /// id are untouched, and a Pro plan on the destination account applies here at once.
    func attachManagedDevice(recoveryKey: String) async -> Bool {
        guard !ScreenshotMode.isActive else { return true }
        managedEnrollmentError = nil
        do {
            _ = try await ClientAuthManager.shared.attachToAccount(recoveryKeyInput: recoveryKey)
            refreshClientAuthStatus()
            await loadManagedDevices()
            if appMode == .managed { await refreshUsage() }
            return true
        } catch {
            managedEnrollmentError = error.localizedDescription
            refreshClientAuthStatus()
            return false
        }
    }

    /// Pro on this device because another device on the account holds the subscription.
    var isProViaAccount: Bool { usageInfo?.isProViaAccount ?? false }

    func revealRecoveryKey() -> String? {
        ClientAuthManager.shared.revealRecoveryKey()
    }

    /// The person confirmed the key is saved (or chose to stop being reminded).
    func acknowledgeRecoveryKey() {
        ClientAuthManager.shared.markRecoveryKeyAcknowledged()
        refreshClientAuthStatus()
    }

    /// Hide the nudge until the next launch.
    func snoozeRecoveryKeyNotice() {
        recoveryKeyNoticeSnoozed = true
        refreshClientAuthStatus()
    }

    func rotateManagedRecoveryKey() async -> String? {
        do {
            let key = try await ClientAuthManager.shared.rotateRecoveryKey()
            refreshClientAuthStatus()
            return key
        } catch {
            managedEnrollmentError = error.localizedDescription
            refreshClientAuthStatus()
            return nil
        }
    }

    func loadManagedDevices() async {
        guard clientAuthStatus.isEnrolled, !ScreenshotMode.isActive else { return }
        do {
            let list = try await ClientAuthManager.shared.listDevices()
            managedDevices = list.devices
            managedDevicesError = nil
        } catch {
            managedDevicesError = error.localizedDescription
            refreshClientAuthStatus()
        }
    }

    func removeManagedDevice(installationID: String) async -> Bool {
        do {
            try await ClientAuthManager.shared.removeDevice(installationID: installationID)
            refreshClientAuthStatus()
            if clientAuthStatus.isEnrolled { await loadManagedDevices() } else { managedDevices = [] }
            return true
        } catch {
            managedDevicesError = error.localizedDescription
            refreshClientAuthStatus()
            return false
        }
    }

    func signOutManagedDevice() async {
        try? await ClientAuthManager.shared.signOut()
        managedDevices = []
        usageInfo = nil
        refreshClientAuthStatus()
    }

    /// Delete the anonymous account. Revokes every device; subscriptions are untouched.
    func deleteManagedAccount() async -> Bool {
        do {
            try await ClientAuthManager.shared.deleteAccount()
            managedDevices = []
            usageInfo = nil
            refreshClientAuthStatus()
            return true
        } catch {
            managedEnrollmentError = error.localizedDescription
            refreshClientAuthStatus()
            return false
        }
    }

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
        guard !ScreenshotMode.isActive else { return }
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
            let key = SelectableAttributed.displayGroupKey(speaker: segment.speaker, names: names, selfIDs: liveSpeakerLabelSelfIDs)
            if key != currentKey {
                currentKey = key
                md += "\n**\(resolvedSpeakerLabel(for: segment.speaker, names: names, selfIDs: liveSpeakerLabelSelfIDs)):**\n"
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

        // Template sections if available (always included, like MEDDPICC)
        if let template = insightTemplate(id: liveTemplateID) {
            md += InsightTemplateSections.markdown(template: template, sections: liveTemplateSections)
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trainingMetricsAsMarkdown() -> String {
        guard let metrics = trainingMetrics, !metrics.speakers.isEmpty else { return "" }

        var md = "## Coaching\n\n"
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

        // A meeting can export more than once (goHome, then again when final insights land).
        // If the AI title changed between exports the filename changes too; remove the stale
        // file so one meeting never leaves two exports behind.
        if let previous = lastExportedMarkdownFilenames[meeting.id], previous != filename {
            try? fm.removeItem(at: folderURL.appendingPathComponent(previous))
            DebugLogger.shared.log(.app, "Markdown export: removed stale export after title change")
        }

        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            lastExportedMarkdownFilenames[meeting.id] = filename
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
        index += "coaching metrics (filler words, pace, talk ratio, clarity), and the full transcript.\n\n"
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

    static let smartMeetingNotificationCategory = "miniti.smart-meeting"
    static let smartMeetingEndAction = "miniti.smart.end"
    static let smartMeetingEndAndStartAction = "miniti.smart.end-and-start"
    static let smartMeetingKeepAction = "miniti.smart.keep"
    static let smartMeetingTakeNotesAction = "miniti.smart.take-notes"
    static let smartMeetingNotNowAction = "miniti.smart.not-now"
    static let smartMeetingEndNowAction = "miniti.smart.end-now"

    static let meetingReminderNotificationCategory = "miniti.meeting-reminder"
    static let meetingReminderWithLinkCategory = "miniti.meeting-reminder.with-link"
    static let meetingReminderNotesOnlyCategory = "miniti.meeting-reminder.notes-only"
    static let meetingReminderPrimaryAction = "miniti.meeting-reminder.primary"
    static let meetingReminderNotNowAction = "miniti.meeting-reminder.not-now"

    static func registerSmartMeetingNotificationCategory() {
        let endAndStart = UNNotificationAction(
            identifier: smartMeetingEndAndStartAction,
            title: "End & start next"
        )
        let end = UNNotificationAction(
            identifier: smartMeetingEndAction,
            title: "End meeting"
        )
        let keep = UNNotificationAction(
            identifier: smartMeetingKeepAction,
            title: "Keep recording"
        )
        let takeNotes = UNNotificationAction(
            identifier: smartMeetingTakeNotesAction,
            title: "Take notes"
        )
        let notNow = UNNotificationAction(
            identifier: smartMeetingNotNowAction,
            title: "Not now"
        )
        let endNow = UNNotificationAction(
            identifier: smartMeetingEndNowAction,
            title: "End now"
        )
        let calendarCategory = UNNotificationCategory(
            identifier: smartMeetingNotificationCategory + ".calendar",
            actions: [endAndStart, end, keep],
            intentIdentifiers: []
        )
        let quietCategory = UNNotificationCategory(
            identifier: smartMeetingNotificationCategory + ".quiet",
            actions: [end, keep],
            intentIdentifiers: []
        )
        let callStartCategory = UNNotificationCategory(
            identifier: smartMeetingNotificationCategory + ".call-start",
            actions: [takeNotes, notNow],
            intentIdentifiers: []
        )
        let callTransitionCategory = UNNotificationCategory(
            identifier: smartMeetingNotificationCategory + ".call-transition",
            actions: [endAndStart, keep],
            intentIdentifiers: []
        )
        let callGraceCategory = UNNotificationCategory(
            identifier: smartMeetingNotificationCategory + ".call-grace",
            actions: [keep, endNow],
            intentIdentifiers: []
        )
        // `.foreground`: these actions start a recording and (with a link) open a
        // URL. On iOS a background-delivered action cannot reliably open a URL or
        // begin capture; on macOS it brings the app forward like the body tap does.
        let reminderJoin = UNNotificationAction(
            identifier: meetingReminderPrimaryAction,
            title: "Join and take notes",
            options: [.foreground]
        )
        let reminderTakeNotes = UNNotificationAction(
            identifier: meetingReminderPrimaryAction,
            title: "Take notes",
            options: [.foreground]
        )
        let reminderNotNow = UNNotificationAction(
            identifier: meetingReminderNotNowAction,
            title: "Not now"
        )
        let reminderWithLinkCategory = UNNotificationCategory(
            identifier: meetingReminderWithLinkCategory,
            actions: [reminderJoin, reminderNotNow],
            intentIdentifiers: []
        )
        let reminderNotesOnlyCategory = UNNotificationCategory(
            identifier: meetingReminderNotesOnlyCategory,
            actions: [reminderTakeNotes, reminderNotNow],
            intentIdentifiers: []
        )
        // One installation call: categories not in this set are clobbered.
        UNUserNotificationCenter.current().setNotificationCategories([
            calendarCategory, quietCategory, callStartCategory, callTransitionCategory, callGraceCategory,
            reminderWithLinkCategory, reminderNotesOnlyCategory
        ])
    }

    private func sendSmartMeetingNotificationIfNeeded(_ prompt: SmartMeetingPrompt) {
        guard smartMeetingsEnabled else { return }
        #if os(macOS)
        guard MacNotificationRoutingPolicy.shouldMirrorToSystem(
            isAppActive: isAppInForeground(),
            recordingIndicatorEnabled: showRecordingIndicator
        ) else { return }
        #else
        guard !isAppInForeground() else { return }
        #endif
        let identifier = "miniti.smart-meeting.\(prompt.id)"
        let title = prompt.title
        let message = prompt.message
        let eventID = prompt.eventID
        let categorySuffix: String
        switch prompt.kind {
        case .calendar: categorySuffix = ".calendar"
        case .quiet, .callEnd: categorySuffix = ".quiet"
        case .callStart: categorySuffix = ".call-start"
        case .callTransition: categorySuffix = ".call-transition"
        }
        let category = Self.smartMeetingNotificationCategory + categorySuffix

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = .default
            content.categoryIdentifier = category
            if let eventID {
                content.userInfo = ["eventID": eventID]
            }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            ) { error in
                if let error {
                    DebugLogger.shared.log(.app, "Smart meeting notification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func clearSmartMeetingNotification() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix("miniti.smart-meeting.") }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix("miniti.smart-meeting.") }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func handleSmartMeetingNotificationAction(
        _ actionIdentifier: String,
        eventID: String?
    ) {
        switch actionIdentifier {
        case Self.smartMeetingEndAndStartAction:
            if let eventID {
                endAndStartCalendarMeeting(eventID: eventID)
            } else {
                endAndStartNewMeeting()
            }
        case Self.smartMeetingEndAction:
            endMeetingFromSmartPrompt()
        case Self.smartMeetingKeepAction:
            #if os(macOS)
            if endingGrace != nil {
                keepRecordingFromEndingGrace()
                return
            }
            #endif
            if let eventID {
                dismissedAutoStartEventIDs.insert(eventID)
                clearSmartMeetingPrompt()
            } else {
                keepRecordingFromSmartMeetingPrompt()
            }
        #if os(macOS)
        case Self.smartMeetingTakeNotesAction:
            startMeetingFromDetectedCall()
        case Self.smartMeetingNotNowAction:
            dismissDetectedCallStartPrompt()
        case Self.smartMeetingEndNowAction:
            endEndingGraceNow()
        #endif
        default:
            break
        }
    }

    /// Routes notification taps/actions. Reminder body taps act like the primary action;
    /// smart-meeting body taps still only raise the window (handled by the delegate).
    func handleNotificationResponse(
        actionIdentifier: String,
        categoryIdentifier: String,
        eventID: String?
    ) {
        if categoryIdentifier == Self.meetingReminderWithLinkCategory
            || categoryIdentifier == Self.meetingReminderNotesOnlyCategory
            || categoryIdentifier.hasPrefix(Self.meetingReminderNotificationCategory) {
            let effective = actionIdentifier == UNNotificationDefaultActionIdentifier
                ? Self.meetingReminderPrimaryAction
                : actionIdentifier
            handleMeetingReminderNotificationAction(effective, eventID: eventID)
            return
        }
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            return
        }
        handleSmartMeetingNotificationAction(actionIdentifier, eventID: eventID)
    }

    func handleMeetingReminderNotificationAction(
        _ actionIdentifier: String,
        eventID: String?
    ) {
        switch actionIdentifier {
        case Self.meetingReminderPrimaryAction:
            guard let eventID else {
                DebugLogger.shared.log(.app, "Meeting reminder primary action missing eventID")
                return
            }
            guard let event = upcomingEvents.first(where: { $0.id == eventID }) else {
                // A reminder tapped on a cold launch arrives before the first calendar
                // refresh has filled `upcomingEvents`. Hold the intent for that one
                // refresh instead of dropping it.
                if upcomingEvents.isEmpty, googleCalendarEnabled, isGoogleCalendarConnected {
                    DebugLogger.shared.log(.app, "Meeting reminder for \(eventID) deferred until the calendar refreshes")
                    pendingReminderJoinEventID = eventID
                    Task { await fetchUpcomingEvents() }
                } else {
                    DebugLogger.shared.log(.app, "Meeting reminder event \(eventID) is no longer available")
                }
                return
            }
            joinAndStartMeeting(from: event)
        case Self.meetingReminderNotNowAction:
            guard let eventID else { return }
            dismissedAutoStartEventIDs.insert(eventID)
            if pendingAutoStartEvent?.id == eventID {
                cancelAutoStartCountdown()
            }
            DebugLogger.shared.log(.app, "Meeting reminder dismissed: \(eventID)")
        default:
            break
        }
    }

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

    #if os(macOS)
    func presentRecordingNudge(
        _ nudge: RecordingNudge,
        duration: TimeInterval = AppState.recordingNudgeDuration
    ) {
        // Ending and transition decisions always outrank coaching guidance. The nudge is
        // deliberately ephemeral and never delays or mutates recording state.
        guard isRecording, smartMeetingPrompt == nil, endingGrace == nil else { return }
        recordingNudgeDismissTask?.cancel()
        recordingNudge = nudge
        let nudgeID = nudge.id
        recordingNudgeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self?.recordingNudge?.id == nudgeID else { return }
            self?.clearRecordingNudge()
        }
    }

    func dismissRecordingNudge() {
        clearRecordingNudge()
    }


    private func clearRecordingNudge() {
        recordingNudgeDismissTask?.cancel()
        recordingNudgeDismissTask = nil
        if recordingNudge != nil {
            recordingNudge = nil
        }
    }
    #endif

    /// "Don't remind me about these" from a nudge card: turns off that nudge kind's
    /// setting (the same toggle in Settings → Notifications, where it can be re-enabled)
    /// and dismisses the current card.
    func disableNudges(ofKind kind: RecordingNudge.Kind) {
        switch kind {
        case .question: notifyOnIncisiveQuestions = false
        case .monologue: notifyOnMonologue = false
        case .fillerRate: notifyOnHighFillerRate = false
        case .salesDetected: notifyOnSalesDetection = false
        }
        #if os(macOS)
        clearRecordingNudge()
        #endif
        DebugLogger.shared.log(.app, "Nudge kind disabled from card: \(kind)")
    }

    /// Primary action on the sales-detection nudge: turn on Sales (MEDDPICC) analysis
    /// and switch the insights view to it, exactly as the specialist insights menu does.
    func enableSalesAnalysisFromNudge() {
        setInsightModeEnabled(.meddpicc, enabled: true)
        insightsMode = .meddpicc
        #if os(macOS)
        clearRecordingNudge()
        #endif
        DebugLogger.shared.log(.app, "Sales analysis enabled from detection nudge")
    }

    /// Accumulate sales-vocabulary evidence from one finalized segment and suggest
    /// enabling Sales analysis once per meeting when it looks like a sales call.
    /// Cheap: a bounded phrase scan of the single new segment, no transcript re-reads.
    private func evaluateSalesDetection(for text: String) {
        guard notifyOnSalesDetection, !salesDetectionNudgeFired, !salesInsightsEnabled else { return }
        let matches = Self.salesSignalMatches(in: text)
        if !matches.isEmpty {
            salesDetectionSignalsSeen.formUnion(matches)
        }
        guard salesDetectionSignalsSeen.count >= Self.salesDetectionMinDistinctSignals else { return }
        // Consume the once-per-meeting shot only when a surface actually accepted the
        // alert — iOS declines foreground delivery, so the suggestion stays pending
        // and lands when the app is next in the background.
        let delivered = deliverLiveRecordingAlert(
            identifier: "miniti.nudge.sales.\(UUID().uuidString)",
            kind: .salesDetected,
            title: "sales conversation?",
            body: "this sounds like a sales call — enable live Sales (MEDDPICC) analysis for this meeting?"
        )
        guard delivered else { return }
        salesDetectionNudgeFired = true
        DebugLogger.shared.log(.app, "Sales detection nudge fired: signals=\(salesDetectionSignalsSeen.sorted())")
    }

    /// Routes live questions/coaching without assuming that a frontmost Miniti window
    /// proves the relevant information is visible. On macOS the floating recording
    /// surface is primary while Miniti is active; Notification Center remains the
    /// background and disabled-surface fallback. iOS preserves its background-only rule.
    @discardableResult
    private func deliverLiveRecordingAlert(
        identifier: String,
        kind: RecordingNudge.Kind,
        title: String,
        body: String
    ) -> Bool {
        #if os(macOS)
        if MacNotificationRoutingPolicy.shouldUseFloatingNudge(
            isAppActive: isAppInForeground(),
            recordingIndicatorEnabled: showRecordingIndicator
        ) {
            presentRecordingNudge(
                RecordingNudge(id: identifier, kind: kind, title: title, message: body)
            )
            return true
        }
        #else
        guard !isAppInForeground() else { return false }
        #endif

        sendLocalNudge(identifier: identifier, title: title, body: body)
        return true
    }

    private func notifyNewHighPriorityQuestions(_ questions: [SuggestedQuestion]) {
        guard notifyOnIncisiveQuestions else { return }
        guard isRecording else { return }

        let newHighs = questions.filter { $0.isHighPriority && !notifiedQuestionIDs.contains($0.id) }
        guard let question = newHighs.first else { return }

        if let last = lastQuestionNotificationAt,
           Date().timeIntervalSince(last) < Self.questionNotificationMinInterval {
            // Still mark as seen so we don't surface them later once the cooldown lifts.
            for q in newHighs { notifiedQuestionIDs.insert(q.id) }
            return
        }

        guard deliverLiveRecordingAlert(
            identifier: "miniti.question.\(UUID().uuidString)",
            kind: .question,
            title: "incisive question",
            body: question.question
        ) else { return }

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
            content.userInfo = ["eventID": event.id]
            content.categoryIdentifier = event.joinURL != nil
                ? Self.meetingReminderWithLinkCategory
                : Self.meetingReminderNotesOnlyCategory

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

    // MARK: - User-triggered investigations

    var canInvestigateCurrentConversation: Bool {
        !liveSegments.isEmpty
    }

    #if os(macOS)
    var investigationCodebaseFolderName: String? {
        guard !investigationCodebaseBookmark.isEmpty,
              let url = try? Self.resolveCodebaseBookmark(investigationCodebaseBookmark) else { return nil }
        return url.lastPathComponent
    }

    func setInvestigationCodebaseFolder(_ url: URL) throws {
        investigationCodebaseBookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func clearInvestigationCodebaseFolder() {
        investigationCodebaseBookmark = Data()
    }
    #endif

    func dismissInvestigationSuggestion() {
        guard let suggestion = investigationSuggestion else { return }
        dismissedInvestigationSuggestionIDs.insert(suggestion.id)
        investigationSuggestion = nil
    }

    func triggerInvestigation(
        scope: InvestigationScope,
        focus: String? = nil
    ) {
        guard canInvestigateCurrentConversation else { return }
        activeInvestigationScope = scope
        activeInvestigationFocus = focus
            ?? investigationSuggestion?.focus
            ?? liveSegments.last?.text
            ?? "Investigate the main unresolved question in this conversation."
        investigationResult = nil
        investigationError = nil
        isInvestigationPresented = true
        dismissInvestigationSuggestion()
        startInvestigationTask()
    }

    func refreshInvestigation() {
        guard isInvestigationPresented, !activeInvestigationFocus.isEmpty else { return }
        startInvestigationTask()
    }

    func dismissInvestigation() {
        activeInvestigationTask?.cancel()
        activeInvestigationTask = nil
        investigationRequestID = nil
        isGeneratingInvestigation = false
        isInvestigationPresented = false
    }

    private func resetInvestigationState() {
        activeInvestigationTask?.cancel()
        activeInvestigationTask = nil
        investigationRequestID = nil
        investigationSuggestion = nil
        investigationResult = nil
        investigationError = nil
        isGeneratingInvestigation = false
        isInvestigationPresented = false
        activeInvestigationScope = .web
        activeInvestigationFocus = ""
        lastInvestigationEvaluatedFinalSegmentID = nil
        dismissedInvestigationSuggestionIDs = []
    }

    private func startInvestigationTask() {
        activeInvestigationTask?.cancel()
        let requestID = UUID()
        investigationRequestID = requestID
        isGeneratingInvestigation = false
        activeInvestigationTask = Task { @MainActor [weak self] in
            await self?.fetchInvestigation(requestID: requestID)
        }
    }

    private func fetchInvestigation(requestID: UUID) async {
        guard investigationRequestID == requestID else { return }
        let meetingIDAtRequest = currentMeeting?.id
        let scope = activeInvestigationScope
        let focus = activeInvestigationFocus
        let meetingContext = Self.investigationMeetingContext(
            meetingTitle: currentMeeting?.displayTitle ?? "Meeting",
            prepNotes: liveNotes,
            segments: liveSegments
        )
        guard !meetingContext.isEmpty else {
            investigationError = "not enough speech captured yet"
            return
        }

        isGeneratingInvestigation = true
        investigationError = nil

        var codebaseContext: String?
        var referencedFiles: [String] = []
        #if os(macOS)
        if scope == .codebase {
            guard !investigationCodebaseBookmark.isEmpty else {
                investigationError = "choose a codebase folder in Settings → AI & Models first"
                isGeneratingInvestigation = false
                return
            }
            let bookmark = investigationCodebaseBookmark
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let rootURL = try Self.resolveCodebaseBookmark(bookmark)
                    guard rootURL.startAccessingSecurityScopedResource() else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    defer { rootURL.stopAccessingSecurityScopedResource() }
                    return try Self.buildCodebaseSnapshot(rootURL: rootURL, focus: focus)
                }.value
                guard investigationRequestID == requestID, !Task.isCancelled else { return }
                codebaseContext = snapshot.context
                referencedFiles = snapshot.files
                guard !snapshot.context.isEmpty else {
                    investigationError = "no relevant readable source files were found in that folder"
                    isGeneratingInvestigation = false
                    return
                }
            } catch {
                guard investigationRequestID == requestID, !Task.isCancelled else { return }
                investigationError = "couldn't read the selected codebase — choose it again in Settings"
                isGeneratingInvestigation = false
                return
            }
        }
        #elseif os(iOS)
        if scope == .codebase {
            investigationError = "codebase investigation is available on macOS"
            isGeneratingInvestigation = false
            return
        }
        #endif

        do {
            let result: InvestigationResult
            if appMode == .managed {
                guard let minitiAPIService else {
                    investigationError = "Miniti's OpenAI service isn't available — try again"
                    isGeneratingInvestigation = false
                    return
                }
                result = try await minitiAPIService.generateInvestigation(
                    deviceId: DeviceIdentifier.getOrCreateDeviceId(),
                    focus: focus,
                    meetingContext: meetingContext,
                    scope: scope,
                    codebaseContext: codebaseContext,
                    referencedFiles: referencedFiles,
                    model: OpenAIModel.gpt54Mini.rawValue,
                    language: meetingLanguage
                )
            } else {
                guard let insightsService, !openaiApiKey.isEmpty else {
                    investigationError = "openai api key required in settings"
                    isGeneratingInvestigation = false
                    return
                }
                result = try await insightsService.generateInvestigation(
                    focus: focus,
                    meetingContext: meetingContext,
                    scope: scope,
                    codebaseContext: codebaseContext,
                    referencedFiles: referencedFiles,
                    model: .gpt54Mini,
                    apiKey: openaiApiKey,
                    language: meetingLanguage
                )
            }

            guard investigationRequestID == requestID,
                  !Task.isCancelled,
                  currentMeeting?.id == meetingIDAtRequest else {
                isGeneratingInvestigation = false
                return
            }
            if result.isEmpty {
                investigationError = "OpenAI returned no investigation result — try again"
            } else {
                investigationResult = result
            }
        } catch {
            guard investigationRequestID == requestID,
                  !Task.isCancelled,
                  !(error is CancellationError) else {
                isGeneratingInvestigation = false
                return
            }
            investigationError = "couldn't investigate — \(error.localizedDescription.lowercased())"
            enqueueDiagnosticEvent(
                "insights_investigation_failed",
                category: .insights,
                level: .warning,
                details: ["scope": scope.rawValue, "error": error.localizedDescription]
            )
        }
        if investigationRequestID == requestID {
            isGeneratingInvestigation = false
        }
    }

    private func evaluateInvestigationSuggestion() {
        guard isRecording,
              let lastFinal = liveSegments.last,
              lastFinal.id != lastInvestigationEvaluatedFinalSegmentID else { return }
        lastInvestigationEvaluatedFinalSegmentID = lastFinal.id

        var inspected = 0
        for segment in liveSegments.reversed() {
            guard segment.isFinal else { continue }
            inspected += 1
            if !dismissedInvestigationSuggestionIDs.contains(segment.id),
               let focus = Self.investigationFocus(from: segment.text) {
                investigationSuggestion = InvestigationSuggestion(id: segment.id, focus: focus)
                return
            }
            if inspected >= 6 { break }
        }
    }

    nonisolated static func investigationFocus(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }
        let normalized = trimmed.lowercased()

        let explicitPhrases = [
            "investigate", "research", "look into", "find out", "check whether",
            "figure out", "verify whether", "is it possible", "would it be possible",
            "what would it take", "would be cool if"
        ]
        let capabilityPhrases = [
            "can we build", "could we build", "can we implement", "could we implement",
            "can we integrate", "could we integrate", "can we automate", "could we automate",
            "can we support", "could we support", "can we fix", "could we fix",
            "is there a way", "is there some way"
        ]
        let diagnosticTerms = [
            "why does", "why is", "how could", "how can", "what causes",
            "feasible", "feasibility", "possible", "tradeoff", "cost", "impact"
        ]
        let looksExplicit = explicitPhrases.contains { normalized.contains($0) }
            || capabilityPhrases.contains { normalized.contains($0) }
        let looksDiagnostic = (normalized.contains("?") || normalized.hasPrefix("why") || normalized.hasPrefix("how"))
            && diagnosticTerms.contains { normalized.contains($0) }
        guard looksExplicit || looksDiagnostic else { return nil }
        return String(trimmed.prefix(280))
    }

    nonisolated static func investigationMeetingContext(
        meetingTitle: String,
        prepNotes: String,
        segments: [LiveSegment],
        maxCharacters: Int = 11_500
    ) -> String {
        let contextBudget = max(1_000, maxCharacters - 1_000)
        let perTurnLimit = min(2_500, max(500, contextBudget / 2))
        var recentLines: [String] = []
        var recentCharacterCount = 0

        for segment in segments.reversed() {
            guard segment.isFinal else { continue }
            let label = segment.speakerLabel
            let line = String("\(label): \(segment.text)".prefix(perTurnLimit))
            if !recentLines.isEmpty, recentCharacterCount + line.count > contextBudget { break }
            recentLines.append(line)
            recentCharacterCount += line.count + 1
            if recentLines.count >= 14 { break }
        }

        let trimmedPrep = prepNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        var context = "Meeting title\n\(meetingTitle)"
        if !trimmedPrep.isEmpty {
            context += "\n\nMeeting prep notes\n\(String(trimmedPrep.prefix(2_000)))"
        }
        if !recentLines.isEmpty {
            context += "\n\nRecent conversation\n\(recentLines.reversed().joined(separator: "\n"))"
        }
        return String(context.prefix(maxCharacters))
    }

    #if os(macOS)
    nonisolated private static func resolveCodebaseBookmark(_ data: Data) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    nonisolated static func buildCodebaseSnapshot(
        rootURL: URL,
        focus: String,
        maxCharacters: Int = 40_000,
        maxFiles: Int = 8
    ) throws -> CodebaseSnapshot {
        let allowedExtensions = Set([
            "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp",
            "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "kts",
            "rb", "php", "cs", "sql", "graphql", "json", "yaml", "yml", "toml", "md"
        ])
        let excludedDirectories = Set([
            ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods", "vendor", "dist", "build"
        ])
        let stopWords = Set([
            "could", "would", "should", "there", "their", "about", "which", "this", "that",
            "with", "from", "have", "what", "when", "where", "into", "some", "investigate"
        ])
        let tokens = Set(
            focus.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )

        struct Candidate {
            let relativePath: String
            let content: String
            let score: Int
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return CodebaseSnapshot(context: "", files: []) }

        var candidates: [Candidate] = []
        var inspectedFiles = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if excludedDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  allowedExtensions.contains(fileURL.pathExtension.lowercased()),
                  (values?.fileSize ?? 0) <= 300_000 else { continue }
            inspectedFiles += 1
            if inspectedFiles > 1_200 { break }

            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                  let content = String(data: data, encoding: .utf8) else { continue }
            let relativePath = String(fileURL.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lowerPath = relativePath.lowercased()
            let lowerContent = content.lowercased()
            var score = 0
            for token in tokens {
                if lowerPath.contains(token) { score += 12 }
                if lowerContent.contains(token) { score += 3 }
            }
            if ["readme.md", "agents.md", "package.json", "project.yml"].contains(lowerPath) {
                score += 1
            }
            guard score > 0 else { continue }
            candidates.append(Candidate(relativePath: relativePath, content: content, score: score))
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.relativePath < $1.relativePath
        }

        var blocks: [String] = []
        var files: [String] = []
        var usedCharacters = 0
        for candidate in candidates.prefix(maxFiles) {
            let excerpt = redactLikelySecrets(
                relevantCodeExcerpt(candidate.content, tokens: tokens, maxCharacters: 5_000)
            )
            let block = "FILE: \(candidate.relativePath)\n\(excerpt)"
            if !blocks.isEmpty, usedCharacters + block.count > maxCharacters { break }
            blocks.append(block)
            files.append(candidate.relativePath)
            usedCharacters += block.count + 2
        }
        return CodebaseSnapshot(context: blocks.joined(separator: "\n\n"), files: files)
    }

    nonisolated private static func relevantCodeExcerpt(
        _ content: String,
        tokens: Set<String>,
        maxCharacters: Int
    ) -> String {
        guard content.count > maxCharacters else { return content }
        let lower = content.lowercased()
        let positions = tokens.compactMap { lower.range(of: $0)?.lowerBound }
        guard let first = positions.min() else { return String(content.prefix(maxCharacters)) }
        let offset = lower.distance(from: lower.startIndex, to: first)
        let startOffset = max(0, offset - maxCharacters / 3)
        let start = content.index(content.startIndex, offsetBy: startOffset)
        return String(content[start...].prefix(maxCharacters))
    }

    nonisolated static func redactLikelySecrets(_ content: String) -> String {
        let sensitiveAssignment = try? NSRegularExpression(
            pattern: #"(?im)^(\s*(?:(?:let|var|const|static\s+let|static\s+var)\s+)?[\"']?[A-Za-z0-9_.-]*(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|private[_-]?key|token|secret)[\"']?\s*[:=]\s*)[^\r\n,}]+"#
        )
        let privateKeyBlock = try? NSRegularExpression(
            pattern: #"(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----"#
        )

        var redacted = content
        if let sensitiveAssignment {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = sensitiveAssignment.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "$1[REDACTED]"
            )
        }
        if let privateKeyBlock {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = privateKeyBlock.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "[REDACTED PRIVATE KEY]"
            )
        }
        return redacted
    }
    #endif

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
        #if os(macOS)
        clearRecordingNudge()
        #endif
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

        // iOS keeps its existing background-only notification behavior. macOS routes
        // foreground guidance through the floating recording surface instead.
        #if os(iOS)
        if isAppInForeground() { return }
        #endif

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

        _ = deliverLiveRecordingAlert(
            identifier: "miniti.nudge.monologue.\(UUID().uuidString)",
            kind: .monologue,
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
            fillerCount += TrainingMetrics.countFillerOccurrences(of: fillers, in: tokens).reduce(0, +)
        }
        guard sawAnyWindowSegment else { return }

        guard youWordCount >= Self.fillerWindowMinYouWords else { return }
        let windowMinutes = max(Self.fillerWindowSeconds / 60.0, 0.01)
        let fillersPerMinute = Double(fillerCount) / windowMinutes
        guard fillersPerMinute >= Self.fillerNudgeMinFillersPerMinute else { return }

        _ = deliverLiveRecordingAlert(
            identifier: "miniti.nudge.filler.\(UUID().uuidString)",
            kind: .fillerRate,
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
