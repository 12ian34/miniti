import XCTest
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class AppStateComputationTests: XCTestCase {

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

    @MainActor
    func testResetSpeakerIdentityForDeepgramReconnectKeepsOnlyMicIdentity() {
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

        XCTAssertEqual(state.liveSpeakerNames, [micKey: "Ian"])
        XCTAssertEqual(state.liveSpeakerOverrides, [micKey])
        XCTAssertEqual(state.liveSelfSpeakerIDs, [DeepgramService.micSpeakerID])
        XCTAssertEqual(meeting.speakerNames, [micKey: "Ian"])
        XCTAssertEqual(meeting.speakerOverrides, [micKey])
        XCTAssertEqual(meeting.selfSpeakerIDs, [DeepgramService.micSpeakerID])
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
