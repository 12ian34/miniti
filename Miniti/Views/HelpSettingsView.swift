import SwiftUI
import Foundation

struct SupportDiagnostic: Codable, Equatable {
    let time: String
    let category: String
    let level: String
    let code: String
    let error_codes: [Int]
    var fields: [String: String]? = nil
    var count: Int? = nil
    var last_time: String? = nil

    static func make(_ event: DiagnosticTimeline.Event) -> SupportDiagnostic {
        Self(time: ISO8601DateFormatter().string(from: event.first), category: event.code.category,
             level: event.level, code: event.code.rawValue, error_codes: [], fields: event.fields,
             count: event.count, last_time: ISO8601DateFormatter().string(from: event.last))
    }

    var text: String {
        "\(time) [\(category)] [\(level)] \(code)"
            + (error_codes.isEmpty ? "" : " (\(error_codes.map(String.init).joined(separator: ", ")))")
            + (fields ?? [:]).keys.sorted().map { " \($0)=\(fields![$0]!)" }.joined()
            + ((count ?? 1) > 1 ? " count=\(count!) last=\(last_time ?? time)" : "")
    }

    /// Raw debug messages can contain titles, names, URLs and paths. Export fixed categories
    /// and numeric error codes only, never the message or a regex-redacted approximation.
    static func make(_ entry: DebugLogger.Entry) -> SupportDiagnostic? {
        guard entry.level.isImportant else { return nil }
        let lower = entry.message.lowercased()
        let code: String
        if lower.contains("mic capture failed") || lower.contains("capture failed") { code = "capture_failed" }
        else if lower.contains("stall") || lower.contains("no transcript") || lower.contains("zero transcript") { code = "audio_stall" }
        else if lower.contains("signing") || lower.contains("revoked") || lower.contains("auth") { code = "authentication_failed" }
        else if lower.contains("connect") || lower.contains("timeout") || lower.contains("timed out") { code = "connection_failed" }
        else { code = entry.level.rawValue }
        let expression = try! NSRegularExpression(pattern: #"(?i)(?:\bcode\s*[=:]\s*|\b(?:osstatus|status)\s*[=:]?\s*|\berror\s+)(-?\d{1,7})\b"#)
        let codes = expression.matches(in: entry.message, range: NSRange(entry.message.startIndex..., in: entry.message)).prefix(3).compactMap { match -> Int? in
            guard let range = Range(match.range(at: 1), in: entry.message) else { return nil }
            return Int(entry.message[range])
        }
        return Self(time: ISO8601DateFormatter().string(from: entry.timestamp), category: entry.category.rawValue, level: entry.level.rawValue, code: code, error_codes: codes)
    }
}

struct SupportReport: Codable, Equatable {
    var id: String = UUID().uuidString.lowercased()
    var kind: String? = nil
    var message = ""
    var reply_email = ""
    var details: [String: String]
    var diagnostics: [SupportDiagnostic]

    static let fields: [(String, String)] = [
        ("captured_at", "Captured at"), ("app", "App version and build"), ("platform", "Platform"),
        ("os", "Operating system"), ("architecture", "Architecture"), ("account_id", "Account ID"),
        ("device_id", "Device ID"), ("sign_in", "Sign-in status"), ("key", "Sign-in key"),
        ("mode", "Mode"), ("plan", "Plan"), ("cloud", "Cloud sync"), ("private_mode", "Private mode"),
        ("microphone", "Microphone capture"), ("system_audio", "System audio capture"),
        ("transcription", "Transcription preference"), ("speakers", "Speaker separation preference"),
        ("ai_permission", "AI permission")
    ]
    static func validEmail(_ email: String) -> Bool {
        email.isEmpty || (email.count <= 254 && email.range(of: #"^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$"#, options: .regularExpression) != nil)
    }
    var text: String {
        (["miniti support report: \(id)", "Reply email: \(reply_email.isEmpty ? "not provided" : reply_email)", "", message, "", "Support details:"]
         + Self.fields.compactMap { key, label in details[key].map { "\(label): \($0)" } }
         + ["", "Diagnostic timeline (sanitized events):"]
         + (diagnostics.isEmpty ? ["Not included or no recent events."] : diagnostics.map(\.text)))
            .joined(separator: "\n")
    }

    @MainActor static func capture(_ appState: AppState, now: Date = Date()) -> SupportReport {
        let status = appState.clientAuthStatus
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        var details = [
            "captured_at": ISO8601DateFormatter().string(from: now),
            "app": "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))",
            "platform": MinitiAPIService.platformHeader, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": architecture, "account_id": status.accountID ?? "none",
            "device_id": DeviceIdentifier.getOrCreateDeviceId(),
            "sign_in": status.keyPermanentlyUnavailable ? "key unavailable" : status.keyTemporarilyUnavailable ? "key temporarily unavailable" : status.isEnrolled ? "signed in" : "signed out",
            "key": status.isEnrolled || status.keyUnusable ? (status.isHardwareBacked ? "Secure Enclave" : "Software") : "none",
            "mode": appState.appMode == .managed ? "managed" : "BYOK", "plan": appState.appMode == .byok ? "BYOK" : appState.isPro ? "Pro" : "Free",
            "cloud": appState.cloudSyncEnabled ? "on" : "off", "private_mode": appState.privateModeEnabled ? "on" : "off",
            "microphone": appState.captureMicrophone ? "on" : "off", "system_audio": appState.captureSystemAudio ? "on" : "off",
            "transcription": appState.onDeviceTranscriptionEnabled ? "local" : "Deepgram", "speakers": appState.onDeviceSpeakerSeparationEnabled ? "local" : "Deepgram",
            "ai_permission": appState.hasAcceptedTerms ? "allowed" : "not allowed"
        ]
        #if os(iOS)
        details["system_audio"] = "not available on iOS"
        details["private_mode"] = "not available on iOS"
        details["transcription"] = "Deepgram"
        #endif
        let legacy = DebugLogger.shared.supportSnapshot().filter { now.timeIntervalSince($0.timestamp) >= 0 && now.timeIntervalSince($0.timestamp) <= 900 }.compactMap(SupportDiagnostic.make)
        let timeline = DiagnosticTimeline.shared.snapshot(now: now).map(SupportDiagnostic.make)
        // Prioritize the structured timeline. Legacy fallbacks retain otherwise-uninstrumented
        // failures without evicting the useful steps. Leave room for the message and details.
        var events = Array((Array(legacy.suffix(max(0, 100 - timeline.count))) + timeline.suffix(100)).sorted { $0.time < $1.time }.suffix(100))
        while !events.isEmpty, (try? JSONEncoder().encode(events).count) ?? Int.max > 32_000 { events.removeFirst() }
        return SupportReport(details: details, diagnostics: events)
    }
}

enum SupportReportFailure: LocalizedError {
    case network, rateLimited, unavailable, invalid, unexpected, sending
    case cooldown(Int)
    var errorDescription: String? {
        switch self {
        case .sending: return "A message is already being sent. Please wait."
        case .cooldown(let seconds): return "Please wait \(seconds) seconds before sending another message. Your text is still here."
        case .network: return "Could not reach miniti. Your report is still here. Check your connection and try again."
        case .rateLimited: return "Too many reports. Please try again later, or copy your report."
        case .unavailable: return "Reports are unavailable right now. Your report is still here. Copy it or try again later."
        case .invalid: return "Check your report and reply email. The report can be up to 4,000 characters."
        case .unexpected: return "Could not confirm the report was sent. Try again with the same report, or copy it."
        }
    }
}

@MainActor
final class SupportSubmissionGate {
    static let shared = SupportSubmissionGate()
    private(set) var busy = false
    private(set) var retryAt = Date.distantPast
    var now: () -> Date = Date.init
    func begin() throws {
        guard !busy else { throw SupportReportFailure.sending }
        let wait = max(0, Int(ceil(retryAt.timeIntervalSince(now()))))
        guard wait == 0 else { throw SupportReportFailure.cooldown(wait) }
        busy = true
    }
    func finish() { busy = false }
    func wait(_ seconds: TimeInterval) { retryAt = now().addingTimeInterval(max(1, min(seconds, 86_400))) }
}

@MainActor
enum SupportReportSender {
    /// Intentionally does not use managed auth: help must work with broken credentials/BYOK.
    static func send(_ report: SupportReport, session: URLSession = .shared, gate: SupportSubmissionGate? = nil) async throws {
        let gate = gate ?? .shared
        try gate.begin()
        defer { gate.finish() }
        var request = URLRequest(url: URL(string: MinitiAPIService.baseURL + "/support/report")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(report)
        request.timeoutInterval = 20
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw SupportReportFailure.network }
        guard let http = response as? HTTPURLResponse else { throw SupportReportFailure.unexpected }
        if http.statusCode == 429 {
            let seconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            let wait = seconds.isFinite ? max(1, min(seconds, 86_400)) : 60
            gate.wait(wait)
            throw SupportReportFailure.cooldown(Int(ceil(wait)))
        }
        if http.statusCode == 400 || http.statusCode == 413 { throw SupportReportFailure.invalid }
        if http.statusCode == 404 || http.statusCode >= 500 { throw SupportReportFailure.unavailable }
        struct Receipt: Decodable { let accepted: Bool; let id: String }
        guard http.statusCode == 200, let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.accepted, receipt.id == report.id else { throw SupportReportFailure.unexpected }
        gate.wait(30)
    }
}

/// Shared sections: the platform's Settings host owns the Form/navigation.
struct HelpSettingsSections: View {
    @EnvironmentObject private var appState: AppState
    @State private var snapshot: SupportReport?
    @State private var message = ""
    @State private var replyEmail = ""
    @State private var includeLog = true
    @State private var busy = false
    @State private var sent = false
    @State private var notice: String?
    @State private var preview: String?
    private var report: SupportReport? {
        guard var report = snapshot else { return nil }
        report.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        report.reply_email = replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !includeLog { report.diagnostics = [] }
        return report
    }
    var body: some View {
        Group {
            Section("Report a problem") {
                Text("What happened, what did you expect, and roughly when did it happen?")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $message).frame(minHeight: 100)
                    .accessibilityLabel("Describe the problem")
                if message.utf16.count > 4_000 { Text("Keep the report under 4,000 characters.").foregroundStyle(ColorPalette.Status.error) }
                TextField("Reply email (optional)", text: $replyEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                if !SupportReport.validEmail(replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Text("Enter a valid email address, or leave it empty.").font(.caption).foregroundStyle(ColorPalette.Status.error)
                }
                Toggle("Include diagnostic log", isOn: $includeLog)
                Text("Includes up to 100 recent diagnostic steps from the last 48 hours, including previous launches. Repeated events are counted together. No raw debug messages, transcripts, audio, meeting titles, keys or file paths are added. Anything you type above is included.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Send report sends the text, details below and selected diagnostics to miniti support through miniti's server and email provider. Add an email if you would like a reply.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Preview") { preview = report?.text }
                    Button("Copy all") { if let report { MinitiPasteboard.copy(report.text); notice = "Report copied." } }
                    Spacer()
                    Button(busy ? "Sending…" : sent ? "Sent" : "Send report") { send() }
                        .disabled(busy || sent || report?.message.isEmpty != false || message.utf16.count > 4_000 || !SupportReport.validEmail(replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                if let notice { Text(notice).font(.callout).textSelection(.enabled) }
            }
            .id("help.report")
            .disabled(busy)
            Section("Support details") {
                if let snapshot {
                    ForEach(SupportReport.fields, id: \.0) { key, label in
                        if let value = snapshot.details[key] {
                            LabeledContent(label) {
                                Text(value).font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                            .id(key == "device_id" ? "account.deviceID" : "help.\(key)")
                        }
                    }
                }
                Button("Refresh details and log") { refresh() }.disabled(busy)
            }
            .id("help.details")
            Section("Help") {
                Link("Documentation", destination: URL(string: "https://miniti.app/docs")!)
                Link("Support website", destination: URL(string: "https://miniti.app/support")!)
                    .id("about.support")
            }
        }
        .task { if snapshot == nil { refresh() } }
        .onChange(of: message) { _, _ in edited() }
        .onChange(of: replyEmail) { _, _ in edited() }
        .onChange(of: includeLog) { _, _ in edited() }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Report preview").font(.headline)
                ScrollView { Text(preview ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Done") { preview = nil }.keyboardShortcut(.cancelAction)
            }.padding().frame(idealWidth: 560, minHeight: 380)
        }
    }
    private func edited() { snapshot?.id = UUID().uuidString.lowercased(); sent = false; notice = nil }
    private func refresh() { snapshot = SupportReport.capture(appState); sent = false; notice = nil }
    private func send() {
        guard let report, !busy, !sent else { return }
        busy = true; notice = nil
        Task {
            defer { busy = false }
            do {
                try await SupportReportSender.send(report)
                sent = true; notice = "Report sent to miniti support. Reference: \(report.id)"
            } catch { notice = error.localizedDescription }
        }
    }
}


/// Lightweight Home entry point. Feedback never attaches account details or diagnostic logs.
struct HomeFeedbackButton: View {
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            MinitiHomeActionLabel(icon: "bubble.left", label: "feedback")
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { FeedbackSheet() }
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var reply = ""
    @State private var reportID = UUID().uuidString.lowercased()
    @State private var busy = false
    @State private var sent = false
    @State private var notice: String?
    @FocusState private var focused: Bool

    static func report(id: String, message: String, reply: String) -> SupportReport {
        SupportReport(id: id, kind: "feedback", message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                      reply_email: reply.trimmingCharacters(in: .whitespacesAndNewlines),
                      details: ["app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                                "platform": MinitiAPIService.platformHeader], diagnostics: [])
    }
    private var valid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.utf16.count <= 4_000
            && SupportReport.validEmail(reply.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            Text("Feedback").font(.title2.weight(.semibold))
            Text("Ideas, problems, or anything else you'd like Ian to know.").foregroundStyle(.secondary)
            TextEditor(text: $message)
                .frame(minHeight: 140, maxHeight: 260)
                .focused($focused).accessibilityLabel("Your feedback")
                .disabled(busy || sent)
            if message.utf16.count > 4_000 { Text("Keep your message under 4,000 characters.").foregroundStyle(ColorPalette.Status.error) }
            TextField("Reply email (optional)", text: $reply)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress).disabled(busy || sent)
            if !SupportReport.validEmail(reply.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Text("Enter a valid email address, or leave it empty.").foregroundStyle(ColorPalette.Status.error)
            }
            Text("Sends your message, optional email, app version and platform to miniti support. No diagnostic log is attached.")
                .font(.caption).foregroundStyle(.secondary)
            if let notice { Text(notice).font(.callout).textSelection(.enabled) }
            HStack {
                Button(sent ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                Button(busy ? "Sending…" : sent ? "Sent" : "Send feedback") { send() }
                    .disabled(busy || sent || !valid)
            }
        }
        .padding(MinitiDesignSystem.Spacing.page)
        .frame(idealWidth: 460)
        .interactiveDismissDisabled(busy)
        .onAppear { focused = true }
        .onChange(of: message) { _, _ in edited() }
        .onChange(of: reply) { _, _ in edited() }
    }
    private func edited() { reportID = UUID().uuidString.lowercased(); notice = nil }
    private func send() {
        guard valid, !busy, !sent else { return }
        let report = Self.report(id: reportID, message: message, reply: reply)
        busy = true; notice = nil
        Task {
            defer { busy = false }
            do {
                try await SupportReportSender.send(report)
                sent = true; notice = "Thanks. Your feedback has been sent."
            } catch { notice = error.localizedDescription }
        }
    }
}
