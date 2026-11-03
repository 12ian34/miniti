import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class DiagnosticsQueueTests: XCTestCase {
    private func event(_ name: String = "recording_attempt") -> MinitiAPIService.ClientEventPayload {
        .init(name: name, category: .app, level: .info, occurredAt: Date(), diagnosticsSessionId: UUID().uuidString,
              appMode: "managed", meetingId: nil, details: nil)
    }

    func testReceiptKeepsArrivalsAndConcurrentFlushCannotDuplicateTheSend() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        let first = event(), second = event()
        queue.append(first)
        var held: CheckedContinuation<Set<UUID>, Error>?
        var sent: [[UUID]] = []
        let task = Task { await queue.flush(allowed: { true }) { batch in
            sent.append(batch.map(\.id))
            if sent.count == 1 { return try await withCheckedThrowingContinuation { held = $0 } }
            throw URLError(.notConnectedToInternet)
        } }
        while held == nil { await Task.yield() }
        queue.append(second)
        await queue.flush(allowed: { true }) { _ in XCTFail("Concurrent send"); return [] }
        held?.resume(returning: [first.id])
        await task.value
        XCTAssertEqual(queue.events.map(\.id), [second.id])
        XCTAssertEqual(sent, [[first.id], [second.id]])
        XCTAssertEqual(DiagnosticsQueue(defaults: defaults).events.map(\.id), [second.id])
        XCTAssertGreaterThan(queue.retryDelay, 0)
    }

    func testClearedOrReownedQueueCannotBeRestoredByLateReceipt() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        queue.setOwner("a")
        let first = event(); queue.append(first)
        var held: CheckedContinuation<Set<UUID>, Error>?
        let task = Task { await queue.flush(allowed: { true }) { _ in try await withCheckedThrowingContinuation { held = $0 } } }
        while held == nil { await Task.yield() }
        queue.clear() // diagnostics consent withdrawn
        queue.setOwner("b")
        let newEvent = event(); queue.append(newEvent)
        held?.resume(returning: [first.id])
        await task.value
        XCTAssertEqual(queue.events.map(\.id), [newEvent.id])
    }

    func testLostResponseKeepsIdentityAcrossRelaunchAndBackoff() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        let item = event(); queue.append(item)
        await queue.flush(allowed: { true }) { _ in throw URLError(.networkConnectionLost) }
        let reloaded = DiagnosticsQueue(defaults: defaults)
        XCTAssertEqual(reloaded.events.map(\.id), [item.id])
        XCTAssertGreaterThan(reloaded.retryDelay, 0)
        reloaded.now = { Date().addingTimeInterval(16) }
        await reloaded.flush(allowed: { true }) { batch in Set(batch.map(\.id)) }
        XCTAssertTrue(reloaded.events.isEmpty)
    }
}

@MainActor
final class RecordingUsageQueueTests: XCTestCase {
    private let owner = RecordingUsageQueue.Owner(deviceID: "550e8400-e29b-41d4-a716-446655440000", accountID: "acct_AbCdEf1234567890")
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("usage-test-\(UUID())/queue.json") }

    func testMidnightSplitAndPauseNeverIncludeTimeClosed() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = RecordingUsageQueue(fileURL: url)
        let midnight = floor(Date().timeIntervalSince1970 / 86400) * 86400
        var date = Date(timeIntervalSince1970: midnight - 2), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }
        queue.begin(owner: owner)
        date.addTimeInterval(5); clock += 5
        queue.observe(owner: owner); queue.finish(observeTail: false)
        XCTAssertEqual(queue.pending.map(\.durationMS), [2000, 3000])
        XCTAssertEqual(Set(queue.pending.map(\.id)).count, 2)
        let ids = queue.pending.map(\.id)
        let reopened = RecordingUsageQueue(fileURL: url)
        XCTAssertEqual(reopened.pending.map(\.id), ids)
        date.addTimeInterval(3600); clock += 3600
        queue.begin(owner: owner)
        date.addTimeInterval(1); clock += 1
        queue.observe(owner: owner); queue.finish(observeTail: false)
        XCTAssertEqual(queue.pending.reduce(0) { $0 + $1.durationMS }, 6000)
    }

    func testCrashRecoversOnlyPersistedCheckpointAndKeepsIDs() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = RecordingUsageQueue(fileURL: url)
        var date = Date(), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        for _ in 0..<4 { date.addTimeInterval(5); clock += 5; queue.observe(owner: owner) }
        let recovered = RecordingUsageQueue(fileURL: url)
        XCTAssertEqual(recovered.pending.reduce(0) { $0 + $1.durationMS }, 15000)
        XCTAssertFalse(recovered.isActive)
        let reopened = RecordingUsageQueue(fileURL: url)
        XCTAssertEqual(reopened.pending, recovered.pending)
    }

    func testOwnerChangeFencesQueuedAndInFlightDelivery() async throws {
        let queue = RecordingUsageQueue(fileURL: nil)
        var date = Date(), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        date.addTimeInterval(1); clock += 1; queue.observe(owner: owner); queue.finish(observeTail: false)
        var current: RecordingUsageQueue.Owner? = owner
        var gate: CheckedContinuation<UUID, Error>?
        let first = try XCTUnwrap(queue.pending.first)
        let flush = Task { await queue.flush(currentOwner: { current }) { _ in try await withCheckedThrowingContinuation { gate = $0 } } }
        try await TestSupport.waitUntil { gate != nil }
        current = .init(deviceID: owner.deviceID, accountID: "acct_NEWowner1234567")
        gate?.resume(returning: first.id); await flush.value
        XCTAssertEqual(queue.pending, [first])
        await queue.flush(currentOwner: { current }) { _ in XCTFail("Must not send the previous account's report"); return UUID() }
        current = owner
        await queue.flush(currentOwner: { current }) { report in report.id }
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testStorageFailurePreventsSendingAndLongUnobservedGapsStayBounded() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("usage-blocked-\(UUID())")
        try Data().write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let queue = RecordingUsageQueue(fileURL: parent.appendingPathComponent("queue.json"))
        var date = Date(), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        date.addTimeInterval(3600); clock += 3600; queue.observe(owner: owner); queue.finish(observeTail: false)
        XCTAssertEqual(queue.pending.first?.durationMS, 5000)
        XCTAssertGreaterThan(queue.dropped, 0)
        await queue.flush(currentOwner: { self.owner }) { _ in XCTFail("Undurable report must not be sent"); return UUID() }
    }

    func testFailedDeliverySurvivesRestartAndExpirationIsBounded() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = RecordingUsageQueue(fileURL: url)
        var date = Date(), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        date.addTimeInterval(1); clock += 1; queue.observe(owner: owner); queue.finish(observeTail: false)
        await queue.flush(currentOwner: { self.owner }) { _ in throw URLError(.notConnectedToInternet) }
        let reopened = RecordingUsageQueue(fileURL: url)
        XCTAssertEqual(reopened.pending, queue.pending)
        date.addTimeInterval(32 * 86400); reopened.now = { date }
        await reopened.flush(currentOwner: { self.owner }) { _ in XCTFail("Expired report"); return UUID() }
        XCTAssertTrue(reopened.pending.isEmpty)
        XCTAssertEqual(reopened.dropped, 1)
    }
}

extension RecordingUsageQueueTests {
    func testSharedReportingFixtureMatchesTimelineSanitization() throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.reporting.utf8)) as? [String: Any])
        let enums = try XCTUnwrap(fixture["enum_fields"] as? [String: [String]])
        for (key, values) in enums {
            for value in values { XCTAssertEqual(DiagnosticTimeline.sanitize([key: value]), [key: value], key) }
            XCTAssertTrue(DiagnosticTimeline.sanitize([key: "customer content"]).isEmpty)
        }
        let limits = try XCTUnwrap(fixture["integer_fields"] as? [String: Int])
        for (key, limit) in limits {
            XCTAssertEqual(DiagnosticTimeline.sanitize([key: String(limit)]), [key: String(limit)])
            XCTAssertTrue(DiagnosticTimeline.sanitize([key: String(limit + 1)]).isEmpty)
        }
        XCTAssertTrue(DiagnosticTimeline.sanitize(["serial_number": "secret", "private_mode": "true", "transcript": "secret"]).isEmpty)
    }
}

extension RecordingUsageQueueTests {
    func testActualUsageRequestHasOnlyDurationMetadataAndRequiresOriginalCredential() async throws {
        let context = StubURLProtocol.Context()
        let session = TestSupport.stubbedSession(context: context)
        let auth = TestSupport.enrolledAuthManager(session: session)
        let service = MinitiAPIService(session: session, auth: auth)
        let id = UUID()
        let report = RecordingUsageQueue.Report(id: id, owner: .init(deviceID: TestSupport.testDeviceID, accountID: "acct_test"), day: "2026-11-03", durationMS: 15000)
        context.script = { request in
            XCTAssertEqual(request.url?.path, "/api/recording-usage")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as? [String: Any])
            XCTAssertEqual(Set(body.keys), Set(["schema_version", "report_id", "account_id", "engine", "day", "duration_ms"]))
            XCTAssertEqual(body["account_id"] as? String, "acct_test")
            XCTAssertEqual(body["engine"] as? String, "on_device")
            XCTAssertEqual(body["duration_ms"] as? Int, 15000)
            return StubURLProtocol.json(200, "{\"accepted_id\":\"\(id.uuidString)\"}")
        }
        let generation = auth.credentialGeneration
        let receipt = try await service.sendRecordingUsage(report, credentialGeneration: generation)
        XCTAssertEqual(receipt, id)
        auth.clearLocal(reason: "test owner changed")
        do { _ = try await service.sendRecordingUsage(report, credentialGeneration: generation); XCTFail("Old owner must not send") }
        catch { }
        XCTAssertEqual(context.requests.count, 1)
    }
}

extension RecordingUsageQueueTests {
    func testFourHourChunksAndQueueCapacityRemainBounded() {
        let queue = RecordingUsageQueue(fileURL: nil)
        var date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 86400) * 86400)
        var clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        for _ in 0..<2881 { date.addTimeInterval(5); clock += 5; queue.observe(owner: owner) }
        queue.finish(observeTail: false)
        XCTAssertEqual(queue.pending.map(\.durationMS), [14400000, 5000])
        for _ in 0..<2050 {
            queue.begin(owner: owner); date.addTimeInterval(1); clock += 1
            queue.observe(owner: owner); queue.finish(observeTail: false)
        }
        XCTAssertEqual(queue.pending.count, 2048)
        XCTAssertEqual(queue.dropped, 4)
    }

    func testClockChangesCannotGrowActiveReportsBeyondQueueCapacity() {
        let queue = RecordingUsageQueue(fileURL: nil)
        let today = floor(Date().timeIntervalSince1970 / 86400) * 86400
        var date = Date(timeIntervalSince1970: today + 3600)
        var clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }; queue.begin(owner: owner)
        for index in 0..<2050 {
            // A wall-clock correction must not create an unbounded active list.
            date = Date(timeIntervalSince1970: today + (index.isMultiple(of: 2) ? 3600 : -3600))
            clock += 1; queue.observe(owner: owner)
        }
        queue.finish(observeTail: false)
        XCTAssertEqual(queue.pending.count, 2048)
        XCTAssertEqual(queue.pending.reduce(0) { $0 + $1.durationMS }, 2048000)
        XCTAssertEqual(queue.dropped, 2)
    }
}

final class HardwareCapabilitiesTests: XCTestCase {
    func testCoarseFieldsNeverContainRawMachineStringsAndUnknownFutureHardwareStaysUnknown() {
        let fields = HardwareCapabilities.fields(model: "MacBookAir10,1", chip: "Apple M1", memoryBytes: 8 * 1_073_741_824,
            supported: true, preparation: "ready", thermal: "nominal", preparationMS: 1400)
        XCTAssertEqual(fields["model_family"], "macbook_air")
        XCTAssertEqual(fields["chip_family"], "apple_m1")
        XCTAssertEqual(fields["ram_band"], "up_to_8_gb")
        XCTAssertEqual(fields["preparation_ms"], "1400")
        XCTAssertTrue(fields.allSatisfy { RecordingReportingContract.valid($0.key, $0.value) })
        let unknown = HardwareCapabilities.fields(model: "Alice's Mac99,99", chip: "Apple M99 Secret", memoryBytes: 0,
            supported: false, preparation: "raw failure", thermal: "raw temperature")
        XCTAssertEqual(unknown["model_family"], "unknown")
        XCTAssertEqual(unknown["chip_family"], "unknown")
        XCTAssertEqual(unknown["ram_band"], "unknown")
        XCTAssertEqual(unknown["preparation_state"], "unknown")
        XCTAssertEqual(unknown["thermal_state"], "unknown")
        XCTAssertFalse(unknown.values.contains { $0.contains("Alice") || $0.contains("Secret") })
        XCTAssertEqual(HardwareCapabilities.fields(model: "Mac16,7", chip: "Apple M5 Pro", memoryBytes: 24 * 1_073_741_824,
            supported: true, preparation: "off", thermal: "fair")["chip_family"], "apple_m5")
        for (gb, band) in [(8, "up_to_8_gb"), (16, "9_to_16_gb"), (32, "17_to_32_gb"), (64, "33_to_64_gb"), (128, "over_64_gb")] {
            XCTAssertEqual(HardwareCapabilities.fields(model: "", chip: "", memoryBytes: UInt64(gb) * 1_073_741_824,
                supported: true, preparation: "off", thermal: "nominal")["ram_band"], band)
        }
    }

    func testHardwareAdmissionRequiresConsentAndEnrollmentAndNeverSamplesActiveRecording() {
        XCTAssertTrue(HardwareCapabilities.eligible(isMac: true, managed: true, sharing: true, enrolled: true, recording: false, finalizing: false))
        for disabled in 0..<6 {
            XCTAssertFalse(HardwareCapabilities.eligible(isMac: disabled != 0, managed: disabled != 1, sharing: disabled != 2,
                enrolled: disabled != 3, recording: disabled == 4, finalizing: disabled == 5))
        }
    }

    func testHardwareTransitionsAreBoundedAndRepeatedProgressDoesNotFlood() {
        var admission = HardwareSnapshotAdmission()
        let now = Date()
        XCTAssertTrue(admission.shouldEmit(["preparation_state": "preparing"], now: now))
        for _ in 0..<100 { XCTAssertFalse(admission.shouldEmit(["preparation_state": "preparing"], now: now)) }
        for index in 1..<6 { XCTAssertTrue(admission.shouldEmit(["state": String(index)], now: now.addingTimeInterval(Double(index)))) }
        XCTAssertFalse(admission.shouldEmit(["state": "another"], now: now.addingTimeInterval(10)))
        XCTAssertTrue(admission.shouldEmit(["state": "another"], now: now.addingTimeInterval(3601)))
    }
}


extension HardwareCapabilitiesTests {
    func testCapabilityEnvelopeCannotLinkToARecordingAndStillReadsAsLegacyQueueData() throws {
        let event = MinitiAPIService.ClientEventPayload(name: "device_capabilities", category: .app, level: .info,
            occurredAt: Date(), diagnosticsSessionId: UUID().uuidString, appMode: "managed", meetingId: UUID().uuidString,
            details: ["schema_version": "1"])
        let encoded = try JSONEncoder().encode(event)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(body["diagnostics_session_id"] as? String, "", "Keep the legacy required string without retaining an identifier")
        XCTAssertNil(body["meeting_id"])
        XCTAssertEqual(try JSONDecoder().decode(MinitiAPIService.ClientEventPayload.self, from: encoded).diagnosticsSessionId, "")
    }
}

final class RecordingOutcomeTests: XCTestCase {
    func testCaptureLifecycleDoesNotDependOnPCMOrVisibleWords() {
        var attempt = RecordingDiagnosticAttempt(route: "managed", microphone: true, system: false)
        XCTAssertEqual(attempt.finalDetails(failed: false, duration: 0)["lifecycle_outcome"], "cancelled")
        attempt.started = true
        let empty = attempt.finalDetails(failed: false, duration: 30)
        XCTAssertEqual(empty["lifecycle_outcome"], "stopped")
        XCTAssertEqual(empty["transcription_outcome"], "no_speech_evidence")
        attempt.speech = true // Provider VAD, never capture energy alone.
        XCTAssertEqual(attempt.finalDetails(failed: false, duration: 30)["transcription_outcome"], "speech_without_words")
        attempt.transcript = true // Includes words delivered by final drain.
        attempt.degraded = true
        let words = attempt.finalDetails(failed: false, duration: 30)
        XCTAssertEqual(words["lifecycle_outcome"], "stopped")
        XCTAssertEqual(words["outcome"], "degraded")
        XCTAssertEqual(words["transcription_outcome"], "words_seen")
        XCTAssertEqual(attempt.finalDetails(failed: true, duration: 30)["lifecycle_outcome"], "failed")
    }

    func testResumedAttemptDoesNotReuseEarlierDurationOrWordsAndFieldsSurviveHelp() {
        var attempt = RecordingDiagnosticAttempt(route: "local", microphone: true, system: true)
        attempt.initialDuration = 600
        attempt.started = true
        let details = attempt.finalDetails(failed: false, duration: 630)
        XCTAssertEqual(details["duration_seconds"], "30")
        XCTAssertEqual(details["transcription_outcome"], "no_speech_evidence")
        XCTAssertEqual(details["transcription_engine"], "on_device")
        attempt.route = "managed" // Pre-start readiness can select the permitted cloud route.
        XCTAssertEqual(attempt.finalDetails(failed: false, duration: 630)["transcription_engine"], "deepgram")
        let safe = DiagnosticTimeline.sanitize(details)
        XCTAssertEqual(safe["lifecycle_outcome"], "stopped")
        XCTAssertEqual(safe["transcription_outcome"], "no_speech_evidence")
        XCTAssertEqual(safe["transcription_engine"], "on_device")
        XCTAssertEqual(attempt.finalDetails(failed: false, duration: .infinity)["duration_seconds"], "0")
        XCTAssertEqual(attempt.finalDetails(failed: false, duration: 1)["duration_seconds"], "0")
    }
}

final class RecordingRecoveryTests: XCTestCase {
    func testConnectionCaptureAndFreshWordsAreIndependentAndGenerationOwned() {
        var recovery = RecordingRecoveryEvidence()
        recovery.begin(at: 100, connection: 2, replacement: true)
        XCTAssertFalse(recovery.observe(connection: 2, connected: true, transcriptAt: 101, recentCapture: true).transcriptionResumed)
        let connected = recovery.observe(connection: 4, connected: true, transcriptAt: 99, recentCapture: true)
        XCTAssertTrue(connected.connectionRestored)
        XCTAssertFalse(connected.transcriptionResumed)
        XCTAssertTrue(recovery.awaitingTranscript, "A quiet connected socket cannot claim words recovered")
        XCTAssertFalse(recovery.observe(connection: 4, connected: true, transcriptAt: 102, recentCapture: false).transcriptionResumed)
        XCTAssertTrue(recovery.observe(connection: 4, connected: true, transcriptAt: 102, recentCapture: true).transcriptionResumed)
        XCTAssertFalse(recovery.awaitingTranscript)
        XCTAssertFalse(recovery.observe(connection: 4, connected: true, transcriptAt: 103, recentCapture: true).transcriptionResumed)
        recovery.begin(at: 110, connection: 4, replacement: false)
        XCTAssertFalse(recovery.observe(connection: 4, connected: true, transcriptAt: 102, recentCapture: true).transcriptionResumed)
        XCTAssertTrue(recovery.observe(connection: 4, connected: true, transcriptAt: 111, recentCapture: true).transcriptionResumed)
    }

    func testSendCompletionsCannotCrossSocketGenerationsAndLocalIngestIsNotCloudSend() {
        let evidence = AudioTransportEvidence()
        evidence.reset(generation: 1)
        let old = evidence.attempt(connected: true, local: false)
        _ = evidence.attempt(connected: false, local: false)
        XCTAssertEqual(evidence.snapshot.attempts, 1)
        XCTAssertEqual(evidence.snapshot.dropped, 1)
        XCTAssertEqual(evidence.snapshot.completions, 0)
        evidence.reset(generation: 3)
        evidence.completed(generation: old)
        XCTAssertEqual(evidence.snapshot.completions, 0)
        let current = evidence.attempt(connected: true, local: false)
        evidence.completed(generation: current)
        _ = evidence.attempt(connected: true, local: true)
        XCTAssertEqual(evidence.snapshot.completions, 1)
        XCTAssertEqual(evidence.snapshot.attempts, 1)
        XCTAssertEqual(evidence.snapshot.localIngests, 1)
    }

    func testRecoveryContractHasIdenticalBoundsInHelpAndProducer() throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.recovery.utf8)) as? [String: Any])
        for (key, values) in try XCTUnwrap(fixture["enum_fields"] as? [String: [String]]) {
            for value in values { XCTAssertEqual(DiagnosticTimeline.sanitize([key: value])[key], value) }
            XCTAssertTrue(DiagnosticTimeline.sanitize([key: "private words"]).isEmpty)
        }
        for (key, limit) in try XCTUnwrap(fixture["integer_fields"] as? [String: Int]) {
            XCTAssertEqual(DiagnosticTimeline.sanitize([key: String(limit)])[key], String(limit))
            XCTAssertTrue(DiagnosticTimeline.sanitize([key: String(limit + 1)]).isEmpty)
        }
    }
}


extension RecordingUsageQueueTests {
    func testDeletionRemovesOnlyItsOwnerAndLateReceiptCannotRestoreIt() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = RecordingUsageQueue(fileURL: url)
        var date = Date(), clock: TimeInterval = 0
        queue.now = { date }; queue.uptime = { clock }
        let other = RecordingUsageQueue.Owner(deviceID: owner.deviceID, accountID: "acct_other")
        for identity in [other, owner] {
            queue.begin(owner: identity)
            date.addTimeInterval(1); clock += 1
            queue.observe(owner: identity); queue.finish(observeTail: false)
        }
        var gate: CheckedContinuation<UUID, Error>?
        let report = try XCTUnwrap(queue.pending.last)
        let flush = Task { await queue.flush(currentOwner: { self.owner }) { _ in
            try await withCheckedThrowingContinuation { gate = $0 }
        } }
        try await TestSupport.waitUntil { gate != nil }
        queue.begin(owner: owner)
        date.addTimeInterval(1); clock += 1; queue.observe(owner: owner)
        XCTAssertTrue(queue.remove(accountID: owner.accountID))
        XCTAssertFalse(queue.isActive)
        gate?.resume(returning: report.id); await flush.value
        let reopened = RecordingUsageQueue(fileURL: url)
        XCTAssertEqual(reopened.pending.count, 1)
        XCTAssertEqual(reopened.pending.first?.owner, other)
        XCTAssertEqual(reopened.pending.first?.durationMS, 1000)
    }
}

extension RecordingUsageQueueTests {
    func testEmptyFlushDoesNotRewriteQueueFile() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = RecordingUsageQueue(fileURL: url)
        let old = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        for _ in 0..<4 {
            await queue.flush(currentOwner: { self.owner }) { _ in XCTFail("No report to send"); return UUID() }
        }
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, old)
    }

    func testTerminalUsageRefusalsDropReportAndPersistDroppedCount() async throws {
        for (status, code) in [(409, "report_owner_mismatch"), (403, "device_disabled")] {
            let url = file()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let queue = RecordingUsageQueue(fileURL: url)
            let context = StubURLProtocol.Context()
            context.script = { _ in StubURLProtocol.json(status, "{\"error\":\"\(code)\"}") }
            let session = TestSupport.stubbedSession(context: context)
            defer { session.invalidateAndCancel() }
            let auth = TestSupport.enrolledAuthManager(session: session)
            let service = MinitiAPIService(session: session, auth: auth)
            let enrolled = RecordingUsageQueue.Owner(deviceID: TestSupport.testDeviceID, accountID: "acct_test")
            var clock: TimeInterval = 0
            queue.uptime = { clock }
            queue.begin(owner: enrolled); clock += 1; queue.observe(owner: enrolled); queue.finish(observeTail: false)
            XCTAssertEqual(queue.pending.count, 1)
            await queue.flush(currentOwner: { enrolled }) { try await service.sendRecordingUsage($0, credentialGeneration: auth.credentialGeneration) }
            XCTAssertTrue(queue.pending.isEmpty)
            XCTAssertEqual(queue.dropped, 1)
            let reopened = RecordingUsageQueue(fileURL: url)
            XCTAssertTrue(reopened.pending.isEmpty)
            XCTAssertEqual(reopened.dropped, 1)
            XCTAssertEqual(context.requests.count, 1)
        }
    }
}
