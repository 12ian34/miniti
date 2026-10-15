import SwiftUI
import SwiftData

/// Settings → Cloud (3.0.0): the switch, status, web sign-in, connected apps, API tokens, and
/// delete. One view on macOS; the sections are reused by the iOS settings list.
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
#endif

struct CloudSettingsSections: View {
    @EnvironmentObject private var appState: AppState
    /// Observed directly: `AppState` holds the engine as a `let`, so its phase, last-synced
    /// time and skipped count would otherwise never refresh while the tab is open.
    @ObservedObject var engine: CloudSyncEngine
    @State private var isPresentingEnable = false
    @State private var isConfirmingDelete = false
    @State private var isBusy = false
    @State private var notice: String?
    @State private var tokens: [CloudToken] = []
    @State private var connectedApps: [CloudConnectedApp] = []
    @State private var email: String?
    @State private var pendingEmail: String?
    @State private var newEmail = ""
    @State private var newTokenName = ""
    @State private var revealedToken: String?
    @State private var copiedToken = false
    @State private var loadedAccount: String?

    var body: some View {
        if appState.appMode == .byok {
            Section("Cloud") {
                Text("Cloud needs the managed plan.")
                    .foregroundStyle(.secondary)
            }
            .id("cloud.sync")
        } else {
            cloudSection
            if appState.cloudSyncEnabled {
                statusSection
                signInSection
                apiSection
                deleteSection
            }
        }
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
            Text("miniti keeps a copy and can read it, so your other devices, your tools and you on the web can too. Off by default.")
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
            CloudEnableSheet(onTurnOn: { emailToAdd in
                appState.setCloudSyncEnabled(true)
                if let emailToAdd { addEmail(emailToAdd) }
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
        }
        .id("cloud.status")
        .task(id: appState.clientAuthStatus.accountID) { await loadIfNeeded() }
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
            if let email {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(email).foregroundStyle(.secondary)
                    Button("Remove") { removeEmail() }.disabled(isBusy)
                }
                Text("Sign in at api.miniti.app/signin with a link sent to this address, and connect tools like Claude. Removing it signs every browser and connected app out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let pendingEmail {
                    Text("Check \(pendingEmail) for a confirmation link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Email for web sign-in", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Add") { addEmail(newEmail) }
                        .disabled(isBusy || !newEmail.contains("@"))
                }
                Text("Optional. Needed to sign in on the web and to connect tools like Claude. It never adds a device by itself; that still needs your recovery key or an approval from a signed-in device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !connectedApps.isEmpty {
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
                .id("cloud.connected")
            }
        }
        .id("cloud.signin")
    }

    private var apiSection: some View {
        Section("API access") {
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
            Text("Tokens read your meetings through the REST API and the MCP server. Claude Code: claude mcp add --transport http miniti https://api.miniti.app/api/mcp --header \"Authorization: Bearer <token>\". Claude.ai and ChatGPT connectors use web sign-in instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .id("cloud.tokens")
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
        async let emailState = try? api.cloudEmail()
        tokens = await tokenList ?? []
        connectedApps = await appList ?? []
        if let state = await emailState {
            email = state.email
            pendingEmail = state.pending
        }
    }

    private func addEmail(_ address: String) {
        guard let api = appState.minitiAPIService else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await api.setCloudEmail(trimmed)
                pendingEmail = trimmed
                newEmail = ""
                notice = nil
            } catch CloudSyncError.server(let code, _) where code == "email_in_use" {
                notice = "That email is on another account. Move this device to it from Settings, Account."
            } catch {
                notice = "Could not send the confirmation link."
            }
        }
    }

    private func removeEmail() {
        guard let api = appState.minitiAPIService else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            if (try? await api.removeCloudEmail()) != nil {
                email = nil
                connectedApps = []
            } else {
                notice = "Could not remove the email."
            }
        }
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

/// The one sheet shown when the switch is turned on: what uploads, the plain sentence about
/// miniti reading the copy, and an optional email.
struct CloudEnableSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onTurnOn: (String?) -> Void
    @State private var email = ""
    @State private var meetingCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep your meetings in the cloud")
                .font(.title3.weight(.semibold))
            Text(meetingCount.map { "\($0) finished meeting\($0 == 1 ? "" : "s") on this device will upload, and everything your other devices hold will come here." } ?? "Your finished meetings will upload, and everything your other devices hold will come here.")
            Text("miniti keeps a copy and can read it, so your other devices, your tools and you on the web can too. Meetings recorded in private mode stay off the cloud.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Email for web sign-in (optional)", text: $email)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                Text("Add an email to sign in on the web and connect tools like Claude. You can skip this and add it later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Turn on") {
                    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    onTurnOn(trimmed.contains("@") ? trimmed : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 440)
        .onAppear {
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.endTime != nil && $0.syncExcluded == false })
            meetingCount = appState.cloudFetchMeetings(descriptor)?.count
        }
    }
}
