import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class AppStateComputationTests: XCTestCase {

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
}
