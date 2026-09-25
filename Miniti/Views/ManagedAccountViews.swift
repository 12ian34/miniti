import SwiftUI

// MARK: - Managed account UI (shared by macOS and iOS)
//
// The anonymous recovery key is the account. These views are the only places it is ever
// shown: the one-time "save it" sheet, the reveal/rotate controls in Settings → Account &
// Plan, and the restore field for adding a device. Everything else is silent.

// MARK: Recovery key sheet

/// Shows the recovery key once and asks the person to confirm they saved it.
struct RecoveryKeySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let recoveryKey: String
    var title: String = "Save your recovery key"
    var explanation: String = "This key is your Miniti account. It is the only way to add another device or come back after a wipe, and it cannot be recovered if lost. Keep it in your password manager."
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)

            Text(explanation)
                .font(.system(size: 12))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            RecoveryKeyDisplay(recoveryKey: recoveryKey, copied: $copied)

            Toggle(isOn: $saved) {
                Text("I have saved this recovery key somewhere safe.")
                    .font(.system(size: 12))
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif

            Text("You can reveal or rotate it later in Settings → Account & Plan.")
                .font(.system(size: 11))
                .foregroundStyle(ColorPalette.Text.dim)

            HStack {
                Spacer()
                Button("Continue") {
                    appState.acknowledgeRecoveryKey()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!saved)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #endif
    }
}

/// The key in a selectable, copyable block.
struct RecoveryKeyDisplay: View {
    let recoveryKey: String
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recoveryKey)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.primary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .fill(ColorPalette.Background.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .stroke(ColorPalette.Border.light, lineWidth: 1)
                )
                .accessibilityLabel("Recovery key")

            Button(copied ? "Copied" : "Copy") {
                copyToPasteboard(recoveryKey)
                copied = true
            }
            .font(.system(size: 12))
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: Restore sheet

/// Attach this device to an existing account by typing its recovery key.
struct RestoreRecoveryKeySheet: View {
    /// `.restore` enrolls an unenrolled device; `.move` re-homes an enrolled one
    /// (`POST /api/auth/account/attach`) without signing it out.
    enum Mode { case restore, move }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var isRestoring = false
    @State private var error: String?
    var mode: Mode = .restore
    var onRestored: (() -> Void)? = nil

    private var title: String {
        mode == .move ? "Move this device to another account" : "Restore with recovery key"
    }

    private var explanation: String {
        switch mode {
        case .restore:
            return "Enter the key from your other device. It starts with M1 and has eight groups of four characters. This adds the device to that account; your Pro plan on a Mac is restored separately with its license key."
        case .move:
            return "Enter the recovery key of the account to join. This device keeps its meetings, usage, calendar, and CRM connections. If that account has a Pro plan, this device gets it too. It leaves its current account; if that account is then empty, it is closed."
        }
    }

    private var canRestore: Bool {
        !isRestoring && ClientAuthCrypto.normalizeRecoveryKey(input) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)

            Text(explanation)
                .font(.system(size: 12))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("M1-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $input)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
                .onSubmit { if canRestore { restore() } }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isRestoring ? (mode == .move ? "Moving…" : "Restoring…") : (mode == .move ? "Move" : "Restore")) { restore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRestore)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #endif
    }

    private func restore() {
        isRestoring = true
        error = nil
        Task { @MainActor in
            let ok = mode == .move
                ? await appState.attachManagedDevice(recoveryKey: input)
                : await appState.restoreManagedAccount(recoveryKey: input)
            isRestoring = false
            if ok {
                onRestored?()
                dismiss()
            } else {
                error = appState.managedEnrollmentError
                    ?? (mode == .move ? "Could not move this device." : "Could not restore this account.")
            }
        }
    }
}

// MARK: Home nudge

/// Shown on Home until the person has confirmed they saved the recovery key.
struct RecoveryKeyNudgeCard: View {
    @EnvironmentObject var appState: AppState
    @State private var isPresentingKey = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorPalette.Accent.green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("save your recovery key")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)

                    Text("it is your account: keep it to add another device or come back after a wipe.")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    appState.snoozeRecoveryKeyNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .focusable(false)
                .help("remind me next time")
                #endif
                .accessibilityLabel("Remind me next time")
            }

            HStack(spacing: 10) {
                Button {
                    isPresentingKey = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 10, weight: .semibold))
                        Text("show key")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(Color(hex: "09090B"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovering ? ColorPalette.Accent.green : ColorPalette.Accent.green.opacity(0.78))
                    )
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .focusable(false)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
                #endif

                Button {
                    appState.snoozeRecoveryKeyNotice()
                } label: {
                    Text("not now")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .focusable(false)
                #endif
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                .fill(ColorPalette.Background.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                .stroke(ColorPalette.Border.primary, lineWidth: 1)
        )
        .sheet(isPresented: $isPresentingKey) {
            if let key = appState.revealRecoveryKey() {
                RecoveryKeySheet(recoveryKey: key)
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

// MARK: Settings section

/// Settings → Account & Plan: the anonymous account behind managed mode.
struct ManagedAccountSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var revealedKey: String?
    @State private var copied = false
    @State private var isPresentingRestore = false
    @State private var isPresentingMove = false
    @State private var isConfirmingReveal = false
    @State private var isConfirmingRotate = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var pendingRemoval: ClientAuthDevice?
    @State private var isBusy = false
    @State private var notice: String?

    private var status: ClientAuthStatus { appState.clientAuthStatus }

    var body: some View {
        Section("Account") {
            if status.isEnrolled {
                enrolledRows
            } else {
                unenrolledRows
            }
        }
        .id("account.recoveryKey")
        .task(id: status.isEnrolled) {
            if status.isEnrolled { await appState.loadManagedDevices() }
        }
        .sheet(isPresented: $isPresentingRestore) {
            RestoreRecoveryKeySheet()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isPresentingMove) {
            RestoreRecoveryKeySheet(mode: .move, onRestored: { notice = "This device is now on the other account." })
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Show your recovery key on screen?", isPresented: $isConfirmingReveal, titleVisibility: .visible) {
            Button("Show key") { revealedKey = appState.revealRecoveryKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone who sees it can add devices to this account.")
        }
        .confirmationDialog("Generate a new recovery key?", isPresented: $isConfirmingRotate, titleVisibility: .visible) {
            Button("Rotate key") { rotate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current key stops working immediately. Your devices stay signed in. Save the new key.")
        }
        .confirmationDialog("Sign this device out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need the recovery key to use managed mode on this device again. Meetings stored on this device are not affected.")
        }
        .confirmationDialog("Delete this account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every device loses access and the recovery key stops working. This does not cancel a Pro subscription; manage that from the App Store or the Polar customer portal first. Meetings stored on your devices are not deleted.")
        }
        .confirmationDialog(
            pendingRemoval?.current == true ? "Sign this device out?" : "Remove this device?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(pendingRemoval?.current == true ? "Sign out" : "Remove", role: .destructive) {
                if let device = pendingRemoval { remove(device) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will need the recovery key to sign back in.")
        }
    }

    @ViewBuilder
    private var enrolledRows: some View {
        HStack {
            Text("Account")
            Spacer()
            Text(status.accountID.map { String($0.prefix(12)) + "…" } ?? "—")
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
        }

        HStack {
            Text("Recovery key")
            Spacer()
            if revealedKey != nil {
                Button("Hide") { revealedKey = nil; copied = false }
            } else {
                Button("Reveal") { isConfirmingReveal = true }
                    .disabled(isBusy)
                Button("Rotate") { isConfirmingRotate = true }
                    .disabled(isBusy)
            }
        }
        if let revealedKey {
            RecoveryKeyDisplay(recoveryKey: revealedKey, copied: $copied)
                .padding(.vertical, 4)
        }
        Text("This key is your account. Use it to add another device or restore after a wipe. \(status.isHardwareBacked ? "This device's key is protected by the Secure Enclave." : "")")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Text("Devices")
            Spacer()
            Text("\(appState.managedDevices.count) / \(status.deviceCap ?? 5)")
                .foregroundStyle(.secondary)
        }
        .id("account.devices")
        if let error = appState.managedDevicesError {
            Text(error)
                .font(.caption)
                .foregroundStyle(ColorPalette.Status.error)
        }
        ForEach(appState.managedDevices) { device in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceTitle(device))
                    Text(deviceSubtitle(device))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(device.current ? "Sign out" : "Remove") { pendingRemoval = device }
                    .disabled(isBusy)
                    .foregroundStyle(ColorPalette.Status.error)
            }
        }

        if let notice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("Move this device to another account…") { isPresentingMove = true }
            .disabled(isBusy)
            .id("account.move")
        Text("Bought Pro on another Mac? Move this device onto that account and it shares the plan.")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Button("Sign out this device") { isConfirmingSignOut = true }
                .disabled(isBusy)
            Spacer()
            Button("Delete account") { isConfirmingDelete = true }
                .disabled(isBusy)
                .foregroundStyle(ColorPalette.Status.error)
        }
        .id("account.delete")
    }

    @ViewBuilder
    private var unenrolledRows: some View {
        if appState.isEnrollingManagedDevice {
            HStack(spacing: 8) {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
                Text("Setting up this device…")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(appState.managedEnrollmentError ?? "Managed mode needs an account on this device. Miniti creates one automatically; if that failed, retry or restore with a recovery key from another device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry setup") {
                    Task { await appState.ensureManagedEnrollment(trigger: "settings") }
                }
                Button("Restore with recovery key…") { isPresentingRestore = true }
            }
        }
    }

    private func deviceTitle(_ device: ClientAuthDevice) -> String {
        let name = device.label ?? String(device.installationID.prefix(8))
        return device.current ? "\(name) · this device" : name
    }

    private func deviceSubtitle(_ device: ClientAuthDevice) -> String {
        var parts: [String] = []
        if let platform = device.platform { parts.append(platform) }
        if let version = device.appVersion { parts.append(version) }
        if let seen = device.lastAuthAt, let date = ISO8601DateFormatter().date(from: seen) {
            parts.append("seen \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private func rotate() {
        isBusy = true
        Task { @MainActor in
            if let key = await appState.rotateManagedRecoveryKey() {
                revealedKey = key
                copied = false
                notice = "Recovery key rotated. Save the new key."
            } else {
                notice = appState.managedEnrollmentError
            }
            isBusy = false
        }
    }

    private func remove(_ device: ClientAuthDevice) {
        isBusy = true
        Task { @MainActor in
            _ = await appState.removeManagedDevice(installationID: device.installationID)
            isBusy = false
        }
    }

    private func signOut() {
        isBusy = true
        Task { @MainActor in
            await appState.signOutManagedDevice()
            isBusy = false
        }
    }

    private func deleteAccount() {
        isBusy = true
        Task { @MainActor in
            _ = await appState.deleteManagedAccount()
            isBusy = false
        }
    }
}


// MARK: - Calendar meeting filters (shared by macOS and iOS Settings)

/// Settings → Calendar → Meeting filters: which calendar events count as meetings,
/// with a preview of the coming week so the rules can be judged before trusting them.
/// Reads and writes `AppState.calendarMeetingFilters`; a change re-applies to the
/// upcoming list immediately without a network call.
struct CalendarMeetingFiltersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var newPrefix = ""
    @State private var prefixMessage: String?
    @State private var previewRows: [AppState.CalendarFilterPreviewRow]?
    @State private var previewError: String?
    @State private var isLoadingPreview = false

    private var filters: Binding<MinitiAPIService.CalendarMeetingFilterPreferences> {
        $appState.calendarMeetingFilters
    }

    var body: some View {
        Section("Meeting filters") {
            Text("Events that are not meetings are hidden from upcoming meetings, so they never trigger a reminder, an auto-start countdown, or the next-meeting prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Skip out of office", isOn: filters.skipOutOfOffice)
            Toggle("Skip focus time", isOn: filters.skipFocusTime)
            Toggle("Skip working location", isOn: filters.skipWorkingLocation)
            Toggle("Skip birthdays", isOn: filters.skipBirthdays)
            Toggle("Skip all-day events", isOn: filters.skipAllDay)
            Toggle("Skip events you declined", isOn: filters.skipDeclined)
            Toggle("Skip events with no guests or meeting link", isOn: filters.skipWithoutGuestsOrLink)

            Text("Skip titles that start with")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(filters.wrappedValue.titlePrefixes, id: \.self) { prefix in
                HStack {
                    Text(prefix)
                    Spacer()
                    Button(role: .destructive) {
                        removePrefix(prefix)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(prefix)")
                }
            }
            HStack {
                TextField("Add a title prefix (example: gym)", text: $newPrefix)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { addPrefix() }
                Button("Add") { addPrefix() }
                    .disabled(newPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let prefixMessage {
                Text(prefixMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(isLoadingPreview ? "Loading…" : "Preview next 7 days") { loadPreview() }
                    .disabled(isLoadingPreview || !appState.isGoogleCalendarConnected)
                Spacer()
                Button("Restore defaults") {
                    appState.calendarMeetingFilters = .defaults
                    prefixMessage = nil
                    refreshPreviewIfLoaded()
                }
                .disabled(appState.calendarMeetingFilters == .defaults)
            }
            if !appState.isGoogleCalendarConnected {
                Text("Connect Google Calendar to preview the week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let previewError {
                Text(previewError)
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Status.error)
            }
            if let previewRows {
                previewList(previewRows)
            }
        }
        .id("integrations.meetingFilters")
        .onChange(of: appState.calendarMeetingFilters) { _, _ in
            refreshPreviewIfLoaded()
        }
    }

    @ViewBuilder
    private func previewList(_ rows: [AppState.CalendarFilterPreviewRow]) -> some View {
        let skipped = rows.filter { $0.skipReason != nil }.count
        Text(rows.isEmpty
             ? "Nothing on the calendar in the next 7 days."
             : "\(rows.count) events in the next 7 days, \(skipped) skipped.")
            .font(.caption)
            .foregroundStyle(.secondary)
        ForEach(rows) { row in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: row.skipReason == nil ? "checkmark.circle" : "minus.circle")
                    .foregroundStyle(row.skipReason == nil ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .lineLimit(1)
                        .foregroundStyle(row.skipReason == nil ? ColorPalette.Text.primary : ColorPalette.Text.muted)
                    Text(previewSubtitle(row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(row.title), \(previewSubtitle(row))")
        }
    }

    private func previewSubtitle(_ row: AppState.CalendarFilterPreviewRow) -> String {
        let when: String
        if let start = row.start {
            when = row.isAllDay
                ? start.formatted(date: .abbreviated, time: .omitted)
                : start.formatted(date: .abbreviated, time: .shortened)
        } else {
            when = "unscheduled"
        }
        if let reason = row.skipReason {
            return "\(when) · skipped: \(reason.label)"
        }
        return "\(when) · meeting"
    }

    private func addPrefix() {
        let cleaned = MinitiAPIService.CalendarMeetingFilterPreferences.normalizedPrefixes([newPrefix]).first
        guard let cleaned else {
            prefixMessage = "Type a word or phrase first."
            return
        }
        var updated = appState.calendarMeetingFilters
        if updated.titlePrefixes.contains(cleaned) {
            prefixMessage = "“\(cleaned)” is already in the list."
            return
        }
        guard updated.titlePrefixes.count < MinitiAPIService.CalendarMeetingFilterPreferences.maxTitlePrefixes else {
            prefixMessage = "The list is full (\(MinitiAPIService.CalendarMeetingFilterPreferences.maxTitlePrefixes)). Remove one first."
            return
        }
        updated.titlePrefixes.append(cleaned)
        appState.calendarMeetingFilters = updated
        newPrefix = ""
        prefixMessage = nil
    }

    private func removePrefix(_ prefix: String) {
        var updated = appState.calendarMeetingFilters
        updated.titlePrefixes.removeAll { $0 == prefix }
        appState.calendarMeetingFilters = updated
        prefixMessage = nil
    }

    private func loadPreview() {
        isLoadingPreview = true
        previewError = nil
        Task { @MainActor in
            do {
                previewRows = try await appState.previewCalendarMeetingFilters()
            } catch {
                previewError = "Could not load the calendar: \(error.localizedDescription)"
            }
            isLoadingPreview = false
        }
    }

    /// The preview is a pure function of fetched events and the filters, so a filter
    /// change re-evaluates the already loaded rows through one more fetch only when
    /// a preview is showing.
    private func refreshPreviewIfLoaded() {
        guard previewRows != nil, !isLoadingPreview else { return }
        loadPreview()
    }
}
