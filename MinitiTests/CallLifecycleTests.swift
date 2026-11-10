import XCTest
#if os(macOS)
import AppKit
#endif
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Pure call-lifecycle policy: helper normalization, snapshot ordering, and the
/// start/association/end state machine. No Core Audio involved — snapshots are synthetic.
final class CallLifecycleTests: XCTestCase {

    func testRecognizedCallStillStartsAlongsideUnknownMicrophoneUser() {
        var engine = CallLifecycleEngine()
        func observed(_ offset: TimeInterval, known: Bool = true) -> CallActivitySnapshot {
            var processes = [CallProcessObservation(pid: 12, bundleID: nil, runningInput: true, runningOutput: false)]
            if known { processes.append(.init(pid: 13, bundleID: "company.thebrowser.Browser", runningInput: true, runningOutput: false)) }
            return CallSnapshotInterpreter.snapshot(processes, excludingPID: 99, now: base.addingTimeInterval(offset))
        }
        let first = observed(0)
        XCTAssertFalse(first.isReliable, "Unknown input cannot prove the end of a call")
        XCTAssertEqual(first.activeCalls.count, 1)
        XCTAssertTrue(engine.ingest(snapshot: first, context: context()).isEmpty)
        XCTAssertEqual(engine.ingest(snapshot: observed(10), context: context()), [.offerStartPrompt(first.activeCalls[0])])
        engine.noteRecordingStarted(activeCalls: first.activeCalls, startedFrom: first.activeCalls[0])
        _ = engine.ingest(snapshot: observed(11), context: context(isRecording: true))
        XCTAssertTrue(engine.ingest(snapshot: observed(20, known: false), context: context(isRecording: true)).isEmpty)
        XCTAssertTrue(engine.ingest(snapshot: observed(200, known: false), context: context(isRecording: true)).isEmpty)
    }

    func testIdentifiedUnrelatedMicrophoneUserDoesNotDisableCallEndDetection() {
        let ignored = CallProcessObservation(pid: 12, bundleID: "example.dictation", runningInput: true, runningOutput: false)
        let detected = CallSnapshotInterpreter.snapshot([ignored,
            .init(pid: 13, bundleID: "us.zoom.xos", runningInput: true, runningOutput: false)], excludingPID: 99, now: base)
        XCTAssertTrue(detected.isReliable)
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: detected.activeCalls, startedFrom: detected.activeCalls[0])
        _ = engine.ingest(snapshot: detected, context: context(isRecording: true))
        let absent = CallSnapshotInterpreter.snapshot([ignored], excludingPID: 99, now: base.addingTimeInterval(10))
        XCTAssertTrue(absent.isReliable)
        XCTAssertTrue(engine.ingest(snapshot: absent, context: context(isRecording: true)).isEmpty)
        let later = CallSnapshotInterpreter.snapshot([ignored], excludingPID: 99, now: base.addingTimeInterval(60))
        XCTAssertEqual(engine.ingest(snapshot: later, context: context(isRecording: true)),
                       [.beginEndingGrace(app: detected.activeCalls[0], askOnly: false)])
    }

    // MARK: - Fixtures

    private let base = Date(timeIntervalSince1970: 1_756_000_000)

    private func app(
        _ bundleID: String = "us.zoom.xos",
        name: String = "Zoom",
        devices: Set<String> = ["BuiltInMic"],
        confidence: CallApplicationConfidence = .native
    ) -> ActiveCallApplication {
        ActiveCallApplication(bundleID: bundleID, displayName: name, deviceUIDs: devices, confidence: confidence)
    }

    private func snapshot(at offset: TimeInterval, calls: [ActiveCallApplication]) -> CallActivitySnapshot {
        CallActivitySnapshot(capturedAt: base.addingTimeInterval(offset), activeCalls: calls)
    }

    private func context(
        isRecording: Bool = false,
        smartMeetings: Bool = true,
        hasContent: Bool = true,
        duration: TimeInterval = 600,
        transcriptGap: TimeInterval = .infinity,
        audioGap: TimeInterval = .infinity,
        inGrace: Bool = false
    ) -> CallLifecycleContext {
        CallLifecycleContext(
            isRecording: isRecording,
            smartMeetingsEnabled: smartMeetings,
            hasMeaningfulContent: hasContent,
            recordingDuration: duration,
            transcriptGap: transcriptGap,
            audioGap: audioGap,
            isInEndingGrace: inGrace
        )
    }

    // MARK: - Directory normalization

    func testNormalizeResolvesDirectHelperAliasAndUnknownBundleIDs() {
        XCTAssertEqual(CallApplicationDirectory.normalize(bundleID: "us.zoom.xos")?.displayName, "Zoom")
        // Helper processes resolve to their owner via prefix matching.
        XCTAssertEqual(
            CallApplicationDirectory.normalize(bundleID: "com.google.Chrome.helper")?.canonicalBundleID,
            "com.google.Chrome"
        )
        XCTAssertEqual(
            CallApplicationDirectory.normalize(bundleID: "com.tinyspeck.slackmacgap.helper")?.displayName,
            "Slack"
        )
        // Shared WebKit helpers retain weak evidence without claiming Safari ownership.
        XCTAssertEqual(CallApplicationDirectory.normalize(bundleID: "com.apple.WebKit.GPU")?.canonicalBundleID, "com.apple.WebKit")
        // Unknown microphone users stay local and unrecognized.
        XCTAssertNil(CallApplicationDirectory.normalize(bundleID: "com.example.dictation"))
        XCTAssertNil(CallApplicationDirectory.normalize(bundleID: ""))
    }

    func testNormalizeExcludesMinitiItself() {
        XCTAssertNil(CallApplicationDirectory.normalize(bundleID: "com.miniti.app"))
        XCTAssertNil(CallApplicationDirectory.normalize(bundleID: "com.miniti.app.tests"))
        XCTAssertTrue(CallApplicationDirectory.isExcluded(bundleID: "com.miniti.mobile"))
    }

    func testBrowsersCarryBrowserConfidence() {
        XCTAssertEqual(CallApplicationDirectory.normalize(bundleID: "com.google.Chrome")?.confidence, .browser)
        XCTAssertEqual(CallApplicationDirectory.normalize(bundleID: "us.zoom.xos")?.confidence, .native)
    }

    func testSnapshotOrderPutsNativeAppsBeforeBrowsersThenAlphabetical() {
        let zoom = app()
        let chrome = app("com.google.Chrome", name: "Chrome", confidence: .browser)
        let slack = app("com.tinyspeck.slackmacgap", name: "Slack")
        let sorted = [chrome, slack, zoom].sorted(by: CallApplicationDirectory.snapshotOrder)
        XCTAssertEqual(sorted.map(\.displayName), ["Slack", "Zoom", "Chrome"])
    }

    // MARK: - Start detection

    func testStartPromptRequiresContinuousActivityForDebounce() {
        var engine = CallLifecycleEngine()
        let zoom = app()

        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context()), [])
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 1, calls: [zoom]), context: context()), [])
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 2, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
        // Prompted once per uninterrupted call, not every tick.
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 3, calls: [zoom]), context: context()), [])
    }

    func testStartCandidateResetsWhenActivityBreaks() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context())
        _ = engine.ingest(snapshot: snapshot(at: 1, calls: []), context: context())
        // 1.5s of renewed activity is not 2 continuous seconds from the new first-seen.
        _ = engine.ingest(snapshot: snapshot(at: 2, calls: [zoom]), context: context())
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 3.5, calls: [zoom]), context: context()), [])
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 4, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
    }

    func testDismissalSuppressesRepeatPromptsForOneUninterruptedCall() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context())
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 2, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
        engine.noteStartPromptDismissed(bundleID: zoom.bundleID)
        // Still the same uninterrupted call: no re-prompt.
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 30, calls: [zoom]), context: context()), [])
        // The call ends and the suppression resets after the gap…
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 31, calls: []), context: context()), [])
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 35, calls: []), context: context()), [])
        // …so a new call prompts again.
        _ = engine.ingest(snapshot: snapshot(at: 60, calls: [zoom]), context: context())
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 62, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
    }

    func testVisibleStartPromptClearsWhenCallDisappears() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context())
        _ = engine.ingest(snapshot: snapshot(at: 2, calls: [zoom]), context: context())
        _ = engine.ingest(snapshot: snapshot(at: 3, calls: []), context: context())
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 6.5, calls: []), context: context()),
            [.clearStartPrompt]
        )
    }

    func testSmartMeetingsOffLeavesSnapshotsInert() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context(smartMeetings: false))
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 5, calls: [zoom]), context: context(smartMeetings: false)),
            []
        )
        XCTAssertNil(engine.startCandidate)
    }

    // MARK: - Association

    func testAssociationFormsFromPromptAppAndFromSingleActiveCall() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: zoom)
        XCTAssertEqual(engine.associatedApp?.bundleID, zoom.bundleID)

        engine.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil)
        XCTAssertEqual(engine.associatedApp?.bundleID, zoom.bundleID)
    }

    func testNoAssociationWithZeroOrMultipleActiveCalls() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil)
        XCTAssertNil(engine.associatedApp)

        let zoom = app()
        let slack = app("com.tinyspeck.slackmacgap", name: "Slack")
        engine.noteRecordingStarted(activeCalls: [zoom, slack], startedFrom: nil)
        XCTAssertNil(engine.associatedApp)
    }

    func testMidRecordingCallNeverAssociatesRetroactively() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: base)
        let facetime = app("com.apple.FaceTime", name: "FaceTime")
        let recording = context(isRecording: true)

        // FaceTime appears well into an in-person recording (past the inferred window):
        // transition candidate after the debounce, never association.
        let late = CallLifecycleEngine.inferredCallWindow + 60
        _ = engine.ingest(snapshot: snapshot(at: late, calls: [facetime]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: late + 2, calls: [facetime]), context: recording),
            [.offerAssociation(facetime)]
        )
        XCTAssertNil(engine.associatedApp)
        XCTAssertNil(engine.associationSource)

        // FaceTime hanging up must not produce any end candidate for this recording.
        _ = engine.ingest(snapshot: snapshot(at: late + 10, calls: []), context: recording)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: late + 20, calls: []), context: recording), [])
        XCTAssertNil(engine.endCandidateSince)
    }

    /// 2026-09-25: "press Record, then join the Zoom" never associated, so the call's end
    /// went unnoticed and the recording ran for hours. A single call that appears shortly
    /// after a plain start is this recording's call, and its end asks.
    func testManualStartAdoptsEarlyCallAsInferredAndEndsAskOnly() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: base)
        XCTAssertNotNil(engine.expectedCallUntil)
        let zoom = app()
        let recording = context(isRecording: true)

        _ = engine.ingest(snapshot: snapshot(at: 30, calls: [zoom]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 32, calls: [zoom]), context: recording),
            [.adoptExpectedCall(zoom)]
        )
        XCTAssertEqual(engine.associatedApp?.bundleID, zoom.bundleID)
        XCTAssertEqual(engine.associationSource, .adoptedInferred)
        // Not evidence that the meeting is remote: the recording was not started for it.
        XCTAssertNil(engine.associatedAppForEnvironmentEvidence)
        XCTAssertNil(engine.expectedCallUntil)

        // Hanging up: an established, content-bearing session still only asks.
        let quiet = context(isRecording: true, duration: 1800, transcriptGap: 60)
        _ = engine.ingest(snapshot: snapshot(at: 1000, calls: []), context: quiet)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 1010, calls: []), context: quiet),
            [.beginEndingGrace(app: zoom, askOnly: true)]
        )
    }

    func testJoinAdoptionStaysAutomaticAndCountsAsRemoteEvidence() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, expectsCall: true, at: base)
        let zoom = app()
        let recording = context(isRecording: true)
        _ = engine.ingest(snapshot: snapshot(at: 30, calls: [zoom]), context: recording)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 32, calls: [zoom]), context: recording), [.adoptExpectedCall(zoom)])
        XCTAssertEqual(engine.associationSource, .adoptedExpected)
        XCTAssertEqual(engine.associatedAppForEnvironmentEvidence?.bundleID, zoom.bundleID)

        var single = CallLifecycleEngine()
        single.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil, at: base)
        XCTAssertEqual(single.associationSource, .singleActiveAtStart)
        var prompted = CallLifecycleEngine()
        prompted.noteRecordingStarted(activeCalls: [], startedFrom: zoom, at: base)
        XCTAssertEqual(prompted.associationSource, .startPrompt)
    }

    func testTwoCallsAtStartNeverArmInferredAdoption() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        let slack = app("com.tinyspeck.slackmacgap", name: "Slack")
        engine.noteRecordingStarted(activeCalls: [zoom, slack], startedFrom: nil, at: base)
        XCTAssertNil(engine.associatedApp)
        XCTAssertNil(engine.expectedCallUntil)
        let recording = context(isRecording: true)
        // Both stay transition candidates; nothing is adopted by sort order.
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom, slack]), context: recording)
        let events = engine.ingest(snapshot: snapshot(at: 2, calls: [zoom, slack]), context: recording)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.contains(.offerAssociation(zoom)))
        XCTAssertTrue(events.contains(.offerAssociation(slack)))
        XCTAssertNil(engine.associatedApp)
    }

    func testInferredWindowExpiresToNonDestructiveAssociation() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: base)
        let zoom = app()
        let recording = context(isRecording: true)
        let late = CallLifecycleEngine.inferredCallWindow + 1
        _ = engine.ingest(snapshot: snapshot(at: late, calls: [zoom]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: late + 2, calls: [zoom]), context: recording),
            [.offerAssociation(zoom)]
        )
        XCTAssertNil(engine.associatedApp)
        XCTAssertNil(engine.expectedCallUntil)
    }

    func testJoinStartAdoptsTheCallThatAppearsInsteadOfOfferingATransition() {
        // Sasha's report: Join on a Meet reminder starts notes first, then the browser
        // joins the call. That call must become the recording's own, not "New meeting detected".
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, expectsCall: true, at: base)
        let chrome = app("com.google.Chrome", name: "Google Chrome", confidence: .browser)
        let recording = context(isRecording: true)

        _ = engine.ingest(snapshot: snapshot(at: 20, calls: [chrome]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 22, calls: [chrome]), context: recording),
            [.adoptExpectedCall(chrome)]
        )
        XCTAssertEqual(engine.associatedApp?.bundleID, chrome.bundleID)
        XCTAssertNil(engine.expectedCallUntil)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 30, calls: [chrome]), context: recording), [])

        // The adopted call is the association: hanging up ends this recording like any other.
        let quiet = context(isRecording: true, transcriptGap: 60)
        _ = engine.ingest(snapshot: snapshot(at: 100, calls: []), context: quiet)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 110, calls: []), context: quiet),
            [.beginEndingGrace(app: chrome, askOnly: true)]
        )
    }

    func testJoinLinkOpenedAfterAnAsynchronousStartStillArmsTheExpectation() {
        // Managed starts register with the engine after the link has already been opened.
        var engine = CallLifecycleEngine()
        engine.noteJoinLinkOpened(at: base)
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: base.addingTimeInterval(1))
        XCTAssertNotNil(engine.expectedCallUntil)

        let chrome = app("com.google.Chrome", name: "Google Chrome", confidence: .browser)
        let recording = context(isRecording: true)
        _ = engine.ingest(snapshot: snapshot(at: 5, calls: [chrome]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 7, calls: [chrome]), context: recording),
            [.adoptExpectedCall(chrome)]
        )
    }

    func testExpectedCallWindowExpiresToNonDestructiveAssociation() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, expectsCall: true, at: base)
        let facetime = app("com.apple.FaceTime", name: "FaceTime")
        let recording = context(isRecording: true)
        let late = CallLifecycleEngine.expectedCallWindow + 1

        _ = engine.ingest(snapshot: snapshot(at: late, calls: [facetime]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: late + 2, calls: [facetime]), context: recording),
            [.offerAssociation(facetime)]
        )
        XCTAssertNil(engine.associatedApp)
    }

    func testExpectationIsIgnoredWhenAnAssociationAlreadyExists() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        engine.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil, expectsCall: true, at: base)
        XCTAssertNil(engine.expectedCallUntil)
        engine.noteJoinLinkOpened(at: base)
        XCTAssertNil(engine.expectedCallUntil)

        let slack = app("com.tinyspeck.slackmacgap", name: "Slack")
        let recording = context(isRecording: true)
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom, slack]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 2, calls: [zoom, slack]), context: recording),
            [.offerTransition(to: slack)]
        )
    }

    func testTransitionOfferedOncePerApp() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        engine.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil)
        let slack = app("com.tinyspeck.slackmacgap", name: "Slack")
        let recording = context(isRecording: true)

        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom, slack]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 2, calls: [zoom, slack]), context: recording),
            [.offerTransition(to: slack)]
        )
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 4, calls: [zoom, slack]), context: recording), [])
    }

    // MARK: - End detection

    private func engineWithObservedZoomCall() -> (CallLifecycleEngine, ActiveCallApplication) {
        var engine = CallLifecycleEngine()
        let zoom = app()
        engine.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil)
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context(isRecording: true))
        return (engine, zoom)
    }

    func testEndRequiresDebounceAndQuietTranscript() {
        var (engine, zoom) = engineWithObservedZoomCall()
        let quiet = context(isRecording: true, transcriptGap: 60)

        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: quiet)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 12, calls: []), context: quiet), [])
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 14, calls: []), context: quiet),
            [.beginEndingGrace(app: zoom, askOnly: false)]
        )
    }

    func testFreshTranscriptVetoesTheEnd() {
        var (engine, _) = engineWithObservedZoomCall()
        // Push-to-talk / release-on-mute shape: mic stream gone but call speech continues.
        let speaking = context(isRecording: true, transcriptGap: 1)
        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: speaking)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 20, calls: []), context: speaking), [])
        // Once the transcript actually goes quiet, the end matures.
        let quiet = context(isRecording: true, transcriptGap: 30)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 30, calls: []), context: quiet).first,
            .beginEndingGrace(app: app(), askOnly: false)
        )
    }

    func testEndRequiresPreviouslyObservedCall() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        engine.noteRecordingStarted(activeCalls: [zoom], startedFrom: nil)
        // Associated but never observed running input during this recording: no end inference.
        let quiet = context(isRecording: true, transcriptGap: 60)
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: []), context: quiet)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 30, calls: []), context: quiet), [])
    }

    func testReactivationCancelsEndCandidateAndGrace() {
        var (engine, zoom) = engineWithObservedZoomCall()
        let quiet = context(isRecording: true, transcriptGap: 60)

        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: quiet)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 12, calls: [zoom]), context: quiet),
            [.cancelEndCandidate]
        )

        // Mature into grace, then the app comes back while grace is pending.
        _ = engine.ingest(snapshot: snapshot(at: 20, calls: []), context: quiet)
        _ = engine.ingest(snapshot: snapshot(at: 24, calls: []), context: quiet)
        XCTAssertEqual(
            engine.ingest(
                snapshot: snapshot(at: 26, calls: [zoom]),
                context: context(isRecording: true, transcriptGap: 60, inGrace: true)
            ),
            [.reactivateDuringGrace]
        )
    }

    func testDeviceSwitchBySameAppIsNotAnEnd() {
        var (engine, _) = engineWithObservedZoomCall()
        let zoomOnAirPods = app(devices: ["AirPods"])
        let quiet = context(isRecording: true, transcriptGap: 60)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 10, calls: [zoomOnAirPods]), context: quiet), [])
        XCTAssertNil(engine.endCandidateSince)
        XCTAssertEqual(engine.associatedApp?.deviceUIDs, ["AirPods"])
    }

    func testShortOrEmptySessionsAskInsteadOfAutomaticEnding() {
        var (engine, zoom) = engineWithObservedZoomCall()
        let shortSession = context(isRecording: true, duration: 30, transcriptGap: 60)
        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: shortSession)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 14, calls: []), context: shortSession),
            [.beginEndingGrace(app: zoom, askOnly: true)]
        )

        var (engine2, zoom2) = engineWithObservedZoomCall()
        let emptySession = context(isRecording: true, hasContent: false, transcriptGap: 60)
        _ = engine2.ingest(snapshot: snapshot(at: 10, calls: []), context: emptySession)
        XCTAssertEqual(
            engine2.ingest(snapshot: snapshot(at: 14, calls: []), context: emptySession),
            [.beginEndingGrace(app: zoom2, askOnly: true)]
        )
    }

    func testGraceStateWhileCallStillMissingProducesNoDuplicateEvents() {
        var (engine, _) = engineWithObservedZoomCall()
        let quiet = context(isRecording: true, transcriptGap: 60)
        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: quiet)
        _ = engine.ingest(snapshot: snapshot(at: 14, calls: []), context: quiet)
        // Grace running, app still gone: quiet ticks, no re-fire.
        let inGrace = context(isRecording: true, transcriptGap: 60, inGrace: true)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 16, calls: []), context: inGrace), [])
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 18, calls: []), context: inGrace), [])
    }

    func testUnreliableSnapshotsNeverAdvanceEndDetection() {
        var (engine, _) = engineWithObservedZoomCall()
        let quiet = context(isRecording: true, transcriptGap: 60)

        // coreaudiod outage: the app "disappears" only because the query failed.
        let outage = { (t: TimeInterval) in
            CallActivitySnapshot(capturedAt: self.base.addingTimeInterval(t), activeCalls: [], isReliable: false)
        }
        XCTAssertEqual(engine.ingest(snapshot: outage(10), context: quiet), [])
        XCTAssertEqual(engine.ingest(snapshot: outage(20), context: quiet), [])
        XCTAssertEqual(engine.ingest(snapshot: outage(30), context: quiet), [])
        XCTAssertNil(engine.endCandidateSince)

        // Reliability returns with the app genuinely gone: the debounce restarts from
        // here rather than maturing instantly off the pre-outage clock.
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 31, calls: []), context: quiet), [])
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 33, calls: []), context: quiet), [])
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 35, calls: []), context: quiet),
            [.beginEndingGrace(app: app(), askOnly: false)]
        )
    }

    func testUnreliableSnapshotsDoNotProduceStartPrompts() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        let unreliable = { (t: TimeInterval) in
            CallActivitySnapshot(capturedAt: self.base.addingTimeInterval(t), activeCalls: [zoom], isReliable: false)
        }
        XCTAssertEqual(engine.ingest(snapshot: unreliable(0), context: context()), [])
        XCTAssertEqual(engine.ingest(snapshot: unreliable(5), context: context()), [])
        XCTAssertNil(engine.startCandidate)
    }

    func testBrowserEndsUseSlowerDebounceAndQuiet() {
        var engine = CallLifecycleEngine()
        let chrome = app("com.google.Chrome", name: "Chrome", confidence: .browser)
        engine.noteRecordingStarted(activeCalls: [chrome], startedFrom: nil)
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [chrome]), context: context(isRecording: true))

        // 4s absence + 5s quiet ends a native call, but not a browser call.
        let nativeQuiet = context(isRecording: true, transcriptGap: 6)
        _ = engine.ingest(snapshot: snapshot(at: 10, calls: []), context: nativeQuiet)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 14, calls: []), context: nativeQuiet), [])
        // At 8s absence with 8s of transcript quiet, the browser end matures.
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 18, calls: []), context: context(isRecording: true, transcriptGap: 9)),
            [.beginEndingGrace(app: chrome, askOnly: true)]
        )
    }

    func testStartPromptNotShownAllowsReOfferForSameCall() {
        var engine = CallLifecycleEngine()
        let zoom = app()
        _ = engine.ingest(snapshot: snapshot(at: 0, calls: [zoom]), context: context())
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 2, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
        // AppState could not show it (terms gate, stopped session…): un-mark, and the same
        // uninterrupted call is offered again on the next tick.
        engine.noteStartPromptNotShown(bundleID: zoom.bundleID)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: 3, calls: [zoom]), context: context()),
            [.offerStartPrompt(zoom)]
        )
        // A user dismissal still suppresses.
        engine.noteStartPromptDismissed(bundleID: zoom.bundleID)
        XCTAssertEqual(engine.ingest(snapshot: snapshot(at: 4, calls: [zoom]), context: context()), [])
    }

    func testRecordingEndedClearsAssociationState() {
        var (engine, _) = engineWithObservedZoomCall()
        engine.noteRecordingEnded()
        XCTAssertNil(engine.associatedApp)
        XCTAssertFalse(engine.hasObservedAssociatedActive)
        XCTAssertNil(engine.endCandidateSince)
        XCTAssertNil(engine.expectedCallUntil)
    }

    #if os(macOS)
    // MARK: - Floating indicator presentation

    func testIndicatorAutoExpandsOnlyOnMeaningfulLifecycleTransitions() {
        let recording = RecordingIndicatorAttentionState(
            promptID: nil,
            isRecording: true,
            isEnding: false
        )
        XCTAssertTrue(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: .idle, to: recording)
        )
        XCTAssertFalse(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: recording, to: recording),
            "A timer tick must not reopen a panel the user collapsed"
        )

        let prompt = RecordingIndicatorAttentionState(
            promptID: "call-start-zoom",
            isRecording: false,
            isEnding: false
        )
        XCTAssertTrue(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: .idle, to: prompt)
        )
        XCTAssertFalse(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: prompt, to: prompt)
        )

        let replacementPrompt = RecordingIndicatorAttentionState(
            promptID: "call-transition-teams",
            isRecording: true,
            isEnding: false
        )
        XCTAssertTrue(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: recording, to: replacementPrompt)
        )

        let ending = RecordingIndicatorAttentionState(
            promptID: nil,
            isRecording: true,
            isEnding: true
        )
        XCTAssertTrue(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: recording, to: ending)
        )

        let nudge = RecordingIndicatorAttentionState(
            promptID: nil,
            nudgeID: "miniti.nudge.monologue.test",
            isRecording: true,
            isEnding: false
        )
        XCTAssertTrue(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: recording, to: nudge),
            "A new foreground coaching nudge must become apparent in the floating surface"
        )
        XCTAssertFalse(
            RecordingIndicatorAttentionPolicy.shouldAutoExpand(from: nudge, to: nudge),
            "An unchanged nudge must not repeatedly reopen the surface"
        )
    }

    func testIndicatorOrdersFrontForEveryMeaningfulAttentionTransition() {
        XCTAssertTrue(
            RecordingIndicatorWindowPolicy.shouldOrderFront(
                isVisible: false,
                attentionRequested: false
            ),
            "A newly shown surface must be ordered front"
        )
        XCTAssertTrue(
            RecordingIndicatorWindowPolicy.shouldOrderFront(
                isVisible: true,
                attentionRequested: true
            ),
            "An already-visible surface must be raised when a meeting decision arrives"
        )
        XCTAssertFalse(
            RecordingIndicatorWindowPolicy.shouldOrderFront(
                isVisible: true,
                attentionRequested: false
            ),
            "Timer ticks must not continuously reorder the surface"
        )
    }

    func testMacNotificationRoutingUsesSurfaceWhileActiveAndSystemFallbackOtherwise() {
        XCTAssertTrue(
            MacNotificationRoutingPolicy.shouldUseFloatingNudge(
                isAppActive: true,
                recordingIndicatorEnabled: true
            )
        )
        XCTAssertFalse(
            MacNotificationRoutingPolicy.shouldMirrorToSystem(
                isAppActive: true,
                recordingIndicatorEnabled: true
            )
        )

        for state in [
            (isAppActive: false, indicatorEnabled: true),
            (isAppActive: true, indicatorEnabled: false),
            (isAppActive: false, indicatorEnabled: false),
        ] {
            XCTAssertFalse(
                MacNotificationRoutingPolicy.shouldUseFloatingNudge(
                    isAppActive: state.isAppActive,
                    recordingIndicatorEnabled: state.indicatorEnabled
                )
            )
            XCTAssertTrue(
                MacNotificationRoutingPolicy.shouldMirrorToSystem(
                    isAppActive: state.isAppActive,
                    recordingIndicatorEnabled: state.indicatorEnabled
                )
            )
        }
    }

    @MainActor
    func testRecordingNudgeExpiresWithoutClearingItsReplacement() async throws {
        let state = AppState()
        state.isRecording = true
        let first = AppState.RecordingNudge(
            id: "first",
            kind: .monologue,
            title: "heads up",
            message: "first"
        )
        let replacement = AppState.RecordingNudge(
            id: "replacement",
            kind: .question,
            title: "incisive question",
            message: "replacement"
        )

        var waits: [CheckedContinuation<Void, Never>] = []
        state.recordingNudgeSleep = { _ in await withCheckedContinuation { waits.append($0) } }
        state.presentRecordingNudge(first, duration: 0.02)
        let firstExpiry = state.recordingNudgeDismissTask
        try await TestSupport.waitUntil { waits.count == 1 }
        state.presentRecordingNudge(replacement, duration: 1)
        let secondExpiry = state.recordingNudgeDismissTask
        try await TestSupport.waitUntil { waits.count == 2 }
        waits[0].resume()
        await firstExpiry?.value
        XCTAssertEqual(state.recordingNudge, replacement)
        state.dismissRecordingNudge()
        waits[1].resume()
        await secondExpiry?.value
        XCTAssertNil(state.recordingNudge)
    }

    func testIndicatorDisclosureDistinguishesClicksFromWindowDrags() {
        XCTAssertFalse(
            RecordingIndicatorDisclosurePolicy.shouldSuppressToggle(
                for: CGSize(width: 0, height: 0)
            )
        )
        XCTAssertFalse(
            RecordingIndicatorDisclosurePolicy.shouldSuppressToggle(
                for: CGSize(width: 2, height: 2)
            ),
            "Small pointer jitter should remain a click"
        )
        XCTAssertTrue(
            RecordingIndicatorDisclosurePolicy.shouldSuppressToggle(
                for: CGSize(width: 12, height: -4)
            ),
            "Moving the floating window must not toggle disclosure on mouse-up"
        )
    }

    func testIndicatorExpansionAnchorsRightEdgeAndStaysFullyVisible() {
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let collapsed = NSRect(x: 900, y: 740, width: 84, height: 44)
        let expanded = RecordingIndicatorGeometry.resizedFrame(
            currentFrame: collapsed,
            contentSize: NSSize(width: 260, height: 160),
            visibleFrame: visible
        )

        XCTAssertEqual(expanded.maxX, collapsed.maxX, accuracy: 0.01)
        XCTAssertEqual(expanded.maxY, collapsed.maxY, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(expanded.minX, visible.minX + RecordingIndicatorGeometry.screenMargin)
        XCTAssertLessThanOrEqual(expanded.maxX, visible.maxX - RecordingIndicatorGeometry.screenMargin)
        XCTAssertGreaterThanOrEqual(expanded.minY, visible.minY + RecordingIndicatorGeometry.screenMargin)
        XCTAssertLessThanOrEqual(expanded.maxY, visible.maxY - RecordingIndicatorGeometry.screenMargin)
    }

    func testIndicatorClampRejectsPartiallyOffscreenFrames() {
        let visible = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let partlyOffscreen = NSRect(x: 950, y: -40, width: 220, height: 180)
        let clamped = RecordingIndicatorGeometry.constrainedFrame(partlyOffscreen, to: visible)

        XCTAssertEqual(clamped.maxX, visible.maxX - RecordingIndicatorGeometry.screenMargin, accuracy: 0.01)
        XCTAssertEqual(clamped.minY, visible.minY + RecordingIndicatorGeometry.screenMargin, accuracy: 0.01)
        XCTAssertEqual(clamped.width, partlyOffscreen.width, accuracy: 0.01)
        XCTAssertEqual(clamped.height, partlyOffscreen.height, accuracy: 0.01)
    }

    @MainActor
    func testClosedMainWindowIsRecreatedInsteadOfTreatedAsRestorable() {
        XCTAssertFalse(
            AppDelegate.isRestorableMainWindowState(
                hasMainIdentifier: true,
                isVisible: false,
                isMiniaturized: false,
                applicationIsHidden: false
            ),
            "An X-closed WindowGroup window must fall through to openWindow(id:)"
        )
        XCTAssertTrue(
            AppDelegate.isRestorableMainWindowState(
                hasMainIdentifier: true,
                isVisible: true,
                isMiniaturized: false,
                applicationIsHidden: false
            )
        )
        XCTAssertTrue(
            AppDelegate.isRestorableMainWindowState(
                hasMainIdentifier: true,
                isVisible: false,
                isMiniaturized: false,
                applicationIsHidden: true
            ),
            "Hiding the app must not create a duplicate main window"
        )
        XCTAssertFalse(
            AppDelegate.isRestorableMainWindowState(
                hasMainIdentifier: false,
                isVisible: true,
                isMiniaturized: false,
                applicationIsHidden: false
            )
        )
    }

    @MainActor
    func testFloatingPanelAndMenuReachTheLiveAppDelegate() {
        // `NSApp.delegate as? AppDelegate` is nil under @NSApplicationDelegateAdaptor,
        // which made "open meeting" a silent no-op whenever miniti was not in front.
        XCTAssertNotNil(AppDelegate.shared, "Window actions must reach the adaptor's AppDelegate")
    }

    @MainActor
    func testPresentMainWindowDeminiaturizesOnlyWhenNeeded() {
        XCTAssertTrue(AppDelegate.shouldDeminiaturizeMainWindow(true))
        XCTAssertFalse(AppDelegate.shouldDeminiaturizeMainWindow(false))
    }
    #endif
}

// MARK: - Auto-start waits for the call (2.11.0)

final class AutoStartPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func decide(
        offset: TimeInterval,
        link: Bool = true,
        detection: Bool = true,
        callActive: Bool = false,
        prompted: Bool = false
    ) -> AppState.AutoStartDecision {
        AppState.autoStartDecision(
            eventStart: t0,
            hasConferenceLink: link,
            callDetectionAvailable: detection,
            callActive: callActive,
            noShowAlreadyPrompted: prompted,
            now: t0.addingTimeInterval(offset)
        )
    }

    func testLinkedEventWaitsForTheCallInsteadOfTheClock() {
        XCTAssertEqual(decide(offset: -600), .none, "too early to arm")
        XCTAssertEqual(decide(offset: -300), .waitForCall, "window opens 5 minutes early")
        XCTAssertEqual(decide(offset: 0), .waitForCall, "the scheduled minute alone never records")
        XCTAssertEqual(decide(offset: 420), .waitForCall, "7 minutes late is still inside the window")
        XCTAssertEqual(decide(offset: 600), .waitForCall, "window closes at 10 minutes")
    }

    func testLinkedEventStartsTheMomentTheCallIsLive() {
        XCTAssertEqual(decide(offset: -240, callActive: true), .startNow, "early joiners record from the join")
        XCTAssertEqual(decide(offset: 420, callActive: true), .startNow, "a late call records from the connect")
        XCTAssertEqual(decide(offset: -600, callActive: true), .none, "a call before the window is some other meeting")
    }

    func testNoShowAsksOnceThenStaysQuiet() {
        XCTAssertEqual(decide(offset: 601), .noShowPrompt)
        XCTAssertEqual(decide(offset: 601, prompted: true), .waitForCall)
        XCTAssertEqual(decide(offset: 601, callActive: true), .startNow, "new positive evidence remains usable until event expiry")
    }

    func testEventsWithoutALinkKeepTheCountdown() {
        XCTAssertEqual(decide(offset: -30, link: false), .none)
        XCTAssertEqual(decide(offset: -16, link: false), .countdown(seconds: 16))
        XCTAssertEqual(decide(offset: -0.4, link: false), .countdown(seconds: 1))
        XCTAssertEqual(decide(offset: 0, link: false), .startNow)
        XCTAssertEqual(decide(offset: 120, link: false), .startNow, "found already running after launch")
        XCTAssertEqual(decide(offset: 121, link: false), .none)
    }

    func testUnavailableDetectionOffersExplicitFallbackInsteadOfClockRecording() {
        XCTAssertEqual(decide(offset: -10, detection: false), .noShowPrompt)
        XCTAssertEqual(decide(offset: 0, detection: false), .noShowPrompt)
        XCTAssertEqual(decide(offset: 601, detection: false), .noShowPrompt)
    }
}


final class BrowserDetectionRegressionTests: XCTestCase {
    func testProcessReadFailureUnknownInputAndSelfExclusionRemainDistinct() {
        let now = Date()
        let failed = CallSnapshotInterpreter.snapshot([.init(pid: 2, bundleID: "company.thebrowser.Browser", runningInput: nil, runningOutput: nil)], excludingPID: 1, now: now)
        XCTAssertEqual(failed.health, .partial)
        XCTAssertFalse(failed.isReliable)
        let unknown = CallSnapshotInterpreter.snapshot([.init(pid: 2, bundleID: nil, runningInput: true, runningOutput: false)], excludingPID: 1, now: now)
        XCTAssertEqual(unknown.health, .unidentifiedInput)
        XCTAssertTrue(unknown.activeCalls.isEmpty)
        let own = CallSnapshotInterpreter.snapshot([.init(pid: 1, bundleID: "com.miniti.app", runningInput: true, runningOutput: nil)], excludingPID: 1, now: now)
        XCTAssertEqual(own.health, .complete)
        XCTAssertTrue(own.activeCalls.isEmpty)
        XCTAssertEqual(CallSnapshotInterpreter.snapshot(nil, excludingPID: 1, now: now).health, .unavailable)
    }

    func testSharedWebKitInputRetainsWeakEvidenceWithoutAnEmbeddedSafariBundle() {
        let snapshot = CallSnapshotInterpreter.snapshot([
            .init(pid: 20, bundleID: "com.apple.WebKit.GPU", ownerBundleID: nil, runningInput: true, runningOutput: true)
        ], excludingPID: 1, now: Date())
        XCTAssertTrue(snapshot.hasPositiveCallEvidence)
        XCTAssertEqual(snapshot.activeCalls.first?.bundleID, "com.apple.WebKit")
        XCTAssertEqual(snapshot.activeCalls.first?.confidence, .browser)
        XCTAssertEqual(snapshot.outputActiveBundleIDs, ["com.apple.WebKit"])
    }

    func testOwnerFallbackResolvesArcAndSharedWebKitWithoutGuessing() {
        for id in ["company.thebrowser.Browser", "company.thebrowser.dia", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.apple.Safari"] {
            let result = CallSnapshotInterpreter.snapshot([
                .init(pid: 3, bundleID: "com.apple.WebKit.GPU", ownerBundleID: id, runningInput: true, runningOutput: false),
                .init(pid: 4, bundleID: id + ".helper", runningInput: true, runningOutput: true)
            ], excludingPID: 1, now: Date())
            XCTAssertEqual(result.activeCalls.map(\.bundleID), [id])
            XCTAssertTrue(result.outputActiveBundleIDs.contains(id))
        }
        let music = CallSnapshotInterpreter.snapshot([.init(pid: 2, bundleID: "com.google.Chrome", runningInput: false, runningOutput: true)], excludingPID: 1, now: Date())
        XCTAssertTrue(music.activeCalls.isEmpty, "Music cannot trigger a call start")
    }

    func testBrowserOutputPreservesMutedAssociationAndSilenceOnlyAsks() {
        let now = Date()
        let arc = ActiveCallApplication(bundleID: "company.thebrowser.Browser", displayName: "Arc", deviceUIDs: [], confidence: .browser)
        var engine = CallLifecycleEngine()
        let context = CallLifecycleContext(isRecording: true, smartMeetingsEnabled: true, hasMeaningfulContent: true, recordingDuration: 600, transcriptGap: 100, audioGap: 100, isInEndingGrace: false)
        engine.noteRecordingStarted(activeCalls: [arc], startedFrom: nil, at: now)
        _ = engine.ingest(snapshot: .init(capturedAt: now, activeCalls: [arc]), context: context)
        for second in [10.0, 30, 120] {
            XCTAssertTrue(engine.ingest(snapshot: .init(capturedAt: now.addingTimeInterval(second), activeCalls: [], outputActiveBundleIDs: [arc.bundleID]), context: context).isEmpty)
        }
        _ = engine.ingest(snapshot: .init(capturedAt: now.addingTimeInterval(121), activeCalls: []), context: context)
        XCTAssertEqual(engine.ingest(snapshot: .init(capturedAt: now.addingTimeInterval(130), activeCalls: []), context: context), [.beginEndingGrace(app: arc, askOnly: true)])
    }

    func testLateFirstCallNeverBecomesDestructiveHandoffAtAdoptionBoundaries() {
        let now = Date()
        let call = ActiveCallApplication(bundleID: "us.zoom.xos", displayName: "Zoom", deviceUIDs: [], confidence: .native)
        let context = CallLifecycleContext(isRecording: true, smartMeetingsEnabled: true, hasMeaningfulContent: true, recordingDuration: 600, transcriptGap: 0, audioGap: 0, isInEndingGrace: false)
        for delay in [30.0, 119, 121, 299, 301, 600] {
            var engine = CallLifecycleEngine()
            engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: now)
            _ = engine.ingest(snapshot: .init(capturedAt: now.addingTimeInterval(delay), activeCalls: [call]), context: context)
            let events = engine.ingest(snapshot: .init(capturedAt: now.addingTimeInterval(delay + 2), activeCalls: [call]), context: context)
            XCTAssertFalse(events.contains(.offerTransition(to: call)))
            XCTAssertTrue(events.contains(.adoptExpectedCall(call)) || events.contains(.offerAssociation(call)))
        }
    }

    func testCalendarLateEvidenceExpiryAndClockModeAreExplicit() {
        let start = Date()
        XCTAssertEqual(AppState.autoStartDecision(eventStart: start, hasConferenceLink: true, callDetectionAvailable: true, callActive: true, noShowAlreadyPrompted: true, now: start.addingTimeInterval(1200), eventEnd: start.addingTimeInterval(1800)), .startNow)
        XCTAssertEqual(AppState.autoStartDecision(eventStart: start, hasConferenceLink: true, callDetectionAvailable: true, callActive: true, noShowAlreadyPrompted: false, now: start.addingTimeInterval(1800), eventEnd: start.addingTimeInterval(1800)), .none)
        XCTAssertEqual(AppState.autoStartDecision(eventStart: start, hasConferenceLink: true, callDetectionAvailable: false, callActive: false, noShowAlreadyPrompted: false, now: start, requiresCallEvidence: false), .startNow)
        XCTAssertFalse(CallActivitySnapshot(capturedAt: start, activeCalls: []).isFresh(at: start.addingTimeInterval(6)))
    }
}

@MainActor
final class ManualCallAssociationTests: XCTestCase {
    private func event(_ id: String, start: TimeInterval = -30, end: TimeInterval = 1800) throws -> MinitiAPIService.CalendarEvent {
        let formatter = ISO8601DateFormatter()
        let json: [String: Any] = ["id": id, "title": "Calendar title",
            "start": formatter.string(from: Date().addingTimeInterval(start)),
            "end": formatter.string(from: Date().addingTimeInterval(end)),
            "isAllDay": false, "status": "confirmed", "attendees": []]
        return try JSONDecoder().decode(MinitiAPIService.CalendarEvent.self,
            from: JSONSerialization.data(withJSONObject: json))
    }

    func testCalendarAssociationKeepsManualRecordingAndPrivacyChoices() throws {
        let state = AppState()
        let container = try TestSupport.makeInMemoryContainer()
        state.modelContext = container.mainContext
        let meeting = Meeting(title: "My chosen title")
        meeting.notes = "My notes"; meeting.syncExcluded = true
        container.mainContext.insert(meeting)
        state.currentMeeting = meeting; state.isRecording = true
        state.smartMeetingsEnabled = true
        state.upcomingEvents = [try event("current")]
        state.checkSmartCalendarTransition()
        XCTAssertEqual(state.smartMeetingPrompt?.kind, .association)
        state.associateCurrentMeetingFromPrompt()
        XCTAssertTrue(state.currentMeeting === meeting)
        XCTAssertEqual(meeting.title, "My chosen title")
        XCTAssertEqual(meeting.notes, "My notes")
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertEqual(meeting.calendarEventId, "current")
        XCTAssertTrue(state.isRecording)
        XCTAssertNil(state.smartMeetingPrompt)
        XCTAssertEqual(state.fetchMeetings(.historyLoad)?.count, 1)
        state.isRecording = false
    }

    func testExplicitAssociationHonoursLocalTitleRulesUnlessUserOverrodeThem() throws {
        for explicitCloud in [false, true] {
            let state = AppState()
            let oldRules = state.cloudExclusionRules
            defer { state.cloudExclusionRules = oldRules }
            state.cloudExclusionRules = ["Calendar title"]
            let container = try TestSupport.makeInMemoryContainer()
            state.modelContext = container.mainContext
            let meeting = Meeting(title: "Manual title")
            container.mainContext.insert(meeting)
            state.currentMeeting = meeting; state.isRecording = true
            state.smartMeetingsEnabled = true
            if explicitCloud { state.activeMeetingCloudOverride = false }
            state.upcomingEvents = [try event("privacy-current")]
            state.checkSmartCalendarTransition()
            state.associateCurrentMeetingFromPrompt()
            XCTAssertEqual(meeting.syncExcluded, !explicitCloud)
            XCTAssertEqual(meeting.title, "Manual title")
            state.isRecording = false
        }
    }

    func testCalendarBoundaryNeverStartsAHandoffCountdownForContinuingRecording() throws {
        let state = AppState()
        let oldSmart = state.smartMeetingsEnabled, oldStart = state.autoStartFromCalendar, oldStop = state.autoStopFromCalendar, oldCalendar = state.googleCalendarEnabled
        defer { state.smartMeetingsEnabled = oldSmart; state.autoStartFromCalendar = oldStart; state.autoStopFromCalendar = oldStop; state.googleCalendarEnabled = oldCalendar; state.isRecording = false }
        state.googleCalendarEnabled = true; state.isGoogleCalendarConnected = true
        state.smartMeetingsEnabled = true
        state.autoStartFromCalendar = true
        state.autoStopFromCalendar = true
        let previous = try event("previous", start: -3600, end: -60)
        let next = try event("next", start: 10)
        let meeting = Meeting(title: "Continuing call")
        meeting.calendarEventId = previous.id
        state.currentMeeting = meeting
        state.selectedCalendarEvent = previous
        state.isRecording = true
        state.upcomingEvents = [next]
        // No transcript/audio activity has been observed: the old quiet/calendar
        // policy started a countdown here even though the user was still in a call.
        state.checkAutoStart()
        state.checkAutoStart()
        XCTAssertTrue(state.currentMeeting === meeting)
        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.smartMeetingPrompt?.kind, .calendar)
        XCTAssertEqual(state.smartMeetingPrompt?.eventID, next.id)
        XCTAssertNil(state.smartMeetingPrompt?.countdown)
        XCTAssertNil(state.pendingAutoStartEvent)
    }

    func testStoppedAdHocMeetingDoesNotConsumeTheNextCalendarEvent() throws {
        let state = AppState()
        let oldSmart = state.smartMeetingsEnabled, oldAuto = state.autoStartFromCalendar, oldCalendar = state.googleCalendarEnabled
        defer { state.smartMeetingsEnabled = oldSmart; state.autoStartFromCalendar = oldAuto; state.googleCalendarEnabled = oldCalendar }
        state.smartMeetingsEnabled = true
        state.autoStartFromCalendar = true
        state.googleCalendarEnabled = true; state.isGoogleCalendarConnected = true
        let stopped = Meeting(title: "Finished", endTime: Date())
        state.currentMeeting = stopped
        state.upcomingEvents = [try event("next", start: 10)]
        state.checkSmartCalendarTransition()
        XCTAssertNil(state.smartMeetingPrompt)
        state.checkAutoStart()
        XCTAssertEqual(state.pendingAutoStartEvent?.id, "next", "A saved result left open cannot block the next meeting")
        XCTAssertTrue(state.currentMeeting === stopped)
        state.cancelAutoStartCountdown()
        stopped.calendarEventId = "next"
        state.checkAutoStart()
        XCTAssertNil(state.pendingAutoStartEvent, "Stopping a calendar meeting must not automatically restart the same event")
    }

    func testStaleAssociationAndNotificationCannotMutateReplacementRecording() throws {
        let state = AppState()
        state.smartMeetingsEnabled = true
        state.currentMeeting = Meeting(title: "Old")
        state.isRecording = true
        state.upcomingEvents = [try event("current")]
        state.checkSmartCalendarTransition()
        let token = state.smartMeetingPromptToken
        let oldID = state.currentMeeting!.id.uuidString
        let replacement = Meeting(title: "New")
        state.currentMeeting = replacement
        state.associateCurrentMeetingFromPrompt()
        state.handleNotificationResponse(actionIdentifier: AppState.smartMeetingEndNowAction,
            categoryIdentifier: AppState.smartMeetingNotificationCategory + ".calendar",
            eventID: "current", promptToken: token, recordingID: oldID)
        XCTAssertTrue(state.currentMeeting === replacement)
        XCTAssertNil(replacement.calendarEventId)
        XCTAssertTrue(state.isRecording)
        state.isRecording = false
    }

    func testExpiredCalendarCannotSuggestAssociationAndStartingCannotBeReplaced() throws {
        let state = AppState()
        state.smartMeetingsEnabled = true
        let meeting = Meeting(title: "Starting")
        state.currentMeeting = meeting; state.isStartingMeeting = true
        state.upcomingEvents = [try event("expired", end: -1)]
        state.checkSmartCalendarTransition()
        XCTAssertNil(state.smartMeetingPrompt)
        XCTAssertFalse(state.startNewMeeting())
        XCTAssertTrue(state.currentMeeting === meeting)
        state.isStartingMeeting = false
    }
}
