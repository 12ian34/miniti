import Foundation
#if os(iOS)
import UIKit
#endif

/// What leaves this device and where it goes, worked out from the current settings so that
/// Settings, Privacy can show it as one list instead of a sentence per feature. Pure value
/// type: `AppState` fills in `Inputs`, the view renders `rows`, and the tests cover the rules
/// without an `AppState`. Every row names one recipient and says exactly what it receives, or
/// "Nothing" and why.
struct DataFlowSummary: Equatable {
    struct Inputs: Equatable {
        var deviceName = "this Mac"
        var appMode: AppMode = .managed
        /// `AppState.hasAcceptedTerms`: permission for Deepgram and OpenAI.
        var sendingAllowed = true
        var privateMode = false
        var onDeviceTranscription = false
        var onDeviceTranscriptionCloudFallback = false
        var onDeviceSpeakers = false
        var salesInsights = false
        var templateInsights = false
        var playbookInsights = false
        var docsServerHost: String?
        var autoInferSpeakerNames = true
        var jevClassifier = false
        /// `CloudSyncPause.label`, or nil while meetings are syncing.
        var cloudPause: String? = "Off"
        var googleCalendarConnected = false
        var webhookHost: String?
        var crmAvailable = false
        var autoAttioSync = false
        var autoTwentySync = false
        var shareDiagnostics = true
        var voicePrints = false
        var isRecording = false
        var sessionTranscribesOnDevice = false
    }

    /// A way to the setting that decides a row: `target` is a `SettingsSearchCatalog` id.
    struct Jump: Equatable, Identifiable {
        var id: String { target }
        let label: String
        let target: String
    }

    struct Row: Equatable, Identifiable {
        var id: String { destination }
        /// Who receives it.
        let destination: String
        /// What they receive, or "Nothing" and why.
        let detail: String
        /// False when the row currently sends nothing.
        let sends: Bool
        /// Where to change it, in the order shown.
        var jumps: [Jump] = []
    }

    let rows: [Row]
    /// What stays here, for the footer.
    let staysHere: String
    /// One line about the recording in progress, nil when not recording.
    let liveNote: String?

    static func build(_ i: Inputs) -> DataFlowSummary {
        let managed = i.appMode == .managed
        let cloudAI = i.sendingAllowed && !i.privateMode
        let nothingReason: String? = {
            if !i.sendingAllowed { return "Nothing. Permission for Deepgram and OpenAI was not given." }
            if i.privateMode { return "Nothing. Private mode keeps the meeting on \(i.deviceName)." }
            return nil
        }()

        var rows: [Row] = []

        // Deepgram: audio, straight from the app (miniti only hands out the token in managed mode).
        let gate: [Jump] = !i.sendingAllowed
            ? [Jump(label: "Permission", target: "privacy.thirdPartyAI")]
            : (i.privateMode ? [Jump(label: "Private mode", target: "privacy.privateMode")] : [])
        let deepgram = managed ? "Deepgram" : "Deepgram, with your key"
        var deepgramJumps = [Jump(label: "Transcription", target: "transcription.model"), Jump(label: "Speakers", target: "transcription.speakers")]
        if i.onDeviceTranscription { deepgramJumps.append(Jump(label: "Fallback", target: "transcription.fallback")) }
        if let reason = nothingReason {
            rows.append(Row(destination: deepgram, detail: reason, sends: false, jumps: gate + deepgramJumps))
        } else if i.onDeviceTranscription && !i.onDeviceTranscriptionCloudFallback {
            rows.append(Row(destination: deepgram, detail: "Nothing. Transcription runs on \(i.deviceName).", sends: false, jumps: deepgramJumps))
        } else {
            let names = "the meeting title and attendee names so it spells them right"
            let speakers = i.onDeviceSpeakers ? "" : " It also tells speakers apart."
            let detail = i.onDeviceTranscription
                ? "Live audio only for a meeting whose language model is not ready on \(i.deviceName), with \(names).\(speakers) Nothing is stored."
                : "Live audio while you record, with \(names).\(speakers) Nothing is stored."
            rows.append(Row(destination: deepgram, detail: detail, sends: true, jumps: deepgramJumps))
        }

        // OpenAI: text, through the miniti backend in managed mode.
        let openAI = managed ? "OpenAI, through miniti" : "OpenAI, with your key"
        let openAIJumps = [
            Jump(label: "Permission", target: "privacy.thirdPartyAI"),
            Jump(label: "Speaker names", target: "ai.speakerNames"),
            Jump(label: "Sales", target: "notifications.salesDetection"),
            Jump(label: "Templates", target: "templates.list"),
            Jump(label: "Playbook", target: "playbook.server"),
        ]
        if let reason = nothingReason {
            rows.append(Row(destination: openAI, detail: reason, sends: false, jumps: gate + Array(openAIJumps.dropFirst())))
        } else {
            var features = ["summaries and action items", "questions"]
            if i.autoInferSpeakerNames { features.append("speaker names") }
            if i.salesInsights { features.append("Sales") }
            if i.templateInsights { features.append("templates") }
            if i.playbookInsights { features.append("Playbook") }
            features.append("catch-up and investigations when you ask")
            let detail = "The transcript, your notes, the meeting title and attendee names, for \(joined(features)). Nothing is stored."
            rows.append(Row(destination: openAI, detail: detail, sends: true, jumps: openAIJumps))
        }

        // TypeSafe: the Jev classifier, managed and opt-in.
        if managed {
            if cloudAI && i.jevClassifier {
                rows.append(Row(destination: "TypeSafe (Jev)", detail: "The last few minutes of transcript during a meeting, for the sales nudge and speaker naming.", sends: true, jumps: [Jump(label: "Jev", target: "ai.speakerNames")]))
            } else {
                rows.append(Row(destination: "TypeSafe (Jev)", detail: nothingReason ?? "Nothing. Jev is off.", sends: false, jumps: gate + [Jump(label: "Jev", target: "ai.speakerNames")]))
            }
        }

        // Your docs server: Playbook searches.
        if i.playbookInsights, let host = i.docsServerHost {
            if cloudAI {
                rows.append(Row(destination: host, detail: "Short searches drawn from the transcript\(managed ? ", through miniti" : ""), for Playbook. The transcript itself is not sent there.", sends: true, jumps: [Jump(label: "Playbook", target: "playbook.server")]))
            } else {
                rows.append(Row(destination: host, detail: nothingReason ?? "Nothing.", sends: false, jumps: gate + [Jump(label: "Playbook", target: "playbook.server")]))
            }
        }

        // miniti itself.
        if managed {
            var parts = ["Your device id, app version and minutes used"]
            if i.cloudPause == nil { parts.append("your meetings, so your other devices see them") }
            if i.shareDiagnostics { parts.append("reliability diagnostics (errors and reconnects, never transcript or audio)") }
            var detail = joined(parts) + "."
            if let pause = i.cloudPause { detail += " Cloud: \(pause.lowercased())." }
            rows.append(Row(destination: "miniti (api.miniti.app)", detail: detail, sends: true, jumps: [
                Jump(label: "Cloud", target: "cloud.sync"),
                Jump(label: "Diagnostics", target: "privacy.diagnostics"),
                Jump(label: "Mode", target: "account.apiMode"),
            ]))
        } else {
            rows.append(Row(destination: "miniti (api.miniti.app)", detail: "A version check at launch. Nothing about your meetings.", sends: true, jumps: [Jump(label: "Mode", target: "account.apiMode")]))
        }

        // Google Calendar, read through miniti.
        if i.googleCalendarConnected {
            rows.append(Row(destination: "Google Calendar", detail: "Your upcoming events are read through miniti so meetings can start on time. Nothing is written to your calendar.", sends: true, jumps: [Jump(label: "Calendar", target: "integrations.googleCalendar")]))
        }

        // CRM export.
        if i.crmAvailable {
            let auto = [i.autoAttioSync ? "Attio" : nil, i.autoTwentySync ? "Twenty" : nil].compactMap { $0 }
            let detail = auto.isEmpty
                ? "A meeting's title, summary, notes and action items, only when you export it. Never the transcript."
                : "Each meeting's title, summary, notes and action items after it ends, to \(joined(auto)). Never the transcript."
            rows.append(Row(destination: "Attio or Twenty", detail: detail, sends: !auto.isEmpty, jumps: [Jump(label: "Attio", target: "integrations.attio"), Jump(label: "Twenty", target: "integrations.twenty")]))
        }

        // Webhook.
        if let host = i.webhookHost {
            rows.append(Row(destination: host, detail: "Each saved meeting as JSON, including the transcript, posted to your webhook.", sends: true, jumps: [Jump(label: "Webhook", target: "integrations.webhook")]))
        }

        var local = ["your meeting history", "search", "export", "coaching"]
        if i.voicePrints { local.append("voice fingerprints") }
        let staysHere = "Stays on \(i.deviceName): \(joined(local))."

        let liveNote: String? = {
            guard i.isRecording else { return nil }
            if i.privateMode { return "Recording now: nothing from this meeting leaves \(i.deviceName)." }
            if i.sessionTranscribesOnDevice {
                return cloudAI
                    ? "Recording now: transcribing on \(i.deviceName). Only the transcript leaves, to OpenAI for insights."
                    : "Recording now: transcribing on \(i.deviceName)."
            }
            return "Recording now: audio is going to Deepgram and the transcript to OpenAI."
        }()

        return DataFlowSummary(rows: rows, staysHere: staysHere, liveNote: liveNote)
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}

extension AppState {
    /// Open the Settings tab that owns a `SettingsSearchCatalog` row and scroll to it, the way a
    /// search hit does. Unknown ids do nothing.
    func jumpToSetting(_ id: String) {
        guard let item = SettingsSearchCatalog.items.first(where: { $0.id == id }) else { return }
        selectedSettingsTab = item.destination.rawValue
        pendingSettingsSearchTarget = nil
        DispatchQueue.main.async { [weak self] in
            self?.pendingSettingsSearchTarget = id
        }
    }

    /// The current settings as `DataFlowSummary` inputs. Read-only; nothing here touches the network.
    var dataFlowInputs: DataFlowSummary.Inputs {
        var inputs = DataFlowSummary.Inputs()
        #if os(iOS)
        inputs.deviceName = UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
        inputs.crmAvailable = false
        #else
        inputs.deviceName = "this Mac"
        inputs.crmAvailable = true
        #endif
        inputs.appMode = appMode
        inputs.sendingAllowed = hasAcceptedTerms
        inputs.privateMode = privateModeEnabled
        inputs.onDeviceTranscription = onDeviceTranscriptionEnabled
        inputs.onDeviceTranscriptionCloudFallback = onDeviceTranscriptionCloudFallback
        inputs.onDeviceSpeakers = onDeviceSpeakerSeparationEnabled
        inputs.salesInsights = salesInsightsEnabled
        inputs.templateInsights = templateInsightsEnabled
        inputs.playbookInsights = playbookInsightsEnabled
        inputs.docsServerHost = validatedDocsMCPURL.flatMap { URL(string: $0)?.host }
        inputs.autoInferSpeakerNames = autoInferSpeakerNames
        inputs.jevClassifier = jevClassifierEnabled
        inputs.cloudPause = cloudPauseReason?.label
        inputs.googleCalendarConnected = googleCalendarEnabled && isGoogleCalendarConnected
        inputs.webhookHost = URL(string: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host
        inputs.autoAttioSync = autoAttioSync
        inputs.autoTwentySync = autoTwentySync
        inputs.shareDiagnostics = shareDiagnostics
        inputs.voicePrints = voicePrintSelfEnabled || voicePrintOthersEnabled
        inputs.isRecording = isRecording
        inputs.sessionTranscribesOnDevice = sessionTranscribesOnDevice
        return inputs
    }
}

// MARK: - View

import SwiftUI

/// The rows of a `DataFlowSummary` for a Settings form section. Shared by the macOS and iOS
/// Privacy screens; the caller supplies the `Section`.
struct DataFlowRowsView: View {
    @EnvironmentObject private var appState: AppState
    /// Show "Change" links on every row. Off where Settings cannot be driven programmatically.
    var showsJumps = true

    var body: some View {
        let summary = DataFlowSummary.build(appState.dataFlowInputs)
        if let note = summary.liveNote {
            Label(note, systemImage: "record.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(summary.rows) { row in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.sends ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                    Text(row.destination)
                    Spacer()
                    Text(row.sends ? "sends" : "nothing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsJumps, !row.jumps.isEmpty {
                    HStack(spacing: 10) {
                        Text("Change:")
                        ForEach(row.jumps) { jump in
                            Button(jump.label) { appState.jumpToSetting(jump.target) }
                                .settingsJumpStyle()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                }
            }
            .accessibilityElement(children: .combine)
        }
        Text(summary.staysHere)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension View {
    /// A text link on the Mac, a borderless button on iOS, where `.link` does not exist.
    @ViewBuilder
    func settingsJumpStyle() -> some View {
        #if os(macOS)
        self.buttonStyle(.link)
        #else
        self.buttonStyle(.borderless)
        #endif
    }
}
