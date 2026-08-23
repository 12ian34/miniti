import XCTest
import SwiftData
import Combine
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
        XCTAssertEqual(SettingsDestination.fromLegacyID("mcp"), .docsMCP)
        XCTAssertEqual(SettingsDestination.fromLegacyID("about"), .privacySupport)
        XCTAssertEqual(SettingsDestination.fromLegacyID("unknown"), .general)
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
        XCTAssertTrue(Set(macManaged.map(\.destination)).isSuperset(of: [.ai, .calendar, .crm, .webhooks, .docsMCP]))

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
        XCTAssertNil(recent.endTime)
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
        XCTAssertNil(longRunning.endTime)
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
        XCTAssertFalse(state.canStartRecording)
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

        let snapshot = try AppState.buildCodebaseSnapshot(
            rootURL: root,
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

    func testAutomaticCalendarHandoffRequiresBothExistingAutomationsAndQuiet() {
        let now = Date(timeIntervalSince1970: 1_000)
        let currentEnd = now.addingTimeInterval(-60)
        let nextStart = now.addingTimeInterval(10)

        XCTAssertTrue(AppState.canAutomaticallyHandoffCalendarMeeting(
            currentEventEnd: currentEnd,
            nextEventStart: nextStart,
            now: now,
            transcriptGap: 120,
            audioGap: 120,
            autoStartEnabled: true,
            calendarAutoStopEnabled: true,
            eventsOverlap: false
        ))
        XCTAssertFalse(AppState.canAutomaticallyHandoffCalendarMeeting(
            currentEventEnd: currentEnd,
            nextEventStart: nextStart,
            now: now,
            transcriptGap: 120,
            audioGap: 120,
            autoStartEnabled: false,
            calendarAutoStopEnabled: true,
            eventsOverlap: false
        ))
        XCTAssertFalse(AppState.canAutomaticallyHandoffCalendarMeeting(
            currentEventEnd: currentEnd,
            nextEventStart: nextStart,
            now: now,
            transcriptGap: 120,
            audioGap: 30,
            autoStartEnabled: true,
            calendarAutoStopEnabled: true,
            eventsOverlap: false
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
        XCTAssertEqual(AppState.AutoStopReason.silence.label, "auto-stopped — no speech detected")
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

    private static func makeCalendarEvent(
        id: String,
        title: String,
        start: Date = Date().addingTimeInterval(300),
        end: Date = Date().addingTimeInterval(3600)
    ) -> MinitiAPIService.CalendarEvent {
        let formatter = ISO8601DateFormatter()
        let json: [String: Any] = [
            "id": id,
            "title": title,
            "start": formatter.string(from: start),
            "end": formatter.string(from: end),
            "is_all_day": false,
            "status": "confirmed",
            "attendees": [],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MinitiAPIService.CalendarEvent.self, from: data)
    }

    @MainActor
    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: config)
    }
}

// MARK: - Cross-speaker mic dedup (cumulative finals whose diarized speaker flips)

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
