import Foundation
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Only the Testing build contains fixture credentials or transport. UI runners
/// do not execute the hosted bundle's TestRunSetup, so isolation starts here.
enum AccountUITestHarness {
    #if MINITI_TEST_HOST
    @MainActor static func seedFolderHistory(in context: ModelContext) {
        guard isActive, ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "folders",
              (try? context.fetchCount(FetchDescriptor<Meeting>())) == 0 else { return }
        for (index, title) in ["Acme customer review", "Borealis sales demo", "Monday standup", "Friday team sync"].enumerated() {
            context.insert(Meeting(title: title, startTime: Date().addingTimeInterval(Double(-index * 3600 - 120)), endTime: Date()))
        }
        try? context.save()
    }
    #endif
    static var isActive: Bool {
        #if MINITI_TEST_HOST
        ProcessInfo.processInfo.environment["MINITI_UI_TEST_ID"] != nil
        #else
        false
        #endif
    }

    /// Inject the effective environment size for rendered tests. Launch arguments
    /// alone do not reliably change SwiftUI's App-level environment on this runner.
    static func dynamicTypeSize(_ systemSize: DynamicTypeSize) -> DynamicTypeSize {
        #if MINITI_TEST_HOST
        if isActive && ProcessInfo.processInfo.environment["MINITI_UI_TEST_LARGE_TEXT"] == "1" {
            return .accessibility5
        }
        if isActive, ProcessInfo.processInfo.environment["MINITI_UI_TEST_READING_MATRIX"] == "1",
           ProcessInfo.processInfo.environment["MINITI_UI_TEST_NORMAL_TEXT"] == "1" {
            return .large
        }
        #endif
        return systemSize
    }

    @MainActor static func configure(_ state: AppState) {
        #if MINITI_TEST_HOST
        guard isActive else { return }
        precondition(["com.miniti.app.testhost", "com.miniti.mobile.testhost"].contains(Bundle.main.bundleIdentifier ?? ""))
        let identifier = ProcessInfo.processInfo.environment["MINITI_UI_TEST_ID"]!
        precondition(UUID(uuidString: identifier) != nil)
        var defaults = UserDefaults(suiteName: "miniti.ui.\(identifier)")!
        if ProcessInfo.processInfo.arguments.contains("-MinitiUITestCleanup") {
            defaults.removePersistentDomain(forName: "miniti.ui.\(identifier)")
            defaults = UserDefaults(suiteName: "miniti.ui.cleanup")!
            defaults.removePersistentDomain(forName: "miniti.ui.cleanup")
        }
        let scenario = ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] ?? "first"
        #if os(macOS)
        // Reproduce ambient Light in this isolated process without changing macOS
        // preferences or the installed app. Individual window roots must override it.
        if scenario == "appearance" { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        #endif
        if scenario == "folders" { state.automaticFolderCreation = true }
        if !defaults.bool(forKey: "setupFixtureInitialized") {
            UserDefaults.standard.removeObject(forKey: AppState.accessCardDismissedKey(accountID: "acct_ui_fixture"))
            state.homeSetupHidden = scenario != "setup"
            state.homeSetupState.calendarHidden = false
            state.homeSetupDismissed = false
            state.homeSetupSkippedSteps = ""
            state.homeSetupState.foldersReviewed = false
            state.calendarNudgeDismissedUntil = 0
            defaults.set(true, forKey: "setupFixtureInitialized")
        }
        if scenario == "revoked" && defaults.data(forKey: "fixtureCredential") == nil {
            defaults.set("revoke", forKey: "managedAccessChoice")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        let store = FixtureCredentials(defaults: defaults, scenario: scenario)
        let manager = ClientAuthManager(store: store, baseURL: "https://miniti-fixture.invalid/api", session: session,
            deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" }, defaults: defaults)
        state.appMode = scenario == "onboardingBYOK" ? .byok : .managed
        state.hasAcceptedTerms = scenario != "setupUpgrade"
        state.hasCompletedOnboarding = !scenario.hasPrefix("onboarding")
        state.clientAuthManager = manager
        state.minitiAPIService = MinitiAPIService(session: session, auth: manager)
        state.insightsService = nil
        state.autoInferSpeakerNames = false
        state.privateModeEnabled = false
        state.onDeviceSpeakerSeparationEnabled = false
        state.refreshClientAuthStatus()
        // Test-host preferences outlive a process. Keep the calendar fixture from
        // making later setup scenarios wait for an unhandled connection check.
        state.googleCalendarEnabled = scenario == "calendar"
        if scenario == "calendar" {
            state.isGoogleCalendarConnected = true
            state.hasResolvedCalendarConnection = true
            state.upcomingEvents = [try! JSONDecoder().decode(MinitiAPIService.CalendarEvent.self,
                from: JSONSerialization.data(withJSONObject: tomorrowCalendarEvent()))]
        }
        if scenario == "association" {
            let formatter = ISO8601DateFormatter()
            let event: [String: Any] = ["id": "fixture-current", "title": "Fixture calendar call",
                "start": formatter.string(from: Date().addingTimeInterval(-30)),
                "end": formatter.string(from: Date().addingTimeInterval(1800)),
                "isAllDay": false, "status": "confirmed", "attendees": []]
            state.currentMeeting = Meeting(title: "My existing recording")
            state.isRecording = true
            state.smartMeetingsEnabled = true
            state.upcomingEvents = [try! JSONDecoder().decode(MinitiAPIService.CalendarEvent.self,
                from: JSONSerialization.data(withJSONObject: event))]
            state.checkSmartCalendarTransition()
        }
        if let service = state.deepgramService {
            service.socketStarter = { [weak service] _ in
                Task { @MainActor in
                    service?.connectionState = .connected
                    service?.speakerSegments = [.init(id: UUID(), speaker: 0, text: "Fixture recording begins", startTime: 0, endTime: 1,
                        isFinal: true, confidence: 1, channelIndex: nil, source: .microphone)]
                }
            }
            service.finalDrainOperation = { [weak service] in
                service?.speakerSegments = [.init(id: UUID(), speaker: 0, text: "Fixture final words", startTime: 1, endTime: 2,
                    isFinal: true, confidence: 1, channelIndex: nil, source: .microphone)]
            }
        }
        #endif
    }

    #if MINITI_TEST_HOST
    private static func tomorrowCalendarEvent() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        let start = tomorrow.addingTimeInterval(12 * 3600)
        return ["id": "fixture-tomorrow", "title": "Fixture tomorrow call",
            "start": formatter.string(from: start), "end": formatter.string(from: start.addingTimeInterval(1800)),
            "isAllDay": false, "status": "confirmed", "attendees": []]
    }

    private final class FixtureCredentials: ClientAuthCredentialStore, @unchecked Sendable {
        let defaults: UserDefaults
        let scenario: String
        init(defaults: UserDefaults, scenario: String) { self.defaults = defaults; self.scenario = scenario }
        var lastLoadDiagnostic: ClientAuthStoreDiagnostic? {
            if scenario == "locked" { return .unreadable(status: -25308) }
            if scenario == "corrupt" { return .undecodable(bytes: 4) }
            return nil
        }
        func load() -> ClientAuthCredentials? {
            guard lastLoadDiagnostic == nil, let data = defaults.data(forKey: "fixtureCredential") else { return nil }
            return try? JSONDecoder().decode(ClientAuthCredentials.self, from: data)
        }
        func save(_ value: ClientAuthCredentials) -> Bool {
            guard let data = try? JSONEncoder().encode(value) else { return false }
            defaults.set(data, forKey: "fixtureCredential"); return true
        }
        func clear() { defaults.removeObject(forKey: "fixtureCredential") }
    }

    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let path = request.url?.path ?? ""
            let scenario = ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"]
            // Hold these responses until the test terminates the app. This models a
            // stalled request without sleeping the protocol queue or contacting a server.
            if ["onboardingPending", "homePending"].contains(scenario ?? ""), path == "/api/auth/account/create" { return }
            if scenario == "onboardingSlowUsage", path == "/api/usage" { return }
            var status = 200
            var body: [String: Any] = [:]
            var headers = ["Content-Type": "application/json"]
            switch path {
            case "/api/google/status" where ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "calendar":
                body = ["connected": true, "email": "calendar@example.invalid"]
            case "/api/google/events" where ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "calendar":
                body = ["events": [AccountUITestHarness.tomorrowCalendarEvent()]]
            case "/api/account/email":
                let identifier = ProcessInfo.processInfo.environment["MINITI_UI_TEST_ID"] ?? "cleanup"
                let defaults = UserDefaults(suiteName: "miniti.ui.\(identifier)")!
                if request.httpMethod == "POST" {
                    let data: Data
                    if let body = request.httpBody { data = body }
                    else if let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var bytes = [UInt8](repeating: 0, count: 4096)
                        let count = stream.read(&bytes, maxLength: bytes.count)
                        data = count > 0 ? Data(bytes.prefix(count)) : Data()
                    } else { data = Data() }
                    if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        defaults.set(payload["email"], forKey: "pendingEmail")
                    }
                }
                body = ["email": NSNull(), "pending": defaults.string(forKey: "pendingEmail") as Any? ?? NSNull()]
            case "/api/auth/challenge": body = ["challenge_id": "fixture", "nonce": "fixture-nonce"]
            case "/api/auth/migrate":
                status = 404; body = ["error": "device_not_eligible"]
            case "/api/auth/account/create", "/api/auth/account/restore":
                if ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "throttled" {
                    status = 429; body = ["error": "rate_limited"]; headers["Retry-After"] = "120"
                } else if ["onboardingOffline", "homeOffline"].contains(scenario ?? "") {
                    status = 503; body = ["error": "temporarily_unavailable"]
                } else {
                    body = ["access_token": "fixture-token", "expires_in": 3600, "account_id": "acct_ui_fixture", "device_cap": 5]
                }
            case "/api/auth/email/start": body = ["link_id": "lnk_fixturefixture01"]
            case "/api/auth/email/status": body = ["status": "approved"]
            case "/api/auth/revoke": body = ["revoked": true]
            case "/api/session": body = ["access_token": "fixture-token", "token_type": "Bearer", "expires_in": 3600,
                "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                "session_id": "sess_v2_fixturefixture01", "accounting_version": 2,
                "session_started_at": ISO8601DateFormatter().string(from: Date())]
            case "/api/session/end": body = ["accounting_version": 2, "accepted_duration_ms": 0, "minutes_used": 0,
                "minutes_remaining": 500, "minutes_limit": 500, "tier": "free"]
            case "/api/usage": body = ["minutes_used": 0, "minutes_limit": 500, "resets_at": "2026-12-01T00:00:00Z", "tier": "free"]
            case "/api/auth/account/devices/550e8400-e29b-41d4-a716-446655440000":
                body = ["installation_id": "550e8400-e29b-41d4-a716-446655440000", "label": "Studio device"]
            case "/api/auth/account/devices":
                body = ["account_id": "acct_ui_fixture", "device_cap": 5, "devices": [[
                    "installation_id": "550e8400-e29b-41d4-a716-446655440000", "platform": "ios", "label": "Studio device",
                    "enrolled_at": "2026-11-04T00:00:00Z", "current": true]]]
            default:
                // No unhandled request is forwarded to a real endpoint.
                status = 503; body = ["error": "fixture_route_unavailable"]
            }
            let data = try! JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    #endif
}

/// Inspect a presented surface without replacing its production content.
struct AccountUITestReadingScopeProbe: ViewModifier {
    let name: String
    #if MINITI_TEST_HOST
    @Environment(\.interfaceScale) private var scale
    @Environment(\.systemReadingSize) private var readingSize
    @Environment(\.dynamicTypeSize) private var controlSize
    private var readingCategory: String {
        guard let readingSize else { return "missing" }
        if readingSize == .large { return "normal" }
        if readingSize == .accessibility5 { return "largest" }
        return "other"
    }
    #endif

    func body(content: Content) -> some View {
        #if MINITI_TEST_HOST
        content.overlay(alignment: .bottomLeading) {
            if AccountUITestHarness.isActive,
               ProcessInfo.processInfo.environment["MINITI_UI_TEST_READING_MATRIX"] == "1" {
                Text("scale \(scale.rawValue); reading \(readingCategory); controls \(controlSize.isAccessibilitySize ? "accessibility" : "standard")")
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.Text.muted)
                    .dynamicTypeSize(.large)
                    .accessibilityIdentifier("ui-test.readingScope.\(name)")
                    .allowsHitTesting(false)
            }
        }
        #else
        content
        #endif
    }
}

struct AccountUITestReady: ViewModifier {
    #if MINITI_TEST_HOST
    @Environment(\.interfaceScale) private var readingScale
    @Environment(\.systemReadingSize) private var readingSize
    private var readingCategory: String {
        if readingSize == .large { return "normal" }
        if readingSize == .accessibility5 { return "largest" }
        return "unexpected"
    }
    #endif
    func body(content: Content) -> some View {
        Group {
            #if MINITI_TEST_HOST
            if AccountUITestHarness.isActive,
               ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "controlTargets" {
                ControlTargetUITestFixture()
            } else if AccountUITestHarness.isActive,
                      ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "insightUpdateTargets" {
                InsightUpdateUITestFixture()
            } else if AccountUITestHarness.isActive,
                      ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "speakerGuidance" {
                SpeakerGuidanceUITestFixture()
            } else if AccountUITestHarness.isActive,
                      let scenario = ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"],
                      scenario.hasPrefix("docsGuidance-") {
                DocsGuidanceUITestFixture(scenario: scenario)
            } else if AccountUITestHarness.isActive,
                      ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "docsTargets" {
                DocsTabContent(
                    topics: [DocTopic(label: "Fixture topic", lookupState: .answered,
                                      card: DocPlaybookCard(topic: "Fixture topic", answer: "A synthetic answer with a real copy action.", citations: []))],
                    isExtracting: false, hasMCPURL: true, autoLookup: false,
                    onRefresh: {}, onLookup: { _ in })
                    .frame(width: 300).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ColorPalette.Background.primary)
            } else {
                #if os(iOS)
                if AccountUITestHarness.isActive,
                   ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "narrowCoaching",
                   ScreenshotMode.current == .coaching {
                    content.frame(width: 320).frame(maxWidth: .infinity)
                } else {
                    content
                }
                #else
                content
                #endif
            }
            #else
            content
            #endif
        }.overlay(alignment: .bottomLeading) {
            if AccountUITestHarness.isActive {
                VStack(alignment: .leading) {
                    Text("Test ready").font(.caption2).foregroundStyle(ColorPalette.Text.muted)
                        .accessibilityIdentifier("ui-test.ready")
                    #if MINITI_TEST_HOST
                    if ProcessInfo.processInfo.environment["MINITI_UI_TEST_READING_MATRIX"] == "1" {
                        Text("Reading scale \(readingScale.rawValue), text \(readingCategory)")
                            .font(.caption2).foregroundStyle(ColorPalette.Text.muted)
                            .accessibilityIdentifier("ui-test.readingMetrics")
                    }
                    #endif
                    #if MINITI_TEST_HOST && os(macOS)
                    if ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "docsTargets" {
                        Text(NSApp.isFullKeyboardAccessEnabled ? "Keyboard navigation on" : "Keyboard navigation off")
                            .font(.caption2).foregroundStyle(ColorPalette.Text.muted)
                            .accessibilityIdentifier("ui-test.keyboardNavigation")
                    }
                    #endif
                }
                // Test status must not grow over the production controls under test.
                .dynamicTypeSize(.large)
                .allowsHitTesting(false)
            }
        }
    }
}

#if MINITI_TEST_HOST
private struct SpeakerGuidanceUITestFixture: View {
    @State private var lastAction = "none"
    private let attendee = MeetingAttendee(email: "ada@example.invalid", displayName: "Ada Fixture",
        domain: "example.invalid", responseStatus: "accepted", isOrganizer: false, isSelf: false)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SpeakerLegend(speakers: [DeepgramService.micSpeakerID, 0],
                              speakerNames: ["0": "Fixture guest"],
                              onRename: { lastAction = "rename:\($0)" })
                RenameSpeakerView(speakerID: 0, currentName: "Current fixture", defaultName: "Speaker 1",
                    isSelf: false, hasOtherSelves: true,
                    onSave: { lastAction = "saved:\($0)" }, onClear: { lastAction = "clear" },
                    onMarkAsSelf: { lastAction = "markSelf" }, onUnmarkAsSelf: { lastAction = "unmarkSelf" },
                    onCancel: { lastAction = "cancel" }, currentEmail: "current@example.invalid",
                    attendees: [attendee], onPickAttendee: { lastAction = "picked:\($0.email)" })
                Text("Action: \(lastAction)")
                    .font(.caption).foregroundStyle(ColorPalette.Text.muted)
                    .accessibilityIdentifier("speaker.fixture.action")
            }
            .padding(16)
        }
        .background(ColorPalette.Background.primary)
    }
}

private struct DocsGuidanceUITestFixture: View {
    let scenario: String
    @State private var lookupCount = 0

    private var topics: [DocTopic] {
        switch scenario {
        case "docsGuidance-noMatch":
            return [DocTopic(label: "Fixture topic", lookupState: .noMatch)]
        case "docsGuidance-pending":
            return [DocTopic(label: "Fixture topic", lookupState: .pending)]
        case "docsGuidance-answered":
            return [DocTopic(label: "Fixture topic", lookupState: .answered,
                card: DocPlaybookCard(topic: "Fixture topic", answer: "A synthetic answer.", citations: [
                    DocCitation(title: "Fixture reference", snippet: "A synthetic grounded citation snippet.")
                ]))]
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if scenario == "docsGuidance-questions" {
                QuestionsEmptyState(variant: .noQuestions)
            } else {
                DocsTabContent(topics: topics, isExtracting: false,
                               hasMCPURL: scenario != "docsGuidance-setup",
                               autoLookup: scenario == "docsGuidance-auto",
                               errorMessage: scenario == "docsGuidance-error" ? "Synthetic lookup failure" : nil,
                               onRefresh: {}, onLookup: { _ in lookupCount += 1 })
            }
            Text("lookups=\(lookupCount)")
                .font(.caption)
                .foregroundStyle(ColorPalette.Text.muted)
                .accessibilityIdentifier("docs.fixture.lookupCount")
        }
        .frame(maxWidth: 500)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ColorPalette.Background.primary)
    }
}

private struct InsightUpdateUITestFixture: View {
    @State private var updateCount = 0
    @State private var regenerateCount = 0
    @State private var disabledCount = 0

    var body: some View {
        VStack(spacing: 16) {
            Button { updateCount += 1 } label: {
                MinitiInsightUpdateLabel(title: "update")
            }.accessibilityIdentifier("update.fixture.enabled")
            Button { regenerateCount += 1 } label: {
                MinitiInsightUpdateLabel(title: "regenerate") { Text("sales") }
            }.accessibilityIdentifier("update.fixture.regenerate")
            Button { disabledCount += 1 } label: {
                MinitiInsightUpdateLabel(title: "finishing")
            }.accessibilityIdentifier("update.fixture.disabled").disabled(true).opacity(0.5)
            Text("update=\(updateCount) regenerate=\(regenerateCount) disabled=\(disabledCount)")
                .accessibilityIdentifier("update.fixture.counts")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
    }
}

/// The real shared labels inside native controls, with observable actions.
/// No alternate hit-testing implementation exists in this fixture.
private struct ControlTargetUITestFixture: View {
    @State private var left = 0
    @State private var right = 0
    @State private var selected = "focus"
    @State private var menuCount = 0
    @State private var disabledCount = 0
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                Button { left += 1 } label: {
                    MinitiControlLabel { Image(systemName: "chevron.left").font(.system(size: 11)) }
                }.accessibilityIdentifier("target.left")
                Button { right += 1 } label: {
                    MinitiControlLabel { Image(systemName: "chevron.right").font(.system(size: 11)) }
                }.accessibilityIdentifier("target.right")
            }.buttonStyle(.plain)
            Text("left=\(left) right=\(right)").accessibilityIdentifier("target.counts")
            MinitiTabStripSurface {
                HStack(spacing: 0) {
                    ForEach(["focus", "stats", "history"], id: \.self) { tab in
                        Button { selected = tab } label: {
                            MinitiTabLabel(title: tab, isSelected: selected == tab, fillsAvailableWidth: true)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("target.tab.\(tab)")
                        .accessibilityAddTraits(selected == tab ? .isSelected : [])
                    }
                }
            }
            Text(selected).accessibilityIdentifier("target.selected")
            HStack(spacing: 8) {
                Menu {
                    Button("Choose") { menuCount += 1 }
                } label: {
                    MinitiControlLabel { Text("menu").font(.system(size: 11)) }
                }.accessibilityIdentifier("target.menu")
                Button { disabledCount += 1 } label: {
                    MinitiControlLabel { Text("disabled").font(.system(size: 11)) }
                }.disabled(true).accessibilityIdentifier("target.disabled")
            }.buttonStyle(.plain)
            Text("menu=\(menuCount) disabled=\(disabledCount)").accessibilityIdentifier("target.menuCounts")
            Form {
                DisclosureGroup(isExpanded: $expanded) {
                    Text("Disclosure content").accessibilityIdentifier("target.disclosed")
                } label: {
                    Text("details")
                }.disclosureGroupStyle(MinitiDisclosureStyle())
            }.frame(height: 160)
        }
        .frame(width: 300)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
    }
}
#endif

/// Read-only diagnostics on real scene roots, absent outside the isolated test case.
struct AccountUITestAppearanceProbe: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        #if MINITI_TEST_HOST && os(macOS)
        content.overlay(alignment: .bottomTrailing) {
            if AccountUITestHarness.isActive,
               ProcessInfo.processInfo.environment["MINITI_UI_TEST_SCENARIO"] == "appearance" {
                MacAppearanceProbe(name: name).frame(width: 360, height: 14)
                    .allowsHitTesting(false)
            }
        }
        #else
        content
        #endif
    }
}

#if MINITI_TEST_HOST && os(macOS)
private struct MacAppearanceProbe: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    func makeNSView(context: Context) -> AppearanceLabel {
        let label = AppearanceLabel(labelWithString: "")
        label.font = .systemFont(ofSize: 9)
        label.setAccessibilityIdentifier("appearance.\(name)")
        return label
    }
    func updateNSView(_ label: AppearanceLabel, context: Context) {
        label.swiftUIScheme = colorScheme == .dark ? "dark" : "light"
        label.refresh()
    }
    final class AppearanceLabel: NSTextField {
        var swiftUIScheme = "unknown"
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
        func refresh() {
            func scheme(_ appearance: NSAppearance?) -> String {
                appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
            }
            stringValue = "swiftUI=\(swiftUIScheme); window=\(scheme(window?.effectiveAppearance)); app=\(scheme(NSApp.effectiveAppearance))"
        }
    }
}
#endif
