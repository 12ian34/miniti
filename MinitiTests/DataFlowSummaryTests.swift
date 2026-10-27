import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// The Sending tab's model (U1, docs/account-sending-consent-ux-plan.md). Every test asserts
/// the group, the status word and the summary of the rows a setting affects, never row counts.
final class DataFlowSummaryTests: XCTestCase {
    private typealias Status = DataFlowSummary.Status

    private func row(_ summary: DataFlowSummary, _ id: String, file: StaticString = #filePath, line: UInt = #line) -> DataFlowSummary.Row {
        guard let found = summary.rows.first(where: { $0.id == id }) else {
            XCTFail("no row \(id)", file: file, line: line)
            return DataFlowSummary.Row(id: id, group: .accountAndConnections, title: "", status: .off, summary: "")
        }
        return found
    }

    private func shownIDs(_ summary: DataFlowSummary, in group: DataFlowSummary.Group) -> [String] {
        summary.groups.first { $0.group == group }?.rows.map(\.id) ?? []
    }

    private var macDefaults: DataFlowSummary.Inputs {
        var i = DataFlowSummary.Inputs()
        i.crmAvailable = true
        return i
    }

    /// Every configuration the table covers, for the sweeping assertions.
    private var allInputs: [DataFlowSummary.Inputs] {
        var list: [DataFlowSummary.Inputs] = []
        for mode in [AppMode.managed, .byok] {
            for sendingAllowed in [true, false] {
                for privateMode in [false, true] {
                    for onDevice in [false, true] {
                        for recording in [false, true] {
                            var i = macDefaults
                            i.appMode = mode
                            i.sendingAllowed = sendingAllowed
                            i.privateMode = privateMode
                            i.onDeviceTranscription = onDevice
                            i.onDeviceTranscriptionCloudFallback = onDevice
                            i.isRecording = recording
                            i.sessionTranscribesOnDevice = onDevice && recording
                            i.jevClassifier = true
                            i.playbookInsights = true
                            i.docsServerHost = "docs.example.com"
                            i.googleCalendarConnected = true
                            i.webhookHost = "hooks.example.com"
                            i.autoAttioSync = true
                            i.cloudPause = nil
                            list.append(i)
                            var bare = macDefaults
                            bare.appMode = mode
                            bare.sendingAllowed = sendingAllowed
                            bare.privateMode = privateMode
                            bare.shareDiagnostics = false
                            list.append(bare)
                        }
                    }
                }
            }
        }
        return list
    }

    // MARK: Groups and statuses

    func testManagedDefaultsPutEachRecipientInItsGroupWithItsStatus() {
        let s = DataFlowSummary.build(macDefaults)

        let deepgram = row(s, "deepgram")
        XCTAssertEqual(deepgram.group, .transcriptionAndAI)
        XCTAssertEqual(deepgram.status, .usedForRecordings)
        XCTAssertEqual(deepgram.status.text, "Used for recordings")
        XCTAssertEqual(deepgram.summary, "Audio, the meeting title and attendee names, for the transcript.")
        XCTAssertTrue(deepgram.details?.contains("straight from this device to Deepgram") == true)
        XCTAssertEqual(deepgram.configure?.target, "transcription.model")

        let openAI = row(s, "openai")
        XCTAssertEqual(openAI.title, "OpenAI, through miniti")
        XCTAssertEqual(openAI.status, .usedForRecordings)
        XCTAssertTrue(openAI.summary.hasPrefix("The transcript, your notes, the meeting title and attendee names, for summaries and action items, questions and speaker names"))
        XCTAssertTrue(openAI.details?.contains("through miniti's servers") == true)

        XCTAssertEqual(row(s, "account").status, .automatic)
        XCTAssertEqual(row(s, "account").group, .accountAndConnections)
        XCTAssertEqual(row(s, "account").summary, "Your device id, app version and minutes used.")
        XCTAssertEqual(row(s, "diagnostics").status, .automatic)
        XCTAssertEqual(row(s, "diagnostics").summary, "Errors and reconnects, never transcript or audio.")

        XCTAssertEqual(row(s, "typesafe").status, .off)
        XCTAssertEqual(row(s, "typesafe").summary, "Jev is off.")
        XCTAssertEqual(row(s, "docs").status, .notConnected)
        XCTAssertEqual(row(s, "docs").summary, "Playbook is off.")
        XCTAssertEqual(row(s, "cloud").status, .off)
        XCTAssertEqual(row(s, "cloud").group, .syncAndExports)
        XCTAssertEqual(row(s, "webhook").status, .notConnected)
        XCTAssertEqual(row(s, "calendar").status, .notConnected)
        XCTAssertEqual(row(s, "crm").status, .onRequest)
        XCTAssertEqual(row(s, "crm").group, .syncAndExports)

        XCTAssertEqual(shownIDs(s, in: .transcriptionAndAI), ["deepgram", "openai"], "off optional recipients leave the group; Deepgram and OpenAI stay")
        XCTAssertEqual(shownIDs(s, in: .syncAndExports), ["crm"])
        XCTAssertEqual(shownIDs(s, in: .accountAndConnections), ["account", "diagnostics"])
        XCTAssertEqual(s.notInUse.map(\.id), ["typesafe", "docs", "cloud", "webhook", "calendar"])
        XCTAssertEqual(s.headline, DataFlowSummary.idleHeadline)
    }

    func testBYOKNamesTheKeyAndKeepsOnlyTheVersionCheck() {
        var i = macDefaults
        i.appMode = .byok
        let s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").title, "Deepgram, with your key")
        XCTAssertTrue(row(s, "deepgram").details?.contains("with your own key") == true)
        XCTAssertEqual(row(s, "openai").title, "OpenAI, with your key")
        XCTAssertEqual(row(s, "account").status, .automatic, "the launch version check is automatic, not on request")
        XCTAssertEqual(row(s, "account").summary, "A version check at launch.")
        XCTAssertNil(s.rows.first { $0.id == "typesafe" }, "Jev is managed only")
        XCTAssertNil(s.rows.first { $0.id == "cloud" }, "cloud needs the managed plan")
        XCTAssertNil(s.rows.first { $0.id == "diagnostics" })
    }

    func testWithdrawnPermissionTurnsBothProvidersOffAndNamesTheReason() {
        var i = macDefaults
        i.sendingAllowed = false
        i.jevClassifier = true
        i.playbookInsights = true
        i.docsServerHost = "docs.example.com"
        let s = DataFlowSummary.build(i)
        for id in ["deepgram", "openai", "typesafe", "docs"] {
            XCTAssertEqual(row(s, id).status, .off, id)
            XCTAssertEqual(row(s, id).summary, "Permission for Deepgram and OpenAI was not given.", id)
            XCTAssertEqual(row(s, id).configure?.target, "privacy.thirdPartyAI", "\(id): the permission is the one thing to change")
        }
        XCTAssertEqual(shownIDs(s, in: .transcriptionAndAI), ["deepgram", "openai"], "both stay visible when off")
        XCTAssertEqual(row(s, "account").status, .automatic, "the account traffic does not depend on the permission")
    }

    func testPrivateModePausesCloudAIButNotConfiguredExports() {
        var i = macDefaults
        i.privateMode = true
        i.webhookHost = "hooks.example.com"
        i.autoAttioSync = true
        i.cloudPause = "Private mode"
        let s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .paused("private mode"))
        XCTAssertEqual(row(s, "deepgram").status.text, "Paused: private mode")
        XCTAssertEqual(row(s, "deepgram").summary, "Private mode keeps new recordings off cloud AI.")
        XCTAssertEqual(row(s, "deepgram").configure?.target, "privacy.privateMode")
        XCTAssertEqual(row(s, "openai").status, .paused("private mode"))
        XCTAssertEqual(row(s, "webhook").status, .automaticExport, "a configured webhook still runs in private mode")
        XCTAssertTrue(row(s, "webhook").details?.contains("private mode too") == true)
        XCTAssertEqual(row(s, "crm").status, .automaticExport)
        XCTAssertEqual(row(s, "cloud").status, .paused("private mode"))
        XCTAssertTrue(row(s, "cloud").details?.contains("stays off unless you put it on") == true, "a private-mode meeting can still be put on the cloud by hand")
        XCTAssertEqual(shownIDs(s, in: .syncAndExports), ["cloud", "webhook", "crm"])
    }

    func testOnDeviceTranscriptionStopsAudioUnlessFallbackIsAllowed() {
        var i = macDefaults
        i.onDeviceTranscription = true
        var s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .off)
        XCTAssertEqual(row(s, "deepgram").summary, "Transcription runs on this Mac; no audio is sent.")
        XCTAssertEqual(row(s, "deepgram").configure?.target, "transcription.model")
        XCTAssertEqual(shownIDs(s, in: .transcriptionAndAI).first, "deepgram", "Deepgram stays in its group even when off")
        XCTAssertEqual(row(s, "openai").status, .usedForRecordings, "the transcript still goes to OpenAI")

        i.onDeviceTranscriptionCloudFallback = true
        s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .usedForRecordings)
        XCTAssertTrue(row(s, "deepgram").summary.hasPrefix("Audio only for a meeting whose language model is not ready on this Mac"))
        XCTAssertEqual(row(s, "deepgram").configure?.target, "transcription.fallback")
    }

    func testCloudRowFollowsThePauseReason() {
        var i = macDefaults
        i.cloudPause = nil
        XCTAssertEqual(row(DataFlowSummary.build(i), "cloud").status, .automaticExport)
        XCTAssertEqual(row(DataFlowSummary.build(i), "cloud").summary, "Finished meetings, so your other devices see them.")
        i.cloudPause = "Off"
        XCTAssertEqual(row(DataFlowSummary.build(i), "cloud").status, .off)
        XCTAssertTrue(DataFlowSummary.build(i).notInUse.contains { $0.id == "cloud" })
        i.cloudPause = "Pro needed"
        XCTAssertEqual(row(DataFlowSummary.build(i), "cloud").status, .paused("pro needed"))
        XCTAssertEqual(row(DataFlowSummary.build(i), "cloud").status.text, "Paused: pro needed")
    }

    func testCalendarIsAutomaticWhileIdleAndDiagnosticsCanBeOff() {
        var i = macDefaults
        i.googleCalendarConnected = true
        i.shareDiagnostics = false
        let s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "calendar").status, .automatic, "events are read whenever connected, not only during recordings")
        XCTAssertEqual(row(s, "calendar").summary, "Upcoming events are read whenever it is connected; nothing is written.")
        XCTAssertEqual(row(s, "calendar").group, .accountAndConnections)
        XCTAssertEqual(row(s, "diagnostics").status, .off)
        XCTAssertEqual(row(s, "diagnostics").summary, "Share Diagnostics is off.")
        XCTAssertTrue(s.notInUse.contains { $0.id == "diagnostics" })
    }

    func testPlaybookTiersAndMissingServer() {
        var i = macDefaults
        i.playbookInsights = true
        i.docsServerHost = "docs.example.com"
        i.playbookLookupIsAutomatic = true
        XCTAssertEqual(row(DataFlowSummary.build(i), "docs").status, .usedForRecordings)
        XCTAssertEqual(row(DataFlowSummary.build(i), "docs").title, "docs.example.com")
        i.playbookLookupIsAutomatic = false
        XCTAssertEqual(row(DataFlowSummary.build(i), "docs").status, .onRequest, "managed free looks up on request")
        XCTAssertTrue(row(DataFlowSummary.build(i), "docs").details?.contains("Each lookup is one you start") == true)
        i.docsServerHost = nil
        XCTAssertEqual(row(DataFlowSummary.build(i), "docs").status, .notConnected)
        XCTAssertEqual(row(DataFlowSummary.build(i), "docs").summary, "No docs server is set.")
    }

    func testJevNeedsManagedAndCloudAI() {
        var i = macDefaults
        i.jevClassifier = true
        XCTAssertEqual(row(DataFlowSummary.build(i), "typesafe").status, .usedForRecordings)
        XCTAssertEqual(row(DataFlowSummary.build(i), "typesafe").summary, "The last few minutes of transcript, for the sales nudge and speaker names.")
        i.privateMode = true
        XCTAssertEqual(row(DataFlowSummary.build(i), "typesafe").status, .paused("private mode"))
    }

    // MARK: Headline

    func testHeadlineHasALatchedEngineHalfAndALiveAIHalf() {
        var i = macDefaults
        i.isRecording = true
        i.sessionTranscribesOnDevice = false
        XCTAssertEqual(DataFlowSummary.build(i).headline, "This recording: audio to Deepgram, transcript to OpenAI.")

        // Private mode switched on during a Deepgram session: the audio half stays, the AI half pauses,
        // and the Deepgram row describes the active route with the preference on its own line (F5).
        i.privateMode = true
        let paused = DataFlowSummary.build(i)
        XCTAssertEqual(paused.headline, "This recording: audio to Deepgram. Cloud AI is paused, so no insights are requested.")
        XCTAssertEqual(row(paused, "deepgram").status, .usedForRecordings, "the running session still sends audio")
        XCTAssertEqual(row(paused, "deepgram").summary, "Audio from this recording, the meeting title and attendee names, for the transcript.")
        XCTAssertEqual(row(paused, "deepgram").nextRecording, "Next recording: paused, private mode.")
        XCTAssertEqual(row(paused, "openai").status, .paused("private mode"), "the insight loop reads the policy live")

        // Switched back: the AI half resumes, the engine was never in question.
        i.privateMode = false
        XCTAssertEqual(DataFlowSummary.build(i).headline, "This recording: audio to Deepgram, transcript to OpenAI.")

        i.sessionTranscribesOnDevice = true
        XCTAssertEqual(DataFlowSummary.build(i).headline, "This recording: transcribing on this Mac, transcript to OpenAI.")
        i.sendingAllowed = false
        XCTAssertEqual(DataFlowSummary.build(i).headline, "This recording: transcribing on this Mac, no cloud AI. Configured exports still run when it ends.")

        i.isRecording = false
        XCTAssertEqual(DataFlowSummary.build(i).headline, DataFlowSummary.idleHeadline)
    }

    func testWhileRecordingTheDeepgramRowFollowsTheSessionAndNamesTheNextRecording() {
        var i = macDefaults
        i.isRecording = true

        // Cloud session, preference flipped to on-device without fallback mid-recording.
        i.sessionTranscribesOnDevice = false
        i.onDeviceTranscription = true
        var s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .usedForRecordings)
        XCTAssertEqual(row(s, "deepgram").nextRecording, "Next recording: transcription on this Mac, no audio sent.")
        XCTAssertEqual(s.headline, "This recording: audio to Deepgram, transcript to OpenAI.")

        // On-device session, preference flipped back to Deepgram mid-recording.
        i.sessionTranscribesOnDevice = true
        i.onDeviceTranscription = false
        s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .off)
        XCTAssertEqual(row(s, "deepgram").summary, "This recording is transcribed on this Mac; no audio is sent.")
        XCTAssertEqual(row(s, "deepgram").nextRecording, "Next recording: audio to Deepgram.")
        XCTAssertEqual(s.headline, "This recording: transcribing on this Mac, transcript to OpenAI.")

        // A session that fell back to Deepgram under an on-device preference with fallback allowed.
        i.sessionTranscribesOnDevice = false
        i.onDeviceTranscription = true
        i.onDeviceTranscriptionCloudFallback = true
        s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .usedForRecordings, "the fallback is the active route")
        XCTAssertEqual(row(s, "deepgram").nextRecording, "Next recording: transcription on this Mac, audio to Deepgram only when the model is not ready.")

        // Preference and session agree: no next-recording line.
        i.onDeviceTranscription = false
        i.onDeviceTranscriptionCloudFallback = false
        XCTAssertNil(row(DataFlowSummary.build(i), "deepgram").nextRecording)
        i.sessionTranscribesOnDevice = true
        i.onDeviceTranscription = true
        XCTAssertNil(row(DataFlowSummary.build(i), "deepgram").nextRecording)

        // Idle rows keep the current-settings meaning.
        i.isRecording = false
        i.sessionTranscribesOnDevice = false
        XCTAssertEqual(row(DataFlowSummary.build(i), "deepgram").status, .off)
        XCTAssertNil(row(DataFlowSummary.build(i), "deepgram").nextRecording)
    }

    func testIdleProcessingAndQueuedExportsDoNotChangeTheRows() {
        var i = macDefaults
        i.isRecording = false
        i.webhookHost = "hooks.example.com"
        let s = DataFlowSummary.build(i)
        XCTAssertEqual(row(s, "deepgram").status, .usedForRecordings, "a recorded file transcribed while idle takes the same route")
        XCTAssertEqual(row(s, "openai").status, .usedForRecordings)
        XCTAssertTrue(row(s, "openai").details?.contains("recording or not") == true)
        XCTAssertEqual(row(s, "webhook").status, .automaticExport, "queued deliveries are still automatic exports")
        XCTAssertTrue(row(s, "webhook").details?.contains("retried") == true)
        #if os(iOS)
        XCTAssertTrue(s.footer.contains("Watch recordings are files on this device until they are transcribed."))
        XCTAssertTrue(row(s, "deepgram").details?.contains("watch") == true)
        #else
        XCTAssertFalse(s.footer.contains("Watch"))
        #endif
        XCTAssertTrue(s.footer.hasSuffix("Exports and cloud copies are the rows above."))
    }

    // MARK: Invariants across every configuration

    func testRowsKeepTheirOrderWhateverTheState() {
        let order = DataFlowSummary.build(macDefaults).rows.map(\.id)
        for i in allInputs where i.appMode == .managed {
            XCTAssertEqual(DataFlowSummary.build(i).rows.map(\.id), order, "rows must not reorder as traffic starts or stops")
        }
    }

    func testEveryRowHasOneConfigureTargetThatExistsOnBothPlatforms() {
        let macIDs = Set(SettingsSearchCatalog.availableItems(on: .macOS, appMode: .managed).map(\.id))
            .union(SettingsSearchCatalog.availableItems(on: .macOS, appMode: .byok).map(\.id))
        let iosIDs = Set(SettingsSearchCatalog.availableItems(on: .iOS, appMode: .managed).map(\.id))
            .union(SettingsSearchCatalog.availableItems(on: .iOS, appMode: .byok).map(\.id))
        for i in allInputs {
            for row in DataFlowSummary.build(i).rows {
                guard let jump = row.configure else {
                    XCTFail("\(row.id) has no Configure")
                    continue
                }
                XCTAssertTrue(macIDs.contains(jump.target), "\(row.id): \(jump.target) is not a Mac settings row")
                // CRM export is Mac only, and private mode (Apple silicon Macs) never gates an iOS row.
                if row.id != "crm", jump.target != "privacy.privateMode" {
                    XCTAssertTrue(iosIDs.contains(jump.target), "\(row.id): \(jump.target) has no iOS destination")
                }
            }
        }
        XCTAssertTrue(SettingsGroup.setup.destinations.contains(.sending))
        XCTAssertEqual(SettingsDestination.fromLegacyID("dataFlow"), .sending)
    }

    func testNoSentenceMakesAClaimTheCodeDoesNotKeep() {
        let banned = ["nothing leaves", "nothing about your meetings", "nothing is stored", "never stored", "stays on this mac", "stays on this device", "—"]
        for i in allInputs {
            let s = DataFlowSummary.build(i)
            var texts = [s.headline, s.footer]
            for row in s.rows {
                texts.append(row.summary)
                if let d = row.details { texts.append(d) }
                if let n = row.nextRecording { texts.append(n) }
            }
            for text in texts {
                let lower = text.lowercased()
                for phrase in banned {
                    XCTAssertFalse(lower.contains(phrase), "\"\(phrase)\" in: \(text)")
                }
            }
        }
    }

    func testNotInUseHoldsOnlyOptionalRecipientsWithAReason() {
        for i in allInputs {
            let s = DataFlowSummary.build(i)
            for row in s.notInUse {
                XCTAssertFalse(row.isInUse)
                XCTAssertFalse(["deepgram", "openai"].contains(row.id), "\(row.id) is always shown in its group")
                XCTAssertFalse(row.summary.isEmpty, "\(row.id) needs a reason")
            }
            for entry in s.groups {
                for row in entry.rows {
                    XCTAssertTrue(row.isInUse || row.alwaysVisible, "\(row.id) is shown in \(entry.group) without being in use")
                }
            }
        }
    }
}
