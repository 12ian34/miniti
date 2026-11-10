import SwiftUI
import AVFoundation

struct PurchaseReturnStatusView: View {
    @ObservedObject var controller: PurchaseReturnController
    var body: some View {
        if let message = controller.state.message {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                Text(message)
                switch controller.state {
                case .checking: ProgressView().controlSize(.small)
                case .retry, .signIn: Button("Retry") { controller.retry() }
                default: EmptyView()
                }
            }
        }
    }
}

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
    @Environment(\.readingMetrics) private var readingMetrics
    let recoveryKey: String
    var title: String = "Save your recovery key"
    var explanation: String = "Another way to sign in. Save it somewhere safe, such as your password manager: it signs this account in on a new device if you have no email, or if email is unavailable. It cannot be recovered if lost."
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            #if os(iOS)
            ScrollView { readingContent.frame(maxWidth: .infinity, alignment: .leading) }
                .accessibilityIdentifier("account.recoveryKey.scroll")
            #else
            readingContent
            #endif
            HStack {
                Spacer()
                Button {
                    appState.acknowledgeRecoveryKey()
                    dismiss()
                } label: {
                    Text("Continue")
                        #if os(iOS)
                        .fixedSize(horizontal: false, vertical: true)
                        .minitiMinimumControlTarget()
                        #endif
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!saved)
                .accessibilityIdentifier("account.recoveryKey.continue")
            }
        }
        .padding(MinitiDesignSystem.Spacing.page)
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
        .modifier(AccountUITestReadingScopeProbe(name: "saveRecovery", alignment: .topLeading))
    }

    private var readingContent: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            Text(title)
                .accessibilityIdentifier("account.recoveryKey.heading")
                .font(.system(size: readingMetrics.dialogHeadingSize, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .font(.system(size: readingMetrics.dialogBodySize))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            RecoveryKeyDisplay(recoveryKey: recoveryKey, copied: $copied)

            Toggle(isOn: $saved) {
                Text("I have saved this recovery key somewhere safe.")
                    .font(.system(size: readingMetrics.dialogBodySize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .accessibilityIdentifier("account.recoveryKey.saved")

            Text("You can show or replace it later in Settings, Account.")
                .font(.system(size: readingMetrics.dialogBodySize))
                .foregroundStyle(ColorPalette.Text.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The key in a selectable, copyable block.
struct RecoveryKeyDisplay: View {
    @Environment(\.readingMetrics) private var readingMetrics
    let recoveryKey: String
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
            Text(recoveryKey)
                .font(.system(size: readingMetrics.recoveryKeySize, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
                .accessibilityIdentifier("account.recoveryKey.value")

            Button {
                copyToPasteboard(recoveryKey)
                copied = true
            } label: {
                Text(copied ? "Copied" : "Copy")
                    .font(.system(size: readingMetrics.dialogBodySize))
                    #if os(iOS)
                    .fixedSize(horizontal: false, vertical: true)
                    .minitiMinimumControlTarget()
                    #endif
            }
            .accessibilityIdentifier("account.recoveryKey.copy")
        }
    }

    private func copyToPasteboard(_ text: String) {
        MinitiPasteboard.copy(text)
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
    @Environment(\.readingMetrics) private var readingMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var stacksActions: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            #if os(iOS)
            ScrollViewReader { proxy in
                ScrollView {
                    formContent.frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("account.restore.scroll")
                .onChange(of: error) { _, message in
                    if message != nil { proxy.scrollTo("account.restore.error", anchor: .bottom) }
                }
            }
            #else
            formContent
            #endif
            actions
        }
        .padding(MinitiDesignSystem.Spacing.page)
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            Text(title)
                .accessibilityIdentifier("account.restore.heading")
                .font(.system(size: readingMetrics.dialogHeadingSize, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .accessibilityIdentifier("account.restore.explanation")
                .font(.system(size: readingMetrics.dialogBodySize))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("M1-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $input)
                .accessibilityIdentifier("account.restore.key")
                .font(.system(size: readingMetrics.transcriptBodySize, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
                .onSubmit { if canRestore { restore() } }

            if let error {
                Text(error)
                    .accessibilityIdentifier("account.restore.error")
                    .id("account.restore.error")
                    .font(.system(size: readingMetrics.dialogBodySize))
                    .foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        let layout = stacksActions
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control))
            : AnyLayout(HStackLayout())
        return layout {
            Button { dismiss() } label: { actionLabel("Cancel") }
                .accessibilityIdentifier("account.restore.cancel")
                .keyboardShortcut(.cancelAction)
            if !stacksActions { Spacer() }
            Button { restore() } label: {
                actionLabel(isRestoring ? (mode == .move ? "Switching…" : "Signing in…") : (mode == .move ? "Switch" : "Sign in"))
            }
            .accessibilityIdentifier("account.restore.submit")
            .keyboardShortcut(.defaultAction)
            .disabled(!canRestore)
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String) -> some View {
        #if os(iOS)
        Text(title)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .minitiMinimumControlTarget()
        #else
        Text(title)
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

}

// MARK: Home card

/// Explicit first-use and signed-out choices shared by onboarding, Home and Account.
/// Cancellation never enrolls; onboarding advances only after a deliberate choice.
struct ManagedAccessChoiceCard: View {
    var onContinued: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @State private var signIn = false
    @State private var recovery = false
    @State private var confirmReset = false
    @State private var isContinuing = false

    var body: some View {
        VStack(spacing: MinitiDesignSystem.Spacing.section) {
            VStack(spacing: MinitiDesignSystem.Spacing.small) {
                Text("your account")
                    .font(.headline)
                    .foregroundStyle(ColorPalette.Text.primary)
                Text(appState.managedAccessIssue ?? appState.managedEnrollmentError ?? "Keep your plan across devices. Email is optional.")
                .font(.callout)
                .foregroundStyle(ColorPalette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account.setupMessage")
            }
            VStack(spacing: MinitiDesignSystem.Spacing.standard) { choices }
            .disabled(isContinuing || appState.isEnrollingManagedDevice)
            if isContinuing || appState.isEnrollingManagedDevice {
                HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                    ProgressView().controlSize(.small)
                    Text("Setting up your account...")
                        .font(.callout)
                        .foregroundStyle(ColorPalette.Text.secondary)
                }
                .accessibilityIdentifier("account.setupProgress")
            }
            if onContinued != nil, appState.canContinueSetupOffline {
                Button { onContinued?() } label: { accountAction("continue setup offline") }
                    .accessibilityLabel("Continue setup offline")
                    .accessibilityIdentifier("account.continueOffline")
                Text("You can finish setup now. Managed recording needs a connection.")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.Text.muted)
            }
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.center)
        .frame(maxWidth: MinitiDesignSystem.HomeSetup.actionColumnWidth)
        .padding(.bottom, MinitiDesignSystem.Spacing.page)
        .minitiSheet(isPresented: $signIn) {
            VStack {
                if recovery {
                    RestoreRecoveryKeySheet(onRestored: onContinued)
                        .modifier(AccountUITestReadingScopeProbe(name: "accessRecovery", alignment: .topLeading))
                } else {
                    EmailSignInSheet(onJoined: onContinued)
                        .modifier(AccountUITestReadingScopeProbe(name: "accessEmail", alignment: .topLeading))
                    Button { recovery = true } label: {
                        Text("Use a recovery key")
                            #if os(iOS)
                            .fixedSize(horizontal: false, vertical: true)
                            .minitiMinimumControlTarget()
                            #endif
                    }
                    .padding(.bottom)
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        }
        .alert("Set up this device again?", isPresented: $confirmReset) {
            Button("Set up this device again", role: .destructive) {
                continueAnonymously(resetUnreadable: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the saved sign-in on this device. Your local meetings stay here. Sign in with your email or recovery key to keep your existing account.")
        }
    }

    @ViewBuilder private var choices: some View {
        Button { recovery = false; signIn = true } label: { accountAction("sign in") }
            .accessibilityLabel("Sign in")
            .accessibilityIdentifier("account.signIn")
        if appState.enrollmentRetryAt != nil && !appState.needsManagedAccessChoice {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button { Task { await appState.ensureManagedEnrollment(trigger: "settings") } } label: { accountAction("retry setup") }
                    .accessibilityLabel("Retry setup")
                    .disabled(appState.isEnrollingManagedDevice || (appState.enrollmentRetryAt ?? .distantPast) > context.date)
                    .accessibilityIdentifier("account.retrySetup")
            }
        } else if appState.managedAccessIssue != nil {
            Button { Task { await appState.retryManagedAccess() } } label: { accountAction("try again") }
                .accessibilityLabel("Try again")
            if appState.clientAuthManager.canResetUnreadableCredentialByChoice {
                Button { confirmReset = true } label: { accountAction("set up this device again") }
                    .accessibilityLabel("Set up this device again")
            }
        } else {
            Button { continueAnonymously() } label: { accountAction("continue without signing in") }
                .accessibilityLabel("Continue without signing in")
                .accessibilityIdentifier("account.continueAnonymous")
                .disabled(appState.isEnrollingManagedDevice)
        }
    }

    private func accountAction(_ title: String) -> some View {
        MinitiControlLabel(role: .secondary, height: nil, horizontalPadding: MinitiDesignSystem.Spacing.section) {
            Text(title)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, MinitiDesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity, minHeight: MinitiDesignSystem.Control.minimumIconHitSize)
        }
    }

    private func continueAnonymously(resetUnreadable: Bool = false) {
        guard !isContinuing else { return }
        isContinuing = true
        Task {
            defer { isContinuing = false }
            guard await appState.continueWithoutSigningIn(resetUnreadable: resetUnreadable) else { return }
            if let onContinued { onContinued() }
            else { await appState.refreshUsage() }
        }
    }
}

// MARK: Optional Home setup

enum HomeSetupStep: String, CaseIterable, Identifiable {
    case readiness, account, calendar, transcription, files, folders
    var id: String { rawValue }
    var documentation: MinitiDocumentationTopic {
        switch self {
        case .readiness: return .permissions
        case .account: return .account
        case .calendar: return .calendar
        case .transcription: return .transcription
        case .files: return .exports
        case .folders: return .folders
        }
    }
    var title: String {
        switch self {
        case .readiness: return "recording access"
        case .account: return "claim your account"
        case .calendar: return "calendar"
        case .transcription: return "audio processing"
        case .files: return "meeting files"
        case .folders: return "organise your meetings"
        }
    }
}

struct HomeSetupItem: Identifiable {
    enum Status { case todo, waiting, complete, skipped }
    let step: HomeSetupStep
    let status: Status
    var id: HomeSetupStep { step }
    var reviewed: Bool { status == .complete || status == .skipped }
    // Completed prerequisites still count toward progress, but do not occupy Home.
    var isRelevantOnHome: Bool {
        !((step == .readiness || step == .calendar) && status == .complete)
    }
    var statusLabel: String {
        switch status {
        case .todo: return "optional"
        case .waiting: return step == .readiness ? "checking access" : "check email"
        case .complete: return "configured"
        case .skipped: return "not now"
        }
    }
}

enum HomeSetupPolicy {
    static func items(managed: Bool, enrolled: Bool, email: AccountEmailState, recoverySaved: Bool,
                      accountDismissed: Bool, calendarConnected: Bool, calendarDeferred: Bool, calendarKnown: Bool = true,
                      localAvailable: Bool, localChosen: Bool, localReviewed: Bool, skipped: Set<String>,
                      filesAvailable: Bool = false, filesConfigured: Bool = false, microphoneGranted: Bool? = nil,
                      microphoneRequired: Bool = false, foldersAvailable: Bool = false, foldersReviewed: Bool = false) -> [HomeSetupItem] {
        var items: [HomeSetupItem] = []
        if microphoneRequired || microphoneGranted != nil {
            items.append(.init(step: .readiness, status: microphoneGranted.map { $0 ? .complete : .todo } ?? .waiting))
        }
        if managed && enrolled {
            let status: HomeSetupItem.Status
            if email.email?.verified != nil { status = .complete }
            else if accountDismissed { status = .skipped }
            else if email.email?.pending != nil { status = .waiting }
            else { status = .todo }
            items.append(.init(step: .account, status: status))
        }
        if calendarKnown {
            items.append(.init(step: .calendar, status: calendarConnected ? .complete :
                (calendarDeferred || skipped.contains("calendar") ? .skipped : .todo)))
        }
        if localAvailable {
            items.append(.init(step: .transcription, status: localReviewed ? .complete :
                (skipped.contains("transcription") ? .skipped : .todo)))
        }
        if filesAvailable {
            items.append(.init(step: .files, status: filesConfigured ? .complete : .todo))
        }
        if foldersAvailable {
            items.append(.init(step: .folders, status: foldersReviewed ? .complete :
                (skipped.contains("folders") ? .skipped : .todo)))
        }
        return items
    }
}

extension AppState {
    var homeSetupItems: [HomeSetupItem] {
        #if os(macOS) && arch(arm64)
        let localAvailable = true
        #else
        let localAvailable = false
        #endif
        #if os(macOS)
        let filesAvailable = true
        // Local app history is already configured; Markdown copies are optional.
        let filesConfigured = true
        #else
        let filesAvailable = false
        let filesConfigured = false
        #endif
        return HomeSetupPolicy.items(managed: appMode == .managed, enrolled: clientAuthStatus.isEnrolled,
            email: accountEmailState, recoverySaved: clientAuthStatus.recoveryKeyAcknowledged,
            accountDismissed: clientAuthStatus.accountID.map { UserDefaults.standard.bool(forKey: Self.accessCardDismissedKey(accountID: $0)) } ?? false,
            calendarConnected: isGoogleCalendarConnected, calendarDeferred: calendarNudgeDismissedUntil > Date().timeIntervalSince1970,
            calendarKnown: hasResolvedCalendarConnection || isGoogleCalendarConnected || !googleCalendarEnabled,
            localAvailable: localAvailable, localChosen: onDeviceTranscriptionEnabled,
            // Existing preferences are preserved, but everyone receives the review nudge.
            localReviewed: homeSetupAudioReviewed, skipped: Set(homeSetupSkippedSteps.split(separator: ",").map(String.init)),
            filesAvailable: filesAvailable, filesConfigured: filesConfigured,
            microphoneGranted: captureMicrophone ? homeSetupMicrophonePermission.map { $0 == .authorized } : nil,
            microphoneRequired: captureMicrophone, foldersAvailable: true, foldersReviewed: homeSetupState.foldersReviewed)
    }

    /// Coalesce refreshes from the guide/footer. A slow system permission read must not
    /// block disclosure, layout or another Home interaction, nor spawn repeated reads.
    func refreshHomeSetupMicrophonePermission(
        read: @escaping @Sendable () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) }
    ) {
        homeSetupState.refresh(read: read)
    }

    var canShowHomeSetup: Bool {
        hasCompletedOnboarding && !isRecording && !isStartingMeeting && !isResumingRecording && !isFinalizingMeeting &&
        pendingAutoStartEvent == nil && (appMode == .byok || clientAuthStatus.isEnrolled)
    }

    var isHomeSetupExpanded: Bool {
        canShowHomeSetup && !homeSetupHidden && !homeSetupDismissed
    }

    var isHomeCalendarVisible: Bool {
        #if os(macOS)
        !homeSetupState.calendarHidden
        #else
        !isHomeSetupExpanded && !homeSetupState.calendarHidden
        #endif
    }

    func toggleHomeCalendar() {
        let wasVisible = isHomeCalendarVisible
        #if os(iOS)
        homeSetupHidden = true
        #endif
        homeSetupState.calendarHidden = wasVisible
        homeSetupState.revision += 1
    }

    var homeSetupProgress: String {
        let items = homeSetupItems
        return "\(items.filter { $0.status == .complete }.count)/\(items.count)"
    }

    func isHomeSetupStepHidden(_ step: HomeSetupStep) -> Bool {
        if homeSetupSkippedSteps.split(separator: ",").contains(Substring(step.rawValue)) { return true }
        if step == .account, let accountID = clientAuthStatus.accountID {
            return UserDefaults.standard.bool(forKey: Self.accessCardDismissedKey(accountID: accountID))
        }
        return step == .calendar && calendarNudgeDismissedUntil > Date().timeIntervalSince1970
    }

    func setHomeSetupCollapsed(_ collapsed: Bool) {
        homeSetupHidden = collapsed
        #if os(iOS)
        if collapsed { homeSetupState.calendarHidden = false }
        #endif
        homeSetupState.revision += 1
    }

    func confirmHomeSetupAudioReview() {
        homeSetupAudioReviewed = true
        // Notify only the guide and its controls, not the whole application.
        homeSetupState.revision += 1
    }

    func confirmHomeSetupFoldersReview() {
        homeSetupState.foldersReviewed = true
        homeSetupState.revision += 1
    }

    func setHomeSetupDismissed(_ dismissed: Bool) {
        homeSetupDismissed = dismissed
        #if os(iOS)
        if dismissed { homeSetupState.calendarHidden = false }
        #endif
        if !dismissed { homeSetupHidden = false }
        homeSetupState.revision += 1
    }

    func skipHomeSetup(_ step: HomeSetupStep) {
        if step == .account { dismissAccessCard() }
        else {
            var skipped = Set(homeSetupSkippedSteps.split(separator: ",").map(String.init))
            skipped.insert(step.rawValue)
            homeSetupSkippedSteps = skipped.sorted().joined(separator: ",")
        }
        homeSetupState.revision += 1
    }

    func restoreHomeSetup(_ step: HomeSetupStep) {
        var skipped = Set(homeSetupSkippedSteps.split(separator: ",").map(String.init))
        skipped.remove(step.rawValue)
        homeSetupSkippedSteps = skipped.sorted().joined(separator: ",")
        if step == .account, let accountID = clientAuthStatus.accountID {
            UserDefaults.standard.removeObject(forKey: Self.accessCardDismissedKey(accountID: accountID))
            refreshAccessCard()
        }
        if step == .calendar { calendarNudgeDismissedUntil = 0 }
        setHomeSetupDismissed(false)
    }

}

/// Subscribe only the setup subtree to its presentation and permission changes.
struct HomeSetupStateObserver<Content: View>: View {
    @ObservedObject var state: HomeSetupState
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

/// Fixed Home utility control, paired with Feedback outside the scrolling content.
struct HomeSetupButton: View {
    var fillsFooterCell = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHighlighted = false
    @State private var highlightTask: Task<Void, Never>?
    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            Group {
                if appState.canShowHomeSetup, !appState.homeSetupDismissed, !appState.homeSetupItems.isEmpty {
                    Button {
                        let update = { appState.setHomeSetupCollapsed(!appState.homeSetupHidden) }
                        if reduceMotion { update() }
                        else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), update) }
                    } label: {
                        MinitiHomeActionLabel(icon: "checklist", label: "set up miniti \(appState.homeSetupProgress)", isEmphasized: appState.isHomeSetupExpanded || isHighlighted, fillsFooterCell: fillsFooterCell)
                            .overlay {
                                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                                    .stroke(ColorPalette.Accent.green, lineWidth: 2)
                                    .opacity(isHighlighted ? 1 : 0)
                                    .allowsHitTesting(false)
                            }
                            .scaleEffect(isHighlighted && !reduceMotion ? 1.06 : 1)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: appState.homeSetupState.reopenHighlight) { _, _ in highlightOnce() }
                    .onDisappear { highlightTask?.cancel() }
                    .accessibilityIdentifier("setup.reopen")
                    .accessibilityLabel("Set up miniti")
                    .accessibilityValue("\(appState.homeSetupItems.filter { $0.status == .complete }.count) of \(appState.homeSetupItems.count) tasks configured")
                    .accessibilityHint(appState.homeSetupHidden ? "Show setup guide" : "Collapse setup guide")
                }
            }
                .task { appState.refreshHomeSetupMicrophonePermission() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { appState.refreshHomeSetupMicrophonePermission() }
                }
                .onChange(of: appState.captureMicrophone) { _, _ in appState.refreshHomeSetupMicrophonePermission() }
        }
    }

    /// One highlight after the guide collapses: a ring, plus a small pulse unless Reduce Motion is on.
    private func highlightOnce() {
        highlightTask?.cancel()
        let change = { (on: Bool) in
            if reduceMotion { isHighlighted = on }
            else { withAnimation(.easeInOut(duration: 0.35)) { isHighlighted = on } }
        }
        highlightTask = Task { @MainActor in
            // Let the guide finish shrinking towards the button first.
            try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 250_000_000)
            guard !Task.isCancelled else { return }
            change(true)
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            change(false)
        }
    }
}

/// Setup and upcoming meetings share one Home content area.
struct HomeSetupOrCalendar<CalendarContent: View>: View {
    @EnvironmentObject private var appState: AppState
    @ViewBuilder var calendar: () -> CalendarContent

    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            if appState.isHomeSetupExpanded {
                HomeSetupGuide()
            } else if appState.isHomeCalendarVisible {
                calendar()
            }
        }
    }
}

struct HomeCalendarButton: View {
    var fillsFooterCell = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            if appState.googleCalendarEnabled && appState.isGoogleCalendarConnected {
                Button {
                    let update = { appState.toggleHomeCalendar() }
                    if reduceMotion { update() }
                    else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), update) }
                } label: {
                    MinitiHomeActionLabel(
                        icon: appState.isHomeCalendarVisible ? "calendar" : "calendar.badge.minus",
                        label: "calendar", isEmphasized: appState.isHomeCalendarVisible, fillsFooterCell: fillsFooterCell)
                }
                .buttonStyle(.plain)
                .disabled(appState.pendingAutoStartEvent != nil)
                .accessibilityIdentifier("home.calendar.toggle")
                .accessibilityLabel("Calendar")
                .accessibilityValue(appState.isHomeCalendarVisible ? "shown" : "hidden")
                .accessibilityHint(appState.isHomeCalendarVisible ? "Hide upcoming meetings" : "Show upcoming meetings")
                .help("Show or hide upcoming meetings. Calendar connection and automatic recording stay unchanged.")
            }
        }
    }
}

/// Equal cells on iOS; left-aligned setup, models and feedback on Mac.
struct HomeUtilityBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        #if os(iOS)
        HStack(spacing: MinitiDesignSystem.Spacing.standard) {
            HomeSetupButton(fillsFooterCell: true)
                .accessibilityShowsLargeContentViewer()
            HomeCalendarButton(fillsFooterCell: true)
                .accessibilityShowsLargeContentViewer()
            HomeFeedbackButton(fillsFooterCell: true)
                .accessibilityShowsLargeContentViewer()
        }
        // Compact navigation keeps a usable content viewport at accessibility sizes.
        // Each native button offers the system large-content viewer on long press.
        .dynamicTypeSize(...MinitiDesignSystem.HomeSetup.footerMaximumDynamicTypeSize)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        #else
        HStack(spacing: MinitiDesignSystem.Spacing.standard) {
            HomeSetupButton()
            #if arch(arm64)
            LocalModelsStatusButton(transcription: appState.onDeviceTranscription, speakers: appState.onDeviceDiarization)
            #endif
            HomeFeedbackButton()
            Spacer(minLength: 0)
        }
        #endif
    }
}

/// Shared restoration controls in Settings, General on both platforms.
struct HomeSetupSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    private var hidden: [HomeSetupStep] { HomeSetupStep.allCases.filter { appState.isHomeSetupStepHidden($0) } }
    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            Section("Setup guide") {
                Toggle("Show setup guide on Home", isOn: Binding(
                    get: { !appState.homeSetupDismissed },
                    set: { appState.setHomeSetupDismissed(!$0) }))
                    .accessibilityIdentifier("setup.settings.visible")
                Button("Expand guide on Home") { appState.setHomeSetupDismissed(false) }
                    .accessibilityIdentifier("setup.settings.open")
                Text("\(appState.homeSetupProgress) tasks configured. Hiding a task does not complete it. Restoring a task does not change its settings.")
                    .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                ForEach(hidden) { step in
                    HStack {
                        Text(step.title).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Restore") { appState.restoreHomeSetup(step) }
                            .accessibilityIdentifier("setup.restore.\(step.rawValue)")
                            .accessibilityLabel("Restore \(step.title)")
                    }
                }
            }
            .id("general.setup")
        }
    }
}

/// One presentation owner replaces the independent account and calendar nudges.
struct HomeSetupGuide: View {
    private struct RecoveryPresentation: Identifiable {
        let id = UUID()
        let key: String
    }
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: HomeSetupStep?
    @State private var emailPresented = false
    @State private var recoveryPresentation: RecoveryPresentation?
    @State private var foldersPresented = false
    init(initialStep: HomeSetupStep? = nil) { _selected = State(initialValue: initialStep) }

    private var items: [HomeSetupItem] {
        let order: [HomeSetupStep] = [.readiness, .calendar, .files, .account, .transcription, .folders]
        return appState.homeSetupItems.filter { $0.isRelevantOnHome && !appState.isHomeSetupStepHidden($0.step) }.sorted { order.firstIndex(of: $0.step)! < order.firstIndex(of: $1.step)! }
    }
    private var current: HomeSetupItem? {
        if let selected, let item = items.first(where: { $0.step == selected }) { return item }
        return items.first { $0.status != .complete && !$0.reviewed }
    }

    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            if appState.isHomeSetupExpanded {
                let visibleItems = items
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                    HStack {
                        Text("make it yours").font(.headline)
                        Spacer()
                        Button("collapse guide") {
                            setHidden(true)
                            appState.homeSetupState.reopenHighlight += 1
                        }
                            .font(.caption)
                            .accessibilityIdentifier("setup.collapse")
                            .help("Keep the setup button on Home so you can reopen the guide.")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleItems) { item in
                            checklistRow(item)
                            if item.id != visibleItems.last?.id { MinitiFadingDivider(accent: ColorPalette.Border.subtle) }
                        }
                    }
                    if visibleItems.isEmpty {
                        Text("No tasks need attention here. Manage hidden tasks in Settings, General.")
                            .font(.callout).foregroundStyle(ColorPalette.Text.secondary)
                    }
                    MinitiFadingDivider(accent: ColorPalette.Border.subtle)
                        .padding(.vertical, MinitiDesignSystem.Spacing.small)
                    Button("remove guide from home") {
                        let update = { appState.setHomeSetupDismissed(true) }
                        if reduceMotion { update() }
                        else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), update) }
                    }
                    .font(.caption)
                    .accessibilityIdentifier("setup.dismiss")
                    Text("Removes the guide and its button. Restore in Settings, General.")
                        .font(.caption).foregroundStyle(ColorPalette.Text.muted)
                }
                .frame(maxWidth: MinitiDesignSystem.HomeSetup.maximumWidth, alignment: .leading)
                // Collapsing shrinks the guide towards the setup button at the bottom of Home.
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.15, anchor: .bottomLeading).combined(with: .opacity)))
                .sheet(isPresented: $emailPresented) {
                    HomeSetupEmailSheet().environmentObject(appState).dynamicTypeSize(dynamicTypeSize)
                }
                .sheet(item: $recoveryPresentation) { presentation in
                    RecoveryKeySheet(recoveryKey: presentation.key).environmentObject(appState).dynamicTypeSize(dynamicTypeSize)
                }
                .sheet(isPresented: $foldersPresented) {
                    MeetingFolderManager(onConfirmSetup: { appState.confirmHomeSetupFoldersReview() })
                        .environmentObject(appState).dynamicTypeSize(dynamicTypeSize)
                }
                .onChange(of: appState.clientAuthStatus.accountID) { _, _ in
                    foldersPresented = false
                    selected = nil; emailPresented = false; recoveryPresentation = nil
                }
                .onAppear { if selected == nil { selected = current?.step } }
                .task { appState.refreshHomeSetupMicrophonePermission() }
            }
        }
    }

    private func checklistRow(_ item: HomeSetupItem) -> some View {
        let expanded = selected == item.step
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: MinitiDesignSystem.Spacing.control))
        return VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
            headerLayout {
            Button {
                let change = { selected = expanded ? nil : item.step }
                if reduceMotion { change() }
                else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), change) }
            } label: {
                // Give reading text the full column at accessibility sizes. Keeping
                // status/chevron beside large prose can make one task taller than Home.
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                    if dynamicTypeSize.isAccessibilitySize {
                        HStack {
                            Image(systemName: item.status == .complete ? "checkmark.circle.fill" :
                                item.status == .waiting ? "clock" : item.status == .skipped ? "minus.circle" : "circle")
                                .foregroundStyle(ColorPalette.Text.muted)
                                .font(.body).accessibilityHidden(true)
                            Spacer(minLength: MinitiDesignSystem.Spacing.standard)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.callout).foregroundStyle(ColorPalette.Text.muted).accessibilityHidden(true)
                                .frame(width: MinitiDesignSystem.Control.minimumIconHitSize, height: MinitiDesignSystem.Control.minimumIconHitSize)
                        }
                        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                            Text(item.step.title).font(.callout.weight(.medium))
                                .strikethrough(item.status == .complete)
                                .foregroundStyle(item.status == .complete ? ColorPalette.Text.muted : ColorPalette.Text.primary)
                            Text(summary(item)).font(.caption)
                                .foregroundStyle(item.status == .complete ? ColorPalette.Text.muted : ColorPalette.Text.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .center, spacing: MinitiDesignSystem.Spacing.control) {
                            Image(systemName: item.status == .complete ? "checkmark.circle.fill" :
                                item.status == .waiting ? "clock" : item.status == .skipped ? "minus.circle" : "circle")
                                .foregroundStyle(ColorPalette.Text.muted)
                                .font(.body).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                                Text(item.step.title).font(.callout.weight(.medium))
                                    .strikethrough(item.status == .complete)
                                    .foregroundStyle(item.status == .complete ? ColorPalette.Text.muted : ColorPalette.Text.primary)
                                Text(summary(item)).font(.caption)
                                    .foregroundStyle(item.status == .complete ? ColorPalette.Text.muted : ColorPalette.Text.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: MinitiDesignSystem.Spacing.compact)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.callout).foregroundStyle(ColorPalette.Text.muted).accessibilityHidden(true)
                                .frame(width: MinitiDesignSystem.Control.minimumIconHitSize, height: MinitiDesignSystem.Control.minimumIconHitSize)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .padding(.vertical, MinitiDesignSystem.Spacing.standard)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("setup.step.\(item.step.rawValue)")
            .accessibilityValue("\(item.statusLabel), \(expanded ? "expanded" : "collapsed")")
            .accessibilityHint(expanded ? "Collapse choices" : "Show choices")
                HStack(spacing: MinitiDesignSystem.Spacing.control) {
                MinitiDocumentationLink(topic: item.step.documentation)
                Button {
                    let update = { appState.skipHomeSetup(item.step); selected = nil }
                    if reduceMotion { update() }
                    else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), update) }
                } label: {
                    Image(systemName: "xmark").font(.callout).foregroundStyle(ColorPalette.Text.muted)
                        .padding(MinitiDesignSystem.Spacing.compact)
                        .frame(minWidth: MinitiDesignSystem.Control.minimumIconHitSize, minHeight: MinitiDesignSystem.Control.minimumIconHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide \(item.step.title)")
                .accessibilityIdentifier("setup.skip.\(item.step.rawValue)")
                .accessibilityHint("Hidden until restored in Settings, General. Does not mark the task complete.")
                .help("Hide this task until restored in Settings, General.")
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
            }
            if expanded {
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                    choices(item.step)

                }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, MinitiDesignSystem.Spacing.comfortable)
                    .transition(.opacity)
            }
        }
    }

    private func summary(_ item: HomeSetupItem) -> String {
        switch item.step {
        case .readiness:
            if appState.homeSetupMicrophonePermission == nil {
                return appState.homeSetupState.permissionCheckUnavailable ? "Access check unavailable" : "Checking microphone access"
            }
            return item.status == .complete ? "Microphone access allowed" : "Capture your voice in meetings"
        case .calendar:
            if appState.isGoogleCalendarConnected {
                return appState.autoStartFromCalendar && appState.googleCalendarEnabled ? "Connected, automatic recording on" : "Connected, automatic recording off"
            }
            return item.status == .skipped ? "Not connected, set up whenever you like" : "Meeting titles, attendees and automatic recording"
        case .account:
            if let email = appState.accountEmailState.email?.verified { return email }
            if appState.accountEmailState.email?.pending != nil { return "Check your email to finish" }
            return "Recover your account, plus optional Pro cloud storage and sync."
        case .files:
            #if os(macOS)
            return appState.autoExportMarkdown ? appState.displayedExportFolderPath : "Keep searchable Markdown copies on your Mac"
            #else
            return "Saved in miniti on this device"
            #endif
        case .folders:
            return "Find past conversations faster with folders that group related meetings."
        case .transcription:
            switch HomeSetupAudioChoice(appState: appState) {
            case .online: return "Online. Fast, with the most languages."
            case .onThisMac: return "On this Mac. Audio stays on your Mac."
            case .custom: return "Custom. Each part is chosen in Settings, Transcription."
            }
        }
    }

    private func setHidden(_ hidden: Bool) {
        let update = {
            appState.setHomeSetupCollapsed(hidden)
        }
        if reduceMotion { update() }
        else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), update) }
    }

    @ViewBuilder private func choices(_ step: HomeSetupStep) -> some View {
        switch step {
        case .readiness:
            HomeSetupRecordingAccess()
        case .account:
            if let verified = appState.accountEmailState.email?.verified {
                Text(verified).font(.callout).textSelection(.enabled)
            } else if let pending = appState.accountEmailState.email?.pending {
                Text("Open the link sent to \(pending) to finish.").font(.callout)
            } else {
                Text("Email recovery is free. Cloud storage and sync are optional with Pro.")
                    .font(.callout).foregroundStyle(ColorPalette.Text.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { accountChoices }
                VStack(alignment: .leading) { accountChoices }
            }
        case .calendar:
            if appState.isGoogleCalendarConnected {
                Text(appState.googleCalendarEmail ?? "Google Calendar connected").font(.callout)
                Toggle("use Google Calendar", isOn: $appState.googleCalendarEnabled)
                Toggle("start calendar meetings automatically", isOn: Binding(
                    get: { appState.autoStartFromCalendar },
                    set: { appState.autoStartFromCalendar = $0; selected = .calendar }))
                    .disabled(!appState.googleCalendarEnabled)
                    .accessibilityIdentifier("setup.calendar.autoStart")
                Text("Recommended: start when your scheduled call is detected.")
                    .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("stop after the calendar end when quiet", isOn: $appState.autoStopFromCalendar)
                    .disabled(!appState.googleCalendarEnabled)
            } else {
                Text("See upcoming meetings and choose when recording starts.")
                    .font(.callout).foregroundStyle(ColorPalette.Text.secondary)
                Button("connect Google Calendar") {
                    selected = .calendar
                        appState.startCalendarConnectFromNudge()
                }
                    .accessibilityIdentifier("setup.action.calendar")
            }
        case .transcription:
            #if os(macOS) && arch(arm64)
            // One plain choice (Charlie's 3.8.0 feedback). Provider names and the
            // separate transcription and speaker pickers stay in Settings, Transcription.
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
                HStack { Text("where audio is processed").font(.callout.weight(.semibold)); MinitiDocumentationLink(topic: .transcription) }
                Picker("where audio is processed", selection: Binding(
                    get: { HomeSetupAudioChoice(appState: appState) },
                    set: { choice in
                        guard choice != .custom else { return }
                        let local = choice == .onThisMac
                        appState.onDeviceTranscriptionEnabled = local
                        appState.onDeviceSpeakerSeparationEnabled = local
                        if local { appState.onDeviceTranscriptionCloudFallback = true }
                        selected = .transcription
                        appState.refreshOnDeviceTranscriptionAvailability()
                        appState.refreshOnDeviceDiarizationAvailability()
                    }
                )) {
                    Text("online").tag(HomeSetupAudioChoice.online)
                    Text("on this Mac").tag(HomeSetupAudioChoice.onThisMac)
                    if HomeSetupAudioChoice(appState: appState) == .custom {
                        Text("custom").tag(HomeSetupAudioChoice.custom)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appState.privateModeEnabled
                          || !OnDeviceTranscriptionService.isHardwareSupported
                          || !OnDeviceDiarizationService.isHardwareSupported)
                .accessibilityIdentifier("setup.audio.choice")
                switch HomeSetupAudioChoice(appState: appState) {
                case .online:
                    Text("Recommended. Fast, with the most languages, and light on your Mac.")
                        .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .onThisMac:
                    Text("Audio stays on your Mac. The first recording downloads about 600 MB. If the model is not ready, miniti uses online processing.")
                        .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if OnDeviceTranscriptionSupport.tier(forCode: appState.meetingLanguage) == .cloudOnly {
                        Text("Your selected language is processed online. Choose a supported language to keep it on your Mac.")
                            .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                    } else {
                        HomeSetupTranscriptionStatus(service: appState.onDeviceTranscription)
                    }
                    HomeSetupSpeakerStatus(service: appState.onDeviceDiarization)
                case .custom:
                    Text("You chose each part separately. Pick one option to use it for both, or keep your choice in Settings, Transcription.")
                        .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(appState.privateModeEnabled ? "Private mode keeps audio on this Mac. Change private mode under Privacy." : "For your next recording. AI insights are separate.")
                .font(.caption).foregroundStyle(ColorPalette.Text.muted)
            if !appState.homeSetupAudioReviewed {
                Button("confirm audio choices") {
                    appState.confirmHomeSetupAudioReview()
                }
                .accessibilityIdentifier("setup.audio.reviewed")
                .help("Marks this task reviewed. Your selected settings already apply.")
            }
            #endif
        case .folders:
            Button("set up folders") { foldersPresented = true }
                .accessibilityIdentifier("setup.action.folders")
            Text("Preview existing meetings, create your own folders or review automatic filing.")
                .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
        case .files:
            #if os(macOS)
            HomeMeetingFilesSetup {
                selected = .files
            }
            #endif
        }
    }

    @ViewBuilder private var accountChoices: some View {
        Button(appState.accountEmailState.email?.verified == nil ? "add email" : "change email") { emailPresented = true }
            .accessibilityIdentifier("setup.action.account")
        if !appState.managedDeviceHasNoRecoveryKey {
            Button("save recovery key") {
                if let key = appState.revealRecoveryKey(), !key.isEmpty {
                    recoveryPresentation = RecoveryPresentation(key: key)
                }
            }.accessibilityIdentifier("setup.account.recovery")
        }
    }
}

private struct HomeSetupRecordingAccess: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var requesting = false
    private var permission: AVAuthorizationStatus? { appState.homeSetupMicrophonePermission }
    var body: some View {
        HomeSetupStateObserver(state: appState.homeSetupState) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                Text(permission == nil ? (appState.homeSetupState.permissionCheckUnavailable
                     ? "Access check unavailable. You can check microphone access in System Settings."
                     : "Checking microphone access. You can keep using miniti.") :
                     permission == .authorized ? "Ready to capture your voice." : "Let miniti capture your voice when you record.")
                    .font(.callout).foregroundStyle(ColorPalette.Text.secondary)
                if permission == .notDetermined {
                    Button(requesting ? "waiting for permission…" : "allow microphone") {
                        requesting = true
                        Task {
                            // The system call itself may do IPC before invoking its callback.
                            let granted = await Task.detached { await AVCaptureDevice.requestAccess(for: .audio) }.value
                            appState.homeSetupState.receivedPermissionRequest(granted: granted)
                            requesting = false
                        }
                    }
                    .disabled(requesting)
                } else if permission != .authorized {
                    Button("open microphone settings") {
                        #if os(macOS)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
                        #else
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        #endif
                    }
                }
            }
            .accessibilityIdentifier("setup.recordingAccess.choices")
            .task { appState.refreshHomeSetupMicrophonePermission() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { appState.refreshHomeSetupMicrophonePermission() } }
        }
    }
}

#if os(macOS)
/// The same persisted destination and export preferences used by Settings, Data.
struct HomeMeetingFilesSetup: View {
    @EnvironmentObject private var appState: AppState
    var onInteraction: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
            Text("Meetings stay in miniti. Save Markdown copies for your notes and AI tools.")
                .font(.callout).foregroundStyle(ColorPalette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("save completed meetings as Markdown files", isOn: Binding(
                get: { appState.autoExportMarkdown },
                set: { onInteraction(); appState.autoExportMarkdown = $0 }))
                .accessibilityIdentifier("setup.files.autoExport")
            Text(appState.displayedExportFolderPath)
                .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("setup.files.path")
            Button("choose folder…") { onInteraction(); appState.presentExportFolderChooser() }
                .accessibilityIdentifier("setup.files.chooseFolder")
            Toggle("help AI assistants find your meetings", isOn: Binding(
                get: { appState.generateAgentsMd },
                set: { onInteraction(); appState.generateAgentsMd = $0 }))
                .disabled(!appState.autoExportMarkdown)
                .accessibilityIdentifier("setup.files.agents")
            Text("Keeps a list of saved notes for AI tools that can read this folder. Skip this if you don’t use one.")
                .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let issue = appState.markdownExportIssue {
                Text(issue).font(.caption).foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif

#if os(macOS) && arch(arm64)
private struct HomeSetupSpeakerStatus: View {
    @ObservedObject var service: OnDeviceDiarizationService
    var body: some View { LocalModelProgress(status: service.status) }
}
private struct HomeSetupTranscriptionStatus: View {
    @ObservedObject var service: OnDeviceTranscriptionService
    var body: some View { LocalModelProgress(status: service.status) }
}
#endif

/// Direct email presentation works even when the Mac Settings window has never opened.
private struct HomeSetupEmailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var busy = false
    @State private var notice: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Keep access to your account") {
                    if case .loaded = appState.accountEmailState {
                        TextField("Email", text: $address).focused($focused)
                            #if os(iOS)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                            .accessibilityIdentifier("setup.email")
                        if let pending = appState.accountEmailState.email?.pending {
                            Text("Check \(pending) and open the newest link to finish.")
                        }
                    } else {
                        Text("Account details are not available yet. Try again before adding an email.")
                        Button("Retry") { Task { await appState.refreshAccountEmail(reason: "setup retry", force: true) } }
                    }
                    Text("Add an email to sign in again on this or another device. Cloud sync stays unchanged. Your recovery key is also available in Settings, Account.")
                    if busy { ProgressView("Sending link") }
                    if let notice { Text(notice).accessibilityIdentifier("setup.emailNotice") }
                }
            }.formStyle(.grouped)
                .navigationTitle("Add email")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send link") { send() }
                            .disabled(busy || !address.contains("@") || appState.accountEmailState.email == nil)
                            .accessibilityIdentifier("setup.sendEmail")
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: MinitiDesignSystem.HomeSetup.maximumWidth, minHeight: 320)
        #endif
        .task {
            await appState.refreshAccountEmail(reason: "setup email")
            if address.isEmpty { address = appState.accountEmailState.email?.pending ?? "" }
            focused = true
        }
        .onChange(of: appState.clientAuthStatus.accountID) { _, _ in dismiss() }
    }
    private func send() {
        guard !busy else { return }
        busy = true; notice = nil
        Task { @MainActor in
            let outcome = await appState.addAccountEmail(address)
            busy = false
            switch outcome {
            case .sent(let address): notice = "Link sent to \(address). Open it in your email to finish."
            case .alreadyVerified: notice = "That email is already verified."
            case .inUse: notice = "That email belongs to another account. Use Switch account in Settings, Account."
            case .failed(let message): notice = message
            case .staleAccount: dismiss()
            }
        }
    }
}

// MARK: Settings section

/// Settings, Account: Your account, Ways to sign in, Devices, then the destructive actions
/// (B6a). Plan and billing follows it in each platform's Settings view.
struct ManagedAccountSettingsSection: View {
    // Reuse the parser across row redraws, including recording timer updates.
    private static let lastSeenDateParser = ISO8601DateFormatter()
    @EnvironmentObject var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var isRenamingDevice = false
    @State private var isConfirmingDeviceRemoval = false
    @State private var renamingDevice: ClientAuthDevice?
    @State private var deviceName = ""
    @State private var isBusy = false
    @State private var notice: String?
    @State private var isEditingEmail = false
    @State private var emailDraft = ""
    @State private var emailNotice: String?
    /// True while `emailNotice` confirms a sent link; it reads as a status, not an error.
    @State private var emailNoticeIsConfirmation = false
    @FocusState private var emailFieldFocused: Bool

    private var status: ClientAuthStatus { appState.clientAuthStatus }
    private var model: AccountSectionModel { AccountSectionModel.make(appState.accountSectionInputs) }
    private var accountIsPresent: Bool { status.isEnrolled || status.keyUnusable }

    var body: some View {
        Group {
            Section {
                if accountIsPresent {
                    yourAccountRows
                } else {
                    unenrolledRows
                        .id("account.recoveryKey")
                }
            } header: {
                accountPresentations(Text(accountIsPresent ? "Your account" : "Account"))
            }
            if accountIsPresent {
                waysToSignInSection
                devicesSection
            }
        }
        .alert("Device name", isPresented: $isRenamingDevice, presenting: renamingDevice) { device in
            TextField("Device name", text: $deviceName)
            Button("Save") {
                let label = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { _ = await appState.renameManagedDevice(device, label: label) }
            }
            .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || deviceName.unicodeScalars.count > 80)
            Button("Use default name") {
                Task { _ = await appState.renameManagedDevice(device, label: nil) }
            }
            Button("Cancel", role: .cancel) {}
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
        .alert(
            pendingRemoval?.current == true ? "Sign this device out?" : "Remove this device?",
            isPresented: $isConfirmingDeviceRemoval,
            presenting: pendingRemoval
        ) { device in
            Button(device.current ? "Sign out" : "Remove", role: .destructive) { remove(device) }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text(device.current ? model.signOutMessage : model.deviceRemovalMessage)
        }
    }

    // MARK: Your account

    @ViewBuilder
    private var yourAccountRows: some View {
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
                emailActionSummary
                if isEditingEmail {
                    emailEditor
                    Text("A confirmation link goes to this address. It becomes a way to sign in once you open the link. This does not turn on cloud sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let emailNotice {
                    // A sent link is the one thing the person must act on next, so it is a
                    // plain status line with the address, not a dim caption (Charlie, 2026-10-27:
                    // the field cleared and nothing said to go and open the email).
                    Label(emailNotice, systemImage: emailNoticeIsConfirmation ? "envelope.badge" : "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(emailNoticeIsConfirmation ? ColorPalette.Status.success : ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Recovery key
            VStack(alignment: .leading, spacing: 6) {
                recoveryKeySummary
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

    private var stacksAccountActions: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    private var accountActionLayout: AnyLayout {
        stacksAccountActions
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control))
            : AnyLayout(HStackLayout())
    }

    private var emailActionSummary: some View {
        accountActionLayout {
            Text("Email")
            if !stacksAccountActions { Spacer() }
            ForEach(model.emailActions, id: \.self) { action in actionButton(action) }
        }
        #if os(iOS)
        .buttonStyle(.borderless)
        #endif
    }

    private var emailEditor: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control) {
            emailEditorContents
        }
        .buttonStyle(.borderless)
        #else
        HStack { emailEditorContents }
        #endif
    }

    @ViewBuilder
    private var emailEditorContents: some View {
        TextField("name@example.com", text: $emailDraft)
            .accessibilityIdentifier("account.email.draft")
            .textFieldStyle(.roundedBorder)
            .focused($emailFieldFocused)
            #if os(iOS)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .onSubmit { submitEmail() }
        #if os(iOS)
        accountActionLayout { emailEditorActions }
        #else
        emailEditorActions
        #endif
    }

    @ViewBuilder
    private var emailEditorActions: some View {
        Button { submitEmail() } label: { accountActionLabel("Send link") }
            .accessibilityIdentifier("account.email.send")
            .disabled(isBusy || !emailDraft.contains("@"))
        Button { isEditingEmail = false; emailDraft = ""; emailNotice = nil } label: {
            accountActionLabel("Cancel")
        }
        .accessibilityIdentifier("account.email.cancel")
    }

    private var recoveryKeyTitle: some View {
        Text("Recovery key")
            .accessibilityIdentifier("account.recovery.title")
    }

    private var recoveryKeyStatus: some View {
        Text(model.recoveryKeyLine)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("account.recovery.status")
    }

    @ViewBuilder
    private var recoveryKeyActions: some View {
        if revealedKey != nil {
            Button { revealedKey = nil; copied = false } label: { accountActionLabel("Hide") }
        } else {
            ForEach(model.recoveryKeyActions, id: \.self) { action in actionButton(action) }
        }
    }

    private var recoveryKeySummary: some View {
        #if os(iOS)
        ViewThatFits(in: .horizontal) {
            HStack {
                recoveryKeyTitle.fixedSize()
                Spacer()
                recoveryKeyStatus.fixedSize()
                recoveryKeyActions.fixedSize()
            }
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control) {
                recoveryKeyTitle
                recoveryKeyStatus
                recoveryKeyActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.borderless)
        #else
        HStack {
            recoveryKeyTitle
            Spacer()
            recoveryKeyStatus
            recoveryKeyActions
        }
        #endif
    }

    @ViewBuilder
    private func accountActionLabel(_ title: String) -> some View {
        #if os(iOS)
        Text(title)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .minitiMinimumControlTarget()
        #else
        Text(title)
        #endif
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
                accountActionLayout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deviceTitle(device))
                            .accessibilityIdentifier("account.device.title.\(device.installationID)")
                            #if os(iOS)
                            .fixedSize(horizontal: false, vertical: true)
                            #endif
                        Text(deviceSubtitle(device))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            #if os(iOS)
                            .fixedSize(horizontal: false, vertical: true)
                            #endif
                        DisclosureGroup("Device ID") {
                            Text(device.installationID).font(.caption).textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                    if !stacksAccountActions { Spacer() }
                    Button {
                        deviceName = device.label ?? ""; renamingDevice = device; isRenamingDevice = true
                    } label: {
                        accountActionLabel("Rename")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isBusy || model.signedActionsDisabled)
                    .accessibilityIdentifier("account.rename.\(device.installationID)")
                    if model.accountActions.contains(.deleteAccount) || device.current {
                        // Removal is a signed request; a device whose key cannot sign only offers
                        // its own sign-out (which clears locally).
                        Button {
                            pendingRemoval = device; isConfirmingDeviceRemoval = true
                        } label: {
                            accountActionLabel(device.current ? "Sign out" : "Remove")
                        }
                        .accessibilityIdentifier("account.device.remove.\(device.installationID)")
                        .buttonStyle(.borderless)
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
            Button { isEditingEmail = true; emailFieldFocused = true } label: { accountActionLabel("Add email") }
                .disabled(disabled)
                .accessibilityIdentifier("account.email.add")
        case .changeEmail:
            Button { isEditingEmail = true; emailFieldFocused = true } label: { accountActionLabel("Change") }
                .disabled(disabled)
        case .resendEmail:
            Button { resendEmail() } label: { accountActionLabel("Resend") }
                .disabled(disabled)
                .accessibilityIdentifier("account.email.resend")
        case .removeEmail:
            Button { isConfirmingRemoveEmail = true } label: { accountActionLabel("Remove") }
                .disabled(disabled)
                .accessibilityIdentifier("account.email.remove")
        case .retryEmail:
            Button { Task { await appState.refreshAccountEmail(reason: "retry", force: true) } } label: { accountActionLabel("Retry") }
                .accessibilityIdentifier("account.email.retry")
        case .showKey:
            Button { isConfirmingReveal = true } label: { accountActionLabel("Show recovery key") }
                .disabled(isBusy)
                .accessibilityIdentifier("account.recovery.show")
        case .replaceKey:
            Button { isConfirmingReplace = true } label: { accountActionLabel("Replace recovery key") }
                .disabled(disabled)
                .accessibilityIdentifier("account.recovery.replace")
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

    // The first Section header stays present across enrollment progress and account acquisition.
    // Keep presenters outside conditional rows so in-flight sign-in retains its sheet.
    private func accountPresentations<Content: View>(_ content: Content) -> some View {
        content
            .minitiSheet(isPresented: $isPresentingRestore) {
                RestoreRecoveryKeySheet()
                    .modifier(AccountUITestReadingScopeProbe(name: "accountKeyRestore", alignment: .topLeading))
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
            .minitiSheet(isPresented: $isPresentingEmailRestore) {
                EmailSignInSheet(mode: .restore)
                    .modifier(AccountUITestReadingScopeProbe(name: "accountEmailRestore", alignment: .topLeading))
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
            .minitiSheet(isPresented: $isPresentingMove) {
                RestoreRecoveryKeySheet(mode: .move, onRestored: { notice = "This device is now on the other account." })
                    .modifier(AccountUITestReadingScopeProbe(name: "accountKeyMove", alignment: .topLeading))
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
            .minitiSheet(isPresented: $isPresentingEmailJoin) {
                EmailSignInSheet(mode: .move, onJoined: { notice = "This device is now on the other account." })
                    .modifier(AccountUITestReadingScopeProbe(name: "accountEmailMove", alignment: .topLeading))
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
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
                emailNoticeIsConfirmation = true
                emailNotice = "Link sent to \(address). Open it in that email to finish; it works for 15 minutes. Nothing more to do here."
            case .alreadyVerified:
                isEditingEmail = false
                emailDraft = ""
                emailNoticeIsConfirmation = true
                emailNotice = "That address is already verified on this account."
            case .inUse:
                emailNoticeIsConfirmation = false
                emailNotice = "That email is on another miniti account. Use Switch account to sign this device in to it, or remove the email there first."
            case .failed(let message):
                emailNoticeIsConfirmation = false
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
            case .sent:
                emailNoticeIsConfirmation = true
                emailNotice = "Sent again to \(pending). Open the newest email to finish."
            case .staleAccount: emailNotice = nil
            default:
                emailNoticeIsConfirmation = false
                emailNotice = "Could not send. Try again in a minute."
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
        if appState.needsManagedAccessChoice || appState.managedAccessIssue != nil {
            ManagedAccessChoiceCard()
        } else if appState.isEnrollingManagedDevice {
            HStack(spacing: 8) {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
                Text("Setting up this device…")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(appState.managedEnrollmentError ?? "Choose how to continue, or retry setting up this device. You can sign in with your email or recovery key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Button("Retry setup") { Task { await appState.ensureManagedEnrollment(trigger: "settings") } }
                        .disabled((appState.enrollmentRetryAt ?? .distantPast) > context.date)
                }
                Button("Sign in with email…") { isPresentingEmailRestore = true }
                Button("Sign in with recovery key…") { isPresentingRestore = true }
            }
            #if os(iOS)
            .buttonStyle(.borderless)
            #endif
        }
    }

    private func deviceTitle(_ device: ClientAuthDevice) -> String {
        let name = device.label ?? (device.platform == "macos" ? "Mac" : device.platform == "ios" ? "iPhone or iPad" : "Device")
        return device.current ? "\(name) · this device" : name
    }

    private func deviceSubtitle(_ device: ClientAuthDevice) -> String {
        var parts: [String] = []
        if appState.managedDevices.filter({ $0.label == device.label }).count > 1 {
            parts.append(String(device.installationID.suffix(8)))
        }
        if let platform = device.platform { parts.append(platform) }
        if let version = device.appVersion { parts.append(version) }
        if let seen = device.lastAuthAt, let date = Self.lastSeenDateParser.date(from: seen) {
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
    @Environment(\.readingMetrics) private var readingMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var emailFieldFocused: Bool
    @State private var email = ""
    @State private var linkID: String?
    @State private var isWorking = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var canRetryLink = false
    var mode: Mode = .restore
    var onJoined: (() -> Void)? = nil

    private var canSend: Bool { !isWorking && linkID == nil && email.contains("@") }

    private var stacksActions: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            #if os(iOS)
            ScrollViewReader { proxy in
                ScrollView { formContent.frame(maxWidth: .infinity, alignment: .leading) }
                    .accessibilityIdentifier("account.emailSignIn.scroll")
                    .onChange(of: error) { _, message in
                        if message != nil { proxy.scrollTo("account.emailSignIn.error", anchor: .bottom) }
                    }
                    .onChange(of: linkID) { _, id in
                        if id != nil { proxy.scrollTo("account.emailSignIn.waiting", anchor: .bottom) }
                    }
                    .onChange(of: canRetryLink) { _, retry in
                        if !retry, linkID != nil { proxy.scrollTo("account.emailSignIn.waiting", anchor: .bottom) }
                    }
            }
            #else
            formContent
            #endif
            actions
        }
        .padding(MinitiDesignSystem.Spacing.page)
        .modifier(AccountUITestAppearanceProbe(name: "email"))
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 440)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
        .onDisappear { pollTask?.cancel() }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
            Text(mode == .move ? "Join another account by email" : "Sign in with email")
                .accessibilityIdentifier("account.emailSignIn.heading")
                .font(.system(size: readingMetrics.dialogHeadingSize, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(mode == .move
                 ? "Enter the email on the account to join. miniti sends it a link; open it anywhere and press Approve. This device keeps its meetings, usage and connections and joins that account."
                 : "Enter the email on your account. miniti sends it a link; open it anywhere and press Approve, and this device joins the account.")
                .font(.system(size: readingMetrics.dialogBodySize))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Email", text: $email)
                .accessibilityIdentifier("account.emailSignIn.field")
                .textFieldStyle(.roundedBorder)
                .disabled(linkID != nil)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .focused($emailFieldFocused)
                #endif
            if linkID != nil && !canRetryLink {
                HStack(spacing: 8) {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                    Text("Waiting for you to approve the link. It works for 15 minutes.")
                        .accessibilityIdentifier("account.emailSignIn.waiting")
                        .font(.system(size: readingMetrics.dialogBodySize))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id("account.emailSignIn.waiting")
            }
            if let error {
                Text(error)
                    .accessibilityIdentifier("account.emailSignIn.error")
                    .id("account.emailSignIn.error")
                    .font(.system(size: readingMetrics.dialogBodySize))
                    .foregroundStyle(ColorPalette.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        let layout = stacksActions
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control))
            : AnyLayout(HStackLayout())
        return layout {
            if !stacksActions { Spacer() }
            Button { pollTask?.cancel(); dismiss() } label: { actionLabel("Cancel") }
                .keyboardShortcut(.cancelAction)
            if canRetryLink, let linkID {
                Button { canRetryLink = false; error = nil; poll(linkID) } label: { actionLabel("Try again") }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                Button { self.linkID = nil; canRetryLink = false; send() } label: { actionLabel("New link") }
                    .disabled(isWorking)
            } else {
                Button { send() } label: { actionLabel("Send link") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String) -> some View {
        #if os(iOS)
        Text(title)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .minitiMinimumControlTarget()
        #else
        Text(title)
        #endif
    }

    private func send() {
        #if os(iOS)
        emailFieldFocused = false
        #endif
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
                        canRetryLink = true
                    }
                    isWorking = false
                    return
                }
            }
            error = "Could not finish checking this link. Try again, or request a new link."
            canRetryLink = true
        }
    }
}


struct APIModeOptions: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
            option(appState.shouldShowManagedSubscriptionPlaceholder ? "miniti (checking plan…)" : appState.isPro ? "miniti Pro (5,000 min/month)" : "miniti Free (500 min/month)", mode: .managed)
            option("My own Deepgram and OpenAI accounts", mode: .byok)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("API mode")
    }
    private func option(_ title: String, mode: AppMode) -> some View {
        Button { appState.appModeRaw = mode.rawValue } label: {
            HStack(alignment: .firstTextBaseline, spacing: MinitiDesignSystem.Spacing.standard) {
                Image(systemName: appState.appMode == mode ? "largecircle.fill.circle" : "circle")
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ColorPalette.Text.primary)
            .padding(.vertical, MinitiDesignSystem.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appState.appMode == mode ? .isSelected : [])
    }
}

/// Calendar headings replace ambiguous per-row abbreviations on both platforms.
enum UpcomingCalendarDay: String, CaseIterable, Identifiable {
    case today, tomorrow, later
    var id: String { rawValue }
    func contains(_ date: Date?, end: Date? = nil, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date else { return self == .later }
        let isToday = calendar.isDate(date, inSameDayAs: now) || (date < now && (end ?? .distantPast) > now)
        let isTomorrow = calendar.date(byAdding: .day, value: 1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        switch self {
        case .today: return isToday
        case .tomorrow: return isTomorrow
        case .later: return !isToday && !isTomorrow
        }
    }
}

/// A native button owns the entire calendar heading, including its empty space.
struct UpcomingCalendarDisclosureStyle: DisclosureGroupStyle {
    let day: UpcomingCalendarDay
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.control) {
            Button {
                let toggle = { configuration.isExpanded.toggle() }
                if reduceMotion { toggle() }
                else { withAnimation(.easeInOut(duration: MinitiDesignSystem.Motion.disclosureDuration), toggle) }
            } label: {
                HStack {
                    configuration.label
                    Spacer(minLength: MinitiDesignSystem.Spacing.standard)
                    Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(ColorPalette.Text.muted)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: MinitiDesignSystem.Control.minimumIconHitSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar.section.\(day.rawValue)")
            .accessibilityLabel("\(day.rawValue), \(count) \(count == 1 ? "meeting" : "meetings")")
            .accessibilityValue(configuration.isExpanded ? "expanded" : "collapsed")
            .accessibilityHint(configuration.isExpanded ? "Collapse meetings" : "Show meetings")
            if configuration.isExpanded { configuration.content }
        }
    }
}

#if os(macOS)
/// The providers report approximate preparation progress, not a byte-accurate ETA.
struct LocalModelProgress: View {
    private let label: String
    private let progress: Double?
    private let detail: String?
    init(status: OnDeviceTranscriptionService.Status) {
        switch status {
        case .unsupported: (label, progress, detail) = ("Requires Apple silicon", nil, nil)
        case .idle: (label, progress, detail) = ("Not loaded", nil, nil)
        case .preparing(let fraction): (label, progress, detail) = ("Preparing model", fraction, nil)
        case .ready: (label, progress, detail) = ("Ready on this Mac", nil, nil)
        case .failed(let message): (label, progress, detail) = ("Model unavailable. Retry in Models settings.", nil, message)
        }
    }
    init(status: OnDeviceDiarizationService.Status) {
        switch status {
        case .unsupported: (label, progress, detail) = ("Requires Apple silicon", nil, nil)
        case .idle: (label, progress, detail) = ("Not loaded", nil, nil)
        case .preparing(let fraction): (label, progress, detail) = ("Preparing model", fraction, nil)
        case .ready: (label, progress, detail) = ("Ready on this Mac", nil, nil)
        case .failed(let message): (label, progress, detail) = ("Model unavailable. Retry in Models settings.", nil, message)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
            HStack(spacing: MinitiDesignSystem.Spacing.compact) {
                Text(label)
                if let progress, progress > 0, progress < 1 {
                    Text("about \(Int(progress * 10) * 10)%").monospacedDigit()
                }
            }
            if let progress {
                if progress > 0, progress < 1 { ProgressView(value: progress).progressViewStyle(.linear).tint(ColorPalette.Text.muted) }
                else { ProgressView().controlSize(.mini) }
            }
        }
        .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
        .help(detail ?? label)
        .accessibilityElement(children: .combine)
    }
}

struct LocalModelsStatusButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var transcription: OnDeviceTranscriptionService
    @ObservedObject var speakers: OnDeviceDiarizationService
    private var states: [String] {
        var result: [String] = []
        if appState.onDeviceTranscriptionEnabled { switch transcription.status {
            case .ready: result.append("ready")
            case .failed, .unsupported: result.append("failed")
            case .idle: result.append("idle")
            case .preparing: result.append("preparing")
            } }
        if appState.onDeviceSpeakerSeparationEnabled { result.append(speakers.preparationState) }
        return result
    }
    private var description: String {
        if states.isEmpty { return "Local models off" }
        if states.contains("failed") { return "A local model needs attention" }
        if states.allSatisfy({ $0 == "ready" }) { return "Local models ready" }
        return states.contains("preparing") ? "Local models preparing" : "Local models not loaded"
    }
    var body: some View {
        Button {
            appState.selectedSettingsTab = SettingsDestination.models.rawValue
            openSettings()
        } label: {
            MinitiHomeActionLabel(
                icon: states.contains("failed") ? "exclamationmark.circle" :
                    states.isEmpty ? "cpu" : states.allSatisfy({ $0 == "ready" }) ? "checkmark.circle" : "arrow.down.circle",
                label: "models")
        }
        .buttonStyle(.plain)
        .help(description + ". Open Models settings.")
        .accessibilityLabel("Models")
        .accessibilityValue(description)
        .accessibilityHint("Open Models settings")
        .accessibilityIdentifier("models.status")
    }
}
#endif


/// The single Home setup choice for where audio is processed. Mixed Settings
/// choices show as custom instead of being overwritten.
enum HomeSetupAudioChoice: Hashable {
    case online, onThisMac, custom

    @MainActor init(appState: AppState) {
        switch (appState.onDeviceTranscriptionEnabled, appState.onDeviceSpeakerSeparationEnabled) {
        case (false, false): self = .online
        case (true, true): self = .onThisMac
        default: self = .custom
        }
    }
}
