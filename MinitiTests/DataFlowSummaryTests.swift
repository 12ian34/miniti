import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class DataFlowSummaryTests: XCTestCase {
    private func row(_ summary: DataFlowSummary, _ prefix: String) -> DataFlowSummary.Row? {
        summary.rows.first { $0.destination.hasPrefix(prefix) }
    }

    func testManagedDefaultsSendAudioToDeepgramAndTextToOpenAI() throws {
        let s = DataFlowSummary.build(.init())
        let deepgram = try XCTUnwrap(row(s, "Deepgram"))
        XCTAssertTrue(deepgram.sends)
        XCTAssertTrue(deepgram.detail.contains("Live audio"))
        XCTAssertTrue(deepgram.detail.contains("tells speakers apart"))
        let openAI = try XCTUnwrap(row(s, "OpenAI, through miniti"))
        XCTAssertTrue(openAI.sends)
        XCTAssertTrue(openAI.detail.contains("summaries and action items, questions, speaker names and catch-up"))
        XCTAssertFalse(openAI.detail.contains("Sales"))
        let jev = try XCTUnwrap(row(s, "TypeSafe"))
        XCTAssertFalse(jev.sends)
        let miniti = try XCTUnwrap(row(s, "miniti"))
        XCTAssertTrue(miniti.detail.contains("minutes used"))
        XCTAssertTrue(miniti.detail.contains("diagnostics"))
        XCTAssertTrue(miniti.detail.contains("Cloud: off"))
        XCTAssertNil(s.liveNote)
        XCTAssertNil(row(s, "Google"))
        XCTAssertNil(row(s, "Attio"))
    }

    func testOnDeviceTranscriptionStopsAudioButNotTranscript() throws {
        var inputs = DataFlowSummary.Inputs()
        inputs.onDeviceTranscription = true
        inputs.templateInsights = true
        let s = DataFlowSummary.build(inputs)
        let deepgram = try XCTUnwrap(row(s, "Deepgram"))
        XCTAssertFalse(deepgram.sends)
        XCTAssertTrue(deepgram.detail.contains("runs on this Mac"))
        let openAI = try XCTUnwrap(row(s, "OpenAI"))
        XCTAssertTrue(openAI.sends, "insights still go out when only transcription is local")
        XCTAssertTrue(openAI.detail.contains("templates"))

        inputs.onDeviceTranscriptionCloudFallback = true
        let fallback = try XCTUnwrap(row(DataFlowSummary.build(inputs), "Deepgram"))
        XCTAssertTrue(fallback.sends)
        XCTAssertTrue(fallback.detail.contains("only for a meeting whose language model is not ready"))
    }

    func testPrivateModeSendsNothingAboutTheMeeting() throws {
        var inputs = DataFlowSummary.Inputs()
        inputs.privateMode = true
        inputs.jevClassifier = true
        inputs.playbookInsights = true
        inputs.docsServerHost = "docs.example.com"
        inputs.cloudPause = "Paused while private mode is on"
        let s = DataFlowSummary.build(inputs)
        for destination in ["Deepgram", "OpenAI", "TypeSafe", "docs.example.com"] {
            let r = try XCTUnwrap(row(s, destination), destination)
            XCTAssertFalse(r.sends, destination)
            XCTAssertTrue(r.detail.hasPrefix("Nothing."), destination)
            XCTAssertTrue(r.detail.contains("Private mode"), destination)
        }
        let miniti = try XCTUnwrap(row(s, "miniti"))
        XCTAssertFalse(miniti.detail.contains("your meetings"))
    }

    func testWithdrawnPermissionNamesTheReason() throws {
        var inputs = DataFlowSummary.Inputs()
        inputs.sendingAllowed = false
        let s = DataFlowSummary.build(inputs)
        XCTAssertFalse(try XCTUnwrap(row(s, "Deepgram")).sends)
        XCTAssertTrue(try XCTUnwrap(row(s, "OpenAI")).detail.contains("Permission"))
    }

    func testOptionalRecipientsAppearOnlyWhenConfigured() throws {
        var inputs = DataFlowSummary.Inputs()
        inputs.jevClassifier = true
        inputs.playbookInsights = true
        inputs.docsServerHost = "docs.example.com"
        inputs.cloudPause = nil
        inputs.googleCalendarConnected = true
        inputs.webhookHost = "hooks.example.com"
        inputs.crmAvailable = true
        inputs.autoAttioSync = true
        inputs.voicePrints = true
        let s = DataFlowSummary.build(inputs)
        XCTAssertTrue(try XCTUnwrap(row(s, "TypeSafe")).sends)
        XCTAssertTrue(try XCTUnwrap(row(s, "docs.example.com")).detail.contains("through miniti"))
        XCTAssertTrue(try XCTUnwrap(row(s, "miniti")).detail.contains("your meetings"))
        XCTAssertTrue(try XCTUnwrap(row(s, "Google")).detail.contains("Nothing is written"))
        XCTAssertTrue(try XCTUnwrap(row(s, "hooks.example.com")).detail.contains("including the transcript"))
        let crm = try XCTUnwrap(row(s, "Attio"))
        XCTAssertTrue(crm.sends)
        XCTAssertTrue(crm.detail.contains("to Attio"))
        XCTAssertTrue(s.staysHere.contains("voice fingerprints"))
    }

    func testBYOKNamesTheKeyAndSkipsManagedOnlyRows() throws {
        var inputs = DataFlowSummary.Inputs()
        inputs.appMode = .byok
        inputs.jevClassifier = true
        let s = DataFlowSummary.build(inputs)
        XCTAssertNotNil(row(s, "Deepgram, with your key"))
        XCTAssertNotNil(row(s, "OpenAI, with your key"))
        XCTAssertNil(row(s, "TypeSafe"))
        XCTAssertTrue(try XCTUnwrap(row(s, "miniti")).detail.contains("version check"))
    }

    func testLiveNoteFollowsTheSessionEngine() {
        var inputs = DataFlowSummary.Inputs()
        inputs.isRecording = true
        XCTAssertEqual(DataFlowSummary.build(inputs).liveNote, "Recording now: audio is going to Deepgram and the transcript to OpenAI.")
        inputs.sessionTranscribesOnDevice = true
        XCTAssertEqual(DataFlowSummary.build(inputs).liveNote, "Recording now: transcribing on this Mac. Only the transcript leaves, to OpenAI for insights.")
        inputs.privateMode = true
        XCTAssertEqual(DataFlowSummary.build(inputs).liveNote, "Recording now: nothing from this meeting leaves this Mac.")
    }
}

extension DataFlowSummaryTests {
    func testEveryJumpPointsAtACatalogRowAndCoversTheGates() {
        let ids = Set(SettingsSearchCatalog.items.map(\.id))
        var inputs = DataFlowSummary.Inputs()
        inputs.onDeviceTranscription = true
        inputs.jevClassifier = true
        inputs.playbookInsights = true
        inputs.docsServerHost = "docs.example.com"
        inputs.googleCalendarConnected = true
        inputs.webhookHost = "hooks.example.com"
        inputs.crmAvailable = true
        for mode in [AppMode.managed, .byok] {
            inputs.appMode = mode
            for sendingAllowed in [true, false] {
                inputs.sendingAllowed = sendingAllowed
                let s = DataFlowSummary.build(inputs)
                for row in s.rows {
                    XCTAssertFalse(row.jumps.isEmpty, "\(row.destination) has no way to change it")
                    for jump in row.jumps {
                        XCTAssertTrue(ids.contains(jump.target), "\(row.destination): \(jump.target) is not a settings row")
                    }
                }
                let deepgram = s.rows.first { $0.destination.hasPrefix("Deepgram") }!
                XCTAssertTrue(deepgram.jumps.contains { $0.target == "transcription.fallback" }, "on-device shows the fallback switch")
                XCTAssertEqual(deepgram.jumps.first?.target == "privacy.thirdPartyAI", !sendingAllowed, "withdrawn permission is the first thing to change")
            }
        }
        XCTAssertTrue(SettingsGroup.setup.destinations.contains(.sending))
        XCTAssertEqual(SettingsDestination.fromLegacyID("dataFlow"), .sending)
    }
}
