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
        // Safari captures media in the WebKit GPU process — explicit alias.
        XCTAssertEqual(
            CallApplicationDirectory.normalize(bundleID: "com.apple.WebKit.GPU")?.canonicalBundleID,
            "com.apple.Safari"
        )
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
            [.offerTransition(to: facetime)]
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
        XCTAssertTrue(events.contains(.offerTransition(to: zoom)))
        XCTAssertTrue(events.contains(.offerTransition(to: slack)))
        XCTAssertNil(engine.associatedApp)
    }

    func testInferredWindowExpiresBackToTransitionCandidates() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, at: base)
        let zoom = app()
        let recording = context(isRecording: true)
        let late = CallLifecycleEngine.inferredCallWindow + 1
        _ = engine.ingest(snapshot: snapshot(at: late, calls: [zoom]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: late + 2, calls: [zoom]), context: recording),
            [.offerTransition(to: zoom)]
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
            [.beginEndingGrace(app: chrome, askOnly: false)]
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

    func testExpectedCallWindowExpiresBackToTransitionCandidates() {
        var engine = CallLifecycleEngine()
        engine.noteRecordingStarted(activeCalls: [], startedFrom: nil, expectsCall: true, at: base)
        let facetime = app("com.apple.FaceTime", name: "FaceTime")
        let recording = context(isRecording: true)
        let late = CallLifecycleEngine.expectedCallWindow + 1

        _ = engine.ingest(snapshot: snapshot(at: late, calls: [facetime]), context: recording)
        XCTAssertEqual(
            engine.ingest(snapshot: snapshot(at: late + 2, calls: [facetime]), context: recording),
            [.offerTransition(to: facetime)]
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
            [.beginEndingGrace(app: chrome, askOnly: false)]
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

        state.presentRecordingNudge(first, duration: 0.02)
        state.presentRecordingNudge(replacement, duration: 1)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(state.recordingNudge, replacement)
        state.dismissRecordingNudge()
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
    func testPresentMainWindowDeminiaturizesOnlyWhenNeeded() {
        XCTAssertTrue(AppDelegate.shouldDeminiaturizeMainWindow(true))
        XCTAssertFalse(AppDelegate.shouldDeminiaturizeMainWindow(false))
    }
    #endif
}
