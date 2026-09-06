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
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var isRestoring = false
    @State private var error: String?
    var onRestored: (() -> Void)? = nil

    private var canRestore: Bool {
        !isRestoring && ClientAuthCrypto.normalizeRecoveryKey(input) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore with recovery key")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)

            Text("Enter the key from your other device. It starts with M1 and has eight groups of four characters. This adds the device to that account; your Pro plan on a Mac is restored separately with its license key.")
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
                Button(isRestoring ? "Restoring…" : "Restore") { restore() }
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
            let ok = await appState.restoreManagedAccount(recoveryKey: input)
            isRestoring = false
            if ok {
                onRestored?()
                dismiss()
            } else {
                error = appState.managedEnrollmentError ?? "Could not restore this account."
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
