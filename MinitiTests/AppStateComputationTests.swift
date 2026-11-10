import XCTest
import SwiftData
import Combine
import UserNotifications
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class AppStateComputationTests: XCTestCase {

    func testSettingsLegacyDestinationsMapIntoStableSidebarDestinations() {
        XCTAssertEqual(SettingsDestination.fromLegacyID("general"), .general)
        XCTAssertEqual(SettingsDestination.fromLegacyID("apikeys"), .account)
        XCTAssertEqual(SettingsDestination.fromLegacyID("audio"), .recording)
        XCTAssertEqual(SettingsDestination.fromLegacyID("integrations"), .calendar)
        XCTAssertEqual(SettingsDestination.fromLegacyID("mcp"), .playbook)
        XCTAssertEqual(SettingsDestination.fromLegacyID("docsMCP"), .playbook)
        XCTAssertEqual(SettingsDestination.fromLegacyID("language"), .transcription)
        XCTAssertEqual(SettingsDestination.fromLegacyID("dataExport"), .data)
        XCTAssertEqual(SettingsDestination.fromLegacyID("privacySupport"), .privacy)
        XCTAssertEqual(SettingsDestination.fromLegacyID("about"), .about)
        XCTAssertEqual(SettingsDestination.fromLegacyID("privacy"), .privacy)
        XCTAssertEqual(SettingsDestination.fromLegacyID("unknown"), .general)
        XCTAssertEqual(SettingsDestination.fromLegacyID("sending"), .privacy)
        XCTAssertEqual(SettingsDestination.fromLegacyID("whatLeaves"), .privacy)
        XCTAssertEqual(SettingsDestination.fromLegacyID("models"), .models)
        XCTAssertEqual(SettingsGroup.setup.destinations, [.general, .account, .cloud, .models])
    }

    func testModelConfigureLinksAndMovedSearchResultsKeepTheirOwners() {
        for target in ["transcription.model", "transcription.speakers", "transcription.voices"] {
            XCTAssertEqual(SettingsSearchCatalog.items.first { $0.id == target }?.destination, .transcription)
        }
        for platform in [SettingsPlatform.macOS, .iOS] {
            let items = SettingsSearchCatalog.availableItems(on: platform, appMode: .managed)
            XCTAssertEqual(items.first { $0.id == "sending.overview" }?.destination, .privacy)
            XCTAssertEqual(items.first { $0.id == "privacy.models" }?.destination, .models)
        }
    }

    func testEveryDestinationSitsInExactlyOneGroupAndCatalogIdsFollowTheirTab() {
        let grouped = SettingsGroup.allCases.flatMap(\.destinations)
        XCTAssertEqual(grouped.count, SettingsDestination.allCases.count)
        XCTAssertEqual(Set(grouped), Set(SettingsDestination.allCases))
        XCTAssertEqual(SettingsGroup.privacy.destinations, [.privacy])
        XCTAssertEqual(SettingsGroup.support.destinations, [.help, .about])
        for item in SettingsSearchCatalog.items {
            // Legacy "integrations." ids are allowed for calendar, CRM and webhook rows; every other
            // id starts with its tab so a search hit can never scroll the wrong screen.
            if item.id.hasPrefix("integrations.") {
                XCTAssertTrue([.calendar, .crm, .webhooks].contains(item.destination), item.id)
            } else if ["account.deviceID", "about.support"].contains(item.id) {
                XCTAssertEqual(item.destination, .help)
            } else if item.id == "sending.overview" {
                XCTAssertEqual(item.destination, .privacy, "Existing overview links must reach Privacy")
            } else if item.id == "privacy.models" {
                XCTAssertEqual(item.destination, .models, "Existing model links must reach Models")
            } else {
                XCTAssertTrue(item.id.hasPrefix(item.destination.rawValue + "."), "\(item.id) is filed under \(item.destination.rawValue)")
            }
        }
    }

    func testSettingsSearchCatalogFiltersByQueryPlatformAndMode() throws {
        let macBYOK = SettingsSearchCatalog.availableItems(on: .macOS, appMode: .byok)
        let macManaged = SettingsSearchCatalog.availableItems(on: .macOS, appMode: .managed)
        let iOSBYOK = SettingsSearchCatalog.availableItems(on: .iOS, appMode: .byok)

        XCTAssertTrue(macBYOK.contains(where: { $0.id == "account.deepgramKey" }))
        XCTAssertFalse(macManaged.contains(where: { $0.id == "account.deepgramKey" }))
        XCTAssertFalse(iOSBYOK.contains(where: { $0.id == "integrations.attio" }))
        XCTAssertFalse(SettingsDestination.available(on: .iOS).contains(.crm))
        XCTAssertTrue(SettingsDestination.available(on: .macOS).contains(.crm))

        let byokOnlyIDs = Set(macBYOK.map(\.id)).subtracting(macManaged.map(\.id))
        XCTAssertEqual(byokOnlyIDs, ["account.deepgramKey", "account.openAIKey"])
        XCTAssertTrue(Set(macManaged.map(\.destination)).isSuperset(of: [.ai, .calendar, .crm, .webhooks, .playbook, .transcription, .privacy, .about]))

        let smartMeeting = try XCTUnwrap(macManaged.first(where: { $0.id == "integrations.smartMeetings" }))
        XCTAssertTrue(smartMeeting.matches("meeting handoff"))
        XCTAssertFalse(smartMeeting.matches("markdown folder"))

        XCTAssertEqual(Set(SettingsSearchCatalog.items.map(\.id)).count, SettingsSearchCatalog.items.count)
    }

    func testDebugLogRingPreservesNewestEntriesInOrder() {
        var ring = DebugLogger.EntryRing(capacity: 3)
        for index in 0..<5 {
            ring.append(.init(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                category: .app,
                level: .routine,
                message: "entry \(index)"
            ))
        }

        XCTAssertEqual(ring.snapshot().map(\.message), ["entry 2", "entry 3", "entry 4"])
    }

    #if IOS_TEST_TARGET
    func testLiveActivityTranscriptPrivacyShowsTextWhenEnabled() {
        XCTAssertEqual(
            LiveActivityPreferences.presentedTranscript("confidential line", isEnabled: true),
            "confidential line"
        )
    }

    func testLiveActivityTranscriptPrivacyRedactsTextWhenDisabled() {
        XCTAssertEqual(
            LiveActivityPreferences.presentedTranscript("confidential line", isEnabled: false),
            ""
        )
    }
    #endif

    @MainActor
    func testAudioLevelsStatePublishesOneAtomicSnapshot() {
        let state = AudioLevelsState()
        var publishCount = 0
        let cancellable = state.objectWillChange.sink { publishCount += 1 }

        state.update(microphoneLevel: 0.25, systemAudioLevel: 0.5)

        XCTAssertEqual(publishCount, 1)
        XCTAssertEqual(state.microphoneLevel, 0.25)
        XCTAssertEqual(state.systemAudioLevel, 0.5)
        XCTAssertEqual(state.combinedLevel, 0.5)

        state.update(microphoneLevel: 0.25, systemAudioLevel: 0.5)
        XCTAssertEqual(publishCount, 1, "An unchanged meter snapshot should not invalidate views")
        _ = cancellable
    }

    @MainActor
    func testTranscriptRuntimeStatePublishesTextAndSpeakerAtomically() {
        let state = TranscriptRuntimeState()
        var snapshots: [TranscriptRuntimeState.Snapshot] = []
        let cancellable = state.$snapshot.dropFirst().sink { snapshots.append($0) }

        state.update(interimText: "hello", currentSpeaker: 2, interimSpeaker: 2)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].interimText, "hello")
        XCTAssertEqual(snapshots[0].currentSpeaker, 2)
        XCTAssertEqual(snapshots[0].interimSpeaker, 2)
        XCTAssertEqual(snapshots[0].revision, 1)
        _ = cancellable
    }

    @MainActor
    func testDelayedFinalCannotClearANewerInterim() {
        let state = TranscriptRuntimeState()
        state.update(interimText: "first phrase", currentSpeaker: 1, interimSpeaker: 1)
        let finalRevision = state.snapshot.revision
        state.update(interimText: "next phrase", currentSpeaker: 1, interimSpeaker: 1)
        state.clearInterim(through: finalRevision)
        XCTAssertEqual(state.snapshot.interimText, "next phrase")
        state.clearInterim(through: nil)
        XCTAssertEqual(state.snapshot.interimText, "next phrase")
        state.clearInterim(through: state.snapshot.revision)
        XCTAssertEqual(state.snapshot.interimText, "")
    }

    #if os(macOS)
    @MainActor
    func testDualSourceFinalKeepsVisibleWordsUntilCommitAndPreservesNextInterim() async throws {
        let state = AppState()
        let oldMic = state.captureMicrophone, oldSystem = state.captureSystemAudio
        defer { state.captureMicrophone = oldMic; state.captureSystemAudio = oldSystem }
        state.captureMicrophone = true; state.captureSystemAudio = true
        let service = try XCTUnwrap(state.deepgramService)
        func update(_ text: String, final: Bool) -> DeepgramService.TranscriptUpdate {
            .init(text: text, speaker: 1, isFinal: final, confidence: 1, words: [], channelIndex: 1, source: .system)
        }
        func final(_ text: String, time: Double) -> DeepgramService.SpeakerSegment {
            .init(id: UUID(), speaker: 1, text: text, startTime: time, endTime: time + 1, isFinal: true, confidence: 1, channelIndex: 1, source: .system)
        }
        service.transcriptUpdate = update("First phrase", final: false)
        try await Task.sleep(for: .milliseconds(40))
        service.speakerSegments = [final("First phrase.", time: 1)]
        service.transcriptUpdate = update("First phrase.", final: true)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(state.interimText, "First phrase", "No blank while ordering waits")
        XCTAssertTrue(state.liveSegments.isEmpty)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(state.liveSegments.map(\.text), ["First phrase."])
        XCTAssertTrue(state.interimText.isEmpty)

        service.transcriptUpdate = update("Second phrase", final: false)
        try await Task.sleep(for: .milliseconds(40))
        service.speakerSegments = [final("Second phrase.", time: 3)]
        service.transcriptUpdate = update("Second phrase.", final: true)
        try await Task.sleep(for: .milliseconds(40))
        service.transcriptUpdate = update("Newer phrase", final: false)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(state.liveSegments.last?.text, "Second phrase.")
        XCTAssertEqual(state.interimText, "Newer phrase", "Older final must not erase newer words")
    }
    #endif

    func testLiveInsightCadenceRequiresMeaningfulDeltaAtMinimumInterval() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = AppState.LiveInsightCadencePolicy(
            minimumInterval: 60,
            minimumSegmentDelta: 4,
            maximumInterval: 120
        )

        XCTAssertFalse(AppState.shouldFireLiveInsightCadence(
            now: now,
            lastSuccessAt: now.addingTimeInterval(-60),
            lastAttemptAt: now.addingTimeInterval(-60),
            lastSuccessfulSegmentCount: 10,
            currentSegmentCount: 13,
            policy: policy
        ))
        XCTAssertTrue(AppState.shouldFireLiveInsightCadence(
            now: now,
            lastSuccessAt: now.addingTimeInterval(-60),
            lastAttemptAt: now.addingTimeInterval(-60),
            lastSuccessfulSegmentCount: 10,
            currentSegmentCount: 14,
            policy: policy
        ))
    }

    func testLiveInsightCadenceMaximumIntervalPreventsQuietMeetingStarvation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = AppState.LiveInsightCadencePolicy(
            minimumInterval: 60,
            minimumSegmentDelta: 6,
            maximumInterval: 120
        )

        XCTAssertTrue(AppState.shouldFireLiveInsightCadence(
            now: now,
            lastSuccessAt: now.addingTimeInterval(-120),
            lastAttemptAt: now.addingTimeInterval(-60),
            lastSuccessfulSegmentCount: 10,
            currentSegmentCount: 11,
            policy: policy
        ))
    }

    func testLiveInsightCadenceAttemptCooldownPreventsFailureRetryStorm() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = AppState.LiveInsightCadencePolicy(
            minimumInterval: 60,
            minimumSegmentDelta: 4,
            maximumInterval: 120
        )

        XCTAssertFalse(AppState.shouldFireLiveInsightCadence(
            now: now,
            lastSuccessAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-5),
            lastSuccessfulSegmentCount: 10,
            currentSegmentCount: 20,
            policy: policy
        ))
    }

    @MainActor
    func testSpecialistInsightModeRequiresOptInAndFallsBackWhenDisabled() {
        let defaults = UserDefaults.standard
        let previousSalesValue = defaults.object(forKey: "salesInsightsEnabled")
        let previousDocsURL = defaults.object(forKey: "docsMCPURL")
        let previousPlaybookValue = defaults.object(forKey: "playbookInsightsEnabled")
        defer {
            if let previousSalesValue {
                defaults.set(previousSalesValue, forKey: "salesInsightsEnabled")
            } else {
                defaults.removeObject(forKey: "salesInsightsEnabled")
            }
            if let previousDocsURL {
                defaults.set(previousDocsURL, forKey: "docsMCPURL")
            } else {
                defaults.removeObject(forKey: "docsMCPURL")
            }
            if let previousPlaybookValue {
                defaults.set(previousPlaybookValue, forKey: "playbookInsightsEnabled")
            } else {
                defaults.removeObject(forKey: "playbookInsightsEnabled")
            }
        }

        defaults.removeObject(forKey: "docsMCPURL")
        defaults.removeObject(forKey: "playbookInsightsEnabled")
        let previousTemplateValue = defaults.object(forKey: "templateInsightsEnabled")
        defaults.removeObject(forKey: "templateInsightsEnabled")
        defer {
            if let previousTemplateValue {
                defaults.set(previousTemplateValue, forKey: "templateInsightsEnabled")
            } else {
                defaults.removeObject(forKey: "templateInsightsEnabled")
            }
        }
        let state = AppState()
        state.setInsightModeEnabled(.meddpicc, enabled: false)

        XCTAssertFalse(state.isInsightModeEnabled(.meddpicc))
        XCTAssertEqual(state.enabledInsightModes, InsightsMode.coreModes)

        state.switchInsightsMode(to: .meddpicc)
        XCTAssertTrue(state.salesInsightsEnabled)
        XCTAssertEqual(state.insightsMode, .meddpicc)

        state.setInsightModeEnabled(.meddpicc, enabled: false)
        XCTAssertEqual(state.insightsMode, .standard)
    }

    @MainActor
    func testTemplateViewIsOptInAndSelectingATemplateEnablesIt() {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: "templateInsightsEnabled")
        let previousTemplateID = defaults.object(forKey: "insightTemplateID")
        defer {
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: "templateInsightsEnabled")
            } else {
                defaults.removeObject(forKey: "templateInsightsEnabled")
            }
            if let previousTemplateID {
                defaults.set(previousTemplateID, forKey: "insightTemplateID")
            } else {
                defaults.removeObject(forKey: "insightTemplateID")
            }
        }

        defaults.removeObject(forKey: "templateInsightsEnabled")
        defaults.removeObject(forKey: "insightTemplateID")
        let state = AppState()

        XCTAssertFalse(state.isInsightModeEnabled(.template))
        XCTAssertFalse(state.enabledInsightModes.contains(.template))
        XCTAssertEqual(state.selectedInsightTemplate.id, InsightTemplate.defaultID)

        state.selectInsightTemplate("interview")
        XCTAssertTrue(state.templateInsightsEnabled)
        XCTAssertEqual(state.insightsMode, .template)
        XCTAssertEqual(state.insightTemplateID, "interview")
        XCTAssertEqual(state.liveTemplateID, "interview")
        XCTAssertEqual(state.liveTemplate.id, "interview")
        XCTAssertTrue(state.enabledInsightModes.contains(.template))

        // Unknown ids are ignored rather than breaking the view.
        state.selectInsightTemplate("not-a-template")
        XCTAssertEqual(state.insightTemplateID, "interview")

        state.setInsightModeEnabled(.template, enabled: false)
        XCTAssertFalse(state.isInsightModeEnabled(.template))
        XCTAssertEqual(state.insightsMode, .standard)
    }

    @MainActor
    func testValidDocsConfigurationEnablesPlaybookAndClearingItDisablesTheView() {
        let defaults = UserDefaults.standard
        let previousDocsURL = defaults.object(forKey: "docsMCPURL")
        let previousPlaybookValue = defaults.object(forKey: "playbookInsightsEnabled")
        defer {
            if let previousDocsURL {
                defaults.set(previousDocsURL, forKey: "docsMCPURL")
            } else {
                defaults.removeObject(forKey: "docsMCPURL")
            }
            if let previousPlaybookValue {
                defaults.set(previousPlaybookValue, forKey: "playbookInsightsEnabled")
            } else {
                defaults.removeObject(forKey: "playbookInsightsEnabled")
            }
        }

        let state = AppState()
        state.docsMCPURL = ""
        state.docsMCPURL = "https://docs.lightdash.com/mcp"

        XCTAssertTrue(state.playbookInsightsEnabled)
        XCTAssertTrue(state.isInsightModeEnabled(.docs))

        state.switchInsightsMode(to: .docs)
        state.docsMCPURL = ""

        XCTAssertFalse(state.playbookInsightsEnabled)
        XCTAssertEqual(state.insightsMode, .standard)
    }

    // MARK: - Multichannel mic echo reconciliation

    func testMicEchoMatcherSuppressesPartialPlaybackDuplicate() {
        let mic = AppState.EchoComparisonSegment(
            text: "And maybe no human ever.",
            startTime: 24,
            endTime: 26
        )
        let system = AppState.EchoComparisonSegment(
            text: "Nobody alive today will, and maybe no human ever.",
            startTime: 23.2,
            endTime: 27.4
        )

        XCTAssertTrue(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: false
            )
        )
    }

    func testMicEchoMatcherUsesEnergyForFuzzyDuplicate() {
        let mic = AppState.EchoComparisonSegment(
            text: "Locked in by an invisible barrier.",
            startTime: 29,
            endTime: 31
        )
        let system = AppState.EchoComparisonSegment(
            text: "Locked in by a nearly invisible barrier, impossible to overcome.",
            startTime: 28.7,
            endTime: 33
        )

        XCTAssertTrue(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: true
            )
        )
    }

    func testMicEchoMatcherHandlesDifferentTailAfterSharedPlaybackPhrase() {
        let mic = AppState.EchoComparisonSegment(
            text: "Nobody alive today, though.",
            startTime: 24,
            endTime: 26
        )
        let system = AppState.EchoComparisonSegment(
            text: "Nobody alive today will, and maybe no human ever.",
            startTime: 23.5,
            endTime: 27
        )

        XCTAssertTrue(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: true
            )
        )
    }

    func testMicEchoMatcherPreservesGenuineOverlappingSpeech() {
        let mic = AppState.EchoComparisonSegment(
            text: "Can you pause there for a moment?",
            startTime: 10,
            endTime: 12
        )
        let system = AppState.EchoComparisonSegment(
            text: "The launch is planned for the end of September.",
            startTime: 9.5,
            endTime: 13
        )

        XCTAssertFalse(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: true
            )
        )
    }

    func testMicEchoMatcherRequiresTimeOverlap() {
        let mic = AppState.EchoComparisonSegment(text: "Same exact sentence here", startTime: 20, endTime: 22)
        let oldSystem = AppState.EchoComparisonSegment(text: "Same exact sentence here", startTime: 2, endTime: 4)

        XCTAssertFalse(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [oldSystem],
                systemDominant: true
            )
        )
    }

    func testMicEchoMatcherKeepsShortPhraseWithoutSystemDominance() {
        let mic = AppState.EchoComparisonSegment(text: "Right", startTime: 5, endTime: 5.4)
        let system = AppState.EchoComparisonSegment(text: "Right", startTime: 5, endTime: 5.4)

        XCTAssertFalse(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: false
            )
        )
        XCTAssertTrue(
            AppState.isLikelyMicEcho(
                mic: mic,
                systemSegments: [system],
                systemDominant: true
            )
        )
    }

    // MARK: - Managed Deepgram credential freshness

    func testManagedDeepgramCredentialFreshBeforeSkew() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(120)
        XCTAssertTrue(
            AppState.isManagedDeepgramCredentialFresh(
                token: "jwt",
                expiresAt: expiresAt,
                now: now,
                skew: 60
            )
        )
    }

    func testManagedDeepgramCredentialStaleWithinSkew() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(30)
        XCTAssertFalse(
            AppState.isManagedDeepgramCredentialFresh(
                token: "jwt",
                expiresAt: expiresAt,
                now: now,
                skew: 60
            )
        )
    }

    func testManagedDeepgramCredentialStaleWhenExpired() {
        let now = Date()
        XCTAssertFalse(
            AppState.isManagedDeepgramCredentialFresh(
                token: "jwt",
                expiresAt: now.addingTimeInterval(-1),
                now: now,
                skew: 60
            )
        )
    }

    func testManagedDeepgramCredentialStaleWhenMissing() {
        XCTAssertFalse(AppState.isManagedDeepgramCredentialFresh(token: nil, expiresAt: Date()))
        XCTAssertFalse(AppState.isManagedDeepgramCredentialFresh(token: "", expiresAt: Date()))
        XCTAssertFalse(AppState.isManagedDeepgramCredentialFresh(token: "jwt", expiresAt: nil))
    }

    // MARK: - isNewer (semver comparison)

    func testIsNewerMajorBump() {
        XCTAssertTrue(AppState.isNewer(remote: "2.0.0", than: "1.5.0"))
    }

    func testIsNewerMinorBump() {
        XCTAssertTrue(AppState.isNewer(remote: "1.6.0", than: "1.5.0"))
    }

    func testIsNewerPatchBump() {
        XCTAssertTrue(AppState.isNewer(remote: "1.5.1", than: "1.5.0"))
    }

    func testIsNewerEqual() {
        XCTAssertFalse(AppState.isNewer(remote: "1.5.0", than: "1.5.0"))
    }

    func testIsNewerOlder() {
        XCTAssertFalse(AppState.isNewer(remote: "1.4.0", than: "1.5.0"))
    }

    func testIsNewerMissingPatch() {
        XCTAssertTrue(AppState.isNewer(remote: "1.6", than: "1.5.0"))
    }

    func testIsNewerDoubleDigitMinor() {
        XCTAssertTrue(AppState.isNewer(remote: "1.10.0", than: "1.9.0"))
        XCTAssertFalse(AppState.isNewer(remote: "1.9.0", than: "1.10.0"))
        XCTAssertTrue(AppState.isNewer(remote: "1.20.0", than: "1.19.0"))
    }

    func testIsNewerDifferentLengths() {
        XCTAssertTrue(AppState.isNewer(remote: "1.5.0.1", than: "1.5.0"))
        XCTAssertFalse(AppState.isNewer(remote: "1.5.0", than: "1.5.0.1"))
    }

    // MARK: - isTransientInsightsError

    func testIsTransientGatewayTimeout() {
        let err = MinitiAPIService.ServiceError.serverError("HTTP 504")
        XCTAssertTrue(AppState.isTransientInsightsError(err))
    }

    func testIsTransientGatewayTimeoutText() {
        let err = MinitiAPIService.ServiceError.serverError("Gateway timeout")
        XCTAssertTrue(AppState.isTransientInsightsError(err))
    }

    func testIsTransientURLErrorTimedOut() {
        let err = URLError(.timedOut)
        XCTAssertTrue(AppState.isTransientInsightsError(err))
    }

    func testIsTransientURLErrorConnectionLost() {
        let err = URLError(.networkConnectionLost)
        XCTAssertTrue(AppState.isTransientInsightsError(err))
    }

    func testIsNotTransientLimitReached() {
        let err = MinitiAPIService.ServiceError.limitReached(minutesUsed: 500, resetsAt: nil)
        XCTAssertFalse(AppState.isTransientInsightsError(err))
    }

    func testIsNotTransientDeviceDisabled() {
        let err = MinitiAPIService.ServiceError.deviceDisabled
        XCTAssertFalse(AppState.isTransientInsightsError(err))
    }

    func testIsNotTransientGenericError() {
        let err = NSError(domain: "test", code: 1)
        XCTAssertFalse(AppState.isTransientInsightsError(err))
    }

    func testIsTransientWrappedNetworkError() {
        let urlErr = URLError(.cannotConnectToHost)
        let err = MinitiAPIService.ServiceError.networkError(urlErr)
        XCTAssertTrue(AppState.isTransientInsightsError(err))
    }

    #if os(macOS)
    // MARK: - sanitizeFilename (macOS only — markdown export)

    func testSanitizeFilenameSimple() {
        XCTAssertEqual(AppState.sanitizeFilename(from: "Hello World"), "hello-world")
    }

    func testSanitizeFilenameSpecialChars() {
        XCTAssertEqual(AppState.sanitizeFilename(from: "Q4 Planning: Review!"), "q4-planning-review")
    }

    func testSanitizeFilenameConsecutiveDashes() {
        XCTAssertEqual(AppState.sanitizeFilename(from: "hello---world"), "hello-world")
    }

    func testSanitizeFilenameLeadingTrailingDashes() {
        XCTAssertEqual(AppState.sanitizeFilename(from: " --hello-- "), "hello")
    }

    func testSanitizeFilenameEmpty() {
        XCTAssertEqual(AppState.sanitizeFilename(from: ""), "")
    }

    func testSanitizeFilenameUnicode() {
        let result = AppState.sanitizeFilename(from: "café meeting")
        XCTAssertTrue(result.contains("caf"))
        XCTAssertTrue(result.contains("meeting"))
    }
    #endif

    // MARK: - suggested titles

    func testCalendarLinkedMeetingsKeepTheEventTitle() {
        XCTAssertFalse(AppState.shouldAcceptSuggestedTitle(calendarEventId: "evt_123"))
        XCTAssertTrue(AppState.shouldAcceptSuggestedTitle(calendarEventId: nil), "ad-hoc meetings are still named from the conversation")
        XCTAssertTrue(AppState.shouldAcceptSuggestedTitle(calendarEventId: "  "), "a blank id is no link")
    }

    // MARK: - parseMeetingTitle

    func testParseMeetingTitleWithDash() {
        let result = AppState.parseMeetingTitle("20260310-003102 - My Meeting")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, "20260310-003102")
        XCTAssertEqual(result?.1, "My Meeting")
    }

    func testParseMeetingTitleWithEmDash() {
        let result = AppState.parseMeetingTitle("20260310-003102 — My Meeting")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, "20260310-003102")
        XCTAssertEqual(result?.1, "My Meeting")
    }

    func testParseMeetingTitleNoSeparator() {
        let result = AppState.parseMeetingTitle("My Meeting")
        XCTAssertNil(result)
    }

    // MARK: - buildSegmentSyncPlan

    func testBuildSegmentSyncPlanNewSegments() {
        let id1 = UUID()
        let id2 = UUID()
        let live = [
            AppState.LiveSegmentSaveSnapshot(id: id1, text: "Hello", speaker: 0, timestamp: 0),
            AppState.LiveSegmentSaveSnapshot(id: id2, text: "World", speaker: 1, timestamp: 5),
        ]
        let existing: [AppState.PersistedSegmentSnapshot] = []

        let plan = AppState.buildSegmentSyncPlan(finalSegments: live, existingSegments: existing)
        XCTAssertTrue(plan.deleteIDs.isEmpty)
        XCTAssertEqual(plan.upserts.count, 2)
    }

    func testBuildSegmentSyncPlanDeleteOldSegments() {
        let oldID = UUID()
        let newID = UUID()
        let live = [
            AppState.LiveSegmentSaveSnapshot(id: newID, text: "New", speaker: 0, timestamp: 0),
        ]
        let existing = [
            AppState.PersistedSegmentSnapshot(id: oldID, text: "Old", speaker: 0, timestamp: 0),
        ]

        let plan = AppState.buildSegmentSyncPlan(finalSegments: live, existingSegments: existing)
        XCTAssertEqual(plan.deleteIDs, [oldID])
        XCTAssertEqual(plan.upserts.count, 1)
    }

    func testBuildSegmentSyncPlanNoChanges() {
        let id = UUID()
        let live = [
            AppState.LiveSegmentSaveSnapshot(id: id, text: "Same", speaker: 0, timestamp: 5),
        ]
        let existing = [
            AppState.PersistedSegmentSnapshot(id: id, text: "Same", speaker: 0, timestamp: 5),
        ]

        let plan = AppState.buildSegmentSyncPlan(finalSegments: live, existingSegments: existing)
        XCTAssertTrue(plan.deleteIDs.isEmpty)
        XCTAssertTrue(plan.upserts.isEmpty)
    }

    func testBuildSegmentSyncPlanTextChanged() {
        let id = UUID()
        let live = [
            AppState.LiveSegmentSaveSnapshot(id: id, text: "Updated", speaker: 0, timestamp: 5),
        ]
        let existing = [
            AppState.PersistedSegmentSnapshot(id: id, text: "Original", speaker: 0, timestamp: 5),
        ]

        let plan = AppState.buildSegmentSyncPlan(finalSegments: live, existingSegments: existing)
        XCTAssertTrue(plan.deleteIDs.isEmpty)
        XCTAssertEqual(plan.upserts.count, 1)
        XCTAssertEqual(plan.upserts[0].text, "Updated")
    }

    func testBuildSegmentSyncPlanSpeakerChanged() {
        let id = UUID()
        let live = [
            AppState.LiveSegmentSaveSnapshot(id: id, text: "Same", speaker: 1, timestamp: 5),
        ]
        let existing = [
            AppState.PersistedSegmentSnapshot(id: id, text: "Same", speaker: 0, timestamp: 5),
        ]

        let plan = AppState.buildSegmentSyncPlan(finalSegments: live, existingSegments: existing)
        XCTAssertEqual(plan.upserts.count, 1)
    }

    func testBuildSegmentSyncPlanEmptyBoth() {
        let plan = AppState.buildSegmentSyncPlan(
            finalSegments: [],
            existingSegments: []
        )
        XCTAssertTrue(plan.deleteIDs.isEmpty)
        XCTAssertTrue(plan.upserts.isEmpty)
    }

    #if os(macOS)
    // MARK: - exportFilename (macOS only — markdown export)

    @MainActor
    func testExportFilenameBasic() {
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 3, day: 15, hour: 14, minute: 30).date!
        let meeting = Meeting(title: "Q4 Planning", startTime: date)
        let filename = AppState.exportFilename(for: meeting)
        XCTAssertEqual(filename, "2026-03-15-1430-q4-planning.md")
    }

    @MainActor
    func testExportFilenameStripsTimestampPrefix() {
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 3, day: 15, hour: 14, minute: 30).date!
        let meeting = Meeting(title: "20260315-143000 - Q4 Planning", startTime: date)
        let filename = AppState.exportFilename(for: meeting)
        XCTAssertEqual(filename, "2026-03-15-1430-q4-planning.md")
    }

    @MainActor
    func testExportFilenameEmptyTitle() {
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 3, day: 15, hour: 14, minute: 30).date!
        let meeting = Meeting(title: "", startTime: date)
        let filename = AppState.exportFilename(for: meeting)
        XCTAssertEqual(filename, "2026-03-15-1430.md")
    }
    #endif

    // MARK: - Speaker identity recovery

    /// The identity allocator gives a reconnected socket fresh, collision-free app
    /// speaker IDs, so names, overrides, and self marks attached to segments from
    /// earlier sockets must survive a reconnect untouched.
    @MainActor
    func testResetSpeakerIdentityForDeepgramReconnectPreservesIdentities() {
        let state = AppState()
        let meeting = Meeting(title: "live")
        let micKey = String(DeepgramService.micSpeakerID)

        state.currentMeeting = meeting
        state.liveSpeakerNames = [
            "0": "Alice",
            "2": "Bob",
            micKey: "Ian",
        ]
        state.liveSpeakerOverrides = ["0", micKey]
        state.liveSelfSpeakerIDs = [DeepgramService.micSpeakerID, 2]

        state.resetSpeakerIdentityForDeepgramReconnect()

        XCTAssertEqual(state.liveSpeakerNames, ["0": "Alice", "2": "Bob", micKey: "Ian"])
        XCTAssertEqual(state.liveSpeakerOverrides, ["0", micKey])
        XCTAssertEqual(state.liveSelfSpeakerIDs, [DeepgramService.micSpeakerID, 2])
    }

    /// Reconnect allocation contract: the sole primary mic identity continues as 1000
    /// across sockets; system speakers and additional mic speakers get fresh IDs that
    /// never collide with earlier ones, even though Deepgram numbering restarts at 0.
    func testSpeakerIdentityAllocationAcrossReconnects() {
        var identity = SpeakerIdentityState()
        identity.beginConnection(preservingIdentities: false)

        // First socket: mic provider 0 -> 1000, system providers keep their numbers.
        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 0), 1000)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 0), 0)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 1), 1)
        // Stable within the socket.
        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 0), 1000)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 1), 1)

        // Reconnect with a single mic speaker: mic continuity keeps 1000; system
        // provider 0 is a fresh person and must not collide with earlier speaker 0.
        identity.beginConnection(preservingIdentities: true)
        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 0), 1000)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 0), 2)
        // A second mic speaker on the new socket gets a fresh mic-range ID.
        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 1), 1001)

        // Next reconnect: several mic speakers existed, so nobody can claim 1000.
        identity.beginConnection(preservingIdentities: true)
        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 0), 1002)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 0), 3)
    }

    func testSpeakerIdentitySeedingAfterRelaunchAvoidsCollisions() {
        var identity = SpeakerIdentityState()
        identity.seedRestoredAppSpeakerIDs([0, 1, 1000])
        identity.beginConnection(preservingIdentities: true)

        XCTAssertEqual(identity.appSpeakerID(source: .microphone, providerID: 0), 1000)
        XCTAssertEqual(identity.appSpeakerID(source: .system, providerID: 0), 2)

        var multiMic = SpeakerIdentityState()
        multiMic.seedRestoredAppSpeakerIDs([0, 1000, 1001])
        multiMic.beginConnection(preservingIdentities: true)
        // Restored meeting already had two mic speakers — no 1000 continuity.
        XCTAssertEqual(multiMic.appSpeakerID(source: .microphone, providerID: 0), 1002)
    }

    func testUnknownSourcePassesProviderIDThrough() {
        var identity = SpeakerIdentityState()
        identity.beginConnection(preservingIdentities: false)
        XCTAssertEqual(identity.appSpeakerID(source: .unknown, providerID: 4), 4)
    }

    func testTranscriptSupportedSpeakerNamesRejectsUnsupportedCandidateGuess() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Let's review the roadmap.", speaker: 0, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Sounds good to me.", speaker: 1, timestamp: 4, isFinal: true),
        ]

        let supported = AppState.transcriptSupportedSpeakerNames(["0": "Alice"], finalSegments: segments)

        XCTAssertTrue(supported.isEmpty)
    }

    func testTranscriptSupportedSpeakerNamesAcceptsSelfIntroduction() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Hi, I'm Alice from product.", speaker: 0, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Great, thanks.", speaker: 1, timestamp: 4, isFinal: true),
        ]

        let supported = AppState.transcriptSupportedSpeakerNames(["0": "Alice"], finalSegments: segments)

        XCTAssertEqual(supported, ["0": "Alice"])
    }

    func testTranscriptSupportedSpeakerNamesAcceptsAdjacentDirectAddress() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "The launch risk is mostly onboarding.", speaker: 0, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Thanks Tom, that matches what we're seeing.", speaker: 1, timestamp: 5, isFinal: true),
        ]

        let supported = AppState.transcriptSupportedSpeakerNames(["0": "Tom"], finalSegments: segments)

        XCTAssertEqual(supported, ["0": "Tom"])
    }

    func testTranscriptSupportedSpeakerNamesCalendarAttendeeUsesWiderWindow() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "We should sync with engineering.", speaker: 0, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Agreed.", speaker: 1, timestamp: 3, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Sasha owns that queue.", speaker: 1, timestamp: 6, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "That queue is busy.", speaker: 1, timestamp: 9, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "I'll take it.", speaker: 0, timestamp: 12, isFinal: true),
        ]
        // Free-form names stay adjacent-only: the name is two segments away from Sasha's speech.
        XCTAssertTrue(
            AppState.transcriptSupportedSpeakerNames(["0": "Sasha"], finalSegments: segments).isEmpty
        )
        // Calendar attendees accept a three-segment window.
        XCTAssertEqual(
            AppState.transcriptSupportedSpeakerNames(
                ["0": "Sasha"],
                finalSegments: segments,
                calendarAttendeeNames: ["Sasha"]
            ),
            ["0": "Sasha"]
        )
    }

    func testTranscriptSupportedSpeakerNamesRejectsThirdPartyMentionEvenForCalendar() {
        // "Did Sasha send the doc?" spoken by someone else without a nearby
        // segment from the candidate ID must not name that ID.
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Did Sasha send the doc?", speaker: 1, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Not yet.", speaker: 2, timestamp: 3, isFinal: true),
        ]
        XCTAssertTrue(
            AppState.transcriptSupportedSpeakerNames(
                ["0": "Sasha"],
                finalSegments: segments,
                calendarAttendeeNames: ["Sasha"]
            ).isEmpty
        )
    }

    // MARK: - Interrupted meeting resume

    @MainActor
    func testResumeInterruptedMeetingDoesNotRestoreStaleDraft() throws {
        let now = Date()
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        // Last segment is 120s in, startTime is 48h ago → last activity ≈ 48h ago → stale.
        let stale = Meeting(
            title: "yesterday",
            startTime: now.addingTimeInterval(-48 * 60 * 60)
        )
        stale.segments = [
            TranscriptSegment(text: "Old words", speaker: 0, timestamp: 120, isFinal: true),
        ]
        stale.speakerNames = ["0": "Alice"]
        context.insert(stale)
        try context.save()

        let state = AppState()
        state.modelContext = context
        state.resumeInterruptedMeeting()

        XCTAssertNil(state.currentMeeting)
        XCTAssertEqual(state.liveSpeakerNames, [:])
        XCTAssertEqual(stale.endTime, stale.startTime.addingTimeInterval(120))
    }

    @MainActor
    func testResumeInterruptedMeetingStillRestoresRecentDraft() throws {
        let now = Date()
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let recent = Meeting(title: "recent", startTime: now.addingTimeInterval(-60 * 60))
        recent.segments = [
            TranscriptSegment(text: "Fresh words", speaker: 1, timestamp: 45, isFinal: true),
        ]
        recent.speakerNames = ["1": "Pat"]
        context.insert(recent)
        try context.save()

        let state = AppState()
        state.modelContext = context
        state.resumeInterruptedMeeting()

        XCTAssertEqual(state.currentMeeting?.id, recent.id)
        XCTAssertEqual(state.liveSpeakerNames, ["1": "Pat"])
        XCTAssertEqual(recent.endTime, AppState.estimatedLastActivity(recent, now: now))
    }

    @MainActor
    func testResumeInterruptedMeetingRestoresOnlyFinalNonEmptySegments() throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let recent = Meeting(title: "recent", startTime: Date().addingTimeInterval(-60))
        recent.segments = [
            TranscriptSegment(text: "Final words", speaker: 1, timestamp: 10, isFinal: true),
            TranscriptSegment(text: "   ", speaker: 1, timestamp: 11, isFinal: true),
            TranscriptSegment(text: "Interim draft", speaker: 1, timestamp: 12, isFinal: false),
        ]
        context.insert(recent)
        try context.save()

        let state = AppState()
        state.modelContext = context
        state.resumeInterruptedMeeting()

        XCTAssertEqual(state.liveSegments.map(\.text), ["Final words"])
        XCTAssertTrue(state.liveSegments.allSatisfy(\.isFinal))
    }

    @MainActor
    func testResumeInterruptedMeetingRestoresLongRunningDraftWithRecentActivity() throws {
        let now = Date()
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        // startTime far outside the 12h window, but the last transcript segment is only 1h in
        // the past → last activity is recent → should still auto-resume.
        let longRunning = Meeting(
            title: "marathon",
            startTime: now.addingTimeInterval(-20 * 60 * 60)
        )
        let recentOffset: TimeInterval = 19 * 60 * 60
        longRunning.segments = [
            TranscriptSegment(text: "Earlier", speaker: 0, timestamp: 60, isFinal: true),
            TranscriptSegment(text: "Still talking", speaker: 0, timestamp: recentOffset, isFinal: true),
        ]
        context.insert(longRunning)
        try context.save()

        let state = AppState()
        state.modelContext = context
        state.resumeInterruptedMeeting()

        XCTAssertEqual(state.currentMeeting?.id, longRunning.id)
        XCTAssertEqual(longRunning.endTime, AppState.estimatedLastActivity(longRunning, now: now))
    }

    // MARK: - formattedDuration

    @MainActor
    func testFormattedDurationZero() {
        let state = AppState()
        state.recordingDuration = 0
        XCTAssertEqual(state.formattedDuration, "00:00")
    }

    @MainActor
    func testFormattedDurationSeconds() {
        let state = AppState()
        state.recordingDuration = 59
        XCTAssertEqual(state.formattedDuration, "00:59")
    }

    @MainActor
    func testFormattedDurationOneMinute() {
        let state = AppState()
        state.recordingDuration = 60
        XCTAssertEqual(state.formattedDuration, "01:00")
    }

    @MainActor
    func testFormattedDurationOverOneHour() {
        let state = AppState()
        state.recordingDuration = 3661
        XCTAssertEqual(state.formattedDuration, "61:01")
    }

    // MARK: - formattedDisplayRemaining

    @MainActor
    func testFormattedDisplayRemainingMinutesOnly() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 450, limit: 500)
        XCTAssertEqual(state.formattedDisplayRemaining, "50m")
    }

    @MainActor
    func testFormattedDisplayRemainingHoursAndMinutes() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 0, limit: 500)
        XCTAssertEqual(state.formattedDisplayRemaining, "8h 20m")
    }

    @MainActor
    func testFormattedDisplayRemainingZero() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 500, limit: 500)
        XCTAssertEqual(state.formattedDisplayRemaining, "0m")
    }

    // MARK: - displayMinutesLimit / displayMinutesRemaining / displayUsagePercentage

    @MainActor
    func testDisplayMinutesLimitByok() {
        let state = AppState()
        state.appMode = .byok
        XCTAssertEqual(state.displayMinutesLimit, 0)
    }

    @MainActor
    func testDisplayMinutesLimitManagedFree() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 100, limit: 500, tier: "free")
        XCTAssertEqual(state.displayMinutesLimit, 500)
    }

    @MainActor
    func testDisplayMinutesLimitManagedPro() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 100, limit: 5000, tier: "pro")
        XCTAssertEqual(state.displayMinutesLimit, 5000)
    }

    @MainActor
    func testDisplayMinutesLimitManagedNoUsageInfo() {
        let state = AppState()
        state.appMode = .managed
        XCTAssertEqual(state.displayMinutesLimit, 500)
    }

    #if os(iOS)
    @MainActor
    func testDisplayMinutesLimitManagedUsesLocalAppStoreEntitlementWhileUsageLoads() {
        let state = AppState()
        state.appMode = .managed
        state.hasActiveAppStoreSubscription = true
        XCTAssertEqual(state.displayMinutesLimit, 5000)
    }
    #endif

    @MainActor
    func testDisplayMinutesRemaining() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 300, limit: 500)
        XCTAssertEqual(state.displayMinutesRemaining, 200)
    }

    @MainActor
    func testDisplayMinutesRemainingNeverNegative() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 600, limit: 500)
        XCTAssertEqual(state.displayMinutesRemaining, 0)
    }

    @MainActor
    func testDisplayUsagePercentage() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 250, limit: 500)
        XCTAssertEqual(state.displayUsagePercentage, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testDisplayUsagePercentageCapped() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 1000, limit: 500)
        XCTAssertEqual(state.displayUsagePercentage, 1.0)
    }

    @MainActor
    func testDisplayUsagePercentageZeroLimit() {
        let state = AppState()
        state.appMode = .byok
        XCTAssertEqual(state.displayUsagePercentage, 0)
    }

    // MARK: - isPro

    @MainActor
    func testIsProFreeUser() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 0, limit: 500, tier: "free")
        XCTAssertFalse(state.isPro)
    }

    @MainActor
    func testIsProBackendPro() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 0, limit: 5000, tier: "pro")
        XCTAssertTrue(state.isPro)
    }

    @MainActor
    func testIsProNoUsageInfo() {
        let state = AppState()
        state.appMode = .managed
        XCTAssertFalse(state.isPro)
    }

    #if os(iOS)
    @MainActor
    func testIsProUsesLocalAppStoreEntitlementWhenBackendStateIsStale() {
        let state = AppState()
        state.appMode = .managed
        state.hasActiveAppStoreSubscription = true
        XCTAssertTrue(state.isPro)
    }
    #endif

    // MARK: - isLimitReached

    @MainActor
    func testIsLimitReachedByok() {
        let state = AppState()
        state.appMode = .byok
        XCTAssertFalse(state.isLimitReached)
    }

    @MainActor
    func testIsLimitReachedManagedNotReached() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 100, limit: 500)
        XCTAssertFalse(state.isLimitReached)
    }

    #if os(iOS)
    @MainActor
    func testIsLimitReachedManagedIgnoresStaleBackendLimitWhenAppStoreSubscriptionIsActive() {
        let state = AppState()
        state.appMode = .managed
        state.hasActiveAppStoreSubscription = true
        state.usageInfo = Self.makeUsageInfo(used: 500, limit: 500)
        XCTAssertFalse(state.isLimitReached)
    }

    @MainActor
    func testManagedSubscriptionPlaceholderHiddenWhenLocalAppStoreEntitlementIsAlreadyActive() {
        let state = AppState()
        state.appMode = .managed
        state.isLoadingUsage = true
        state.hasActiveAppStoreSubscription = true
        XCTAssertFalse(state.shouldShowManagedSubscriptionPlaceholder)
    }
    #endif

    @MainActor
    func testIsLimitReachedManagedAtLimit() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 500, limit: 500)
        XCTAssertTrue(state.isLimitReached)
    }

    @MainActor
    func testIsLimitReachedManagedNoUsageInfo() {
        let state = AppState()
        state.appMode = .managed
        XCTAssertFalse(state.isLimitReached)
    }

    // MARK: - canStartRecording

    @MainActor
    func testCanStartRecordingByokWithKey() {
        let state = AppState()
        state.appMode = .byok
        state.deepgramApiKey = "some-key"
        XCTAssertTrue(state.canStartRecording)
    }

    @MainActor
    func testCanStartRecordingByokNoKey() {
        let state = AppState()
        state.appMode = .byok
        state.deepgramApiKey = ""
        // The host install may have on-device transcription on, which needs no key.
        let previous = UserDefaults.standard.object(forKey: "onDeviceTranscription")
        state.onDeviceTranscriptionEnabled = false
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "onDeviceTranscription") } else { UserDefaults.standard.removeObject(forKey: "onDeviceTranscription") }
        }
        XCTAssertFalse(state.canStartRecording)
    }

    @MainActor
    func testCanStartRecordingByokWithoutKeyWhenOnDeviceTranscriptionIsOnButNotReady() {
        let state = AppState()
        state.appMode = .byok
        state.deepgramApiKey = ""
        let previous = UserDefaults.standard.object(forKey: "onDeviceTranscription")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "onDeviceTranscription") } else { UserDefaults.standard.removeObject(forKey: "onDeviceTranscription") }
        }
        state.onDeviceTranscriptionEnabled = true
        // No model loaded or on disk in a fresh service: the key is still required, and a start
        // would be refused rather than quietly sent to Deepgram.
        if !state.onDeviceTranscription.isReady(forLanguageCode: "en"),
           !OnDeviceTranscriptionService.isDownloaded(languageCode: "en") {
            XCTAssertFalse(state.willTranscribeOnDevice)
            XCTAssertFalse(state.canStartRecording)
            XCTAssertTrue(state.onDeviceTranscriptionBlocksStart)
            state.onDeviceTranscriptionCloudFallback = true
            XCTAssertFalse(state.onDeviceTranscriptionBlocksStart)
            state.onDeviceTranscriptionCloudFallback = false
        }
        state.meetingLanguage = "el"
        XCTAssertFalse(state.willTranscribeOnDevice, "Greek stays on Deepgram")
        XCTAssertFalse(state.onDeviceTranscriptionBlocksStart, "a cloud-only language never blocks a start")
    }

    @MainActor
    func testCanStartRecordingManagedOk() {
        let state = AppState()
        state.appMode = .managed
        state.isDeviceDisabled = false
        state.usageInfo = Self.makeUsageInfo(used: 100, limit: 500)
        XCTAssertTrue(state.canStartRecording)
    }

    @MainActor
    func testCanStartRecordingManagedDisabled() {
        let state = AppState()
        state.appMode = .managed
        state.isDeviceDisabled = true
        XCTAssertFalse(state.canStartRecording)
    }

    @MainActor
    func testCanStartRecordingManagedLimitReached() {
        let state = AppState()
        state.appMode = .managed
        state.usageInfo = Self.makeUsageInfo(used: 500, limit: 500)
        XCTAssertFalse(state.canStartRecording)
    }

    // MARK: - Transcript trimming

    func testTranscriptTextAfterDeletingSelectionsNormalizesWhitespace() {
        let id = UUID()
        let selection = TranscriptTextSelection(segmentID: id, lowerUTF16Offset: 6, upperUTF16Offset: 16)
        let trimmed = AppState.transcriptTextAfterDeletingSelections([selection], from: "hello brave new world!")
        XCTAssertEqual(trimmed, "hello world!")
    }

    @MainActor
    func testMarkTranscriptEditedClearsGeneratedInsights() {
        let meeting = Meeting(
            title: "edited",
            summaryText: "summary",
            actionItems: ["follow up"],
            keyDecisions: ["decide"],
            topics: ["topic"],
            discussionFlow: ["flow"],
            meddpiccMetrics: "metric",
            meddpiccEconomicBuyer: "buyer"
        )
        meeting.suggestedQuestions = [SuggestedQuestion(question: "What next?", type: "follow_up", context: "context")]

        meeting.markTranscriptEdited()

        XCTAssertNotNil(meeting.transcriptEditedAt)
        XCTAssertEqual(meeting.transcriptRevision, 1)
        XCTAssertFalse(meeting.hasGeneratedInsights)
        XCTAssertTrue(meeting.needsInsightsAfterTranscriptEdit)
    }

    func testMarkTranscriptCorrectedBumpsRevisionAndKeepsInsights() {
        let meeting = Meeting(
            title: "corrected",
            summaryText: "summary",
            actionItems: ["follow up"],
            keyDecisions: ["decide"],
            topics: ["topic"],
            discussionFlow: ["flow"],
            meddpiccMetrics: "metric",
            meddpiccEconomicBuyer: "buyer"
        )
        meeting.suggestedQuestions = [SuggestedQuestion(question: "What next?", type: "follow_up", context: "context")]

        meeting.markTranscriptCorrected()

        XCTAssertNotNil(meeting.transcriptEditedAt)
        XCTAssertEqual(meeting.transcriptRevision, 1)
        XCTAssertTrue(meeting.hasGeneratedInsights)
        XCTAssertEqual(meeting.summaryText, "summary")
        XCTAssertEqual(meeting.suggestedQuestions.count, 1)
    }

    @MainActor
    func testRetroactiveCorrectionRewritesOnlyMatchingTextInOnePublish() {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: PersonalDictionaryPreferences.correctionsStorageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: PersonalDictionaryPreferences.correctionsStorageKey)
            } else {
                defaults.removeObject(forKey: PersonalDictionaryPreferences.correctionsStorageKey)
            }
        }
        PersonalDictionaryPreferences.saveCorrections([.init(heard: "many tea", correct: "miniti")], defaults: defaults)

        let state = AppState()
        state.reloadTranscriptCorrector()
        let first = AppState.LiveSegment(id: UUID(), text: "we use many tea daily", speaker: 1000, timestamp: 0, isFinal: true)
        let second = AppState.LiveSegment(id: UUID(), text: "sounds good", speaker: 0, timestamp: 3, isFinal: true)
        state.liveSegments = [first, second]

        var publishes = 0
        let cancellable = state.$liveSegments.dropFirst().sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        XCTAssertTrue(state.applyRetroactiveCorrectionsToLiveTranscript())
        XCTAssertEqual(publishes, 1, "one atomic assignment")
        XCTAssertEqual(state.liveSegments.map(\.text), ["we use miniti daily", "sounds good"])
        XCTAssertEqual(state.liveSegments.map(\.id), [first.id, second.id], "identity preserved")
        XCTAssertEqual(state.liveSegments.map(\.timestamp), [0, 3])

        // Nothing left to change: no publish at all.
        XCTAssertFalse(state.applyRetroactiveCorrectionsToLiveTranscript())
        XCTAssertEqual(publishes, 1)
    }

    func testMergeFinalSegmentReplacesCumulativeTranscript() {
        let originalID = UUID()
        var segments = [
            AppState.LiveSegment(
                id: originalID,
                text: "You zoom in to the level of individual particles",
                speaker: 0,
                timestamp: 12,
                isFinal: true
            )
        ]
        let cumulative = AppState.LiveSegment(
            id: UUID(),
            text: "You zoom in to the level of individual particles, then every interaction matters",
            speaker: 0,
            timestamp: 18,
            isFinal: true
        )

        let result = AppState.mergeFinalSegment(cumulative, into: &segments)

        XCTAssertEqual(result, .replacedSuperset)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].id, originalID)
        XCTAssertEqual(segments[0].timestamp, 12)
        XCTAssertEqual(segments[0].text, cumulative.text)
    }

    func testMergeFinalSegmentSkipsContainedDuplicate() {
        var segments = [
            AppState.LiveSegment(
                id: UUID(),
                text: "typically more ordered, to more likely states, typically a mess",
                speaker: 0,
                timestamp: 10,
                isFinal: true
            )
        ]
        let shorterDuplicate = AppState.LiveSegment(
            id: UUID(),
            text: "to more likely states",
            speaker: 0,
            timestamp: 14,
            isFinal: true
        )

        let result = AppState.mergeFinalSegment(shorterDuplicate, into: &segments)

        XCTAssertEqual(result, .skippedContainedDuplicate)
        XCTAssertEqual(segments.count, 1)
    }

    func testTranscriptTimelineTimestampAddsReconnectEpoch() {
        XCTAssertEqual(
            AppState.transcriptTimelineTimestamp(streamStart: 2.75, timelineOffset: 120),
            122.75
        )
    }

    func testCollisionFreeTranscriptTimestampSeparatesEqualChannelFinals() {
        var segments = [
            AppState.LiveSegment(
                id: UUID(),
                text: "system channel",
                speaker: 1,
                timestamp: 10,
                isFinal: true
            )
        ]

        let micTimestamp = AppState.collisionFreeTranscriptTimestamp(proposed: 10, in: segments)
        XCTAssertEqual(micTimestamp, 10.000_001, accuracy: 0.000_000_1)
        segments.append(
            AppState.LiveSegment(
                id: UUID(),
                text: "mic channel",
                speaker: DeepgramService.micSpeakerID,
                timestamp: micTimestamp,
                isFinal: true
            )
        )

        let nextTimestamp = AppState.collisionFreeTranscriptTimestamp(proposed: 10, in: segments)
        XCTAssertEqual(nextTimestamp, 10.000_002, accuracy: 0.000_000_1)
    }

    func testMergeFinalSegmentInsertsDelayedMicSpeechChronologically() {
        var segments = [
            AppState.LiveSegment(
                id: UUID(),
                text: "before",
                speaker: 1,
                timestamp: 10,
                isFinal: true
            ),
            AppState.LiveSegment(
                id: UUID(),
                text: "after",
                speaker: 1,
                timestamp: 14,
                isFinal: true
            ),
        ]
        let delayedMic = AppState.LiveSegment(
            id: UUID(),
            text: "local reply",
            speaker: DeepgramService.micSpeakerID,
            timestamp: 12,
            isFinal: true
        )

        let result = AppState.mergeFinalSegment(delayedMic, into: &segments)

        XCTAssertEqual(result, .appended)
        XCTAssertEqual(segments.map(\.text), ["before", "local reply", "after"])
        XCTAssertEqual(segments.map(\.timestamp), [10, 12, 14])
    }

    func testDelayedCumulativeFinalFindsMatchBeyondRecentSuffix() {
        let originalID = UUID()
        var segments = [
            AppState.LiveSegment(
                id: originalID,
                text: "the local speaker starts",
                speaker: DeepgramService.micSpeakerID,
                timestamp: 10,
                isFinal: true
            ),
        ]
        for index in 0..<5 {
            segments.append(
                AppState.LiveSegment(
                    id: UUID(),
                    text: "later system segment \(index)",
                    speaker: 1,
                    timestamp: 11 + TimeInterval(index),
                    isFinal: true
                )
            )
        }
        let cumulative = AppState.LiveSegment(
            id: UUID(),
            text: "the local speaker starts and finishes the thought",
            speaker: DeepgramService.micSpeakerID,
            timestamp: 10.2,
            isFinal: true
        )

        let result = AppState.mergeFinalSegment(cumulative, into: &segments)

        XCTAssertEqual(result, .replacedSuperset)
        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments[0].id, originalID)
        XCTAssertEqual(segments[0].text, cumulative.text)
    }

    func testChronologicalInsertionIndexHandlesLongTranscriptMiddle() {
        let segments = (0..<4_000).map { index in
            AppState.LiveSegment(
                id: UUID(),
                text: "segment \(index)",
                speaker: index % 2,
                timestamp: TimeInterval(index * 2),
                isFinal: true
            )
        }

        XCTAssertEqual(
            AppState.chronologicalInsertionIndex(for: 3_999, in: segments),
            2_000
        )
    }

    func testStoppedInterimTranscriptIsPromotedWhenNoFinalExists() {
        var segments: [AppState.LiveSegment] = []

        let result = AppState.mergeStoppedInterimTranscript(
            "  short meeting transcript  ",
            speaker: 2,
            timestamp: 7,
            into: &segments
        )

        XCTAssertEqual(result, .appended)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "short meeting transcript")
        XCTAssertEqual(segments[0].speaker, 2)
        XCTAssertEqual(segments[0].timestamp, 7)
        XCTAssertTrue(segments[0].isFinal)
    }

    func testStoppedInterimTranscriptDoesNotDuplicateFinalFromGracefulShutdown() {
        let existingID = UUID()
        var segments = [
            AppState.LiveSegment(
                id: existingID,
                text: "short meeting transcript",
                speaker: 2,
                timestamp: 6,
                isFinal: true
            )
        ]

        let result = AppState.mergeStoppedInterimTranscript(
            "short meeting transcript",
            speaker: 2,
            timestamp: 7,
            into: &segments
        )

        XCTAssertEqual(result, .skippedExactDuplicate)
        XCTAssertEqual(segments.map(\.id), [existingID])
    }

    func testStoppedInterimTranscriptIgnoresBlankText() {
        var segments: [AppState.LiveSegment] = []

        let result = AppState.mergeStoppedInterimTranscript(
            "   \n  ",
            speaker: 0,
            timestamp: 1,
            into: &segments
        )

        XCTAssertNil(result)
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - AudioRecoveryState.label

    @MainActor func testInitialConnectionCopyIsDistinctFromReconnectAndResetsForNextAttempt() {
        let state = AppState()
        let service = DeepgramService()
        state.deepgramService = service
        state.audioCaptureService = nil
        state.isRecording = true
        defer { state.isRecording = false; state.updateAudioRecoveryState() }

        service.connectionState = .connecting
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioStatusLabel, "connecting transcription…")
        XCTAssertTrue(state.isAudioStartupStatus, "Normal connection must not use warning styling")
        #if os(macOS)
        XCTAssertEqual(state.recordingPresence.audioStatus, "Connecting transcription…")
        #endif

        service.connectionState = .connected
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioStatusLabel, "starting audio…", "A socket alone does not prove capture")
        XCTAssertTrue(state.isAudioStartupStatus)

        service.connectionState = .error
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioRecoveryState, .degraded)
        service.connectionState = .connecting
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioRecoveryActivity, .reconnectingTranscription)
        XCTAssertFalse(state.isAudioStartupStatus)
        XCTAssertEqual(state.audioRecoveryState, .degraded, "Keep the existing recovery hold, not a cosmetic policy change")

        state.isRecording = false
        state.updateAudioRecoveryState()
        state.beginRecordingDiagnostics()
        state.isRecording = true
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioStatusLabel, "connecting transcription…", "A new recording starts fresh")
        XCTAssertTrue(state.isAudioStartupStatus)
    }

    func testAudioRecoveryStateHealthy() {
        XCTAssertEqual(AppState.AudioRecoveryState.healthy.label, "audio healthy")
    }

    func testAudioRecoveryStateRecovering() {
        XCTAssertEqual(AppState.AudioRecoveryState.recovering.label, "recovering audio...")
    }

    func testAudioRecoveryStateDegraded() {
        XCTAssertEqual(AppState.AudioRecoveryState.degraded.label, "audio degraded")
    }

    // MARK: - Google Calendar disconnect cleanup

    func testCalendarPrepNotesCodingRoundTrip() {
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let records = [
            "evt-1": AppState.CalendarPrepNote(
                eventID: "evt-1",
                text: "Ask about the rollout plan",
                eventStart: now.addingTimeInterval(3_600),
                updatedAt: now
            )
        ]

        let data = AppState.encodeCalendarPrepNotes(records)
        XCTAssertNotNil(data)
        XCTAssertEqual(AppState.decodeCalendarPrepNotes(data), records)
        XCTAssertEqual(AppState.decodeCalendarPrepNotes(Data("invalid".utf8)), [:])
    }

    func testInvestigationFocusRecognizesResearchAndCapabilityQuestions() {
        XCTAssertEqual(
            AppState.investigationFocus(from: "Could we integrate this workflow with the codebase?"),
            "Could we integrate this workflow with the codebase?"
        )
        XCTAssertEqual(
            AppState.investigationFocus(from: "Please look into why the export is failing."),
            "Please look into why the export is failing."
        )
        XCTAssertNil(AppState.investigationFocus(from: "How are you doing today?"))
        XCTAssertNil(AppState.investigationFocus(from: "Let's meet again on Tuesday."))
    }

    func testInvestigationMeetingContextIncludesPrepAndRecentTranscriptWithinLimit() {
        let segments = [
            AppState.LiveSegment(
                id: UUID(),
                text: "Could we automate this approval flow?",
                speaker: 1,
                timestamp: 10,
                isFinal: true
            ),
            AppState.LiveSegment(
                id: UUID(),
                text: String(repeating: "implementation context ", count: 500),
                speaker: 2,
                timestamp: 20,
                isFinal: true
            )
        ]

        let context = AppState.investigationMeetingContext(
            meetingTitle: "Workflow review",
            prepNotes: "Compare the current manual process.",
            segments: segments,
            maxCharacters: 5_000
        )

        XCTAssertLessThanOrEqual(context.count, 5_000)
        XCTAssertTrue(context.contains("Workflow review"))
        XCTAssertTrue(context.contains("Compare the current manual process."))
        XCTAssertTrue(context.contains("Could we automate this approval flow?"))
        XCTAssertTrue(context.contains("Recent conversation"))
        XCTAssertTrue(context.contains("Speaker 2: Could we automate this approval flow?"))
    }

    #if os(macOS)
    func testCodebaseSnapshotRanksRelevantSourceAndBoundsContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniti-investigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("struct BillingCoordinator { func retryInvoicePayment() {} }".utf8)
            .write(to: root.appendingPathComponent("BillingCoordinator.swift"))
        try Data("struct UnrelatedWaveformRenderer {}".utf8)
            .write(to: root.appendingPathComponent("Waveform.swift"))
        // The folder is chosen through a symlink, as `/var/folders` and `/tmp` are on every Mac
        // (CI reported "E7F9F2FC/BillingCoordinator.swift" because the relative path was cut by
        // the unresolved root's length).
        let alias = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniti-investigation-alias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }

        let snapshot = try AppState.buildCodebaseSnapshot(
            rootURL: alias,
            focus: "Could we retry a failed invoice payment?",
            maxCharacters: 2_000,
            maxFiles: 2
        )

        XCTAssertEqual(snapshot.files.first, "BillingCoordinator.swift")
        XCTAssertTrue(snapshot.context.contains("retryInvoicePayment"))
        XCTAssertLessThanOrEqual(snapshot.context.count, 2_000)
    }

    func testCodebaseSnapshotSkipsSymlinksAndRedactsLikelySecrets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniti-investigation-security-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniti-investigation-outside-\(UUID().uuidString).swift")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try Data("let apiKey = super-secret-value\nfunc retryPayment() {}".utf8)
            .write(to: root.appendingPathComponent("Billing.swift"))
        try Data("func retryPaymentOutsideFolder() {}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Outside.swift"),
            withDestinationURL: outside
        )

        let snapshot = try AppState.buildCodebaseSnapshot(
            rootURL: root,
            focus: "retry payment api key",
            maxCharacters: 2_000,
            maxFiles: 4
        )

        XCTAssertEqual(snapshot.files, ["Billing.swift"])
        XCTAssertTrue(snapshot.context.contains("apiKey = [REDACTED]"))
        XCTAssertFalse(snapshot.context.contains("super-secret-value"))
        XCTAssertFalse(snapshot.context.contains("retryPaymentOutsideFolder"))
    }

    func testCodebaseSecretRedactionRemovesPrivateKeyBlocks() {
        let content = """
        token: abc123
        -----BEGIN PRIVATE KEY-----
        secret-material
        -----END PRIVATE KEY-----
        """
        let redacted = AppState.redactLikelySecrets(content)
        XCTAssertTrue(redacted.contains("token: [REDACTED]"))
        XCTAssertTrue(redacted.contains("[REDACTED PRIVATE KEY]"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("secret-material"))
    }
    #endif

    @MainActor
    func testUpcomingMeetingEventsIncludesFutureDaysAndExcludesEndedEvents() {
        let state = AppState()
        let soon = Self.makeCalendarEvent(
            id: "soon",
            title: "Soon",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1_200)
        )
        let tomorrow = Self.makeCalendarEvent(
            id: "tomorrow",
            title: "Tomorrow",
            start: Date().addingTimeInterval(86_400),
            end: Date().addingTimeInterval(90_000)
        )
        let ended = Self.makeCalendarEvent(
            id: "ended",
            title: "Ended",
            start: Date().addingTimeInterval(-1_200),
            end: Date().addingTimeInterval(-600)
        )
        state.upcomingEvents = [tomorrow, ended, soon]

        XCTAssertEqual(state.upcomingMeetingEvents.map(\.id), ["soon", "tomorrow"])
    }

    @MainActor
    func testApplyGoogleCalendarDisconnectedStateClearsStaleCalendarUI() {
        let state = AppState()
        let event = Self.makeCalendarEvent(id: "evt-1", title: "Pipeline review")
        state.isGoogleCalendarConnected = true
        state.googleCalendarEmail = "ian@example.com"
        state.upcomingEvents = [event]
        state.pendingAutoStartEvent = event
        state.autoStartCountdown = 9

        state.applyGoogleCalendarDisconnectedState()

        XCTAssertFalse(state.isGoogleCalendarConnected)
        XCTAssertNil(state.googleCalendarEmail)
        XCTAssertTrue(state.upcomingEvents.isEmpty)
        XCTAssertNil(state.pendingAutoStartEvent)
        XCTAssertEqual(state.autoStartCountdown, 0)
    }

    // MARK: - Calendar join links

    func testCalendarEventJoinURLPrefersConferenceURLThenMeetLink() {
        let preferred = Self.makeCalendarEvent(
            id: "a",
            title: "Pref",
            meetLink: "https://meet.google.com/aaa",
            conferenceUrl: "https://zoom.us/j/123"
        )
        XCTAssertEqual(preferred.joinURL?.absoluteString, "https://zoom.us/j/123")

        let fallback = Self.makeCalendarEvent(
            id: "b",
            title: "Fall",
            meetLink: " https://meet.google.com/bbb "
        )
        XCTAssertEqual(fallback.joinURL?.absoluteString, "https://meet.google.com/bbb")

        let trimmedEmpty = Self.makeCalendarEvent(
            id: "c",
            title: "Empty",
            meetLink: "   ",
            conferenceUrl: ""
        )
        XCTAssertNil(trimmedEmpty.joinURL)

        let rejectsHTTP = Self.makeCalendarEvent(
            id: "d",
            title: "HTTP",
            meetLink: "http://meet.google.com/ddd"
        )
        XCTAssertNil(rejectsHTTP.joinURL)

        let rejectsJunk = Self.makeCalendarEvent(
            id: "e",
            title: "Junk",
            conferenceUrl: "not a url"
        )
        XCTAssertNil(rejectsJunk.joinURL)
    }

    @MainActor
    func testOpenMeetingLinkOneShotGuard() {
        let state = AppState()
        let event = Self.makeCalendarEvent(
            id: "join-1",
            title: "Standup",
            conferenceUrl: "https://meet.google.com/xyz-abcd-efg"
        )
        var opened: [URL] = []
        state.testOpenURLHandler = { url in
            opened.append(url)
            return true
        }

        XCTAssertTrue(state.openMeetingLink(for: event))
        XCTAssertFalse(state.openMeetingLink(for: event))
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.absoluteString, "https://meet.google.com/xyz-abcd-efg")

        // Explicit rejoin after a drop may open again.
        XCTAssertTrue(state.openMeetingLink(for: event, allowingRepeat: true))
        XCTAssertEqual(opened.count, 2)
    }

    @MainActor
    func testOpenMeetingLinkFailedOpenDoesNotBurnOneShotGuard() {
        let state = AppState()
        let event = Self.makeCalendarEvent(
            id: "join-fail",
            title: "Standup",
            conferenceUrl: "https://zoom.us/j/123"
        )
        var attempts = 0
        state.testOpenURLHandler = { _ in
            attempts += 1
            return attempts > 1
        }

        XCTAssertFalse(state.openMeetingLink(for: event), "first open fails")
        XCTAssertTrue(state.openMeetingLink(for: event), "retry from any surface must still work")
        XCTAssertFalse(state.openMeetingLink(for: event), "now one-shot blocked")
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testMeetingReminderNotNowCancelsMatchingCountdown() {
        let state = AppState()
        let event = Self.makeCalendarEvent(id: "rem-2", title: "Sync")
        state.upcomingEvents = [event]
        state.pendingAutoStartEvent = event

        state.handleNotificationResponse(
            actionIdentifier: AppState.meetingReminderNotNowAction,
            categoryIdentifier: AppState.meetingReminderNotesOnlyCategory,
            eventID: event.id
        )
        XCTAssertNil(state.pendingAutoStartEvent)
        XCTAssertTrue(state.testingDismissedAutoStartEventIDs.contains(event.id))
    }

    @MainActor
    func testMeetingReminderNotificationRouting() {
        let state = AppState()
        let event = Self.makeCalendarEvent(
            id: "rem-1",
            title: "Kickoff",
            conferenceUrl: "https://meet.google.com/kick-off"
        )
        state.upcomingEvents = [event]
        var opened: [URL] = []
        state.testOpenURLHandler = { url in
            opened.append(url)
            return true
        }

        // Force a refused start (terms not accepted). The default body tap and the
        // primary action must then NOT open the call: the user would be in a meeting
        // miniti is not recording. The one-shot guard must also stay clear so a later
        // accepted start can still open the link.
        let defaults = UserDefaults.standard
        let previousTerms = defaults.object(forKey: "acceptedTermsVersion")
        defer {
            if let previousTerms {
                defaults.set(previousTerms, forKey: "acceptedTermsVersion")
            } else {
                defaults.removeObject(forKey: "acceptedTermsVersion")
            }
        }
        defaults.set(0, forKey: "acceptedTermsVersion")
        XCTAssertFalse(state.hasAcceptedTerms)

        state.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: AppState.meetingReminderWithLinkCategory,
            eventID: event.id
        )
        XCTAssertEqual(opened.count, 0)
        state.handleNotificationResponse(
            actionIdentifier: AppState.meetingReminderPrimaryAction,
            categoryIdentifier: AppState.meetingReminderWithLinkCategory,
            eventID: event.id
        )
        XCTAssertEqual(opened.count, 0)
        XCTAssertTrue(state.openMeetingLink(for: event), "guard must not be burned by a refused start")
        XCTAssertEqual(opened.count, 1)
        XCTAssertFalse(state.openMeetingLink(for: event), "now one-shot blocked for this start")

        state.handleNotificationResponse(
            actionIdentifier: AppState.meetingReminderNotNowAction,
            categoryIdentifier: AppState.meetingReminderNotesOnlyCategory,
            eventID: "dismiss-me"
        )
        XCTAssertTrue(state.testingDismissedAutoStartEventIDs.contains("dismiss-me"))
    }

    @MainActor
    func testMeetingReminderCategoriesAreRegisteredWithSmartMeetingCategories() async throws {
        // GitHub's runner builds the host without a team signature, and such a host has no
        // working notification center: every category read comes back empty there (2026-10-19
        // and 2026-10-21 runs; an ad-hoc signature still validates, so the signature is no
        // signal, and the shell's CI variables never reach the host process). An empty read
        // right after registering is the host's limitation; a partial one is a real failure.
        AppState.registerSmartMeetingNotificationCategory()
        let categories = await withCheckedContinuation { (continuation: CheckedContinuation<Set<UNNotificationCategory>, Never>) in
            UNUserNotificationCenter.current().getNotificationCategories { cats in
                continuation.resume(returning: cats)
            }
        }
        if categories.isEmpty { throw XCTSkip("this host has no notification center") }
        let ids = Set(categories.map(\.identifier))
        XCTAssertTrue(ids.contains(AppState.meetingReminderWithLinkCategory))
        XCTAssertTrue(ids.contains(AppState.meetingReminderNotesOnlyCategory))
        XCTAssertTrue(ids.contains(AppState.smartMeetingNotificationCategory + ".calendar"))
        XCTAssertTrue(ids.contains(AppState.smartMeetingNotificationCategory + ".quiet"))
        XCTAssertTrue(ids.contains(AppState.smartMeetingNotificationCategory + ".call-start"))
    }

    // MARK: - evaluateAutoStop

    func testAutoStopFiresAfterSilenceWindow() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 300, audioGap: .infinity, autoStopMinutes: 5, calendarEventEnded: false),
            .silence
        )
    }

    func testAutoStopHoldsBeforeSilenceWindow() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 299, audioGap: .infinity, autoStopMinutes: 5, calendarEventEnded: false),
            .keepRecording
        )
    }

    func testAutoStopHoldsWhileAudioStillFlowing() {
        // The regression: transcript pipeline stalled mid-meeting while people kept talking.
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 600, audioGap: 2, autoStopMinutes: 5, calendarEventEnded: false),
            .keepRecording
        )
    }

    func testAutoStopGivesUpOnPermanentlyStalledPipeline() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 900, audioGap: 2, autoStopMinutes: 5, calendarEventEnded: false),
            .stalledPipeline
        )
    }

    func testAutoStopTreatsStaleAudioAsSilence() {
        // Audio last seen longer ago than the activity window — the room really is quiet.
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 300, audioGap: 61, autoStopMinutes: 5, calendarEventEnded: false),
            .silence
        )
    }

    func testAutoStopDisabledWhenMinutesZero() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 100_000, audioGap: .infinity, autoStopMinutes: 0, calendarEventEnded: false),
            .keepRecording
        )
    }

    func testAutoStopUsesTwoMinuteWindowAfterCalendarEventEnds() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 120, audioGap: .infinity, autoStopMinutes: 5, calendarEventEnded: true),
            .calendarSilence
        )
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 119, audioGap: .infinity, autoStopMinutes: 5, calendarEventEnded: true),
            .keepRecording
        )
    }

    func testAutoStopCalendarWindowAppliesWithAutoStopDisabled() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 120, audioGap: .infinity, autoStopMinutes: 0, calendarEventEnded: true),
            .calendarSilence
        )
    }

    func testAutoStopKeepsShorterConfiguredWindowAfterCalendarEventEnds() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 60, audioGap: .infinity, autoStopMinutes: 1, calendarEventEnded: true),
            .calendarSilence
        )
    }

    func testAutoStopCalendarPathStillBacksOffWhileAudioFlows() {
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 300, audioGap: 5, autoStopMinutes: 5, calendarEventEnded: true),
            .keepRecording
        )
        XCTAssertEqual(
            AppState.evaluateAutoStop(transcriptGap: 360, audioGap: 5, autoStopMinutes: 5, calendarEventEnded: true),
            .stalledPipeline
        )
    }

    // MARK: - Smart meetings

    func testSmartMeetingQuietThresholdsStayAheadOfConfiguredAutoStop() {
        XCTAssertEqual(AppState.smartMeetingQuietThreshold(autoStopMinutes: 0), 300)
        XCTAssertEqual(AppState.smartMeetingQuietThreshold(autoStopMinutes: 3), 120)
        XCTAssertEqual(AppState.smartMeetingQuietThreshold(autoStopMinutes: 5), 180)
        XCTAssertEqual(AppState.smartMeetingQuietThreshold(autoStopMinutes: 10), 300)
        XCTAssertEqual(AppState.smartMeetingQuietThreshold(autoStopMinutes: 15), 300)
    }

    func testSmartQuietPromptRequiresTranscriptAndBothQuietSignals() {
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: false,
            transcriptGap: 600,
            audioGap: 600,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 600,
            audioGap: 30,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
        XCTAssertTrue(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 300,
            audioGap: 300,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
    }

    func testSmartQuietPromptUsesTwoMinuteThresholdAfterCalendarEnd() {
        // Past the event's end the ask comes at two minutes (the calendar auto-stop window),
        // regardless of the silence picker; before it, the normal table applies.
        XCTAssertTrue(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 121,
            audioGap: 121,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            calendarEventEnded: true,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 121,
            audioGap: 121,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            calendarEventEnded: false,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
        // Still both signals: speech-like audio within the window holds the ask.
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 121,
            audioGap: 30,
            autoStopMinutes: 0,
            crossedCommonBoundary: false,
            calendarEventEnded: true,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: false
        ))
    }

    func testSmartMeetingSpeechGapPrefersDeepgramSpeechWhilePipelineHealthy() {
        // Healthy pipeline with VAD evidence: the room's noise floor (level gap ~0) is ignored.
        XCTAssertEqual(AppState.smartMeetingSpeechGap(pipelineHealthy: true, speechGap: 400, levelGap: 0.05), 400)
        // Healthy but no SpeechStarted has arrived this recording: keep the level.
        XCTAssertEqual(AppState.smartMeetingSpeechGap(pipelineHealthy: true, speechGap: nil, levelGap: 0.05), 0.05)
        // Reconnecting or degraded: the VAD cannot be trusted, the level is all there is.
        XCTAssertEqual(AppState.smartMeetingSpeechGap(pipelineHealthy: false, speechGap: 400, levelGap: 0.05), 0.05)
    }

    func testAudioLevelActivityOnlyResetsQuietEpisodeWhenPipelineIsDown() {
        // A noise burst must not dismiss the ask or forget "Keep recording" while words
        // are the available evidence of speech.
        XCTAssertFalse(AppState.audioLevelActivityResetsQuietEpisode(pipelineHealthy: true))
        XCTAssertTrue(AppState.audioLevelActivityResetsQuietEpisode(pipelineHealthy: false))
    }

    func testSmartQuietPromptIsOncePerEpisodeAndHonoursSuppression() {
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 600,
            audioGap: 600,
            autoStopMinutes: 5,
            crossedCommonBoundary: false,
            alreadyPromptedThisQuietEpisode: true,
            isSuppressed: false
        ))
        XCTAssertFalse(AppState.shouldOfferSmartQuietPrompt(
            hasMeaningfulTranscript: true,
            transcriptGap: 600,
            audioGap: 600,
            autoStopMinutes: 5,
            crossedCommonBoundary: false,
            alreadyPromptedThisQuietEpisode: false,
            isSuppressed: true
        ))
    }

    func testSmartBoundaryRequiresEstablishedMeetingAndTwoMinutesQuiet() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let quietStart = Date(timeIntervalSince1970: 10 * 3600 + 28 * 60)
        let afterBoundary = Date(timeIntervalSince1970: 10 * 3600 + 31 * 60)

        XCTAssertFalse(AppState.quietPeriodCrossedCommonMeetingBoundary(
            quietStartedAt: quietStart,
            now: afterBoundary,
            recordingDuration: 14 * 60,
            calendar: calendar
        ))
        XCTAssertTrue(AppState.quietPeriodCrossedCommonMeetingBoundary(
            quietStartedAt: quietStart,
            now: afterBoundary,
            recordingDuration: 20 * 60,
            calendar: calendar
        ))
    }

    // MARK: - evaluateTranscriptHealth

    private func transcriptHealth(
        transcriptGap: TimeInterval,
        audioGap: TimeInterval,
        sinceLastRecoveryAttempt: TimeInterval = .infinity,
        consecutiveRecoveries: Int = 0,
        isConnected: Bool = true,
        isConnecting: Bool = false,
        hasPendingReconnect: Bool = false
    ) -> AppState.TranscriptHealthAction {
        AppState.evaluateTranscriptHealth(
            transcriptGap: transcriptGap,
            audioGap: audioGap,
            sinceLastRecoveryAttempt: sinceLastRecoveryAttempt,
            consecutiveRecoveries: consecutiveRecoveries,
            isConnected: isConnected,
            isConnecting: isConnecting,
            hasPendingReconnect: hasPendingReconnect
        )
    }

    func testTranscriptHealthReconnectsWhenWordsStopButAudioContinues() {
        XCTAssertEqual(transcriptHealth(transcriptGap: 25, audioGap: 1), .reconnectStarvation)
    }

    func testTranscriptHealthIgnoresPauseBetweenWords() {
        // The regression: judging by an instantaneous level sample meant a tick landing in a pause
        // between words looked identical to a dead pipeline. A quiet *moment* is not a quiet room.
        XCTAssertEqual(transcriptHealth(transcriptGap: 25, audioGap: 3), .reconnectStarvation)
    }

    func testTranscriptHealthHoldsWhenSpeechStoppedBeforeTheLastTranscript() {
        // Someone finished talking and the words came back — the gap is a lull, not a stall, so
        // reconnecting here would drop a healthy socket mid-meeting.
        XCTAssertEqual(transcriptHealth(transcriptGap: 24, audioGap: 25), .none)
        XCTAssertEqual(transcriptHealth(transcriptGap: 25, audioGap: 22), .none)
    }

    func testTranscriptHealthHoldsWhenRoomIsGenuinelyQuiet() {
        XCTAssertEqual(transcriptHealth(transcriptGap: 300, audioGap: 90), .none)
        XCTAssertEqual(transcriptHealth(transcriptGap: 300, audioGap: .infinity), .none)
    }

    func testTranscriptHealthReconnectsWhenSpeechContinuedPastTheLastTranscript() {
        // Talking carried on for a while after the last words came back, then stopped.
        XCTAssertEqual(transcriptHealth(transcriptGap: 40, audioGap: 15), .reconnectStarvation)
    }

    func testTranscriptHealthHoldsBeforeStarvationGap() {
        XCTAssertEqual(transcriptHealth(transcriptGap: 20, audioGap: 1), .none)
    }

    func testTranscriptHealthRespectsStarvationCooldown() {
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 25, audioGap: 1, sinceLastRecoveryAttempt: 29),
            .none
        )
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 25, audioGap: 1, sinceLastRecoveryAttempt: 31),
            .reconnectStarvation
        )
    }

    func testTranscriptHealthDoesNotStackOnPendingReconnect() {
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 60, audioGap: 1, hasPendingReconnect: true),
            .none
        )
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 60, audioGap: 1, isConnected: false, isConnecting: true),
            .none
        )
    }

    func testTranscriptHealthRetriesAfterReconnectLadderExhausted() {
        // Reconnects are otherwise only triggered by a connection-state transition, so a socket
        // left in .error after the last backoff attempt would stay dead for the whole meeting.
        XCTAssertEqual(
            transcriptHealth(
                transcriptGap: 120,
                audioGap: 1,
                sinceLastRecoveryAttempt: 90,
                isConnected: false
            ),
            .reconnectAfterExhaustion
        )
    }

    func testTranscriptHealthBacksOffWhenReconnectsKeepNotHelping() {
        // A room whose ambient noise clears the speech threshold looks like a permanent stall.
        // Reconnecting isn't free, so repeated no-op recoveries must stretch the cooldown.
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 60, audioGap: 1, sinceLastRecoveryAttempt: 45, consecutiveRecoveries: 3),
            .none
        )
        XCTAssertEqual(
            transcriptHealth(transcriptGap: 60, audioGap: 1, sinceLastRecoveryAttempt: 300, consecutiveRecoveries: 3),
            .reconnectStarvation
        )
    }

    func testTranscriptRecoveryCooldownGrowsAndCaps() {
        let maxCooldown = AppState.transcriptRecoveryMaxCooldown
        XCTAssertEqual(AppState.transcriptRecoveryCooldown(base: 30, consecutiveRecoveries: 0), 30)
        XCTAssertEqual(AppState.transcriptRecoveryCooldown(base: 30, consecutiveRecoveries: 2), 120)
        XCTAssertEqual(
            AppState.transcriptRecoveryCooldown(base: 30, consecutiveRecoveries: 99),
            maxCooldown
        )
    }

    func testTranscriptHealthUsesLongerCooldownAfterExhaustion() {
        XCTAssertEqual(
            transcriptHealth(
                transcriptGap: 120,
                audioGap: 1,
                sinceLastRecoveryAttempt: 45,
                isConnected: false
            ),
            .none
        )
    }

    // MARK: - Auto-stop reason copy

    func testAutoStopReasonLabelsDistinguishSilenceFromStall() {
        XCTAssertEqual(AppState.AutoStopReason.silence.label, "auto-stopped, no speech detected")
        XCTAssertNotEqual(
            AppState.AutoStopReason.stalledPipeline.label,
            AppState.AutoStopReason.silence.label
        )
    }

    // MARK: - Deleted-meeting guard

    @MainActor
    func testNoteMeetingDeletedMarksMeetingForInFlightWork() throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let meeting = Meeting(title: "history entry")
        context.insert(meeting)
        try context.save()
        let meetingID = meeting.id

        let state = AppState()
        state.modelContext = context
        XCTAssertFalse(state.isMeetingDeleted(meetingID))

        // History delete records the ID first so regeneration that resumes after its network
        // awaits can't write the row back.
        state.noteMeetingDeleted(meeting)
        context.delete(meeting)
        try context.save()

        XCTAssertTrue(state.isMeetingDeleted(meetingID))
    }

    @MainActor
    func testDiscardCurrentMeetingMarksMeetingDeleted() throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let meeting = Meeting(title: "discarded")
        context.insert(meeting)
        try context.save()
        let meetingID = meeting.id

        let state = AppState()
        state.modelContext = context
        state.currentMeeting = meeting
        state.discardCurrentMeeting()

        XCTAssertTrue(state.isMeetingDeleted(meetingID))
        XCTAssertNil(state.currentMeeting)
    }

    // MARK: - Meeting save durability

    @MainActor
    func testSaveFencePersistsLatestRevisionForEachMeeting() async throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let firstMeeting = Meeting(title: "first")
        let secondMeeting = Meeting(title: "second")
        let firstSegment = AppState.LiveSegment(
            id: UUID(),
            text: "opening",
            speaker: 0,
            timestamp: 1,
            isFinal: true
        )
        let firstTail = AppState.LiveSegment(
            id: UUID(),
            text: "terminal tail",
            speaker: 1,
            timestamp: 2,
            isFinal: true
        )
        let secondSegment = AppState.LiveSegment(
            id: UUID(),
            text: "next meeting",
            speaker: 0,
            timestamp: 1,
            isFinal: true
        )

        let state = AppState()
        state.modelContext = context
        state.currentMeeting = firstMeeting
        state.liveSegments = [firstSegment]
        state.saveCurrentMeetingIfNeeded()

        // Queue a newer terminal snapshot for the first meeting, then a save for a second
        // meeting before the serialized worker gets actor time. A single global latest slot
        // would drop the first meeting's tail here.
        state.liveSegments = [firstSegment, firstTail]
        state.saveCurrentMeetingIfNeeded()
        state.currentMeeting = secondMeeting
        state.liveSegments = [secondSegment]

        let didSave = await state.saveCurrentMeetingAndWait()
        XCTAssertTrue(didSave)
        XCTAssertEqual(Set(firstMeeting.segments.map(\.text)), ["opening", "terminal tail"])
        XCTAssertEqual(secondMeeting.segments.map(\.text), ["next meeting"])
    }

    @MainActor
    func testSaveFenceReportsFailureWithoutModelContext() async {
        let state = AppState()
        state.currentMeeting = Meeting(title: "not wired")
        state.liveSegments = [
            AppState.LiveSegment(
                id: UUID(),
                text: "unsaved",
                speaker: 0,
                timestamp: 1,
                isFinal: true
            ),
        ]

        let didSave = await state.saveCurrentMeetingAndWait()
        XCTAssertFalse(didSave)
    }

    // MARK: - recoverySeverity

    func testRecoverySeverityHealthy() {
        XCTAssertEqual(AppState.recoverySeverity(.healthy), 0)
    }

    func testRecoverySeverityRecovering() {
        XCTAssertEqual(AppState.recoverySeverity(.recovering), 1)
    }

    func testRecoverySeverityDegraded() {
        XCTAssertEqual(AppState.recoverySeverity(.degraded), 2)
    }

    // MARK: - Realtime nudge targeting

    func testRealtimeNudgeTargetSpeakerIDsMacTargetsExplicitSelfOnly() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: DeepgramService.micSpeakerID,
            effectiveSelfSpeakerIDs: [DeepgramService.micSpeakerID],
            explicitSelfSpeakerIDs: [],
            detectedSpeakers: [DeepgramService.micSpeakerID, 0],
            prefersSingleSpeakerFallback: false
        )
        XCTAssertEqual(result, [DeepgramService.micSpeakerID])
    }

    func testRealtimeNudgeTargetSpeakerIDsMacSkipsRemoteSpeaker() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: 0,
            effectiveSelfSpeakerIDs: [DeepgramService.micSpeakerID],
            explicitSelfSpeakerIDs: [],
            detectedSpeakers: [DeepgramService.micSpeakerID, 0],
            prefersSingleSpeakerFallback: false
        )
        XCTAssertNil(result)
    }

    func testRealtimeNudgeTargetSpeakerIDsIOSSingleSpeakerFallback() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: 2,
            effectiveSelfSpeakerIDs: [DeepgramService.micSpeakerID],
            explicitSelfSpeakerIDs: [],
            detectedSpeakers: [2],
            prefersSingleSpeakerFallback: true
        )
        XCTAssertEqual(result, [2])
    }

    func testRealtimeNudgeTargetSpeakerIDsIOSSkipsMultiSpeakerWithoutExplicitSelf() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: 2,
            effectiveSelfSpeakerIDs: [DeepgramService.micSpeakerID],
            explicitSelfSpeakerIDs: [],
            detectedSpeakers: [1, 2],
            prefersSingleSpeakerFallback: true
        )
        XCTAssertNil(result)
    }

    func testRealtimeNudgeTargetSpeakerIDsIOSUsesExplicitSelfWhenAvailable() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: 7,
            effectiveSelfSpeakerIDs: [7, 8],
            explicitSelfSpeakerIDs: [7, 8],
            detectedSpeakers: [7, 9],
            prefersSingleSpeakerFallback: true
        )
        XCTAssertEqual(result, [7, 8])
    }

    func testRealtimeNudgeTargetSpeakerIDsIOSSkipsNonSelfWhenExplicitSelfExists() {
        let result = AppState.realtimeNudgeTargetSpeakerIDs(
            lastFinalSpeaker: 9,
            effectiveSelfSpeakerIDs: [7, 8],
            explicitSelfSpeakerIDs: [7, 8],
            detectedSpeakers: [7, 9],
            prefersSingleSpeakerFallback: true
        )
        XCTAssertNil(result)
    }

    // MARK: - Monologue run gating

    func testIsEligibleMonologueRunRequiresWordsAndTime() {
        XCTAssertFalse(AppState.isEligibleMonologueRun(wordCount: 179, runSeconds: 120))
        XCTAssertFalse(AppState.isEligibleMonologueRun(wordCount: 300, runSeconds: 59))
        XCTAssertTrue(AppState.isEligibleMonologueRun(wordCount: 180, runSeconds: 60))
    }

    // MARK: - Google OAuth callback parsing

    func testParseGoogleOAuthCallbackAcceptsExpectedSchemeAndHost() {
        let url = URL(string: "miniti-google://oauth-callback?status=success&message=ok")!
        let payload = AppState.parseGoogleOAuthCallback(url)
        XCTAssertEqual(payload, .init(status: "success", message: "ok"))
    }

    func testParseGoogleOAuthCallbackRejectsUnexpectedScheme() {
        let url = URL(string: "miniti-attio://oauth-callback?status=success")!
        XCTAssertNil(AppState.parseGoogleOAuthCallback(url))
    }

    func testParseGoogleOAuthCallbackRejectsUnexpectedHost() {
        let url = URL(string: "miniti-google://wrong-host?status=success")!
        XCTAssertNil(AppState.parseGoogleOAuthCallback(url))
    }

    #if os(macOS)
    func testParseAttioOAuthCallbackAcceptsExpectedSchemeAndHost() {
        let url = URL(string: "miniti-attio://oauth-callback?status=success&message=ok")!
        let payload = AttioSendSheet.parseOAuthCallback(url)
        XCTAssertEqual(payload, .init(status: "success", message: "ok"))
    }

    func testParseAttioOAuthCallbackRejectsUnexpectedScheme() {
        let url = URL(string: "miniti-google://oauth-callback?status=success")!
        XCTAssertNil(AttioSendSheet.parseOAuthCallback(url))
    }

    func testParseAttioOAuthCallbackRejectsUnexpectedHost() {
        let url = URL(string: "miniti-attio://wrong-host?status=success")!
        XCTAssertNil(AttioSendSheet.parseOAuthCallback(url))
    }

    func testParseTwentyOAuthCallbackAcceptsExpectedSchemeAndHost() {
        let url = URL(string: "miniti-twenty://oauth-callback?status=success&message=ok")!
        let payload = TwentySendSheet.parseOAuthCallback(url)
        XCTAssertEqual(payload, .init(status: "success", message: "ok"))
    }

    func testParseTwentyOAuthCallbackRejectsAttioScheme() {
        let url = URL(string: "miniti-attio://oauth-callback?status=success")!
        XCTAssertNil(TwentySendSheet.parseOAuthCallback(url))
    }
    #endif

    // MARK: - finalized live segments

    func testFinalizedLiveSegmentCountIgnoresInterimAndBlankSegments() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "hello", speaker: 0, timestamp: 2, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "   ", speaker: 0, timestamp: 1, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "draft", speaker: 0, timestamp: 0, isFinal: false),
        ]
        XCTAssertEqual(AppState.finalizedLiveSegmentCount(in: segments), 1)
    }

    func testFinalizedLiveSegmentsReturnsSortedSnapshot() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "later", speaker: 0, timestamp: 5, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "first", speaker: 0, timestamp: 1, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "", speaker: 0, timestamp: 0, isFinal: true),
        ]
        let snapshot = AppState.finalizedLiveSegments(from: segments)
        XCTAssertEqual(snapshot.map(\.text), ["first", "later"])
    }

    // MARK: - transcriptText

    func testTranscriptTextSingleSegment() {
        let segment = AppState.LiveSegment(
            id: UUID(), text: "Hello world", speaker: 0, timestamp: 0, isFinal: true
        )
        let result = AppState.transcriptText(from: [segment])
        XCTAssertEqual(result, "[Speaker 1] Hello world")
    }

    func testTranscriptTextMultipleSegments() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Hi", speaker: DeepgramService.micSpeakerID, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "Hello", speaker: 0, timestamp: 1, isFinal: true),
        ]
        let result = AppState.transcriptText(from: segments)
        XCTAssertEqual(result, "[You] Hi\n[Speaker 1] Hello")
    }

    func testTranscriptTextEmpty() {
        XCTAssertEqual(AppState.transcriptText(from: []), "")
    }

    // MARK: - tailTranscriptSegments

    func testTailTranscriptSegmentsAllFit() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Hello", speaker: 0, timestamp: 0, isFinal: true),
            AppState.LiveSegment(id: UUID(), text: "World", speaker: 0, timestamp: 1, isFinal: true),
        ]
        let result = AppState.tailTranscriptSegments(from: segments, maxChars: 10000)
        XCTAssertEqual(result.count, 2)
    }

    func testTailTranscriptSegmentsTruncates() {
        var segments: [AppState.LiveSegment] = []
        for i in 0..<20 {
            segments.append(AppState.LiveSegment(
                id: UUID(), text: "This is sentence number \(i)", speaker: 0, timestamp: TimeInterval(i), isFinal: true
            ))
        }
        let result = AppState.tailTranscriptSegments(from: segments, maxChars: 100)
        XCTAssertTrue(result.count < segments.count)
        XCTAssertTrue(result.count > 0)
        XCTAssertEqual(result.last?.text, segments.last?.text)
    }

    func testTailTranscriptSegmentsZeroChars() {
        let segments = [
            AppState.LiveSegment(id: UUID(), text: "Hello", speaker: 0, timestamp: 0, isFinal: true),
        ]
        let result = AppState.tailTranscriptSegments(from: segments, maxChars: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testTailTranscriptSegmentsEmpty() {
        let result = AppState.tailTranscriptSegments(from: [], maxChars: 1000)
        XCTAssertTrue(result.isEmpty)
    }

    #if !IOS_TEST_TARGET
    func testHistoryPageIsADestinationThatMeetingsReturnTo() {
        let meetingID = UUID()
        var history = MainNavigationHistory(current: .home)
        history.visit(.history)
        history.visit(.meeting(meetingID))
        XCTAssertEqual(history.goBack(), .history, "Back from a meeting opened on History returns to History")
        XCTAssertEqual(history.goBack(), .home)
        history.retainMeetings([])
        XCTAssertEqual(history.goForward(), .history, "History survives pruning of deleted meetings")
    }

    func testSidebarWidthLeavesSavedMeetingsTheirMinimum() {
        XCTAssertEqual(MainWindowSidebarWidth.maximum(windowWidth: 940), 259, "940pt window keeps 680pt for the meeting")
        XCTAssertEqual(MainWindowSidebarWidth.maximum(windowWidth: 1600), MinitiDesignSystem.Sidebar.maximumExpandedWidth)
        XCTAssertEqual(MainWindowSidebarWidth.maximum(windowWidth: 700), MinitiDesignSystem.Sidebar.minimumExpandedWidth)
        XCTAssertEqual(MainWindowSidebarWidth.clamped(500, maximum: 259), 259)
        XCTAssertEqual(MainWindowSidebarWidth.clamped(120, maximum: 400), MinitiDesignSystem.Sidebar.minimumExpandedWidth)
        XCTAssertEqual(MainWindowSidebarWidth.clamped(320, maximum: 400), 320)
    }

    func testListNavigationStepsWithinTheGivenOrder() {
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(MainWindowListNavigation.step(in: ids, from: nil, direction: 1), ids[0])
        XCTAssertEqual(MainWindowListNavigation.step(in: ids, from: nil, direction: -1), ids[2])
        XCTAssertEqual(MainWindowListNavigation.step(in: ids, from: ids[0], direction: 1), ids[1])
        XCTAssertNil(MainWindowListNavigation.step(in: ids, from: ids[2], direction: 1), "No wrap past the end")
        XCTAssertEqual(MainWindowListNavigation.step(in: ids, from: UUID(), direction: 1), ids[0], "A meeting outside the list starts at the top")
        XCTAssertNil(MainWindowListNavigation.step(in: [], from: nil, direction: 1))
    }

    func testHistoryPageGroupsPinnedFirstThenByDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15)))
        func meeting(_ title: String, daysAgo: Int, pinned: Bool = false) -> Meeting {
            let m = Meeting(title: title, startTime: now.addingTimeInterval(TimeInterval(-daysAgo * 86400 - 3600)), endTime: now)
            m.isPinned = pinned
            return m
        }
        let meetings = [meeting("today", daysAgo: 0), meeting("pinned", daysAgo: 30, pinned: true),
                        meeting("yesterday", daysAgo: 1), meeting("this week", daysAgo: 2), meeting("older", daysAgo: 20)]
        let sections = HistoryPageView.sections(of: meetings, searching: false, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["pinned", "today", "yesterday", "this week", "older"])
        XCTAssertEqual(sections.flatMap { $0.meetings.map(\.title) }, ["pinned", "today", "yesterday", "this week", "older"])
        let searching = HistoryPageView.sections(of: meetings, searching: true, now: now, calendar: calendar)
        XCTAssertEqual(searching.map(\.title), ["results"])
        XCTAssertTrue(HistoryPageView.sections(of: [], searching: true).isEmpty)
    }

    @MainActor func testHistoryPageRendersAndReportsItsVisibleOrder() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext
        state.folderFilterID = nil; state.showUnfiledMeetings = false
        let recent = Meeting(title: "Recent", startTime: Date().addingTimeInterval(-600), endTime: Date())
        let pinned = Meeting(title: "Pinned", startTime: Date().addingTimeInterval(-40 * 86400), endTime: Date().addingTimeInterval(-40 * 86400 + 600))
        pinned.isPinned = true
        [recent, pinned].forEach { container.mainContext.insert($0) }
        var reported: [UUID] = []
        let page = HistoryPageView(meetings: [recent, pinned], onOpen: { _ in }, onTogglePin: { _ in }, onDelete: { _ in },
                                   onVisibleMeetingsChange: { reported = $0 })
        let host = NSHostingView(rootView: page.environmentObject(state).frame(width: 900, height: 700))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertEqual(reported, [pinned.id, recent.id], "J/K follow the page: pinned first, then newest")
        window.contentView = nil
    }

    func testMainNavigationHistoryMovesBackAndForwardInVisitOrder() {
        let meetingID = UUID()
        var history = MainNavigationHistory(current: .home)

        history.visit(.coaching)
        history.visit(.meeting(meetingID))

        XCTAssertEqual(history.goBack(), .coaching)
        XCTAssertEqual(history.goBack(), .home)
        XCTAssertNil(history.goBack())
        XCTAssertEqual(history.goForward(), .coaching)
        XCTAssertEqual(history.goForward(), .meeting(meetingID))
        XCTAssertNil(history.goForward())
    }

    func testMainNavigationHistoryClearsForwardStackAfterNewVisit() {
        let firstMeetingID = UUID()
        let secondMeetingID = UUID()
        var history = MainNavigationHistory(current: .home)

        history.visit(.meeting(firstMeetingID))
        XCTAssertEqual(history.goBack(), .home)
        history.visit(.meeting(secondMeetingID))

        XCTAssertNil(history.goForward())
        XCTAssertEqual(history.goBack(), .home)
    }

    func testMainNavigationHistoryPrunesDeletedMeetings() {
        let retainedMeetingID = UUID()
        let deletedMeetingID = UUID()
        var history = MainNavigationHistory(current: .home)

        history.visit(.meeting(retainedMeetingID))
        history.visit(.meeting(deletedMeetingID))
        history.retainMeetings([retainedMeetingID])

        XCTAssertEqual(history.current, .home)
        XCTAssertTrue(history.forwardStack.isEmpty)
        XCTAssertEqual(history.goBack(), .meeting(retainedMeetingID))
    }

    func testMainNavigationSwipeRequiresDeliberateHorizontalTravel() {
        XCTAssertFalse(MainWindowNavigationSwipePolicy.shouldCommit(horizontal: 72, vertical: 4))
        XCTAssertTrue(MainWindowNavigationSwipePolicy.shouldCommit(horizontal: 84, vertical: 4))
        XCTAssertFalse(MainWindowNavigationSwipePolicy.shouldCommit(horizontal: 100, vertical: 80))
    }

    func testMainNavigationSwipeAllowsMeetingSearchButNotOtherTextEditors() {
        XCTAssertTrue(
            MainWindowNavigationSwipePolicy.allowsGestureWhileEditing(
                isEditingText: false,
                isMeetingSearchFocused: false
            )
        )
        XCTAssertTrue(
            MainWindowNavigationSwipePolicy.allowsGestureWhileEditing(
                isEditingText: true,
                isMeetingSearchFocused: true
            )
        )
        XCTAssertFalse(
            MainWindowNavigationSwipePolicy.allowsGestureWhileEditing(
                isEditingText: true,
                isMeetingSearchFocused: false
            )
        )
    }

    func testMainNavigationSwipeProgressTracksDirectionAndThreshold() throws {
        let backProgress = try XCTUnwrap(
            MainWindowNavigationSwipePolicy.presentationProgress(horizontal: -42, vertical: 2)
        )
        let forwardProgress = try XCTUnwrap(
            MainWindowNavigationSwipePolicy.presentationProgress(horizontal: 84, vertical: 2)
        )

        XCTAssertEqual(backProgress, -0.5, accuracy: 0.001)
        XCTAssertEqual(forwardProgress, 1, accuracy: 0.001)
        XCTAssertNil(MainWindowNavigationSwipePolicy.presentationProgress(horizontal: 8, vertical: 20))

        let diagonalProgress = try XCTUnwrap(
            MainWindowNavigationSwipePolicy.presentationProgress(horizontal: 84, vertical: 70)
        )
        XCTAssertLessThan(diagonalProgress, 1)
    }
    #endif

    // MARK: - UsageInfo helper

    private static func makeUsageInfo(
        used: Double,
        limit: Double,
        tier: String = "free",
        subscriptionStatus: String? = nil
    ) -> MinitiAPIService.UsageInfo {
        let json: [String: Any] = [
            "minutes_used": used,
            "minutes_limit": limit,
            "resets_at": ISO8601DateFormatter().string(from: Date()),
            "tier": tier,
            "subscription_status": subscriptionStatus as Any,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(MinitiAPIService.UsageInfo.self, from: data)
    }

    // MARK: - Calendar status after launch / reboot (2026-09-25)

    func testCalendarStatusOutcomeTreatsErrorsAsUnknownNotDisconnected() {
        XCTAssertEqual(AppState.calendarStatusOutcome(from: .success(true)), .connected)
        XCTAssertEqual(AppState.calendarStatusOutcome(from: .success(false)), .disconnected)
        // Network not up yet after login, DNS, token refresh on the wire: no information.
        XCTAssertEqual(AppState.calendarStatusOutcome(from: .failure(URLError(.notConnectedToInternet))), .unknown)
        XCTAssertEqual(AppState.calendarStatusOutcome(from: .failure(MinitiAPIService.ServiceError.notEnrolled)), .unknown)
    }

    func testCalendarStatusRetryLadderIsQuickThenEveryFiveMinutes() {
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 0), 5)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 1), 5)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 2), 15)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 3), 45)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 4), 120)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 5), 300)
        XCTAssertEqual(AppState.calendarStatusRetryDelay(attempt: 40), 300)
    }

    func testDeviceIDIsOnlyCreatedWhenTheKeychainItemIsAbsent() {
        // A stored fallback always wins.
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: errSecItemNotFound, hasFallback: true), .useFallback)
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: errSecInteractionNotAllowed, hasFallback: true), .useFallback)
        // Genuinely absent: first launch, create and persist.
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: errSecItemNotFound, hasFallback: false), .createAndPersist)
        // Locked, prompting, or otherwise unreadable: never mint a replacement identity,
        // which would look like a Google Calendar disconnect on the backend.
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: errSecInteractionNotAllowed, hasFallback: false), .sessionOnly)
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: errSecAuthFailed, hasFallback: false), .sessionOnly)
        XCTAssertEqual(DeviceIdentifier.resolution(afterReadStatus: -34018, hasFallback: false), .sessionOnly)
    }

    func testMeetingFilterPreferencesNormalizeAndRoundTrip() {
        typealias Prefs = MinitiAPIService.CalendarMeetingFilterPreferences
        XCTAssertEqual(Prefs.normalizedPrefixes(["  Out  Of Office ", "ooo", "OOO", "", "gym"]), ["out of office", "ooo", "gym"])
        let defaults = UserDefaults(suiteName: "test_calendar_filters_\(UUID().uuidString)")!
        XCTAssertEqual(Prefs.load(defaults: defaults), .defaults)
        var custom = Prefs.defaults
        custom.skipAllDay = false
        custom.titlePrefixes.append("Gym ")
        custom.save(defaults: defaults)
        let loaded = Prefs.load(defaults: defaults)
        XCTAssertFalse(loaded.skipAllDay)
        XCTAssertTrue(loaded.titlePrefixes.contains("gym"))
        XCTAssertTrue(loaded.skipWithoutGuestsOrLink)
        var noGuestsOff = Prefs.defaults
        noGuestsOff.skipWithoutGuestsOrLink = false
        noGuestsOff.save(defaults: defaults)
        XCTAssertFalse(Prefs.load(defaults: defaults).skipWithoutGuestsOrLink)
        // Saving the defaults clears the key so a future default change applies.
        Prefs.defaults.save(defaults: defaults)
        XCTAssertNil(defaults.data(forKey: Prefs.storageKey))

        // A blob written before the no-guests rule existed (2.9.0) still decodes, keeps
        // the person's prefixes, and picks up the new rule's default. Losing the decode
        // would silently reset every custom filter on upgrade.
        let legacy = """
        {"skipOutOfOffice":true,"skipFocusTime":false,"skipWorkingLocation":true,"skipBirthdays":true,\
        "skipAllDay":true,"skipDeclined":true,"titlePrefixes":["ooo","gym"]}
        """
        defaults.set(Data(legacy.utf8), forKey: Prefs.storageKey)
        let migrated = Prefs.load(defaults: defaults)
        XCTAssertFalse(migrated.skipFocusTime)
        XCTAssertEqual(migrated.titlePrefixes, ["ooo", "gym"])
        XCTAssertTrue(migrated.skipWithoutGuestsOrLink)
    }

    func testMeetingFiltersRespectEveryToggleAndCustomPrefixes() {
        typealias Prefs = MinitiAPIService.CalendarMeetingFilterPreferences
        let all = Prefs.defaults
        XCTAssertEqual(Self.makeCalendarEvent(id: "1", title: "Team day", isAllDay: true).skipReason(under: all), .allDay)
        XCTAssertEqual(Self.makeCalendarEvent(id: "2", title: "Sync", selfDeclined: true).skipReason(under: all), .declined)
        XCTAssertEqual(Self.makeCalendarEvent(id: "3", title: "Ian", eventType: "outOfOffice").skipReason(under: all), .outOfOffice)
        XCTAssertEqual(Self.makeCalendarEvent(id: "4", title: "Gym", eventType: "focusTime").skipReason(under: all), .focusTime)
        XCTAssertEqual(Self.makeCalendarEvent(id: "5", title: "PTO - Lisbon").skipReason(under: all), .title("pto"))
        // A block the person made for themselves: no link, no other guest, self-organized.
        XCTAssertEqual(Self.makeCalendarEvent(id: "10", title: "Kids pickup").skipReason(under: all), .noGuestsOrLink)
        XCTAssertEqual(
            Self.makeCalendarEvent(id: "11", title: "Kids pickup", organizerEmail: "me@x.com", organizerIsSelf: true).skipReason(under: all),
            .noGuestsOrLink
        )
        // Any of a link, another guest, or an outside organizer makes it a meeting.
        XCTAssertNil(Self.makeCalendarEvent(id: "12", title: "Lunch", meetLink: "https://meet.google.com/abc-defg-hij").skipReason(under: all))
        XCTAssertNil(Self.makeCalendarEvent(id: "13", title: "1:1", guests: ["sam@acme.com"]).skipReason(under: all))
        XCTAssertNil(
            Self.makeCalendarEvent(id: "14", title: "Board update", organizerEmail: "chair@acme.com", organizerIsSelf: false).skipReason(under: all),
            "an invitation from someone else with a hidden guest list is still a meeting"
        )
        // More specific reasons win over the no-guests rule so the preview names the real cause.
        XCTAssertEqual(Self.makeCalendarEvent(id: "15", title: "Focus time").skipReason(under: all), .title("focus time"))

        var relaxed = Prefs.defaults
        relaxed.skipAllDay = false
        relaxed.skipDeclined = false
        relaxed.skipOutOfOffice = false
        relaxed.skipFocusTime = false
        relaxed.skipWithoutGuestsOrLink = false
        relaxed.titlePrefixes = ["gym"]
        XCTAssertNil(Self.makeCalendarEvent(id: "10", title: "Kids pickup").skipReason(under: relaxed))
        XCTAssertNil(Self.makeCalendarEvent(id: "1", title: "Team day", isAllDay: true).skipReason(under: relaxed))
        XCTAssertNil(Self.makeCalendarEvent(id: "2", title: "Sync", selfDeclined: true).skipReason(under: relaxed))
        XCTAssertNil(Self.makeCalendarEvent(id: "3", title: "Ian", eventType: "outOfOffice").skipReason(under: relaxed))
        XCTAssertNil(Self.makeCalendarEvent(id: "5", title: "PTO - Lisbon").skipReason(under: relaxed))
        XCTAssertEqual(Self.makeCalendarEvent(id: "6", title: "Gym with Sam").skipReason(under: relaxed), .title("gym"))
        // Prefix matching is a word boundary at the start: "gymnastics review" is a meeting.
        XCTAssertNil(Self.makeCalendarEvent(id: "7", title: "Gymnastics review").skipReason(under: relaxed))

        // The backend's own skipReason is informational; the local rules decide.
        let serverSkipped = Self.makeCalendarEvent(id: "8", title: "Deep work", eventType: "focusTime", skipReason: "event_type")
        XCTAssertEqual(serverSkipped.skipReason, "event_type")
        XCTAssertNil(serverSkipped.skipReason(under: relaxed))
        XCTAssertEqual(
            AppState.filterCalendarMeetings(
                [
                    serverSkipped,
                    Self.makeCalendarEvent(id: "9", title: "Weekly sync", guests: ["sam@acme.com"]),
                    Self.makeCalendarEvent(id: "16", title: "Kids pickup"),
                ],
                preferences: all
            ).map(\.id),
            ["9"]
        )
    }

    /// Ian, 2026-09-11: "end and start next" fired for an out-of-office block.
    /// Time blocks are not meetings: they never reach `upcomingEvents`.
    func testOutOfOfficeAndFocusBlocksAreNotRecordableMeetings() {
        XCTAssertFalse(Self.makeCalendarEvent(id: "1", title: "Ian", eventType: "outOfOffice").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "2", title: "Deep work", eventType: "focusTime").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "3", title: "Office", eventType: "workingLocation").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "4", title: "Sam", eventType: "birthday").isRecordableMeeting)
        // Older backends send no type: the title heuristic catches the common labels.
        XCTAssertFalse(Self.makeCalendarEvent(id: "5", title: "OOO").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "6", title: "Out of office - Portugal").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "7", title: "  pto").isRecordableMeeting)
        XCTAssertFalse(Self.makeCalendarEvent(id: "8", title: "Focus time").isRecordableMeeting)
        // Real meetings (someone else invited), including ones that merely mention those words, survive.
        XCTAssertTrue(Self.makeCalendarEvent(id: "9", title: "Design review", eventType: "default", guests: ["sam@acme.com"]).isRecordableMeeting)
        XCTAssertTrue(Self.makeCalendarEvent(id: "10", title: "Prep for holiday campaign", guests: ["sam@acme.com"]).isRecordableMeeting)
        XCTAssertTrue(Self.makeCalendarEvent(id: "11", title: "Lunch with Acme", meetLink: "https://meet.google.com/abc-defg-hij").isRecordableMeeting)
        XCTAssertTrue(Self.makeCalendarEvent(id: "12", title: "Weekly sync", guests: ["sam@acme.com"]).isRecordableMeeting)
        // 2026-09-25: a timed block with nobody else invited and no link ("kids pickup")
        // auto-started a recording. Under the defaults it is no longer a meeting.
        XCTAssertFalse(Self.makeCalendarEvent(id: "13", title: "Kids pickup").isRecordableMeeting)
    }

    private static func makeCalendarEvent(
        id: String,
        title: String,
        start: Date = Date().addingTimeInterval(300),
        end: Date = Date().addingTimeInterval(3600),
        meetLink: String? = nil,
        conferenceUrl: String? = nil,
        eventType: String? = nil,
        isAllDay: Bool = false,
        selfDeclined: Bool = false,
        skipReason: String? = nil,
        guests: [String] = [],
        organizerEmail: String? = nil,
        organizerIsSelf: Bool = true
    ) -> MinitiAPIService.CalendarEvent {
        let formatter = ISO8601DateFormatter()
        var attendees: [[String: Any]] = selfDeclined
            ? [["email": "me@x.com", "responseStatus": "declined", "organizer": false, "self": true, "domain": "x.com"]]
            : []
        for guest in guests {
            attendees.append(["email": guest, "responseStatus": "accepted", "organizer": false, "self": false])
        }
        var json: [String: Any] = [
            "id": id,
            "title": title,
            "start": formatter.string(from: start),
            "end": formatter.string(from: end),
            "isAllDay": isAllDay,
            "status": "confirmed",
            "attendees": attendees,
        ]
        if let organizerEmail {
            json["organizer"] = ["email": organizerEmail, "self": organizerIsSelf]
        }
        // Real wire format from miniti-api is camelCase.
        if let eventType { json["eventType"] = eventType }
        if let skipReason { json["skipReason"] = skipReason }
        if let meetLink { json["meetLink"] = meetLink }
        if let conferenceUrl { json["conferenceUrl"] = conferenceUrl }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MinitiAPIService.CalendarEvent.self, from: data)
    }

    func testCalendarEventDecodesBackendCamelCaseAndFixtureSnakeCase() throws {
        // camelCase is what `miniti-api` `lib/google.ts` serializes (and what the
        // Linux client reads). Decoding snake_case only silently dropped links,
        // display names, and response statuses for every Apple user.
        let camel = """
        {"id":"e1","title":"Sync","start":"2026-09-10T09:34:00Z","end":"2026-09-10T10:34:00Z",
         "isAllDay":false,"status":"confirmed","meetLink":"https://meet.google.com/php-eomc-zqw","conferenceUrl":null,
         "attendees":[{"email":"a@x.com","displayName":"Alice","responseStatus":"accepted","organizer":true,"self":false,"domain":"x.com"}],
         "organizer":{"email":"a@x.com","displayName":"Alice","self":false}}
        """
        let event = try JSONDecoder().decode(MinitiAPIService.CalendarEvent.self, from: Data(camel.utf8))
        XCTAssertEqual(event.joinURL?.absoluteString, "https://meet.google.com/php-eomc-zqw")
        XCTAssertEqual(event.attendees.first?.displayName, "Alice")
        XCTAssertEqual(event.attendees.first?.responseStatus, "accepted")
        XCTAssertEqual(event.organizer?.displayName, "Alice")

        let snake = """
        {"id":"e2","title":"Fixture","start":"2026-09-10T09:34:00Z","end":"2026-09-10T10:34:00Z",
         "is_all_day":false,"status":"confirmed","meet_link":"https://meet.google.com/abc-defg-hij",
         "attendees":[{"email":"b@x.com","display_name":"Bob","response_status":"declined","self":true}]}
        """
        let fixture = try JSONDecoder().decode(MinitiAPIService.CalendarEvent.self, from: Data(snake.utf8))
        XCTAssertEqual(fixture.joinURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(fixture.attendees.first?.displayName, "Bob")
        XCTAssertEqual(fixture.attendees.first?.responseStatus, "declined")
        XCTAssertTrue(fixture.attendees.first?.isSelf ?? false)
    }

    @MainActor
    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return TestSupport.retain(try ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: config))
    }
}

// MARK: - Cross-speaker mic dedup (cumulative finals whose diarized speaker flips)

@MainActor
final class ThirdPartyAIConsentTests: XCTestCase {
    private let keys = ["acceptedTermsVersion", "declinedTermsVersion", "hasAcceptedTerms"]

    private func withCleanConsentDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        try body()
    }

    func testTheFirstScreenStepsAsideOnceAnsweredEitherWay() {
        XCTAssertFalse(AppState.thirdPartyAIConsentAnswered(acceptedVersion: 0, declinedVersion: 0, currentVersion: 2))
        XCTAssertFalse(AppState.thirdPartyAIConsentAnswered(acceptedVersion: 1, declinedVersion: 0, currentVersion: 2), "an older acceptance sees the new disclosure")
        XCTAssertFalse(AppState.thirdPartyAIConsentAnswered(acceptedVersion: 0, declinedVersion: 1, currentVersion: 2), "an older decline sees the new disclosure")
        XCTAssertTrue(AppState.thirdPartyAIConsentAnswered(acceptedVersion: 2, declinedVersion: 0, currentVersion: 2))
        XCTAssertTrue(AppState.thirdPartyAIConsentAnswered(acceptedVersion: 0, declinedVersion: 2, currentVersion: 2))
    }

    func testNotNowOpensTheAppWithoutPermissionAndRecordAsksAgain() {
        withCleanConsentDefaults {
            let state = AppState()
            XCTAssertFalse(state.hasAcceptedTerms)
            XCTAssertFalse(state.hasAnsweredThirdPartyAIConsent, "fresh install sees the first screen")

            state.setThirdPartyAIConsent(false)
            XCTAssertTrue(state.hasAnsweredThirdPartyAIConsent, "not now moves past the first screen")
            XCTAssertFalse(state.hasAcceptedTerms, "but nothing may be sent")

            XCTAssertFalse(state.startNewMeeting(), "a record attempt is refused")
            XCTAssertTrue(state.showThirdPartyAIConsent, "and asks for permission at that moment")

            state.setThirdPartyAIConsent(true)
            XCTAssertTrue(state.hasAcceptedTerms)
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "declinedTermsVersion"), 0, "allowing clears the decline")

            state.setThirdPartyAIConsent(false)
            XCTAssertFalse(state.hasAcceptedTerms, "withdrawing in Settings turns it off again")
            XCTAssertTrue(state.hasAnsweredThirdPartyAIConsent, "without bringing the first screen back")
        }
    }

    // MARK: U2, the concise consent screen (docs/archive/account-sending-consent-ux-plan.md)

    func testTheDisclosureStillNamesEveryRecipientAndDataCategory() {
        let text = TermsAcceptanceView.disclosureText.lowercased()
        for required in ["deepgram", "openai", "audio", "meeting title", "attendee names", "transcript", "your notes", "not now", "settings, privacy"] {
            XCTAssertTrue(text.contains(required), "the consent screen no longer says \"\(required)\"; the disclosure must name every recipient and data category or the terms version has to change")
        }
        for banned in ["never stored", "nothing leaves", "two companies", "—"] {
            XCTAssertFalse(text.contains(banned), "\"\(banned)\" is a claim the code does not keep")
        }
        #if os(iOS)
        XCTAssertTrue(text.contains("watch"), "the iPhone names the watch recordings Deepgram transcribes")
        #else
        XCTAssertFalse(text.contains("watch"), "the Mac has no recorded-audio route")
        XCTAssertTrue(text.contains("private mode"))
        #endif
        XCTAssertEqual(TermsAcceptanceView.providerLines.map(\.name), ["Deepgram", "OpenAI"])
    }

    func testTheConsentVersionIsUnchangedByTheShorterWording() {
        XCTAssertEqual(AppState.currentTermsVersion, 2, "U2 rewrote the consent screen without changing recipients, data or purposes, so nobody is asked again; bump this only for a material change and say why in docs/archive/account-sending-consent-ux-plan.md")
    }

    func testCancelOnTheSheetLeavesTheStoredAnswerAlone() {
        XCTAssertTrue(TermsAcceptanceView.declineRecordsAnswer(.firstScreen), "not now on the first screen is a recorded answer")
        XCTAssertFalse(TermsAcceptanceView.declineRecordsAnswer(.sheet), "cancel on the sheet only closes it")
        withCleanConsentDefaults {
            let state = AppState()
            state.setThirdPartyAIConsent(true)
            // The sheet's cancel never reaches the state; a second allow is idempotent.
            state.setThirdPartyAIConsent(true)
            XCTAssertTrue(state.hasAcceptedTerms)
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "acceptedTermsVersion"), AppState.currentTermsVersion)
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "declinedTermsVersion"), 0, "allow writes the acceptance once and no decline")
        }
    }

    func testHistoryUpdateSendsNothingWithoutPermissionAndNeedsItAgainForTheNextRequest() async throws {
        // Narrowed R2 (2026-10-27): History's Update is a real external AI send and must ask first.
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        keys.forEach { defaults.removeObject(forKey: $0) }
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let session = TestSupport.stubbedSession()
        let manager = TestSupport.enrolledAuthManager(session: session)
        let state = AppState()
        state.appModeRaw = AppMode.managed.rawValue
        state.clientAuthManager = manager
        state.minitiAPIService = MinitiAPIService(session: session, auth: manager)
        state.refreshClientAuthStatus()
        state.insightsMode = .standard
        state.privateModeEnabled = false
        let meeting = Meeting(title: "saved")
        meeting.segments = [TranscriptSegment(text: "we agreed to ship on Friday", speaker: 0, timestamp: 1, isFinal: true)]
        StubURLProtocol.handler = { _ in (500, Data("{}".utf8)) }
        func insightsRequests() -> Int { StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/insights") == true }.count }

        // Unanswered: nothing sent, the permission sheet is the answer.
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(insightsRequests(), 0)
        XCTAssertTrue(state.showThirdPartyAIConsent)

        // Declined: the same.
        state.showThirdPartyAIConsent = false
        state.setThirdPartyAIConsent(false)
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(insightsRequests(), 0)
        XCTAssertTrue(state.showThirdPartyAIConsent)

        // Allowed: the normal action sends.
        state.showThirdPartyAIConsent = false
        state.setThirdPartyAIConsent(true)
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(insightsRequests(), 1)
        XCTAssertFalse(state.showThirdPartyAIConsent)

        // Withdrawn while a request is in flight: that one finishes, the next needs permission.
        StubURLProtocol.delay = 0.3
        let inFlight = Task { await state.generateInsightsForMeeting(meeting) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        state.setThirdPartyAIConsent(false)
        await inFlight.value
        XCTAssertEqual(insightsRequests(), 2, "a dispatched request may finish")
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(insightsRequests(), 2, "the next request needed permission again")
    }

    func testHistoryRetryNeedsPermissionAgain() async throws {
        // Review 2026-10-27: the transient-error retry is a new request.
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        keys.forEach { defaults.removeObject(forKey: $0) }
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let session = TestSupport.stubbedSession()
        let manager = TestSupport.enrolledAuthManager(session: session)
        let state = AppState()
        state.appModeRaw = AppMode.managed.rawValue
        state.clientAuthManager = manager
        state.minitiAPIService = MinitiAPIService(session: session, auth: manager)
        state.refreshClientAuthStatus()
        state.insightsMode = .questions
        state.privateModeEnabled = false
        state.setThirdPartyAIConsent(true)
        let meeting = Meeting(title: "saved")
        meeting.segments = [TranscriptSegment(text: "we agreed to ship on Friday", speaker: 0, timestamp: 1, isFinal: true)]
        StubURLProtocol.script = { _ in throw URLError(.timedOut) }
        let generating = Task { await state.generateInsightsForMeeting(meeting) }
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/insights") == true } }
        state.setThirdPartyAIConsent(false)
        await generating.value
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/insights") == true }.count, 1, "History must not retry after withdrawal")

        // With permission kept, the transient failure is retried once as before.
        StubURLProtocol.requests = []
        state.setThirdPartyAIConsent(true)
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/insights") == true }.count, 2)
    }

    #if os(macOS)
    func testPresentingTheScreenAnswersNothing() {
        withCleanConsentDefaults {
            let state = AppState()
            let host = NSHostingView(rootView: TermsAcceptanceView().environmentObject(state))
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(state.hasAnsweredThirdPartyAIConsent, "showing the screen is not an answer")
            XCTAssertFalse(state.hasAcceptedTerms)
            let sheet = NSHostingView(rootView: TermsAcceptanceView(presentation: .sheet).environmentObject(state))
            sheet.frame = NSRect(x: 0, y: 0, width: 520, height: 480)
            sheet.layoutSubtreeIfNeeded()
            XCTAssertFalse(state.hasAnsweredThirdPartyAIConsent)
        }
    }
    #endif
}

final class MicFinalDedupTests: XCTestCase {
    private func micSegment(_ text: String, speaker: Int, timestamp: TimeInterval) -> AppState.LiveSegment {
        AppState.LiveSegment(
            id: UUID(), text: text, speaker: speaker, timestamp: timestamp,
            isFinal: true, source: .microphone
        )
    }

    func testCumulativeMicFinalWithFlippedSpeakerMergesInsteadOfDuplicating() {
        var segments = [micSegment("we should ship on friday", speaker: 1000, timestamp: 10.0)]
        let flipped = micSegment("we should ship on friday", speaker: 1001, timestamp: 10.4)
        let result = AppState.mergeFinalSegment(flipped, into: &segments)
        XCTAssertEqual(result, .skippedExactDuplicate)
        XCTAssertEqual(segments.count, 1)
    }

    func testCumulativeMicFinalSupersetWithFlippedSpeakerReplaces() {
        var segments = [micSegment("we should ship", speaker: 1000, timestamp: 10.0)]
        let superset = micSegment("we should ship on friday", speaker: 1001, timestamp: 10.6)
        let result = AppState.mergeFinalSegment(superset, into: &segments)
        XCTAssertEqual(result, .replacedSuperset)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "we should ship on friday")
        // Presentation identity of the original segment is preserved.
        XCTAssertEqual(segments[0].speaker, 1000)
    }

    func testShortRepeatFromDifferentRoomSpeakerIsNotSwallowed() {
        var segments = [micSegment("yeah", speaker: 1000, timestamp: 10.0)]
        let echoOfAgreement = micSegment("yeah", speaker: 1001, timestamp: 10.8)
        let result = AppState.mergeFinalSegment(echoOfAgreement, into: &segments)
        XCTAssertEqual(result, .appended)
        XCTAssertEqual(segments.count, 2)

        // Short polite repeats up to three words are also protected — one person
        // saying "thank you" right after another must not be deduped.
        var thanks = [micSegment("Thank you.", speaker: 1000, timestamp: 20.0)]
        let secondThanks = micSegment("Thank you.", speaker: 1001, timestamp: 20.7)
        XCTAssertEqual(AppState.mergeFinalSegment(secondThanks, into: &thanks), .appended)
        XCTAssertEqual(thanks.count, 2)
    }

    func testDistantMicFinalFromOtherSpeakerIsNotDeduped() {
        var segments = [micSegment("we should ship on friday", speaker: 1000, timestamp: 10.0)]
        let laterRepeat = micSegment("we should ship on friday", speaker: 1001, timestamp: 14.0)
        let result = AppState.mergeFinalSegment(laterRepeat, into: &segments)
        XCTAssertEqual(result, .appended)
        XCTAssertEqual(segments.count, 2)
    }

    func testCrossSpeakerDedupNeverAppliesToSystemSegments() {
        var segments = [AppState.LiveSegment(
            id: UUID(), text: "sounds good to me", speaker: 0, timestamp: 10.0,
            isFinal: true, source: .system
        )]
        let otherRemote = AppState.LiveSegment(
            id: UUID(), text: "sounds good to me", speaker: 1, timestamp: 10.4,
            isFinal: true, source: .system
        )
        let result = AppState.mergeFinalSegment(otherRemote, into: &segments)
        XCTAssertEqual(result, .appended)
        XCTAssertEqual(segments.count, 2)
    }

    func testLegacySegmentsWithoutSourceStillDedupMicRange() {
        var segments = [AppState.LiveSegment(
            id: UUID(), text: "we should ship on friday", speaker: 1000, timestamp: 10.0, isFinal: true
        )]
        let flipped = AppState.LiveSegment(
            id: UUID(), text: "we should ship on friday", speaker: 1001, timestamp: 10.4, isFinal: true
        )
        XCTAssertEqual(AppState.mergeFinalSegment(flipped, into: &segments), .skippedExactDuplicate)
    }
}

// MARK: - Sales-conversation detection heuristic

final class SalesDetectionTests: XCTestCase {
    func testSalesSignalMatchesFindCommercialPhrases() {
        let matches = AppState.salesSignalMatches(
            in: "Let's talk pricing and whether the contract covers procurement."
        )
        XCTAssertEqual(matches, ["pricing", "contract", "procurement"])
    }

    func testSalesSignalMatchesRespectWordBoundaries() {
        // "contractor" must not count as "contract".
        XCTAssertTrue(AppState.salesSignalMatches(in: "The contractor rewired the office.").isEmpty)
    }

    func testOrdinaryPlanningTalkDoesNotMatch() {
        XCTAssertTrue(AppState.salesSignalMatches(
            in: "We need a decision on the timeline before the next sprint."
        ).isEmpty)
    }

    func testMultiWordPhrasesMatch() {
        let matches = AppState.salesSignalMatches(in: "Who is the decision maker for the annual plan?")
        XCTAssertEqual(matches, ["decision maker", "annual plan"])
    }
}

// MARK: - Live insights backoff (2.11.0)

final class LiveInsightsBackoffTests: XCTestCase {
    func testBackoffDoublesFromFifteenSecondsToAFiveMinuteCap() {
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 0), 0)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 1), 15)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 2), 30)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 3), 60)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 5), 240)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 6), 300)
        XCTAssertEqual(AppState.liveInsightsBackoff(afterFailures: 40), 300, "never grows past five minutes")
    }
}

#if os(macOS)
/// The floating surface's action row (field report 2026-10-27: four handoff actions truncated
/// to "join…", "end &…" on the 360 pt panel).
@MainActor
final class RecordingIndicatorLayoutTests: XCTestCase {
    private func row() -> some View {
        WrappingRow(spacing: 6) {
            ForEach(["join next", "end & start next", "end meeting", "keep recording"], id: \.self) { title in
                MinitiControlLabel(role: .secondary, isEmphasized: false, height: 28, horizontalPadding: 9) {
                    Label(title, systemImage: "record.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    func testFourHandoffActionsWrapAtThePanelWidthInsteadOfTruncating() {
        let wide = NSHostingView(rootView: row().frame(width: 1000, alignment: .leading))
        let wideHeight = wide.fittingSize.height
        XCTAssertLessThan(wideHeight, 40, "one row when there is room")

        let panel = NSHostingView(rootView: row().frame(width: 340, alignment: .leading))
        let panelHeight = panel.fittingSize.height
        XCTAssertGreaterThan(panelHeight, wideHeight + 20, "at the panel's inner width the actions take a second line")
        XCTAssertLessThan(panelHeight, 3 * 28 + 2 * 6 + 1, "and no more than three")

        // Every label keeps its full width: the widest one alone is wider than a quarter of the panel.
        let single = NSHostingView(rootView: MinitiControlLabel(role: .secondary, isEmphasized: false, height: 28, horizontalPadding: 9) {
            Label("end & start next", systemImage: "arrow.right").font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
        })
        XCTAssertGreaterThan(single.fittingSize.width, 340 / 4, "which is why a single row truncated")
    }
}
#endif

@MainActor
final class SupportReportTests: XCTestCase {
    func testDiagnosticsExportOnlyFixedLabelsAndCodesNeverRawContext() throws {
        let entry = DebugLogger.Entry(timestamp: Date(), category: .audio, level: .error,
            message: "Mic capture FAILED: Code=-10877, private meeting title, alice@example.com /Users/alice/secret secret-key")
        let event = try XCTUnwrap(SupportDiagnostic.make(entry))
        XCTAssertEqual(event.code, "capture_failed")
        XCTAssertEqual(event.error_codes, [-10877])
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        for value in ["private", "alice", "/Users", "secret", "FAILED"] { XCTAssertFalse(encoded.contains(value)) }
        XCTAssertNil(SupportDiagnostic.make(DebugLogger.Entry(timestamp: Date(), category: .app, level: .routine, message: "meeting title")))
        XCTAssertEqual(SupportDiagnostic.make(DebugLogger.Entry(timestamp: Date(), category: .app, level: .error, message: "unknown failure with content"))?.code, "error")
    }

    func testCopyIncludesChosenDiagnosticsAndOptionalReplyOnly() {
        let entry = DebugLogger.Entry(timestamp: Date(), category: .app, level: .warning, message: "timed out Code=-1001")
        var report = SupportReport(message: "What happened", reply_email: "person@example.com", details: ["device_id": "device", "app": "3.4.0 (141)"], diagnostics: [SupportDiagnostic.make(entry)!])
        XCTAssertTrue(report.text.contains("What happened"))
        XCTAssertTrue(report.text.contains("person@example.com"))
        XCTAssertTrue(report.text.contains("Device ID: device"))
        XCTAssertTrue(report.text.contains("-1001"))
        report.diagnostics = []
        XCTAssertFalse(report.text.contains("-1001"))
        XCTAssertTrue(SupportReport.validEmail(""))
        XCTAssertFalse(SupportReport.validEmail("a@example.com\r\nBcc: b@example.com"))
    }

    func testSendingUsesNoCredentialsAndRequiresAMatchingReceipt() async throws {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let report = SupportReport(message: "A bug", details: ["device_id": "device"], diagnostics: [])
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/support/report")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Request-Proof"))
            return (200, Data("{\"accepted\":true,\"id\":\"\(report.id)\"}".utf8))
        }
        try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: SupportSubmissionGate())
        StubURLProtocol.handler = { _ in (200, Data(#"{"accepted":true,"id":"wrong"}"#.utf8)) }
        do { try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: SupportSubmissionGate()); XCTFail("Wrong receipt must not mean sent") }
        catch { XCTAssertTrue(error is SupportReportFailure) }
        for status in [400, 413, 429, 503, 404] {
            StubURLProtocol.handler = { _ in (status, Data()) }
            do { try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: SupportSubmissionGate()); XCTFail("Failure must stay retryable") }
            catch { XCTAssertTrue(error is SupportReportFailure) }
        }
        StubURLProtocol.handler = nil
        StubURLProtocol.script = { _ in throw URLError(.notConnectedToInternet) }
        do { try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: SupportSubmissionGate()); XCTFail("Offline must not mean sent") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Your report is still here")) }
    }
}

final class DiagnosticTimelineTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("timeline.json")
    }

    func testOnlyFixedMetadataSurvivesAndLegacyKeychainStatusIsPreserved() throws {
        let safe = DiagnosticTimeline.sanitize(["status": "-34018", "phase": "sign", "recovery": "no",
            "error_domain": "CryptoTokenKit", "error_code": "-10", "message": "private meeting",
            "token": "secret", "phase_with_email": "alice@example.com", "route": "/Users/alice",
            "server_code": "a provider response with content", "attempt_id": "account-id"])
        XCTAssertEqual(safe, ["status": "-34018", "phase": "sign", "recovery": "no", "error_domain": "CryptoTokenKit", "error_code": "-10"])
        let legacy = SupportDiagnostic.make(DebugLogger.Entry(timestamp: Date(), category: .app, level: .error, message: "Keychain failed: status=-34018 private value"))
        XCTAssertEqual(legacy?.error_codes, [-34018])
        let unknown = DiagnosticTimeline.errorFields(NSError(domain: "secret@example.com", code: 42, userInfo: [NSLocalizedDescriptionKey: "secret"]))
        XCTAssertEqual(unknown, ["error_domain": "other", "error_code": "42"])
    }

    func testAnHourOfRepeatedFailuresIsOneCountedEventAndKeepsSuccessfulMilestones() throws {
        let timeline = DiagnosticTimeline(fileURL: nil)
        let start = Date().addingTimeInterval(-3600)
        let id = UUID().uuidString
        timeline.record(.recordingAttempt, fields: ["attempt_id": id], at: start)
        timeline.record(.audioReceived, fields: ["attempt_id": id], at: start)
        _ = timeline.snapshot()
        for second in 0..<3600 {
            timeline.record(.connectionFailed, fields: ["reason": "network"], at: start.addingTimeInterval(Double(second)))
            if second % 32 == 0 { _ = timeline.snapshot() }
        }
        timeline.record(.transcriptionConnected)
        timeline.record(.transcriptReceived, fields: ["attempt_id": id])
        let events = timeline.snapshot()
        XCTAssertEqual(events.count, 5)
        let failures = try XCTUnwrap(events.first { $0.code == .connectionFailed })
        XCTAssertEqual(failures.count, 3600)
        XCTAssertEqual(failures.last.timeIntervalSince(failures.first), 3599, accuracy: 0.01)
        XCTAssertLessThan(try JSONEncoder().encode(events).count, 4096)
        XCTAssertTrue(SupportDiagnostic.make(events.last!).text.contains("transcript_received"))
    }

    func testRetentionIsBoundedByCountBytesAndAge() throws {
        let timeline = DiagnosticTimeline(fileURL: nil)
        let start = Date()
        for index in 0..<650 {
            timeline.record(.cloudStarted, fields: ["attempt_id": UUID().uuidString], at: start.addingTimeInterval(Double(index) / 10))
            if index % 16 == 0 { _ = timeline.snapshot(now: start.addingTimeInterval(65)) }
        }
        let events = timeline.snapshot(now: start.addingTimeInterval(65))
        XCTAssertLessThanOrEqual(events.count, DiagnosticTimeline.maxEvents)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(events).count, DiagnosticTimeline.maxBytes)
        XCTAssertTrue(timeline.snapshot(now: start.addingTimeInterval(DiagnosticTimeline.maxAge + 100)).isEmpty)
    }

    func testRelaunchKeepsSanitizedHistoryAndClearPersists() throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let original = DiagnosticTimeline(fileURL: file)
        original.record(.keyUnavailable, fields: ["error_domain": "CryptoTokenKit", "error_code": "-10", "phase": "sign", "recovery": "no", "raw": "secret"])
        original.flushForTesting()
        let restarted = DiagnosticTimeline(fileURL: file)
        XCTAssertEqual(restarted.snapshot().count, 1)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(restarted.snapshot()[0].text.contains("phase=sign"))
        restarted.clear(); restarted.flushForTesting()
        XCTAssertTrue(DiagnosticTimeline(fileURL: file).snapshot().isEmpty)
    }

    func testCorruptOversizeAndUnwritableFilesNeverBreakRecordingOfEvents() throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for data in [Data("not json".utf8), Data(repeating: 32, count: DiagnosticTimeline.maxBytes + 1)] {
            try data.write(to: file)
            let timeline = DiagnosticTimeline(fileURL: file)
            XCTAssertTrue(timeline.snapshot().isEmpty)
        }
        // A regular file cannot be the parent directory of a diagnostic file.
        let blocked = DiagnosticTimeline(fileURL: file.appendingPathComponent("blocked.json"))
        blocked.record(.purchaseReady)
        blocked.flushForTesting()
        XCTAssertTrue(blocked.snapshot().contains { $0.code == .purchaseReady })
        XCTAssertEqual(blocked.snapshot().last?.code, .storageUnavailable)
    }

    func testPersistedUnknownFieldsAreNotExported() throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = DiagnosticTimeline.Event(code: .keyUnavailable, first: Date(), last: Date(), count: 1, fields: ["raw": "secret"])
        try JSONEncoder().encode([entry]).write(to: file)
        XCTAssertTrue(DiagnosticTimeline(fileURL: file).snapshot().isEmpty)
    }
}

@MainActor
final class FeedbackSubmissionTests: XCTestCase {
    func testFeedbackContainsOnlyTheMessageReplyAndBasicAppDetails() throws {
        let report = FeedbackSheet.report(id: UUID().uuidString.lowercased(), message: "  An idea  ", reply: " person@example.com ")
        XCTAssertEqual(report.kind, "feedback")
        XCTAssertEqual(report.message, "An idea")
        XCTAssertEqual(report.reply_email, "person@example.com")
        XCTAssertEqual(Set(report.details.keys), ["app", "platform"])
        XCTAssertTrue(report.diagnostics.isEmpty)
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(SupportReport.self, from: data), report)
    }

    func testSharedAdmissionAllowsOnlyOneSendAndHonoursCooldown() throws {
        let gate = SupportSubmissionGate()
        var now = Date()
        gate.now = { now }
        try gate.begin()
        XCTAssertThrowsError(try gate.begin()) { error in
            guard case SupportReportFailure.sending = error else { return XCTFail("Expected in-flight protection") }
        }
        gate.wait(30); gate.finish()
        XCTAssertThrowsError(try gate.begin()) { error in
            guard case SupportReportFailure.cooldown(30) = error else { return XCTFail("Expected cooldown") }
        }
        now = now.addingTimeInterval(30)
        try gate.begin(); gate.finish()
        XCTAssertFalse(gate.busy)
    }

    func testSuccessAndRateLimitBlockASecondRequestWithoutDroppingThePayload() async throws {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let report = FeedbackSheet.report(id: UUID().uuidString.lowercased(), message: "Feedback", reply: "")
        let gate = SupportSubmissionGate()
        let now = Date(); gate.now = { now }
        StubURLProtocol.handler = { _ in (200, Data("{\"accepted\":true,\"id\":\"\(report.id)\"}".utf8)) }
        try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: gate)
        StubURLProtocol.handler = { _ in XCTFail("Must not send during cooldown"); return (500, Data()) }
        do { try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: gate); XCTFail("Expected cooldown") }
        catch { guard case SupportReportFailure.cooldown(30) = error else { return XCTFail("Wrong error") } }
        let limited = SupportSubmissionGate(); limited.now = { now }
        StubURLProtocol.handler = { _ in (429, Data()) }
        do { try await SupportReportSender.send(report, session: TestSupport.stubbedSession(), gate: limited); XCTFail("Expected rate limit") }
        catch { guard case SupportReportFailure.cooldown(60) = error else { return XCTFail("Expected server wait fallback") } }
        XCTAssertFalse(limited.busy)
        XCTAssertEqual(report.message, "Feedback")
        XCTAssertEqual(limited.retryAt, now.addingTimeInterval(60))
    }
}
