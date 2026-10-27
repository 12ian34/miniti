import SwiftUI

// MARK: - Managed account UI (shared by macOS and iOS)
//
// The account is identified by its verified email when it has one and by the anonymous
// recovery key as a backup (B6a). The key is shown only here: the one-time "save it" sheet,
// Show and Replace in Settings, Account, and the sign-in field for adding a device.

// MARK: Recovery key sheet

/// Shows the recovery key once and asks the person to confirm they saved it.
struct RecoveryKeySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let recoveryKey: String
    var title: String = "Save your recovery key"
    var explanation: String = "Another way to sign in. Save it somewhere safe, such as your password manager: it signs this account in on a new device if you have no email, or if email is unavailable. It cannot be recovered if lost."
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

            Text("You can show or replace it later in Settings, Account.")
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
        mode == .move ? "Switch account" : "Sign in with a recovery key"
    }

    private var explanation: String {
        switch mode {
        case .restore:
            return "Enter the key from your other device. It starts with M1 and has eight groups of four characters. This signs the device in to that account. A Pro purchase made on a Mac is restored separately with its license key."
        case .move:
            return "Enter the recovery key of the account to switch to. This device keeps its meetings, usage, calendar and CRM connections. If that account has a Pro plan, this device gets it too. It leaves its current account; if that account is then empty, it is closed."
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
                Button(isRestoring ? (mode == .move ? "Switching…" : "Signing in…") : (mode == .move ? "Switch" : "Sign in")) { restore() }
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
                    ?? (mode == .move ? "Could not switch this device." : "Could not sign in to this account.")
            }
        }
    }
}

// MARK: Account section model

/// What Settings, Account shows and offers for one combination of enrolment, email and key
/// state (B6a). Pure value type so the eight states in the plan are tested without a view.
struct AccountSectionModel: Equatable {
    enum KeyState: Equatable {
        case usable
        /// A key failure that may pass: signed actions are disabled, nothing is hidden.
        case temporarilyUnavailable
        /// The key cannot work here and no recovery key can repair it: signed actions are
        /// hidden and the way back is Sign in again.
        case unusable
    }

    enum Action: Equatable {
        case addEmail, changeEmail, resendEmail, removeEmail, retryEmail
        case showKey, replaceKey
        case switchAccount, signInAgain, tryAgain, signOut, deleteAccount
    }

    struct Inputs: Equatable {
        var status: ClientAuthStatus = .notEnrolled
        var emailState: AccountEmailState = .loading
        /// The credential holds a recovery key (false for a device that joined by email).
        var hasLocalRecoveryKey = true
        var keyState: KeyState = .usable
        var isPro = false
        var isMac = true
    }

    /// First line under Your account.
    let emailLine: String
    /// "Verified" beside a verified address.
    let emailBadge: String?
    /// "Replacement pending: address" while a change awaits its link.
    let pendingLine: String?
    let emailActions: [Action]
    let recoveryKeyLine: String
    let recoveryKeyActions: [Action]
    /// The email-joined sentence, or nil.
    let recoveryKeyNote: String?
    /// Shown above the account actions when the key failed.
    let keyNote: String?
    let accountActions: [Action]
    /// True while signed actions are disabled (temporary key failure).
    let signedActionsDisabled: Bool
    let planLine: String
    let restoreTitle: String
    let restoreCaption: String
    let deviceRemovalMessage: String
    let signOutMessage: String

    static let temporarilyUnavailable = "Temporarily unavailable. Try again."

    static func make(_ i: Inputs) -> AccountSectionModel {
        let signedHidden = i.keyState == .unusable
        let disabled = i.keyState == .temporarilyUnavailable

        var emailLine: String
        var badge: String?
        var pendingLine: String?
        var emailActions: [Action] = []
        switch i.emailState {
        case .loading:
            emailLine = "Checking this account's email…"
        case .unavailable(let message):
            emailLine = "Could not check this account's email. \(message)"
            emailActions = [.retryEmail]
        case .loaded(let email):
            if let verified = email.verified {
                emailLine = verified
                badge = "Verified"
                emailActions = [.changeEmail, .removeEmail]
                if let pending = email.pending {
                    pendingLine = "Replacement pending: \(pending)"
                    emailActions = [.resendEmail, .changeEmail, .removeEmail]
                }
            } else if let pending = email.pending {
                emailLine = "Check your email: link sent to \(pending)"
                emailActions = [.resendEmail, .changeEmail]
            } else {
                emailLine = "No email yet"
                emailActions = [.addEmail]
            }
        }
        if signedHidden { emailActions = emailActions.filter { $0 == .retryEmail } }

        let recoveryKeyLine: String
        var recoveryKeyActions: [Action] = []
        var recoveryKeyNote: String?
        if i.hasLocalRecoveryKey {
            recoveryKeyLine = i.status.recoveryKeyAcknowledged ? "Saved" : "Not yet saved"
            recoveryKeyActions = signedHidden ? [.showKey] : [.showKey, .replaceKey]
        } else {
            recoveryKeyLine = "Not on this device"
            recoveryKeyNote = "This device signed in by email, so it does not hold the recovery key. Show it on a device that does, or replace it here; the old key then stops working."
            recoveryKeyActions = signedHidden ? [] : [.replaceKey]
        }

        var keyNote: String?
        var accountActions: [Action]
        switch i.keyState {
        case .usable:
            accountActions = [.switchAccount, .signOut, .deleteAccount]
        case .temporarilyUnavailable:
            keyNote = "This device's sign-in key did not work just now. Try again, or sign in again with your email or recovery key."
            accountActions = [.tryAgain, .signInAgain, .switchAccount, .signOut, .deleteAccount]
        case .unusable:
            keyNote = "This device's sign-in key no longer works here, which happens after a move from another \(i.isMac ? "Mac" : "device"). Sign in again with your email or recovery key; this device keeps its meetings."
            accountActions = [.signInAgain, .signOut]
        }

        // Your account keeps the plan word only; Plan and billing holds the limit, the source
        // and the controls (L3).
        let planLine = i.isPro ? "Pro" : "Free"
        let restoreTitle = i.isMac ? "Restore Pro purchase with a license key" : "Restore App Store purchases"
        let restoreCaption = i.isMac
            ? "This restores a purchase. It does not sign you into an account. Bought Pro already? Sign in to that account first."
            : "This restores a purchase from the App Store. It does not sign you into an account. Bought Pro already? Sign in to that account first."

        return AccountSectionModel(
            emailLine: emailLine,
            emailBadge: badge,
            pendingLine: pendingLine,
            emailActions: emailActions,
            recoveryKeyLine: recoveryKeyLine,
            recoveryKeyActions: recoveryKeyActions,
            recoveryKeyNote: recoveryKeyNote,
            keyNote: keyNote,
            accountActions: accountActions,
            signedActionsDisabled: disabled,
            planLine: planLine,
            restoreTitle: restoreTitle,
            restoreCaption: restoreCaption,
            deviceRemovalMessage: "It can sign back in with the account's email or recovery key. Its meetings stay on it.",
            signOutMessage: "This device can sign back in with the account's email or recovery key. Meetings stored on this device are not affected."
        )
    }

    /// Search targets that live inside the Support details disclosure (L2): opening one
    /// expands the disclosure before the scroll.
    static func revealsSupportDetails(target: String?) -> Bool {
        target == "account.deviceID"
    }

    /// Whether an action sends a signed request (and so is disabled on a temporary failure).
    static func needsSignature(_ action: Action) -> Bool {
        switch action {
        case .addEmail, .changeEmail, .resendEmail, .removeEmail, .replaceKey, .switchAccount, .deleteAccount: return true
        case .retryEmail, .showKey, .signInAgain, .tryAgain, .signOut: return false
        }
    }
}

extension AppState {
    /// The account section's inputs from the live state.
    var accountSectionInputs: AccountSectionModel.Inputs {
        var inputs = AccountSectionModel.Inputs()
        inputs.status = clientAuthStatus
        inputs.emailState = accountEmailState
        inputs.hasLocalRecoveryKey = !managedDeviceHasNoRecoveryKey
        // Permanent failures count whether or not enrolment survives them (a stored recovery
        // key keeps `isEnrolled` true while the coordinator repairs); the person still needs
        // Sign in again and must not be offered signed actions that would fail.
        if clientAuthStatus.keyUnusable || clientAuthStatus.keyPermanentlyUnavailable {
            inputs.keyState = .unusable
        } else if clientAuthStatus.keyTemporarilyUnavailable {
            inputs.keyState = .temporarilyUnavailable
        }
        inputs.isPro = isPro
        #if os(macOS)
        inputs.isMac = true
        #else
        inputs.isMac = false
        #endif
        return inputs
    }

    /// Open Settings, Account on the email row (both platforms).
    func openAccountEmailSettings() {
        jumpToSetting("account.email")
        showSettings = true
    }
}

// MARK: Home card

/// "Keep access to your account" (B6a): shown on Home after the first saved meeting while the
/// account has no verified email and the recovery key is not acknowledged. Not now dismisses
/// it for this account on this installation.
struct AccountAccessCard: View {
    @EnvironmentObject var appState: AppState
    @State private var isPresentingKey = false
    @State private var isHovering = false
    @State private var resendNotice: String?

    private var pendingAddress: String? { appState.accountEmailState.email?.pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: pendingAddress == nil ? "envelope" : "envelope.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorPalette.Accent.green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pendingAddress == nil ? "keep access to your account" : "check your email to finish")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)

                    Text(pendingAddress.map { "a link went to \($0). open it to make that address a way to sign in." }
                         ?? "add an email so you can sign in on another device or recover access if this one stops working. this won't turn on cloud sync.")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    appState.dismissAccessCard()
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
                .help("not now")
                #endif
                .accessibilityLabel("Not now")
            }

            HStack(spacing: 10) {
                if let pendingAddress {
                    Button {
                        Task { @MainActor in
                            let outcome = await appState.addAccountEmail(pendingAddress)
                            switch outcome {
                            case .sent: resendNotice = "sent again"
                            case .staleAccount: resendNotice = nil
                            default: resendNotice = "could not send; try again in a minute"
                            }
                        }
                    } label: {
                        primaryLabel("resend", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .focusable(false)
                    #endif
                    if let resendNotice {
                        Text(resendNotice)
                            .font(.system(size: 11))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                } else {
                    Button {
                        appState.openAccountEmailSettings()
                    } label: {
                        primaryLabel("add email", systemImage: "envelope")
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .focusable(false)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: MinitiDesignSystem.Motion.hoverDuration)) { isHovering = hovering }
                    }
                    #endif

                    if !appState.managedDeviceHasNoRecoveryKey {
                        Button {
                            isPresentingKey = true
                        } label: {
                            Text("use a recovery key instead")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(ColorPalette.Text.secondary)
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .focusable(false)
                        #endif
                    }
                }

                Button {
                    appState.dismissAccessCard()
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

    private func primaryLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .default))
        }
        .foregroundStyle(Color(hex: "09090B"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                .fill(isHovering ? ColorPalette.Accent.green : ColorPalette.Accent.green.opacity(0.78))
        )
    }
}

// MARK: Settings section

/// Settings, Account: Your account, Ways to sign in, Devices, then the destructive actions
/// (B6a). Plan and billing follows it in each platform's Settings view.
struct ManagedAccountSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var revealedKey: String?
    @State private var copied = false
    @State private var isPresentingRestore = false
    @State private var isPresentingMove = false
    @State private var isPresentingEmailJoin = false
    @State private var isPresentingEmailRestore = false
    @State private var isConfirmingReveal = false
    @State private var isConfirmingReplace = false
    @State private var isConfirmingRemoveEmail = false
    @State private var pendingRemoval: ClientAuthDevice?
    @State private var isBusy = false
    @State private var notice: String?
    @State private var isEditingEmail = false
    @State private var emailDraft = ""
    @State private var emailNotice: String?
    @State private var supportDetailsExpanded = false
    @FocusState private var emailFieldFocused: Bool

    private var status: ClientAuthStatus { appState.clientAuthStatus }
    private var model: AccountSectionModel { AccountSectionModel.make(appState.accountSectionInputs) }
    private var accountIsPresent: Bool { status.isEnrolled || status.keyUnusable }

    var body: some View {
        Group {
            if accountIsPresent {
                yourAccountSection
                waysToSignInSection
                devicesSection
            } else {
                Section("Account") {
                    unenrolledRows
                }
                .id("account.recoveryKey")
            }
        }
        .task(id: status.accountID) {
            if status.isEnrolled {
                await appState.loadManagedDevices()
                await appState.refreshAccountEmail(reason: "account settings")
            }
        }
        .onChange(of: appState.pendingSettingsSearchTarget) { _, target in
            if target == "account.email", status.isEnrolled, appState.accountEmailState.email?.verified == nil {
                isEditingEmail = true
                emailFieldFocused = true
            }
            if AccountSectionModel.revealsSupportDetails(target: target) { supportDetailsExpanded = true }
        }
        .onAppear {
            if AccountSectionModel.revealsSupportDetails(target: appState.pendingSettingsSearchTarget) { supportDetailsExpanded = true }
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
        .sheet(isPresented: $isPresentingEmailJoin) {
            EmailSignInSheet(mode: .move, onJoined: { notice = "This device is now on the other account." })
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isPresentingEmailRestore) {
            EmailSignInSheet(mode: .restore)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Show your recovery key on screen?", isPresented: $isConfirmingReveal, titleVisibility: .visible) {
            Button("Show key") { revealedKey = appState.revealRecoveryKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone who sees it can sign in to this account.")
        }
        .confirmationDialog("Replace the recovery key?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
            Button("Replace key") { replaceKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current key stops working at once. Devices already signed in stay signed in. Save the new key somewhere safe.")
        }
        .confirmationDialog("Remove the email from this account?", isPresented: $isConfirmingRemoveEmail, titleVisibility: .visible) {
            Button("Remove email", role: .destructive) { removeEmail() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeEmailMessage)
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
            Text(pendingRemoval?.current == true ? model.signOutMessage : model.deviceRemovalMessage)
        }
    }

    // MARK: Your account

    private var yourAccountSection: some View {
        Section("Your account") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Email")
                    Spacer()
                    if let badge = model.emailBadge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(ColorPalette.Status.success)
                    }
                }
                Text(model.emailLine)
                    .foregroundStyle(model.emailBadge == nil ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let pending = model.pendingLine {
                    Text(pending)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id("account.email")

            HStack {
                Text("Plan")
                Spacer()
                Text(model.planLine)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Support details", isExpanded: $supportDetailsExpanded) {
                detailRow("Account id", status.accountID ?? "none")
                detailRow("Device id", DeviceIdentifier.getOrCreateDeviceId())
                    .id("account.deviceID")
                detailRow("Sign-in key", status.isHardwareBacked ? "Secure Enclave" : "Software")
                detailRow("App", "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
            }
            .font(.callout)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: Ways to sign in

    private var waysToSignInSection: some View {
        Section("Ways to sign in") {
            if let note = model.keyNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.signedActionsDisabled {
                Text(AccountSectionModel.temporarilyUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Email
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Email")
                    Spacer()
                    ForEach(model.emailActions, id: \.self) { action in
                        actionButton(action)
                    }
                }
                if isEditingEmail {
                    HStack {
                        TextField("name@example.com", text: $emailDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($emailFieldFocused)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                            .onSubmit { submitEmail() }
                        Button("Send link") { submitEmail() }
                            .disabled(isBusy || !emailDraft.contains("@"))
                        Button("Cancel") { isEditingEmail = false; emailDraft = ""; emailNotice = nil }
                    }
                    Text("A confirmation link goes to this address. It becomes a way to sign in once you open the link. This does not turn on cloud sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let emailNotice {
                    Text(emailNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Recovery key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recovery key")
                    Spacer()
                    Text(model.recoveryKeyLine)
                        .foregroundStyle(.secondary)
                    if revealedKey != nil {
                        Button("Hide") { revealedKey = nil; copied = false }
                    } else {
                        ForEach(model.recoveryKeyActions, id: \.self) { action in
                            actionButton(action)
                        }
                    }
                }
                .id("account.recoveryKey")
                if let note = model.recoveryKeyNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let revealedKey, !revealedKey.isEmpty {
                    RecoveryKeyDisplay(recoveryKey: revealedKey, copied: $copied)
                        .padding(.vertical, 4)
                }
                Text("Another way to sign in: it signs this account in on a new device if you have no email, or if email is unavailable.\(status.isHardwareBacked ? " This device's sign-in key is protected by the Secure Enclave." : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Account actions
            HStack {
                ForEach(model.accountActions.filter { [.tryAgain, .signInAgain, .switchAccount].contains($0) }, id: \.self) { action in
                    actionButton(action)
                }
            }
            .id("account.move")
            if model.accountActions.contains(.switchAccount) {
                Text("Switch account signs this device in to another account by email or recovery key. It keeps its meetings; if that account has Pro, this device gets it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Devices

    private var devicesSection: some View {
        Section("Devices") {
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
                    if model.accountActions.contains(.deleteAccount) || device.current {
                        // Removal is a signed request; a device whose key cannot sign only offers
                        // its own sign-out (which clears locally).
                        Button(device.current ? "Sign out" : "Remove") { pendingRemoval = device }
                            .disabled(isBusy || (model.signedActionsDisabled && !device.current))
                            .foregroundStyle(ColorPalette.Status.error)
                    }
                }
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionButton(_ action: AccountSectionModel.Action) -> some View {
        let disabled = isBusy || (model.signedActionsDisabled && AccountSectionModel.needsSignature(action))
        switch action {
        case .addEmail:
            Button("Add email") { isEditingEmail = true; emailFieldFocused = true }.disabled(disabled)
        case .changeEmail:
            Button("Change") { isEditingEmail = true; emailFieldFocused = true }.disabled(disabled)
        case .resendEmail:
            Button("Resend") { resendEmail() }.disabled(disabled)
        case .removeEmail:
            Button("Remove") { isConfirmingRemoveEmail = true }.disabled(disabled)
        case .retryEmail:
            Button("Retry") { Task { await appState.refreshAccountEmail(reason: "retry", force: true) } }
        case .showKey:
            Button("Show recovery key") { isConfirmingReveal = true }.disabled(isBusy)
        case .replaceKey:
            Button("Replace recovery key") { isConfirmingReplace = true }.disabled(disabled)
        case .switchAccount:
            Menu("Switch account…") {
                Button("With email…") { isPresentingEmailJoin = true }
                Button("With recovery key…") { isPresentingMove = true }
            }
            .disabled(disabled)
        case .signInAgain:
            Menu("Sign in again…") {
                Button("With email…") { isPresentingEmailRestore = true }
                Button("With recovery key…") { isPresentingRestore = true }
            }
        case .tryAgain:
            Button("Try again") {
                if appState.retrySigning() { notice = "The sign-in key works again." }
            }
        case .signOut, .deleteAccount:
            // Rendered by ManagedAccountDangerSection below Plan and billing (L1).
            EmptyView()
        }
    }

    private var removeEmailMessage: String {
        let keyPart = appState.managedDeviceHasNoRecoveryKey
            ? "This device holds no recovery key, so make sure another device does before removing it."
            : "The recovery key stays a way to sign in."
        return "Every browser signed in with it and every connected app (Claude, ChatGPT) is signed out. \(keyPart)"
    }

    private func submitEmail() {
        guard emailDraft.contains("@") else { return }
        isBusy = true
        emailNotice = nil
        Task { @MainActor in
            let outcome = await appState.addAccountEmail(emailDraft)
            isBusy = false
            switch outcome {
            case .staleAccount:
                isEditingEmail = false
                emailDraft = ""
            case .sent(let address):
                isEditingEmail = false
                emailDraft = ""
                emailNotice = "Check \(address) for the link. It works for 15 minutes."
            case .alreadyVerified:
                isEditingEmail = false
                emailDraft = ""
                emailNotice = "That address is already verified on this account."
            case .inUse:
                emailNotice = "That email is on another miniti account. Use Switch account to sign this device in to it, or remove the email there first."
            case .failed(let message):
                emailNotice = message
            }
        }
    }

    private func resendEmail() {
        guard let pending = appState.accountEmailState.email?.pending else { return }
        isBusy = true
        Task { @MainActor in
            let outcome = await appState.addAccountEmail(pending)
            isBusy = false
            switch outcome {
            case .sent: emailNotice = "Sent again to \(pending)."
            case .staleAccount: emailNotice = nil
            default: emailNotice = "Could not send. Try again in a minute."
            }
        }
    }

    private func removeEmail() {
        isBusy = true
        Task { @MainActor in
            switch await appState.removeAccountEmail() {
            case .removed: emailNotice = nil
            case .failed(let message): emailNotice = message
            case .staleAccount: emailNotice = nil
            }
            isBusy = false
        }
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
            Text(appState.managedEnrollmentError ?? "Managed mode needs an account on this device. miniti creates one automatically; if that failed, retry, or sign in to an account you already have with its email or recovery key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry setup") {
                    Task { await appState.ensureManagedEnrollment(trigger: "settings") }
                }
                Button("Sign in with email…") { isPresentingEmailRestore = true }
                Button("Sign in with recovery key…") { isPresentingRestore = true }
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

    private func replaceKey() {
        isBusy = true
        Task { @MainActor in
            if let key = await appState.rotateManagedRecoveryKey() {
                revealedKey = key
                copied = false
                notice = "Recovery key replaced. Save the new key; the old one no longer works."
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
}


/// Sign out and Delete account, rendered below Plan and billing on both platforms (L1).
struct ManagedAccountDangerSection: View {
    @EnvironmentObject var appState: AppState
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isBusy = false

    @State private var signOutFailure: String?

    private var model: AccountSectionModel { AccountSectionModel.make(appState.accountSectionInputs) }
    private var accountIsPresent: Bool { appState.clientAuthStatus.isEnrolled || appState.clientAuthStatus.keyUnusable }

    var body: some View {
        if accountIsPresent {
            Section {
                if let signOutFailure {
                    Text(signOutFailure)
                        .font(.caption)
                        .foregroundStyle(ColorPalette.Status.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if model.accountActions.contains(.signOut) {
                        Button("Sign out this device") { isConfirmingSignOut = true }
                            .disabled(isBusy)
                    }
                    Spacer()
                    if model.accountActions.contains(.deleteAccount) {
                        Button("Delete account") { isConfirmingDelete = true }
                            .disabled(isBusy || model.signedActionsDisabled)
                            .foregroundStyle(ColorPalette.Status.error)
                    }
                }
                .id("account.delete")
            }
            .confirmationDialog("Sign this device out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(model.signOutMessage)
            }
            .confirmationDialog("Delete this account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every device loses access, and the email and recovery key stop working. This does not cancel a Pro subscription; manage that from the App Store or the Polar customer portal first. Meetings stored on your devices are not deleted.")
            }
        }
    }

    private func signOut() {
        isBusy = true
        Task { @MainActor in
            let ok = await appState.signOutManagedDevice()
            signOutFailure = ok ? nil : appState.managedDevicesError
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


// MARK: Sign in by email (3.0.0)

/// Join an account from its email: miniti sends an approval link to that address, the holder
/// approves it in the browser, and this device joins without anyone typing the recovery key.
struct EmailSignInSheet: View {
    enum Mode { case restore, move }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var linkID: String?
    @State private var isWorking = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?
    var mode: Mode = .restore
    var onJoined: (() -> Void)? = nil

    private var canSend: Bool { !isWorking && linkID == nil && email.contains("@") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .move ? "Join another account by email" : "Sign in with email")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)
            Text(mode == .move
                 ? "Enter the email on the account to join. miniti sends it a link; open it anywhere and press Approve. This device keeps its meetings, usage and connections and joins that account."
                 : "Enter the email on your account. miniti sends it a link; open it anywhere and press Approve, and this device joins the account.")
                .font(.system(size: 12))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .disabled(linkID != nil)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
            if linkID != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                    Text("Waiting for you to approve the link. It works for 15 minutes.")
                        .font(.system(size: 12))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { pollTask?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send link") { send() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 440)
        .onDisappear { pollTask?.cancel() }
    }

    private func send() {
        isWorking = true
        error = nil
        Task { @MainActor in
            guard let id = await appState.startEmailSignIn(email: email) else {
                error = appState.managedEnrollmentError ?? "Could not send the link."
                isWorking = false
                return
            }
            linkID = id
            isWorking = false
            poll(id)
        }
    }

    private func poll(_ id: String) {
        pollTask = Task { @MainActor in
            var lastCheckFailed = false
            for _ in 0..<300 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                let status = await appState.emailSignInStatus(linkID: id)
                switch status {
                case .unreachable:
                    // The link may be fine; say the check failed rather than calling it expired.
                    lastCheckFailed = true
                    error = "Could not check yet. Still waiting for your approval."
                    continue
                case .pending:
                    if lastCheckFailed { error = nil; lastCheckFailed = false }
                    continue
                case .expired:
                    error = "The link expired or was refused. Send a new one."
                    linkID = nil
                    return
                case .approved:
                    isWorking = true
                    if await appState.joinAccount(approvedLinkID: id) {
                        onJoined?()
                        dismiss()
                    } else {
                        error = appState.managedEnrollmentError ?? "Could not join the account."
                        linkID = nil
                    }
                    isWorking = false
                    return
                }
            }
            error = lastCheckFailed ? "miniti's servers could not be reached. Send a new link when you are back online." : "The link expired. Send a new one."
            linkID = nil
        }
    }
}
