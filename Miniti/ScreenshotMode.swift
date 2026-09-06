import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Screenshot mode
//
// Deterministic "screenshot mode" for the marketing capture pipeline in
// scripts/screenshots/. Debug builds only. Launch the app with
//
//     -MinitiScreenshotScene <scene>
//
// and it renders that scene from a seeded in-memory store with no microphone,
// Deepgram, OpenAI, calendar, or backend traffic:
//
// - the terms / onboarding / force-update gates are bypassed through volatile
//   UserDefaults overrides (the argument domain), so nothing is persisted;
// - History, Coaching, and saved-meeting detail read a fixed set of meetings
//   seeded into an in-memory SwiftData container;
// - the recording-* scenes put AppState into a live-recording state with a canned
//   transcript, speaker names, insights, questions, coaching metrics, and MEDDPICC;
// - on macOS the app sizes its own window, writes the window image to its
//   container's temporary directory, restores the user's defaults, and exits.
//
// Scene names must match scripts/screenshots/env.sh. See scripts/screenshots/README.md.

enum ScreenshotScene: String, CaseIterable {
    case home
    /// macOS only: transcript + notes + live insights in one window.
    case recording
    case recordingTranscript = "recording-transcript"
    case recordingInsights = "recording-insights"
    case recordingSales = "recording-sales"
    case recordingQuestions = "recording-questions"
    case recordingCoaching = "recording-coaching"
    case recordingTemplate = "recording-template"
    case coaching
    case coachingStats = "coaching-stats"
    case history
    case meeting
    /// Saved meeting detail with the coaching view selected.
    case meetingCoaching = "meeting-coaching"
    case settings
    /// Settings with the Account & Plan destination selected (managed account section).
    case settingsAccount = "settings-account"

    var isLiveRecording: Bool {
        switch self {
        case .recording, .recordingTranscript, .recordingInsights,
             .recordingSales, .recordingQuestions, .recordingCoaching, .recordingTemplate:
            return true
        default:
            return false
        }
    }

    var insightsMode: InsightsMode {
        switch self {
        case .recordingSales: return .meddpicc
        case .recordingQuestions: return .questions
        case .recordingCoaching, .meetingCoaching: return .training
        case .recordingTemplate: return .template
        default: return .standard
        }
    }

    var showsCoachingOverview: Bool {
        self == .coaching || self == .coachingStats
    }

    /// Scenes that open the seeded saved meeting's detail screen.
    var opensSavedMeeting: Bool {
        self == .meeting || self == .meetingCoaching
    }

    var coachingOverviewTab: CoachingOverviewTab {
        self == .coachingStats ? .stats : .focus
    }

    /// The iOS meeting screen section (transcript / insights / notes) the scene wants.
    var wantsInsightsSection: Bool {
        switch self {
        case .recordingInsights, .recordingSales, .recordingQuestions, .recordingCoaching, .recordingTemplate, .meeting, .meetingCoaching:
            return true
        default:
            return false
        }
    }
}

enum ScreenshotMode {
    static let sceneDefaultsKey = "MinitiScreenshotScene"
    static let settleDefaultsKey = "MinitiScreenshotSettleSeconds"
    static let macWindowSize = CGSize(width: 1440, height: 900)

    /// Seconds to wait after the window is sized before the macOS capture (launch
    /// argument -MinitiScreenshotSettleSeconds). Some destinations prewarm content.
    static var settleSeconds: TimeInterval {
        let value = UserDefaults.standard.double(forKey: settleDefaultsKey)
        return value > 0 ? value : 3
    }

    nonisolated(unsafe) static var levelTimer: Timer?

    /// Fixed IDs so scripts and views can find the seeded meetings.
    static let liveMeetingID = UUID(uuidString: "6D3B5F0A-0000-4000-8000-000000000001")!
    static let savedMeetingID = UUID(uuidString: "6D3B5F0A-0000-4000-8000-000000000002")!

    /// The active scene, or nil outside screenshot mode. Resolving it installs the
    /// UserDefaults overrides, so touch it before anything reads @AppStorage.
    static let current: ScreenshotScene? = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: sceneDefaultsKey),
              let scene = ScreenshotScene(rawValue: raw) else { return nil }
        installDefaultsOverrides(for: scene)
        return scene
        #else
        return nil
        #endif
    }()

    static var isActive: Bool { current != nil }

    private(set) nonisolated(unsafe) static var seededContainer: ModelContainer?
    private nonisolated(unsafe) static var savedPersistentDefaults: [String: Any]?

    // MARK: Defaults

    /// Gate and setting values every scene needs, installed in the volatile argument
    /// domain so they win over persisted values and are never written to disk.
    private static func installDefaultsOverrides(for scene: ScreenshotScene) {
        let defaults = UserDefaults.standard
        #if os(macOS)
        if let bundleID = Bundle.main.bundleIdentifier {
            savedPersistentDefaults = defaults.persistentDomain(forName: bundleID) ?? [:]
        }
        #endif
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let overrides: [String: Any] = [
            "hasCompletedOnboarding": true,
            "acceptedTermsVersion": 1,
            "appMode": "managed",
            "salesInsightsEnabled": true,
            "templateInsightsEnabled": true,
            "insightTemplateID": "bant",
            "playbookInsightsEnabled": false,
            "googleCalendarEnabled": true,
            "calendarNudgeDismissedUntil": Date.distantFuture.timeIntervalSince1970,
            "smartMeetingsEnabled": true,
            "showRecordingIndicator": false,
            "autoInferSpeakerNames": true,
            "captureSystemAudio": true,
            "captureMicrophone": true,
            "defaultLanguage": "en",
            "interfaceScale": InterfaceScale.standard.rawValue,
            "mainWindow.sidebarCollapsed": false,
            "mainWindow.historyCollapsed": false,
            "mainWindow.insightsCollapsed": false,
            "selectedSettingsDestination": scene == .settingsAccount ? "account" : "general",
            "deepgramApiKey": "",
            "openaiApiKey": "",
            "webhookURL": "",
            "docsMCPURL": "",
            "shareDiagnostics": false,
            "autoExportMarkdown": false,
        ]
        for (key, value) in overrides where domain[key] == nil {
            domain[key] = value
        }
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// Put the user's persisted defaults back exactly as they were before this run.
    /// The app writes a few keys as a side effect of rendering (last settings
    /// destination, pane collapse state); this undoes them on macOS, where the Debug
    /// build shares its container with the installed app.
    static func restorePersistentDefaults() {
        #if os(macOS)
        guard let bundleID = Bundle.main.bundleIdentifier, let saved = savedPersistentDefaults else { return }
        UserDefaults.standard.setPersistentDomain(saved, forName: bundleID)
        UserDefaults.standard.synchronize()
        #endif
    }

    // MARK: Store

    /// An in-memory container seeded with the fixture meetings, or nil outside
    /// screenshot mode.
    static func makeSeededContainer(schema: Schema) -> ModelContainer? {
        guard isActive else { return nil }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            MainActor.assumeIsolated {
                let context = container.mainContext
                for meeting in ScreenshotFixtures.meetings() {
                    context.insert(meeting)
                }
                try? context.save()
            }
            seededContainer = container
            return container
        } catch {
            fatalError("Could not create screenshot ModelContainer: \(error)")
        }
    }

    // MARK: AppState

    /// Called at the end of AppState.init. Fills the published state the scene needs.
    @MainActor
    static func apply(to appState: AppState) {
        guard let scene = current else { return }

        appState.usageInfo = ScreenshotFixtures.usage()
        appState.isLoadingUsage = false
        // `-MinitiScreenshotRecoveryNudge YES` shows the save-your-key card on Home.
        let showNudge = UserDefaults.standard.bool(forKey: "MinitiScreenshotRecoveryNudge")
        appState.clientAuthStatus = ClientAuthStatus(
            isEnrolled: true, accountID: "acct_screenshot", deviceCap: 5,
            enrolledAt: ISO8601DateFormatter().string(from: Date()), enrollmentPath: "migrate",
            recoveryKeyAcknowledged: !showNudge, isHardwareBacked: true
        )
        if showNudge { appState.refreshClientAuthStatusForScreenshots() }
        appState.isGoogleCalendarConnected = true
        appState.googleCalendarEmail = ScreenshotFixtures.calendarEmail
        appState.upcomingEvents = ScreenshotFixtures.upcomingEvents()
        appState.insightsMode = scene.insightsMode

        if scene.isLiveRecording, let container = seededContainer {
            let id = liveMeetingID
            let meetings = (try? container.mainContext.fetch(FetchDescriptor<Meeting>())) ?? []
            if let meeting = meetings.first(where: { $0.id == id }) {
                ScreenshotFixtures.applyLiveRecording(meeting, to: appState)
            }
        }

        if scene.opensSavedMeeting {
            appState.pendingOpenSavedMeetingID = savedMeetingID
        }
        if scene == .settings || scene == .settingsAccount {
            #if os(iOS)
            appState.showSettings = true
            #endif
        }
        if scene == .settingsAccount {
            // Scroll the Account & Plan form to the managed-account section.
            appState.pendingSettingsSearchTarget = "account.recoveryKey"
        }
    }

    // MARK: macOS capture

    #if os(macOS)
    /// Where the macOS capture lands. The app is sandboxed, so this is inside its
    /// container: ~/Library/Containers/com.miniti.app/Data/tmp/.
    static func macOutputURL(for scene: ScreenshotScene) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("miniti-screenshot-\(scene.rawValue).png")
    }

    /// Waits for the main window, sizes it, renders the scene, writes the PNG, restores
    /// the user's defaults, and exits the process. Call from applicationDidFinishLaunching.
    @MainActor
    static func beginMacCapture(mainWindowIdentifier: NSUserInterfaceItemIdentifier) {
        guard let scene = current else { return }
        let output = macOutputURL(for: scene)
        try? FileManager.default.removeItem(at: output)

        Task { @MainActor in
            guard let main = await waitForWindow(timeout: 15, where: { window in
                window.identifier == mainWindowIdentifier && window.isVisible
            }) else {
                finish(success: false, message: "main window never appeared")
                return
            }
            placeForCapture(main, size: macWindowSize)
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(settleSeconds))

            var target = main
            if scene == .settings || scene == .settingsAccount {
                // The main window's scene bridge opens the Settings scene on appear.
                guard let settings = await waitForWindow(timeout: 10, where: { window in
                    window.isVisible && window !== main && window.styleMask.contains(.titled)
                }) else {
                    finish(success: false, message: "settings window never appeared")
                    return
                }
                placeForCapture(settings, size: settings.frame.size)
                settings.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(2))
                target = settings
            }

            // Frontmost at the moment of capture, so the window chrome is drawn active.
            NSApp.activate(ignoringOtherApps: true)
            target.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(400))
            let success = writeImage(of: target, to: output)
            finish(success: success, message: success ? "wrote \(output.path)" : "could not render \(output.path)")
        }
    }

    @MainActor
    private static func waitForWindow(timeout: TimeInterval, where predicate: (NSWindow) -> Bool) async -> NSWindow? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let window = NSApp.windows.first(where: predicate) { return window }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Centers the window on the sharpest display so the on-screen pixels are Retina.
    @MainActor
    private static func placeForCapture(_ window: NSWindow, size: CGSize) {
        let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) ?? NSScreen.main
        window.setContentSize(NSSize(width: size.width, height: size.height))
        if let screen {
            let visible = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        } else {
            window.center()
        }
    }

    @MainActor
    private static func writeImage(of window: NSWindow, to url: URL) -> Bool {
        // Prefer the real on-screen pixels: a process may image its own windows
        // without Screen Recording permission, and this includes content that offscreen
        // rendering skips (Swift Charts, some layer-backed views).
        window.displayIfNeeded()
        if let image = legacyWindowImage(windowNumber: CGWindowID(window.windowNumber)), image.width > 1 {
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]),
               (try? data.write(to: url, options: .atomic)) != nil {
                return true
            }
        }
        return writeOffscreenImage(of: window, to: url)
    }

    /// `CGWindowListCreateImage`, resolved at runtime. It is deprecated in favour of
    /// ScreenCaptureKit, which needs Screen Recording permission even for our own windows;
    /// the legacy call still images the app's own windows without a prompt. Debug-only.
    private static func legacyWindowImage(windowNumber: CGWindowID) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let function = unsafeBitCast(symbol, to: Fn.self)
        return function(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue()
    }

    @MainActor
    private static func writeOffscreenImage(of window: NSWindow, to url: URL) -> Bool {
        guard let content = window.contentView else { return false }
        // The theme frame (contentView's superview) includes the title bar area, so the
        // capture matches the window the user sees.
        let view = content.superview ?? content
        let bounds = view.bounds
        // Always render at 2x, whichever display the window landed on, so the capture
        // is the same size on a Retina laptop and a 1x external monitor.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return false }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private static func finish(success: Bool, message: String) {
        DebugLogger.shared.log(.app, "Screenshot mode: \(message)")
        restorePersistentDefaults()
        exit(success ? 0 : 1)
    }
    #endif
}

// MARK: - Fixtures

/// Plausible B2B content for the seeded store. No real customers or people.
enum ScreenshotFixtures {
    static let calendarEmail = "ian@miniti.app"
    static let micSpeaker = DeepgramService.micSpeakerID
    /// Remote speakers for the live discovery call.
    static let liveSpeakerNames: [String: String] = ["0": "Priya Raman", "1": "Marcus Lee"]
    static let liveDuration: TimeInterval = 25 * 60 + 23

    // MARK: Usage + calendar

    static func usage() -> MinitiAPIService.UsageInfo? {
        let resets = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date())
        let json = """
        {"minutes_used": 1240, "minutes_limit": 5000, "resets_at": "\(resets)", "tier": "pro", "subscription_status": "active"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MinitiAPIService.UsageInfo.self, from: Data(json.utf8))
    }

    static func upcomingEvents() -> [MinitiAPIService.CalendarEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // Round to the next quarter hour so the list reads like a real calendar.
        let quarter: TimeInterval = 15 * 60
        let now = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        func at(minutes: Int, length: Int) -> (String, String) {
            let start = now.addingTimeInterval(TimeInterval(minutes * 60))
            let end = start.addingTimeInterval(TimeInterval(length * 60))
            return (formatter.string(from: start), formatter.string(from: end))
        }
        let events: [(String, Int, Int, [(String, String)])] = [
            ("Halcyon Labs — pricing follow-up", 45, 45, [("priya@halcyonlabs.io", "Priya Raman"), ("marcus@halcyonlabs.io", "Marcus Lee")]),
            ("Design sync: onboarding flow", 135, 30, [("sofia@fernwood.co", "Sofia Alvarez")]),
            ("Customer interview — Fernwood Analytics", 24 * 60 + 60, 30, [("daniel@fernwood.co", "Daniel Okafor")]),
            ("Weekly pipeline review", 48 * 60 + 15, 30, [("lena@brightharbor.com", "Lena Fischer")]),
            ("1:1 with Marcus", 72 * 60, 30, [("marcus@halcyonlabs.io", "Marcus Lee")]),
        ]
        var payload: [[String: Any]] = []
        for (index, event) in events.enumerated() {
            let (start, end) = at(minutes: event.1, length: event.2)
            let attendees: [[String: Any]] = event.3.map { email, name in
                let domain = email.split(separator: "@").last.map(String.init) ?? ""
                return ["email": email, "display_name": name, "response_status": "accepted",
                        "organizer": false, "self": false, "domain": domain]
            } + [["email": calendarEmail, "display_name": "Ian", "response_status": "accepted",
                  "organizer": true, "self": true, "domain": "miniti.app"]]
            payload.append([
                "id": "screenshot-event-\(index)",
                "title": event.0,
                "start": start,
                "end": end,
                "is_all_day": false,
                "status": "confirmed",
                "meet_link": "https://meet.google.com/abc-defg-hij",
                "attendees": attendees,
                "organizer": ["email": calendarEmail, "display_name": "Ian", "self": true],
            ])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        return (try? JSONDecoder().decode([MinitiAPIService.CalendarEvent].self, from: data)) ?? []
    }

    // MARK: Live recording

    @MainActor
    static func applyLiveRecording(_ meeting: Meeting, to appState: AppState) {
        appState.currentMeeting = meeting
        appState.meetingLanguage = meeting.language
        appState.liveSegments = meeting.segments
            .filter { $0.isFinal }
            .sorted { $0.timestamp < $1.timestamp }
            .map { segment in
                AppState.LiveSegment(
                    id: segment.id,
                    text: segment.text,
                    speaker: segment.speaker,
                    timestamp: segment.timestamp,
                    isFinal: true,
                    source: segment.source
                )
            }
        appState.detectedSpeakers = Set(meeting.segments.map(\.speaker))
        appState.liveMicSpeakerIDs = [micSpeaker]
        appState.liveSelfSpeakerIDs = [micSpeaker]
        appState.liveSpeakerNames = liveSpeakerNames
        appState.liveSummary = meeting.summaryText ?? ""
        appState.liveActionItems = meeting.actionItems
        appState.liveTopics = meeting.topics
        appState.liveDiscussionFlow = meeting.discussionFlow
        appState.liveMetrics = meeting.meddpiccMetrics
        appState.liveEconomicBuyer = meeting.meddpiccEconomicBuyer
        appState.liveDecisionCriteria = meeting.meddpiccDecisionCriteria
        appState.liveDecisionProcess = meeting.meddpiccDecisionProcess
        appState.livePaperProcess = meeting.meddpiccPaperProcess
        appState.liveIdentifiedPain = meeting.meddpiccIdentifiedPain
        appState.liveChampion = meeting.meddpiccChampion
        appState.liveCompetition = meeting.meddpiccCompetition
        appState.liveQuestions = meeting.suggestedQuestions
        appState.liveTemplateID = meeting.insightTemplateID
        appState.liveTemplateSections = meeting.templateSections
        appState.liveNotes = meeting.notes
        appState.recordingDuration = liveDuration
        appState.isStartingMeeting = false
        appState.isRecording = true
        #if DEBUG
        appState.markAllInsightsReceivedForScreenshots()
        #endif
        appState.recomputeTrainingMetrics()
        animateAudioLevels(appState)
    }

    /// Keeps the live waveforms moving the way real speech does; a single static level
    /// renders as a flat line.
    @MainActor
    private static func animateAudioLevels(_ appState: AppState) {
        ScreenshotMode.levelTimer?.invalidate()
        let start = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            let tick = Date().timeIntervalSince(start)
            let mic = Float(0.35 + 0.3 * abs(sin(tick * 3.1)) + 0.15 * abs(sin(tick * 11.7)))
            let system = Float(0.12 + 0.2 * abs(sin(tick * 2.3 + 1.2)) + 0.1 * abs(sin(tick * 9.1)))
            Task { @MainActor in
                appState.audioLevels.update(microphoneLevel: min(mic, 1), systemAudioLevel: min(system, 1))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ScreenshotMode.levelTimer = timer
    }

    // MARK: Meetings

    static func meetings() -> [Meeting] {
        let calendar = Calendar.current
        let now = Date()
        func day(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        var all: [Meeting] = []

        // The live discovery call, in progress right now.
        let live = Meeting(
            id: ScreenshotMode.liveMeetingID,
            title: "Halcyon Labs — discovery call",
            startTime: now.addingTimeInterval(-liveDuration),
            segments: segments(liveTranscript),
            summaryText: "Halcyon Labs is replacing a homegrown call-notes process for a 40-person sales team. Priya (VP Revenue) owns the budget and wants live summaries their reps will actually read; Marcus (RevOps) needs Attio sync without a Zapier chain. They are piloting with six reps this month and want a decision before their Q4 kickoff.",
            actionItems: [
                "Send Priya the pilot pricing for six seats by Thursday",
                "Marcus to share the Attio field mapping for deal notes",
                "Set up a shared Slack channel for the pilot reps",
                "Book a technical review with their RevOps team next week",
            ],
            keyDecisions: ["Pilot with six reps through the end of the month", "Attio is the system of record for deal notes"],
            topics: ["pilot scope", "attio sync", "pricing", "security review"],
            discussionFlow: [
                "Priya described the current process: reps paste notes into Attio after calls, usually a day late",
                "Marcus asked how speaker names and action items reach Attio and whether tasks are created",
                "Pricing for a six-seat pilot and what a team-wide rollout would look like",
                "Security questionnaire and data retention for transcripts",
            ],
            notes: "Priya mentioned their kickoff is the second week of October.\nMarcus is the one who will run the pilot day to day.",
            insightsUpdatedAt: now.addingTimeInterval(-90),
            meddpiccMetrics: "Reps lose roughly 40 minutes a day on manual notes; target is same-day CRM updates for every call",
            meddpiccEconomicBuyer: "Priya Raman, VP Revenue — owns the tooling budget, CFO sign-off needed above $20k a year",
            meddpiccDecisionCriteria: "Rep adoption during the pilot, Attio sync quality, security review, and price per seat",
            meddpiccDecisionProcess: "Six-rep pilot through month end, then a go or no-go with Priya before the Q4 kickoff",
            meddpiccPaperProcess: "Standard MSA plus a security questionnaire from their IT lead",
            meddpiccIdentifiedPain: "CRM notes arrive a day late and managers cannot see what happened on calls",
            meddpiccChampion: "Marcus Lee, RevOps — running the pilot and pushing for a native Attio integration",
            meddpiccCompetition: "Staying on the current homegrown process; a generic notetaker evaluated last year"
        )
        live.language = "en"
        live.speakerNames = liveSpeakerNames
        live.selfSpeakerIDs = [micSpeaker]
        live.suggestedQuestions = liveQuestions
        live.insightTemplateID = "bant"
        live.templateSections = [
            "budget": "Anything above $20k a year needs CFO sign-off (Priya)\nPilot pricing for six seats requested by Thursday",
            "authority": "Priya Raman, VP Revenue, owns the tooling budget\nCFO approves spend above $20k a year",
            "need": "CRM notes land a day late and are two lines long\nManagers cannot see what happened on calls without reading notes all Friday",
            "timeline": "Six-rep pilot this month\nDecision before the Q4 kickoff in October",
            "next_steps": "Send pilot pricing by Thursday (you)\nShare the Attio field mapping (Marcus)\nReturn the security questionnaire",
        ]
        all.append(live)

        // Saved meetings for History, Coaching, and the detail screen.
        let saved = Meeting(
            id: ScreenshotMode.savedMeetingID,
            title: "Halcyon Labs — technical deep dive",
            startTime: day(1, 14, 0),
            endTime: day(1, 14, 47),
            segments: segments(deepDiveTranscript),
            summaryText: "Technical review of how Miniti would fit into Halcyon's RevOps stack. Marcus walked through their Attio setup and the fields reps are expected to fill after every call. The main open question was how transcripts are retained and who can see them; the security questionnaire will cover the rest.",
            actionItems: [
                "Share the data retention and deletion policy with Marcus",
                "Confirm which Attio objects receive meeting notes and tasks",
                "Send the security questionnaire back before Friday",
            ],
            keyDecisions: ["Notes go to the Attio deal record, tasks to the rep who ran the call"],
            topics: ["attio", "security", "retention", "rollout"],
            discussionFlow: [
                "Marcus demoed the Attio pipeline and the fields reps must fill",
                "How transcripts, summaries, and tasks map to Attio objects",
                "Data retention, deletion, and who can see transcripts",
                "Rollout plan for the remaining reps after the pilot",
            ],
            notes: "Marcus wants a weekly digest of pilot usage.",
            insightsUpdatedAt: day(1, 14, 50),
            meddpiccMetrics: "Same-day CRM updates for every call; managers reviewing calls without listening back",
            meddpiccEconomicBuyer: "Priya Raman, VP Revenue",
            meddpiccDecisionCriteria: "Attio sync quality, security review, rep adoption",
            meddpiccDecisionProcess: "Pilot then decision before the Q4 kickoff",
            meddpiccPaperProcess: "MSA plus security questionnaire",
            meddpiccIdentifiedPain: "Late, inconsistent CRM notes",
            meddpiccChampion: "Marcus Lee, RevOps",
            meddpiccCompetition: "Current homegrown process"
        )
        saved.speakerNames = ["0": "Marcus Lee"]
        saved.selfSpeakerIDs = [micSpeaker]
        saved.suggestedQuestions = Array(liveQuestions.prefix(3))
        all.append(saved)

        let others: [(String, Date, Int, [(Int, String)], String, [String], [String], [String: String], Bool)] = [
            ("Weekly pipeline review", day(0, 9, 30), 28, pipelineTranscript,
             "Pipeline stands at 14 open opportunities. Halcyon and Fernwood are the two most likely to close this quarter; Brightharbor slipped a month while they finish procurement. Lena flagged that two renewals need a check-in before the end of the month.",
             ["Lena to reach out to both renewal accounts this week", "Move Brightharbor close date to next month", "Update the forecast before Thursday's leadership call"],
             ["forecast", "renewals", "halcyon", "brightharbor"],
             ["0": "Lena Fischer"], true),
            ("Design sync: onboarding flow", day(1, 10, 30), 31, designTranscript,
             "Reviewed the new onboarding flow. Sofia proposed collapsing the two permission steps into one screen with a live microphone meter, which tested well with three users. The team agreed to keep BYOK as a secondary path and to drop the tour overlay.",
             ["Sofia to share the updated prototype by Wednesday", "Write copy for the single permissions screen", "Schedule two more usability sessions"],
             ["onboarding", "permissions", "prototype", "copy"],
             ["0": "Sofia Alvarez"], false),
            ("1:1 with Marcus", day(3, 15, 0), 26, oneOnOneTranscript,
             "Marcus is happy with how the pilot reps are using summaries but wants tasks created automatically for action items. Discussed the weekly digest and agreed to trial it with the pilot group first.",
             ["Draft the weekly digest format", "Enable automatic task creation for the pilot reps"],
             ["pilot", "digest", "tasks"],
             ["0": "Marcus Lee"], false),
            ("Customer interview — Fernwood Analytics", day(4, 11, 0), 34, interviewTranscript,
             "Daniel runs a nine-person analytics consultancy and records every client call. He wants coaching feedback for junior consultants and a way to hand a summary to the client the same day. Price is not the main concern; trust in the transcript is.",
             ["Send Daniel the coaching overview walkthrough", "Follow up on the same-day client summary export"],
             ["coaching", "consultancy", "client summaries"],
             ["0": "Daniel Okafor"], false),
            ("Q3 planning", day(8, 13, 0), 52, planningTranscript,
             "Set the three priorities for the quarter: shipping the Attio and Twenty integrations, the coaching overview, and the shared-microphone diarization work. Agreed to defer the Android app until the iOS version is stable.",
             ["Write the Q3 one-pager", "Break the diarization work into weekly milestones", "Set a date for the Android decision"],
             ["priorities", "integrations", "diarization", "android"],
             ["0": "Lena Fischer", "1": "Sofia Alvarez"], true),
            ("Board prep", day(11, 16, 0), 41, boardTranscript,
             "Walked through the numbers and the narrative for the board update. Revenue is ahead of plan on the Pro tier; the ask is to fund one more engineer. Lena suggested leading with the pilot conversion rate.",
             ["Finalize the board deck by Monday", "Pull the pilot conversion numbers for the last two quarters"],
             ["board", "hiring", "revenue"],
             ["0": "Lena Fischer"], false),
            ("Vendor call — data warehouse", day(13, 10, 0), 29, vendorTranscript,
             "Evaluated moving analytics into a managed warehouse. The vendor's pricing scales with rows scanned, which makes the transcript tables expensive; they will send a quote with a flat tier.",
             ["Wait for the flat-tier quote", "Estimate monthly rows scanned for transcripts"],
             ["warehouse", "pricing", "analytics"],
             ["0": "Vendor rep"], false),
        ]
        for (title, start, minutes, script, summary, actions, topics, names, pinned) in others {
            let meeting = Meeting(
                title: title,
                startTime: start,
                endTime: start.addingTimeInterval(TimeInterval(minutes * 60)),
                segments: segments(script),
                summaryText: summary,
                actionItems: actions,
                topics: topics,
                isPinned: pinned,
                insightsUpdatedAt: start.addingTimeInterval(TimeInterval(minutes * 60 + 120))
            )
            meeting.speakerNames = names
            meeting.selfSpeakerIDs = [micSpeaker]
            all.append(meeting)
        }
        return all
    }

    static let liveQuestions: [SuggestedQuestion] = [
        SuggestedQuestion(question: "What would make the pilot a clear yes for you by the end of the month?", type: "deeper", context: "Priya said they want a decision before the Q4 kickoff but has not named the bar.", priority: "high"),
        SuggestedQuestion(question: "Who else needs to see the pilot results before the CFO signs off?", type: "explore", context: "CFO sign-off is required above $20k a year; the approval path is still unclear."),
        SuggestedQuestion(question: "If reps still paste notes a day late during the pilot, what does that tell us?", type: "challenge", context: "Adoption is the stated decision criterion, but nobody has defined a failure case."),
        SuggestedQuestion(question: "Which Attio fields do managers actually read after a call?", type: "clarify", context: "Marcus listed the required fields; the useful ones may be a smaller set."),
        SuggestedQuestion(question: "Should the pilot include one manager as well as the six reps?", type: "reframe", context: "Managers are the ones who cannot see what happened on calls."),
    ]

    // MARK: Transcripts
    //
    // (speaker, line) pairs. The mic speaker is "You"; 0 and 1 are remote speakers.
    // Timestamps are spread evenly across the meeting when segments are built.

    private static func segments(_ lines: [(Int, String)]) -> [TranscriptSegment] {
        var timestamp: TimeInterval = 4
        return lines.map { speaker, text in
            let words = Double(text.split(separator: " ").count)
            let segment = TranscriptSegment(
                text: text,
                speaker: speaker,
                timestamp: timestamp,
                isFinal: true,
                confidence: 0.96,
                sourceRaw: speaker == micSpeaker ? TranscriptSource.microphone.rawValue : TranscriptSource.system.rawValue
            )
            timestamp += max(3, words / 2.6) + 1.5
            return segment
        }
    }

    private static let you = DeepgramService.micSpeakerID

    static let liveTranscript: [(Int, String)] = [
        (0, "Thanks for making time. Marcus and I have been talking about this for a while, so it is good to finally see it."),
        (you, "Glad to be here. Before I show anything, can you walk me through what happens after a rep finishes a call today?"),
        (0, "Honestly, not much. They are supposed to update the deal in Attio the same day. In practice it is the next morning, and half the time it is two lines."),
        (1, "And then I chase them. I spend most of Friday reading notes that do not tell me what was actually said on the call."),
        (you, "So the pain is less about taking notes and more about managers not being able to see what happened."),
        (0, "That is exactly it. I do not need transcripts, I need to know if the deal moved and what we promised."),
        (you, "Okay. What Miniti does is listen to the call, build the summary and action items live, and then push that to the Attio deal when the meeting ends. Speaker names come from the calendar invite."),
        (1, "Does it create tasks, or just a note on the deal?"),
        (you, "Both, if you want. Each action item can become a task on the rep who ran the call, with a deadline if one was mentioned. You can preview and untick any before it sends."),
        (1, "That is the part I could not get from the generic tools we looked at last year. Everything went through Zapier and broke every month."),
        (0, "Let us talk about the pilot. I want six reps on it this month and a decision before our Q4 kickoff in October."),
        (you, "That works. For six seats the pilot pricing is simple, and I will send it over by Thursday. What would make it a clear yes for you at the end of the month?"),
        (0, "If the reps actually use it without me nagging, and if Marcus is not spending Friday reading notes. Anything above twenty thousand a year needs our CFO, so I will need numbers for a full rollout too."),
        (1, "One more thing. Our IT lead will send a security questionnaire. Transcript retention is going to come up."),
        (you, "Send it over. Transcripts stay on the device by default, and the managed tier deletes audio as soon as it is transcribed. I will put the details in writing."),
        (0, "Great. Let us get the pilot reps into a shared channel and go from there."),
    ]

    static let deepDiveTranscript: [(Int, String)] = [
        (0, "Let me share my screen. This is the pipeline view the reps live in, and these are the fields they are supposed to fill after every call."),
        (you, "Which of those fields do managers actually read?"),
        (0, "Next step, and the notes. Everything else is for reporting. If the notes were good, half these fields would not exist."),
        (you, "Then the mapping is straightforward. The summary goes into the notes field on the deal, and each action item becomes a task assigned to the rep who ran the call."),
        (0, "What about calls with two reps on them?"),
        (you, "The organizer of the calendar event owns the tasks. You can change that per meeting before it sends."),
        (0, "Okay. Security is the other thing. Where do transcripts live and who can see them?"),
        (you, "On the device, in the app's own store. Nothing is uploaded except the audio stream for transcription, and that is discarded once the text comes back. Managers only see what a rep sends to Attio."),
        (0, "Our IT lead will still want that in writing, but it is a good answer."),
        (you, "I will send the retention and deletion policy with the questionnaire. What does the rollout look like after the pilot?"),
        (0, "If the six reps stick with it, we do the rest of the team in one go. I would want a weekly digest of who is actually using it."),
        (you, "We can do that from the pilot group first and see if the format is useful."),
    ]

    static let pipelineTranscript: [(Int, String)] = [
        (0, "We are at fourteen open opportunities, four of them past the proposal stage."),
        (you, "Where are Halcyon and Fernwood?"),
        (0, "Halcyon is in a pilot and should decide by the end of the month. Fernwood wants one more call with their junior team before they commit."),
        (you, "And Brightharbor? They were supposed to close this week."),
        (0, "Procurement. They asked for the MSA again and their finance team is slow. I would move it to next month rather than, um, hope."),
        (you, "Agreed. Move it and note the reason. Anything on renewals?"),
        (0, "Two renewals are up at the end of the month and neither has replied to the check-in email. I will call them both this week."),
        (you, "Good. I need the forecast updated before Thursday's leadership call, so let us make sure the close dates are honest."),
        (0, "I will have it done by Wednesday evening."),
    ]

    static let designTranscript: [(Int, String)] = [
        (0, "So the biggest thing from the sessions was the permissions. People did not understand why there were two steps."),
        (you, "What did you try?"),
        (0, "One screen. Ask for the microphone, show a live meter so they can see it working, then continue. All three testers got through it without asking anything."),
        (you, "I like that. Does it still work for people who want to bring their own keys?"),
        (0, "Yes, that stays as a secondary link at the bottom. Nobody in the sessions needed it, so it should not be in the main path."),
        (you, "And the tour overlay?"),
        (0, "Drop it. Two of the three closed it immediately and the third read it and still asked where to start a meeting. The start button is obvious enough on its own."),
        (you, "Okay, let us go with the single permissions screen. Can you have the prototype updated by Wednesday so we can write the copy?"),
        (0, "Wednesday is fine. I want two more sessions after that to check the copy lands."),
    ]

    static let oneOnOneTranscript: [(Int, String)] = [
        (0, "The reps like the summaries. I have seen three of them actually read the note before their follow-up call, which never happened before."),
        (you, "That is the outcome we wanted. What is missing?"),
        (0, "Tasks. Right now they read the action items and then create tasks by hand, which means they do not."),
        (you, "We can turn on automatic task creation for the pilot group. Each action item becomes a task on the rep, and they can untick anything that should not be one."),
        (0, "Let us do that. And I still want the weekly digest, even a rough one."),
        (you, "I will draft a format this week and send it just to you first. If it is useful we widen it."),
        (0, "Sounds good. Priya asked me how it was going, by the way, and I told her it was working."),
    ]

    static let interviewTranscript: [(Int, String)] = [
        (0, "We are nine people, all consultants, and every client call gets recorded. The recordings mostly sit there."),
        (you, "What would you do with them if they were easy to use?"),
        (0, "Two things. Coach the junior consultants, because I cannot sit on every call, and get a summary to the client the same day. Right now that summary is written by hand the next morning."),
        (you, "When you say coaching, what are you looking for?"),
        (0, "Are they talking too much, are they asking questions, do they, you know, ramble. I can hear it when I am on the call but I cannot be on every call."),
        (you, "The coaching overview tracks talk ratio, questions, pace, and fillers per meeting and over time. Would you want to see that per consultant?"),
        (0, "Per consultant, yes, and I would want them to see their own without me having to show them."),
        (you, "And on the client summary, what does a good one look like?"),
        (0, "Short. What we agreed, what we owe them, what they owe us. If I can trust the transcript I can send it without rewriting it."),
        (you, "Trust in the transcript is the thing then, more than price."),
        (0, "Price matters, but a wrong summary sent to a client costs me a lot more than a subscription."),
    ]

    static let planningTranscript: [(Int, String)] = [
        (you, "Three priorities for the quarter, and we hold ourselves to three. Let us list candidates first."),
        (0, "The CRM integrations. Attio is already in progress and Twenty is asked for every week."),
        (1, "The coaching overview. Every interview mentions it and we have the data already."),
        (you, "And the shared-microphone diarization. In-room meetings are half of what people record and the transcript treats the room as one person."),
        (0, "That is three. What about Android?"),
        (you, "I want to defer it until iOS is stable. Splitting the mobile effort now would slow both down."),
        (1, "Agreed, as long as we set a date to decide rather than letting it drift."),
        (0, "First week of the next quarter. I will put it in the one-pager."),
        (you, "Good. For diarization I want weekly milestones, because it is the riskiest of the three."),
        (1, "I will break it down with the audio work next week."),
        (0, "And I will write the Q3 one-pager so everyone sees the same list."),
    ]

    static let boardTranscript: [(Int, String)] = [
        (0, "The numbers are ahead of plan on Pro. Free to Pro conversion has held above the target for two quarters."),
        (you, "What is the narrative for the update?"),
        (0, "Lead with the pilot conversion rate. Every team pilot in the last two quarters converted, which is the strongest thing we have."),
        (you, "And the ask is one more engineer."),
        (0, "Yes. Frame it as shipping the integrations faster, because that is what the pilots keep asking for."),
        (you, "Can you pull the pilot numbers for both quarters so the deck is finished by Monday?"),
        (0, "I will have them by Friday."),
    ]

    static let vendorTranscript: [(Int, String)] = [
        (0, "Pricing scales with rows scanned, so it depends on how much of the transcript data you query."),
        (you, "Transcript tables are the biggest thing we have. A per-row model gets expensive quickly."),
        (0, "We do have a flat tier for predictable workloads. I can put a quote together if you can estimate monthly volume."),
        (you, "I will estimate rows scanned for the transcript tables and send it over."),
        (0, "Once I have that I will send the flat-tier quote within a couple of days."),
    ]
}
