import Foundation
#if os(iOS)
import UIKit
#endif

/// What leaves this device and where it goes, worked out from the current settings so that
/// Settings, Sending can show it as three short groups instead of a sentence per feature. Pure
/// value type: `AppState` fills in `Inputs`, the views render `groups`, `notInUse`, `headline`
/// and `footer`, and the tests cover the rules without an `AppState`.
///
/// Rules (U1, docs/account-sending-consent-ux-plan.md): every row names one recipient, one
/// status word the model decides, one line of what is sent and why, optional details, and at
/// most one way to the setting that decides it. The status describes routing, never live
/// traffic. No sentence claims that a meeting "stays on this device": local transcription is
/// described as such, and what leaves afterwards is the exports and cloud rows.
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
        /// Pro and BYOK look topics up as the meeting goes; managed free looks up on request.
        var playbookLookupIsAutomatic = true
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
        /// Latched when the session started; a preference change does not move a running engine.
        var sessionTranscribesOnDevice = false
    }

    enum Group: CaseIterable, Equatable {
        case transcriptionAndAI
        case syncAndExports
        case accountAndConnections

        var title: String {
            switch self {
            case .transcriptionAndAI: return "Transcription and AI"
            case .syncAndExports: return "Sync and exports"
            case .accountAndConnections: return "Account and connections"
            }
        }
    }

    /// The routing state of one recipient. The text is the only thing the view shows for it.
    enum Status: Equatable {
        /// The route is taken when a recording runs or a recorded file is transcribed.
        case usedForRecordings
        /// Only when you ask (an export, a lookup).
        case onRequest
        /// Happens without a recording (checks, calendar reads, diagnostics).
        case automatic
        /// Leaves by itself after a meeting ends.
        case automaticExport
        case off
        /// Switched off for now by something named here (private mode, a cloud pause).
        case paused(String)
        case notConnected

        var text: String {
            switch self {
            case .usedForRecordings: return "Used for recordings"
            case .onRequest: return "On request"
            case .automatic: return "Automatic"
            case .automaticExport: return "Automatic export"
            case .off: return "Off"
            case .paused(let what): return "Paused: \(what)"
            case .notConnected: return "Not connected"
            }
        }

        /// False for the rows that belong under "Not in use".
        var isInUse: Bool {
            switch self {
            case .off, .notConnected: return false
            default: return true
            }
        }
    }

    /// A way to the setting that decides a row: `target` is a `SettingsSearchCatalog` id.
    struct Jump: Equatable, Identifiable {
        var id: String { target }
        let label: String
        let target: String
    }

    struct Row: Equatable, Identifiable {
        /// Stable across states, so the list never reorders or re-animates rows.
        let id: String
        let group: Group
        /// Who receives it.
        let title: String
        let status: Status
        /// One readable line: the essential data and purpose, or why nothing goes.
        let summary: String
        /// Payload, retention, path: the longer text under Details.
        var details: String?
        /// The one setting that decides this row.
        var configure: Jump?
        /// While recording, the preference for the next recording when it differs from the
        /// active route (F5). Shown without opening Details.
        var nextRecording: String?
        /// Deepgram and OpenAI stay in their group even when off, so they are easy to find.
        var alwaysVisible = false

        var isInUse: Bool { status.isInUse }
    }

    /// Every row in its fixed order, in use or not.
    let rows: [Row]
    /// One line above the groups: this recording's routes, or what the list is.
    let headline: String
    /// What is kept on this device, without claiming that a meeting never leaves.
    let footer: String

    /// The rows shown in their groups: in use, plus the always-visible ones.
    var groups: [(group: Group, rows: [Row])] {
        Group.allCases.compactMap { group in
            let shown = rows.filter { $0.group == group && ($0.isInUse || $0.alwaysVisible) }
            return shown.isEmpty ? nil : (group, shown)
        }
    }

    /// Optional recipients that are off or not configured, with the reason in `summary`.
    var notInUse: [Row] {
        rows.filter { !$0.isInUse && !$0.alwaysVisible }
    }

    /// The headline when nothing is recording.
    static let idleHeadline = "Based on your current settings. This is a routing summary, not a network monitor."

    // MARK: Build

    static func build(_ i: Inputs) -> DataFlowSummary {
        let managed = i.appMode == .managed
        /// The insight loop reads this live: a private-mode switch stops cloud AI at once.
        let cloudAI = i.sendingAllowed && !i.privateMode
        let gateStatus: Status? = {
            if !i.sendingAllowed { return .off }
            if i.privateMode { return .paused("private mode") }
            return nil
        }()
        let gateReason: String? = {
            if !i.sendingAllowed { return "Permission for Deepgram and OpenAI was not given." }
            if i.privateMode { return "Private mode keeps new recordings off cloud AI." }
            return nil
        }()
        let gateJump: Jump = !i.sendingAllowed
            ? Jump(label: "Permission", target: "privacy.thirdPartyAI")
            : Jump(label: "Private mode", target: "privacy.privateMode")

        var rows: [Row] = []

        // Deepgram: audio, straight from the app (miniti only hands out the token in managed mode).
        // The preference row describes the next recording; while recording, the row describes
        // the active audio route from the latched session and names the preference when it
        // differs (F5). The engine of a running session never follows a preference change.
        let deepgramTitle = managed ? "Deepgram" : "Deepgram, with your key"
        let deepgramPath = managed
            ? "Audio goes straight from this device to Deepgram; miniti only supplies the session token."
            : "Audio goes straight from this device to Deepgram with your own key."
        #if os(iOS)
        let recordedAudio = " Recordings your watch hands over are transcribed the same way."
        #else
        let recordedAudio = ""
        #endif
        let speakers = i.onDeviceSpeakers ? " Speakers are told apart on \(i.deviceName)." : " It also tells speakers apart."
        let preference: Row
        let preferenceRoute: String
        if let gateStatus, let gateReason {
            preference = Row(id: "deepgram", group: .transcriptionAndAI, title: deepgramTitle, status: gateStatus, summary: gateReason, details: nil, configure: gateJump, alwaysVisible: true)
            preferenceRoute = i.sendingAllowed ? "paused, private mode" : "off, permission not given"
        } else if i.onDeviceTranscription && !i.onDeviceTranscriptionCloudFallback {
            preference = Row(id: "deepgram", group: .transcriptionAndAI, title: deepgramTitle, status: .off, summary: "Transcription runs on \(i.deviceName); no audio is sent.", details: "A meeting whose language model is not ready on \(i.deviceName) cannot start unless Deepgram fallback is allowed for it.", configure: Jump(label: "Transcription", target: "transcription.model"), alwaysVisible: true)
            preferenceRoute = "transcription on \(i.deviceName), no audio sent"
        } else {
            let summary = i.onDeviceTranscription
                ? "Audio only for a meeting whose language model is not ready on \(i.deviceName), with the meeting title and attendee names."
                : "Audio, the meeting title and attendee names, for the transcript."
            let details = (i.onDeviceTranscription
                ? "Transcription normally runs on \(i.deviceName); Deepgram is the fallback you allowed. "
                : "") + deepgramPath + " The title and names help it spell them right." + speakers + recordedAudio
            preference = Row(id: "deepgram", group: .transcriptionAndAI, title: deepgramTitle, status: .usedForRecordings, summary: summary, details: details, configure: Jump(label: "Transcription", target: i.onDeviceTranscription ? "transcription.fallback" : "transcription.model"), alwaysVisible: true)
            preferenceRoute = i.onDeviceTranscription ? "transcription on \(i.deviceName), audio to Deepgram only when the model is not ready" : "audio to Deepgram"
        }
        if i.isRecording {
            var active: Row
            let sameAsActive: Bool
            if i.sessionTranscribesOnDevice {
                active = Row(id: "deepgram", group: .transcriptionAndAI, title: deepgramTitle, status: .off, summary: "This recording is transcribed on \(i.deviceName); no audio is sent.", details: preference.details, configure: preference.configure, alwaysVisible: true)
                sameAsActive = preferenceRoute.hasPrefix("transcription on \(i.deviceName)")
            } else {
                active = Row(id: "deepgram", group: .transcriptionAndAI, title: deepgramTitle, status: .usedForRecordings, summary: "Audio from this recording, the meeting title and attendee names, for the transcript.", details: deepgramPath + " The title and names help it spell them right." + speakers + recordedAudio, configure: preference.configure, alwaysVisible: true)
                sameAsActive = preferenceRoute == "audio to Deepgram"
            }
            if !sameAsActive { active.nextRecording = "Next recording: \(preferenceRoute)." }
            rows.append(active)
        } else {
            rows.append(preference)
        }

        // OpenAI: text, through the miniti backend in managed mode.
        let openAITitle = managed ? "OpenAI, through miniti" : "OpenAI, with your key"
        if let gateStatus, let gateReason {
            rows.append(Row(id: "openai", group: .transcriptionAndAI, title: openAITitle, status: gateStatus, summary: gateReason, details: nil, configure: gateJump, alwaysVisible: true))
        } else {
            var features = ["summaries and action items", "questions"]
            if i.autoInferSpeakerNames { features.append("speaker names") }
            if i.salesInsights { features.append("Sales") }
            if i.templateInsights { features.append("templates") }
            if i.playbookInsights { features.append("Playbook") }
            let summary = "The transcript, your notes, the meeting title and attendee names, for \(joined(features))."
            let details = (managed
                ? "Text goes to OpenAI through miniti's servers, which hold it only for the request."
                : "Text goes straight to OpenAI with your own key.")
                + " Catch-up and investigations run when you ask. Saved and watch meetings are processed when they finish, recording or not."
            rows.append(Row(id: "openai", group: .transcriptionAndAI, title: openAITitle, status: .usedForRecordings, summary: summary, details: details, configure: Jump(label: "AI", target: "ai.speakerNames"), alwaysVisible: true))
        }

        // TypeSafe: the Jev classifier, managed and opt-in.
        if managed {
            if cloudAI && i.jevClassifier {
                rows.append(Row(id: "typesafe", group: .transcriptionAndAI, title: "TypeSafe (Jev)", status: .usedForRecordings, summary: "The last few minutes of transcript, for the sales nudge and speaker names.", details: "Through miniti, under a second per answer; it never generates text. GPT and the phrase list take over on any failure.", configure: Jump(label: "Jev", target: "ai.speakerNames")))
            } else {
                rows.append(Row(id: "typesafe", group: .transcriptionAndAI, title: "TypeSafe (Jev)", status: gateStatus ?? .off, summary: gateReason ?? "Jev is off.", details: nil, configure: gateStatus == nil ? Jump(label: "Jev", target: "ai.speakerNames") : gateJump))
            }
        }

        // Your docs server: Playbook searches.
        if i.playbookInsights, let host = i.docsServerHost {
            if cloudAI {
                rows.append(Row(id: "docs", group: .transcriptionAndAI, title: host, status: i.playbookLookupIsAutomatic ? .usedForRecordings : .onRequest, summary: "Short searches drawn from the transcript, for Playbook.", details: (managed ? "Searches go through miniti. " : "") + "The transcript itself is not sent there." + (i.playbookLookupIsAutomatic ? " Topics are looked up as the meeting goes." : " Each lookup is one you start."), configure: Jump(label: "Playbook", target: "playbook.server")))
            } else {
                rows.append(Row(id: "docs", group: .transcriptionAndAI, title: host, status: gateStatus ?? .off, summary: gateReason ?? "Playbook is off.", details: nil, configure: gateJump))
            }
        } else {
            rows.append(Row(id: "docs", group: .transcriptionAndAI, title: "Your docs server", status: .notConnected, summary: i.playbookInsights ? "No docs server is set." : "Playbook is off.", details: nil, configure: Jump(label: "Playbook", target: "playbook.server")))
        }

        // miniti cloud: finished meetings to the other devices on the account.
        if managed {
            let status: Status
            let summary: String
            if i.cloudPause == nil {
                status = .automaticExport
                summary = "Finished meetings, so your other devices see them."
            } else if i.cloudPause == "Off" {
                status = .off
                summary = "Cloud is off; meetings stay on each device."
            } else {
                status = .paused(i.cloudPause!.lowercased())
                summary = "Cloud is paused; nothing uploads until it resumes."
            }
            rows.append(Row(id: "cloud", group: .syncAndExports, title: "miniti cloud", status: status, summary: summary, details: "Pro only. The switch belongs to the account. Each meeting can be kept off the cloud, or put on it later. A meeting recorded in private mode stays off unless you put it on.", configure: Jump(label: "Cloud", target: "cloud.sync")))
        }

        // Webhook.
        if let host = i.webhookHost {
            rows.append(Row(id: "webhook", group: .syncAndExports, title: host, status: .automaticExport, summary: "Each saved meeting as JSON, including the transcript.", details: "Https only. It runs in private mode too, because you configured it. Deliveries that fail are retried.", configure: Jump(label: "Webhook", target: "integrations.webhook")))
        } else {
            rows.append(Row(id: "webhook", group: .syncAndExports, title: "Webhook", status: .notConnected, summary: "No webhook is set.", details: nil, configure: Jump(label: "Webhook", target: "integrations.webhook")))
        }

        // CRM export (Mac).
        if i.crmAvailable {
            let auto = [i.autoAttioSync ? "Attio" : nil, i.autoTwentySync ? "Twenty" : nil].compactMap { $0 }
            if auto.isEmpty {
                rows.append(Row(id: "crm", group: .syncAndExports, title: "Attio or Twenty", status: .onRequest, summary: "A meeting's title, summary, notes and action items, only when you export it. Never the transcript.", details: "Exports go through miniti to the CRM you connected.", configure: Jump(label: "CRM", target: "integrations.attio")))
            } else {
                rows.append(Row(id: "crm", group: .syncAndExports, title: joined(auto), status: .automaticExport, summary: "Each meeting's title, summary, notes and action items after it ends. Never the transcript.", details: "Exports go through miniti. It runs in private mode too, because you configured it.", configure: Jump(label: "CRM", target: i.autoAttioSync ? "integrations.attio" : "integrations.twenty")))
            }
        }

        // miniti itself.
        if managed {
            rows.append(Row(id: "account", group: .accountAndConnections, title: "miniti (api.miniti.app)", status: .automatic, summary: "Your device id, app version and minutes used.", details: "Sign-in, the usage check before and after a recording, and the version check at launch. Nothing about what was said.", configure: Jump(label: "Account", target: "account.apiMode")))
            rows.append(Row(id: "diagnostics", group: .accountAndConnections, title: "miniti diagnostics", status: i.shareDiagnostics ? .automatic : .off, summary: i.shareDiagnostics ? "Errors and reconnects, never transcript or audio." : "Share Diagnostics is off.", details: i.shareDiagnostics ? "Reliability events with the device id and app version, so failures can be fixed without asking you." : nil, configure: Jump(label: "Diagnostics", target: "privacy.diagnostics")))
        } else {
            rows.append(Row(id: "account", group: .accountAndConnections, title: "miniti (api.miniti.app)", status: .automatic, summary: "A version check at launch.", details: "The app version and platform, so the minimum-version gate can answer. No meeting content is involved.", configure: Jump(label: "Mode", target: "account.apiMode")))
        }

        // Google Calendar, read through miniti.
        if i.googleCalendarConnected {
            rows.append(Row(id: "calendar", group: .accountAndConnections, title: "Google Calendar", status: .automatic, summary: "Upcoming events are read whenever it is connected; nothing is written.", details: "Events are read through miniti so meetings can start on time and attendees can be named. Not tied to recording.", configure: Jump(label: "Calendar", target: "integrations.googleCalendar")))
        } else {
            rows.append(Row(id: "calendar", group: .accountAndConnections, title: "Google Calendar", status: .notConnected, summary: "Not connected.", details: nil, configure: Jump(label: "Calendar", target: "integrations.googleCalendar")))
        }

        // Headline: the engine half is latched at session start; the AI half is read live.
        let headline: String = {
            guard i.isRecording else { return idleHeadline }
            switch (i.sessionTranscribesOnDevice, cloudAI) {
            case (false, true): return "This recording: audio to Deepgram, transcript to OpenAI."
            case (false, false): return "This recording: audio to Deepgram. Cloud AI is paused, so no insights are requested."
            case (true, true): return "This recording: transcribing on \(i.deviceName), transcript to OpenAI."
            case (true, false): return "This recording: transcribing on \(i.deviceName), no cloud AI. Configured exports still run when it ends."
            }
        }()

        var kept = ["your meeting history", "search", "coaching"]
        if i.voicePrints { kept.append("voice fingerprints") }
        #if os(iOS)
        let files = " Watch recordings are files on this device until they are transcribed."
        #else
        let files = ""
        #endif
        let footer = "Available on \(i.deviceName): \(joined(kept)).\(files) Granola imports are saved as text. Cloud sync and configured exports can copy meetings, including imports. Exports and cloud copies are the rows above."

        return DataFlowSummary(rows: rows, headline: headline, footer: footer)
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
        #if os(iOS)
        // The iOS Settings consumes one request: push or select the destination, then scroll.
        settingsNavigationRequest = SettingsNavigationRequest(destination: item.destination, target: id)
        #else
        DispatchQueue.main.async { [weak self] in
            self?.pendingSettingsSearchTarget = id
        }
        #endif
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
        inputs.playbookLookupIsAutomatic = appMode == .byok || isPro
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

/// The Sending tab's body for a `Form`: the headline, one `Section` per group, the "Not in use"
/// disclosure and the footer. Shared by macOS and iOS; the caller supplies how a Configure
/// control reaches the owning setting (a `jumpToSetting` button on the Mac, a `NavigationLink`
/// on iOS), so the rows stay identical on both.
struct DataFlowRowsView<Configure: View>: View {
    @EnvironmentObject private var appState: AppState
    @ViewBuilder var configure: (DataFlowSummary.Jump) -> Configure

    var body: some View {
        let summary = DataFlowSummary.build(appState.dataFlowInputs)
        Section {
            Label(summary.headline, systemImage: appState.isRecording ? "record.circle" : "arrow.up.right")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(summary.groups, id: \.group) { entry in
            Section(entry.group.title) {
                ForEach(entry.rows) { row in
                    DataFlowRowView(row: row, configure: configure)
                }
            }
        }
        if !summary.notInUse.isEmpty {
            Section {
                DisclosureGroup {
                    ForEach(summary.notInUse) { row in
                        DataFlowRowView(row: row, configure: configure)
                    }
                } label: {
                    HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                        Text("Not in use")
                        Text("\(summary.notInUse.count)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .disclosureGroupStyle(MinitiDisclosureStyle())
            }
        }
        Section {
            Text(summary.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One recipient: title and status on a line (stacked when narrow), the summary under it,
/// Details when there is more to say, and the single Configure control.
private struct DataFlowRowView<Configure: View>: View {
    let row: DataFlowSummary.Row
    @ViewBuilder var configure: (DataFlowSummary.Jump) -> Configure
    @State private var detailsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: MinitiDesignSystem.Spacing.standard) {
                    Text(row.title)
                        .lineLimit(nil)
                    Spacer(minLength: MinitiDesignSystem.Spacing.standard)
                    statusText
                }
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                    Text(row.title)
                    statusText
                }
            }
            Text(row.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = row.nextRecording {
                Text(next)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if row.details != nil || row.configure != nil {
                HStack(spacing: MinitiDesignSystem.Spacing.section) {
                    if let jump = row.configure {
                        configure(jump)
                    }
                    if row.details != nil {
                        Button(detailsShown ? "Hide details" : "Details") {
                            detailsShown.toggle()
                        }
                        .settingsJumpStyle()
                    }
                }
                .font(.callout)
            }
            if detailsShown, let details = row.details {
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, MinitiDesignSystem.Spacing.hairline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.title). \(row.status.text). \(row.summary)\(row.nextRecording.map { " \($0)" } ?? "")")
    }

    private var statusText: some View {
        Text(row.status.text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
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
