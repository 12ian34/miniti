import SwiftUI
import SwiftData

struct MeetingCloudPrivacyStatus: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting
    @ObservedObject var engine: CloudSyncEngine
    var showsChoice = true
    @Query private var pending: [MeetingTombstone]

    init(meeting: Meeting, engine: CloudSyncEngine, showsChoice: Bool = true) {
        self.meeting = meeting; self.engine = engine; self.showsChoice = showsChoice
        let id = meeting.id
        _pending = Query(filter: #Predicate<MeetingTombstone> { $0.id == id })
    }

    private var pause: CloudSyncPause? {
        if let reason = appState.cloudPauseReason { return reason }
        if case .paused(let reason) = engine.phase { return reason }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if meeting.syncExcluded {
                if showsChoice { Label("Kept off the cloud", systemImage: "icloud.slash") }
                if !pending.isEmpty, pause == nil || pending.contains(where: { $0.cloudRevision > 0 }) {
                    Text(engine.lastError == nil ? "Cloud copy removal pending. Sync must be connected to finish." : "Cloud copy removal has not finished. Check Settings, Cloud and try syncing again.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if meeting.cloudRestoreRequested {
                Label(MeetingCloudPrivacyPresentation.uploadStatus(pause: pause), systemImage: "icloud.and.arrow.up")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("This controls miniti cloud storage. Transcription, AI and exports still use your settings. Removing a cloud copy does not remove exports or backups immediately.")
    }
}

/// Settings → Cloud (3.0.0): the switch, status, web sign-in and delete. Settings → API
/// (3.2.1): connected apps, tokens and the connector setup, with the upgrade path for people
/// who are not on Pro or have cloud off. One view each on macOS; the sections are reused by
/// the iOS settings list.
#if os(macOS)
struct CloudSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            CloudSettingsSections(engine: appState.cloudSync)
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .cloud)
    }
}

struct APIAccessSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            CloudSettingsSections(engine: appState.cloudSync, mode: .api)
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .api)
    }
}
#endif

struct CloudSettingsSections: View {
    enum Mode { case cloud, api }

    @EnvironmentObject private var appState: AppState
    /// Observed directly: `AppState` holds the engine as a `let`, so its phase, last-synced
    /// time and skipped count would otherwise never refresh while the tab is open.
    @ObservedObject var engine: CloudSyncEngine
    var mode: Mode = .cloud
    @State private var isPresentingEnable = false
    @State private var isConfirmingDelete = false
    @State private var isBusy = false
    @State private var notice: String?
    @State private var tokens: [CloudToken] = []
    @State private var connectedApps: [CloudConnectedApp] = []
    @State private var newTokenName = ""
    @State private var revealedToken: String?
    @State private var copiedToken = false
    @State private var loadedAccount: String?
    @State private var isShowingLog = false

    var body: some View {
        switch mode {
        case .cloud:
            if appState.appMode == .byok {
                Section("Cloud") {
                    Text("Cloud needs the managed plan.")
                        .foregroundStyle(.secondary)
                }
                .id("cloud.sync")
            } else {
                cloudSection
                CloudExclusionRulesSection()
                if appState.cloudSyncEnabled {
                    statusSection
                    signInSection
                    deleteSection
                }
            }
            if appState.appMode == .byok { CloudExclusionRulesSection() }
        case .api:
            apiIntroSection
            if appState.appMode != .byok, appState.isPro, appState.cloudSyncEnabled {
                connectedAppsSection
                apiSection
            }
        }
    }

    // MARK: API tab

    /// What the API gives you, and the one thing standing between this person and it.
    private var apiIntroSection: some View {
        Section("Your meetings in your own tools") {
            Text("Ask Claude or ChatGPT about last week's call, let Claude Code and Cursor read a meeting while you work, or pull transcripts and action items into a script. Read only: nothing here can change or delete a meeting.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.appMode == .byok {
                Text("Needs the managed plan with Pro, because the tools read the cloud copy of your meetings. Bring-your-own-keys mode has no account to connect to.")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Text.dim)
            } else if !appState.isPro {
                Text("Needs Pro: the tools read the cloud copy of your meetings, and cloud is part of Pro.")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Text.dim)
                #if os(macOS)
                Button("Upgrade to Pro ($5/month, 5,000 min)") {
                    Task { await appState.openSubscribePage() }
                }
                #else
                Button("Upgrade to Pro in Settings, Account") {
                    appState.selectedSettingsTab = SettingsDestination.account.rawValue
                }
                #endif
            } else if !appState.cloudSyncEnabled {
                Text("Turn on cloud first: the tools read the cloud copy of your meetings, so there is nothing to read until it exists.")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Text.dim)
                #if os(macOS)
                Button("Open Cloud settings") {
                    appState.selectedSettingsTab = SettingsDestination.cloud.rawValue
                }
                #endif
            } else if appState.accountEmailState.email?.verified == nil {
                Text("Claude and ChatGPT sign you in with the email on your account. Add one in Settings, Account before connecting them. Tokens work without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add email in Settings, Account") { appState.jumpToSetting("account.email") }
                    .settingsJumpStyle()
            }
        }
        .id("api.setup")
        .task(id: appState.clientAuthStatus.accountID) { await loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .minitiCloudCallback)) { _ in
            loadedAccount = nil
            Task { await loadIfNeeded() }
        }
    }

    private var connectedAppsSection: some View {
        Section("Connected apps") {
            if connectedApps.isEmpty {
                Text("Nothing connected yet. Connect Claude or ChatGPT with the URL below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(connectedApps) { app in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.clientName)
                        Text(app.lastUsedAt.map { "Last used \(CloudSettingsSections.relative($0))" } ?? "Not used yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") { disconnect(app) }.disabled(isBusy)
                }
            }
        }
        .id("api.connected")
    }

    // MARK: Sections

    private var cloudSection: some View {
        Section("Cloud") {
            Toggle("Keep a copy of your meetings on miniti's servers", isOn: Binding(
                get: { appState.cloudSyncEnabled },
                set: { on in
                    if on { isPresentingEnable = true } else { appState.setCloudSyncEnabled(false) }
                }
            ))
            .disabled(!appState.isPro || appState.privateModeEnabled)
            Text("miniti keeps a copy and can read it, so your other devices, your tools and you on the web can too. Off by default. One switch for your account: every device follows it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !appState.isPro {
                Text("Cloud needs Pro. Upgrade in Settings, Account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appState.privateModeEnabled {
                Text("Paused while private mode is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id("cloud.sync")
        .sheet(isPresented: $isPresentingEnable) {
            CloudEnableSheet(onTurnOn: {
                appState.setCloudSyncEnabled(true)
            })
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Text(phaseLabel)
                Spacer()
                Button("Sync now") { appState.kickCloudSync(reason: "manual") }
                    .disabled(appState.cloudPauseReason != nil)
            }
            if let status = engine.status {
                HStack {
                    Text("In the cloud")
                    Spacer()
                    Text("\(status.meetingCount) meetings, \(CloudSettingsSections.format(bytes: status.bytes))")
                        .foregroundStyle(.secondary)
                }
            }
            if let last = engine.lastSyncedAt {
                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
            if !engine.skippedMeetingIDs.isEmpty {
                Text("\(engine.skippedMeetingIDs.count) meeting\(engine.skippedMeetingIDs.count == 1 ? "" : "s") too large for the cloud and kept on this device only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            Button("View log") { isShowingLog = true }
        }
        .id("cloud.status")
        .sheet(isPresented: $isShowingLog) {
            CloudSyncLogView(engine: engine)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .task(id: appState.clientAuthStatus.accountID) { await loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .minitiCloudCallback)) { _ in
            // The browser confirmed the email and handed back to the app: show it without a relaunch.
            loadedAccount = nil
            Task { await loadIfNeeded() }
        }
    }

    private var phaseLabel: String {
        switch engine.phase {
        case .idle: return "Up to date"
        case .reconciling: return "Checking the cloud"
        case .pushing(let done, let total): return "Uploading \(done) of \(total)"
        case .pulling: return "Downloading"
        case .paused(let reason): return reason.label
        case .failed(let text): return text
        }
    }

    private var signInSection: some View {
        Section("Web sign-in") {
            switch appState.accountEmailState {
            case .loading:
                Text("Checking this account's email…")
                    .foregroundStyle(.secondary)
            case .unavailable(let message):
                HStack {
                    Text("Could not check this account's email. \(message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await appState.refreshAccountEmail(reason: "cloud retry", force: true) } }
                }
            case .loaded(let email):
                if let verified = email.verified {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(verified).foregroundStyle(.secondary)
                    }
                    Text("Sign in at api.miniti.app/signin with a link sent to this address, and approve a new device from your inbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let pending = email.pending {
                    Text("Check \(pending) for a confirmation link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No email on this account yet. Add one to sign in on the web and to connect tools like Claude.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Manage email in Settings, Account") { appState.jumpToSetting("account.email") }
                .settingsJumpStyle()
            Text("Connected apps and tokens live in Settings, API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .id("cloud.signin")
    }

    private var apiSection: some View {
        Section("Tokens and setup") {
            ForEach(tokens) { token in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name.isEmpty ? token.prefix : token.name)
                        Text("\(token.prefix)…  \(token.lastUsedAt.map { "last used \(CloudSettingsSections.relative($0))" } ?? "not used yet")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke") { revoke(token) }.disabled(isBusy)
                }
            }
            if let revealedToken {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Copy this token now. It is shown once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(revealedToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(copiedToken ? "Copied" : "Copy") { copy(revealedToken); copiedToken = true }
                        Button("Done") { self.revealedToken = nil; copiedToken = false }
                    }
                }
            }
            HStack {
                TextField("Token name, for example laptop", text: $newTokenName)
                    .textFieldStyle(.roundedBorder)
                Button("New token") { createToken() }
                    .disabled(isBusy || newTokenName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Tokens read your meetings through the REST API and the MCP server. Claude.ai and ChatGPT connectors use web sign-in instead of a token.")
                .font(.caption)
                .foregroundStyle(.secondary)
            MCPSetupRows(token: revealedToken)
        }
        .id("api.tokens")
    }

    private var deleteSection: some View {
        Section("Delete") {
            Button("Delete cloud copy", role: .destructive) { isConfirmingDelete = true }
                .disabled(isBusy)
            Text("Removes every meeting, token and connected app from miniti's servers. Meetings on your devices stay. With the switch on they upload again on the next sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .id("cloud.delete")
        .confirmationDialog("Delete the cloud copy of every meeting?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete cloud copy", role: .destructive) { deleteCloudCopy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your devices keep their meetings. Tokens and connected apps stop working.")
        }
    }

    // MARK: Actions

    private func loadIfNeeded() async {
        guard appState.cloudSyncEnabled, let api = appState.minitiAPIService, appState.cloudPauseReason == nil else { return }
        let account = appState.clientAuthStatus.accountID
        guard account != loadedAccount else { return }
        loadedAccount = account
        async let tokenList = try? api.listCloudTokens()
        async let appList = try? api.listConnectedApps()
        tokens = await tokenList ?? []
        connectedApps = await appList ?? []
        await appState.refreshAccountEmail(reason: "cloud settings")
    }

    private func disconnect(_ app: CloudConnectedApp) {
        guard let api = appState.minitiAPIService else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            if (try? await api.revokeConnectedApp(id: app.id)) != nil { connectedApps.removeAll { $0.id == app.id } }
        }
    }

    private func createToken() {
        guard let api = appState.minitiAPIService else { return }
        let name = newTokenName.trimmingCharacters(in: .whitespaces)
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let created = try await api.createCloudToken(name: name)
                tokens.insert(created.token, at: 0)
                revealedToken = created.secret
                copiedToken = false
                newTokenName = ""
            } catch {
                notice = "Could not create the token."
            }
        }
    }

    private func revoke(_ token: CloudToken) {
        guard let api = appState.minitiAPIService else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            if (try? await api.revokeCloudToken(id: token.id)) != nil { tokens.removeAll { $0.id == token.id } }
        }
    }

    private func deleteCloudCopy() {
        isBusy = true
        Task {
            defer { isBusy = false }
            if await appState.deleteCloudCopy() {
                tokens = []
                connectedApps = []
                notice = "Cloud copy deleted."
            } else {
                notice = "Could not delete the cloud copy."
            }
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// A per-meeting storage choice. The label describes the choice, not a completed upload.
struct MeetingCloudStorageButton: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var meeting: Meeting
    private var locked: Bool {
        appState.currentMeeting?.id == meeting.id && appState.privateModeEnabled && appState.privateModeLocked
    }
    var body: some View {
        Button { appState.toggleMeetingCloudStorage(meeting) } label: {
            MinitiControlLabel(role: .primary, isEmphasized: !meeting.syncExcluded && appState.cloudPauseReason == nil) {
                HStack(spacing: 6) {
                    Image(systemName: meeting.syncExcluded ? "icloud.slash" : "icloud")
                        .font(.system(size: 11, weight: .medium))
                    Text(meeting.syncExcluded ? "Local" : "Cloud")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .opacity(meeting.syncExcluded ? 0.65 : 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(locked)
        .accessibilityLabel(meeting.syncExcluded ? "Local, keep this meeting off the cloud" : "Cloud, save this meeting to the cloud")
        .accessibilityHint(locked ? "Private mode keeps this recording local." : "Changes cloud storage for this meeting only. Transcription, AI and exports still use your settings.")
        .help(locked ? "Private mode keeps this recording off the cloud." : "Cloud storage for this meeting. Transcription, AI and exports still follow your settings.")
    }
}

private struct MeetingCloudFeedbackView: View {
    @EnvironmentObject private var appState: AppState
    let meetingID: UUID?
    var body: some View {
        Group {
            if let feedback = appState.meetingCloudFeedback, feedback.meetingID == meetingID {
                Text(feedback.message)
                    .font(.callout)
                    .foregroundStyle(ColorPalette.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MinitiDesignSystem.Spacing.comfortable)
                    .frame(maxWidth: 310, alignment: .leading)
                    .background(ColorPalette.Background.card, in: RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control).stroke(ColorPalette.Border.light, lineWidth: 1))
                    .padding(MinitiDesignSystem.Spacing.comfortable)
                    .allowsHitTesting(false)
                    .onDisappear {
                        if appState.meetingCloudFeedback?.id == feedback.id { appState.meetingCloudFeedback = nil }
                    }
                    .task(id: feedback.id) {
                        AccessibilityNotification.Announcement(feedback.message).post()
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled, appState.meetingCloudFeedback?.id == feedback.id else { return }
                        appState.meetingCloudFeedback = nil
                    }
            }
        }
    }
}

extension View {
    func meetingCloudFeedback(for meetingID: UUID?) -> some View {
        overlay(alignment: .bottomTrailing) { MeetingCloudFeedbackView(meetingID: meetingID) }
    }
}

private struct CloudExclusionRuleEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    private var problem: String? { CloudRuleValidation.problem(draft, existing: appState.cloudExclusionRules) }
    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
            Text("Add cloud rule").font(.headline)
            Text("Keep calendar meetings off the cloud when their title contains:")
                .foregroundStyle(.secondary)
            TextField("For example, therapy", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(save)
                .accessibilityLabel("Meeting title contains")
            if let problem, !draft.isEmpty { Text(problem).font(.caption).foregroundStyle(.secondary) }
            Text("On this device only. Transcription, AI and exports still follow your settings.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save rule", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(MinitiDesignSystem.Spacing.section)
        .frame(idealWidth: 380)
        .task { fieldFocused = true }
        .presentationDetents([.medium])
    }
    private func save() {
        if appState.addCloudExclusionRule(draft) { dismiss() }
    }
}

private struct CloudExclusionRulesSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAddingRule = false
    @State private var preview: [AppState.CalendarFilterPreviewRow]?
    @State private var isLoading = false
    @State private var previewError: String?
    @State private var previewSequence = 0

    var body: some View {
        Section("Keep matching meetings off the cloud") {
            Text("On this device. Calendar meetings stay visible and recordable. A matching title keeps new recordings off miniti cloud; transcription, AI and exports still follow your settings. Changes here do not affect saved meetings.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(appState.cloudExclusionRules.enumerated()), id: \.offset) { index, rule in
                HStack {
                    Text("Title contains: \(rule)")
                    Spacer()
                    Button("Remove") { appState.cloudExclusionRules.remove(at: index) }
                        .accessibilityLabel("Remove rule \(rule)")
                }
            }
            Button("Add rule") { isAddingRule = true }
            .disabled(appState.cloudExclusionRules.count >= 30)
            if appState.cloudExclusionRules.count >= 30 {
                Text("You have 30 rules. Remove one to add another.").font(.caption).foregroundStyle(.secondary)
            }
            Text("A renamed event or a recording without a calendar event may not match. You can change a meeting between Cloud and Local in its toolbar. These rules do not apply to Watch recordings or imports.")
                .font(.caption).foregroundStyle(.secondary)
            Button(isLoading ? "Loading preview…" : "Preview next 7 days") {
                isLoading = true; previewError = nil
                previewSequence += 1
                let sequence = previewSequence
                let generation = appState.accountGeneration
                Task {
                    do {
                        let rows = try await appState.previewCalendarMeetingFilters()
                        guard generation == appState.accountGeneration, sequence == previewSequence else { return }
                        preview = rows
                    } catch {
                        guard generation == appState.accountGeneration, sequence == previewSequence else { return }
                        previewError = "Could not load the calendar preview. Try again."
                    }
                    isLoading = false
                }
            }
            .disabled(isLoading || !appState.isGoogleCalendarConnected)
            if let previewError { Text(previewError).font(.caption).foregroundStyle(.secondary) }
            if let preview {
                let matches = preview.filter { CloudExclusionPolicy.matchingRule(title: $0.title, rules: appState.cloudExclusionRules) != nil }
                if matches.isEmpty { Text("No matching events in this preview.").font(.caption).foregroundStyle(.secondary) }
                ForEach(matches) { row in
                    VStack(alignment: .leading) {
                        Text(row.title)
                        if let start = row.start { Text(start, style: .date).font(.caption).foregroundStyle(.secondary) }
                        Text("Kept off the cloud: title contains \(CloudExclusionPolicy.matchingRule(title: row.title, rules: appState.cloudExclusionRules) ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Preview covers up to 50 calendar events.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .id("cloud.exclusions")
        .sheet(isPresented: $isAddingRule) { CloudExclusionRuleEditor().environmentObject(appState) }
        .onChange(of: appState.accountGeneration) { _, _ in
            previewSequence += 1
            preview = nil; previewError = nil; isLoading = false
        }
    }


}

/// The one sheet shown when the switch is turned on: what uploads, the plain sentence about
/// miniti reading the copy, and an optional email.
struct CloudEnableSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onTurnOn: () -> Void
    @State private var meetingCount: Int?

    private var hasEmail: Bool { appState.accountEmailState.email?.verified != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep your meetings in the cloud")
                .font(.title3.weight(.semibold))
            Text(meetingCount.map { "\($0) finished meeting\($0 == 1 ? "" : "s") on this device will upload, and everything your other devices hold will come here. Cloud turns on for every device on your account." } ?? "Your finished meetings will upload, and everything your other devices hold will come here. Cloud turns on for every device on your account.")
            Text("miniti keeps a copy and can read it, so your other devices, your tools and you on the web can too. A meeting recorded in private mode stays off the cloud unless you put it on.")
                .foregroundStyle(.secondary)
            if !hasEmail {
                Text("Web sign-in and tools like Claude need an email on the account. You can add one in Settings, Account now or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if !hasEmail {
                    Button("Add email first") {
                        dismiss()
                        appState.jumpToSetting("account.email")
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(hasEmail ? "Turn on" : "Turn on without email") {
                    onTurnOn()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 440)
        .onAppear {
            meetingCount = appState.cloudFetchMeetings(FetchDescriptor<Meeting>())?.filter { $0.endTime != nil && !$0.syncExcluded }.count
        }
    }
}


/// Ready-to-paste MCP setup for the tools people actually use. While a freshly created token
/// is on screen the snippets carry it; afterwards they carry a placeholder, because the token
/// is shown once.
struct MCPSetupRows: View {
    let token: String?
    @State private var copiedTool: MCPTool?
    @Environment(\.openURL) private var openURL

    /// Ordered as people meet them: the two chat apps sign in by OAuth and only need the URL;
    /// the editors and command-line tools below take a one-click install or a token snippet.
    enum MCPTool: String, CaseIterable, Identifiable {
        case claude = "Claude"
        case chatGPT = "ChatGPT"
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
        case vsCode = "VS Code"
        case windsurf = "Windsurf"
        case codex = "Codex"
        case geminiCLI = "Gemini CLI"
        case curl = "curl, Grok Bot, scripts"
        var id: String { rawValue }

        /// Rows that need a personal access token in the snippet.
        var needsToken: Bool {
            switch self {
            case .claude, .chatGPT, .claudeCode, .cursor, .vsCode: return false
            case .windsurf, .codex, .geminiCLI, .curl: return true
            }
        }

        /// A page to open after copying, when the tool has one.
        var openLink: (label: String, url: URL)? {
            switch self {
            case .claude: return ("Open Claude connectors", URL(string: "https://claude.ai/settings/connectors")!)
            case .chatGPT: return ("Open ChatGPT settings", URL(string: "https://chatgpt.com/#settings/Connectors")!)
            case .cursor: return ("Add to Cursor", MCPSetupRows.cursorInstallURL)
            case .vsCode: return ("Add to VS Code", MCPSetupRows.vsCodeInstallURL)
            default: return nil
            }
        }
    }

    nonisolated static let serverURL = "https://api.miniti.app/api/mcp"
    nonisolated static let restURL = "https://api.miniti.app/api/v1"

    /// Cursor's install deep link: name plus a base64 JSON config. OAuth handles sign-in.
    nonisolated static var cursorInstallURL: URL {
        let config = Data("{\"url\":\"\(serverURL)\"}".utf8).base64EncodedString()
        return URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=miniti&config=\(config)")!
    }

    /// VS Code's install link: the server config as URL-encoded JSON.
    nonisolated static var vsCodeInstallURL: URL {
        let json = "{\"name\":\"miniti\",\"type\":\"http\",\"url\":\"\(serverURL)\"}"
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json
        return URL(string: "vscode:mcp/install?\(encoded)")!
    }

    static func snippet(for tool: MCPTool, token: String?) -> String {
        let t = token ?? "<token>"
        switch tool {
        case .claude, .chatGPT:
            return serverURL
        case .claudeCode:
            return "claude mcp add --transport http miniti \(serverURL)"
        case .cursor:
            return """
            {
              "mcpServers": {
                "miniti": { "url": "\(serverURL)" }
              }
            }
            """
        case .vsCode:
            return """
            {
              "servers": {
                "miniti": { "type": "http", "url": "\(serverURL)" }
              }
            }
            """
        case .windsurf:
            return """
            {
              "mcpServers": {
                "miniti": {
                  "serverUrl": "\(serverURL)",
                  "headers": { "Authorization": "Bearer \(t)" }
                }
              }
            }
            """
        case .codex:
            return """
            [mcp_servers.miniti]
            url = "\(serverURL)"
            http_headers = { Authorization = "Bearer \(t)" }
            """
        case .geminiCLI:
            return """
            {
              "mcpServers": {
                "miniti": {
                  "httpUrl": "\(serverURL)",
                  "headers": { "Authorization": "Bearer \(t)" }
                }
              }
            }
            """
        case .curl:
            return "curl \(restURL)/meetings -H \"Authorization: Bearer \(t)\""
        }
    }

    static func hint(for tool: MCPTool) -> String {
        switch tool {
        case .claude: return "Settings, Connectors, Add custom connector, paste this URL, Add, then Connect and approve. Signs you in with your miniti email. The same connector works in the Claude desktop app. No token needed."
        case .chatGPT: return "Settings, Connectors, add a custom connector with this URL, then sign in and approve. Needs Pro, Business or Enterprise, or developer mode on Plus. No token needed."
        case .claudeCode: return "Run in a terminal, then type /mcp in Claude Code to sign in. No token needed."
        case .cursor: return "Add to Cursor opens Cursor and installs it; sign in when Cursor asks. Or put the snippet in .cursor/mcp.json."
        case .vsCode: return "Add to VS Code opens VS Code and installs it; sign in when it asks. Or put the snippet in .vscode/mcp.json."
        case .windsurf: return "Add to Windsurf's mcp_config.json. Needs a token."
        case .codex: return "Add to ~/.codex/config.toml. Needs a token."
        case .geminiCLI: return "Add to ~/.gemini/settings.json. Needs a token."
        case .curl: return "Lists your meetings as JSON. Also /meetings/{id}, /meetings/{id}/transcript?format=markdown, /action-items. Needs a token."
        }
    }

    var body: some View {
        ForEach(MCPTool.allCases) { tool in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tool.rawValue)
                    Spacer()
                    if let link = tool.openLink {
                        Button(link.label) { openURL(link.url) }
                    }
                    Button(copiedTool == tool ? "Copied" : "Copy") {
                        MCPSetupRows.copy(MCPSetupRows.snippet(for: tool, token: token))
                        copiedTool = tool
                    }
                }
                Text(MCPSetupRows.hint(for: tool))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MCPSetupRows.snippet(for: tool, token: token))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
            .padding(.vertical, 2)
        }
        if token == nil {
            Text("The rows marked \"needs a token\": make a token and copy the snippet while it is on screen; the token is filled in for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Settings → Cloud → View log: what the engine uploaded, downloaded, changed, deleted or
/// skipped this session, newest first. Titles only, never transcript text.
struct CloudSyncLogView: View {
    @ObservedObject var engine: CloudSyncEngine
    @Environment(\.dismiss) private var dismiss

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cloud log")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Clear") { engine.clearLog() }
                    .disabled(engine.log.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if engine.log.isEmpty {
                Text("Nothing has moved yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(engine.log) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text(CloudSyncLogView.time.string(from: entry.at))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.kind.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: entry.kind))
                                Text(entry.title)
                                    .lineLimit(1)
                            }
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
            Text("This session only. Meeting titles, never transcript text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 360, idealHeight: 480)
    }

    private func color(for kind: CloudSyncEngine.CloudSyncLogEntry.Kind) -> Color {
        switch kind {
        case .uploaded, .downloaded, .updated: return ColorPalette.Status.success
        case .deletedLocally, .deletedInCloud: return ColorPalette.Text.secondary
        case .conflict, .skipped, .paused: return ColorPalette.Status.warning
        case .error: return ColorPalette.Status.error
        case .info: return ColorPalette.Text.secondary
        }
    }
}
