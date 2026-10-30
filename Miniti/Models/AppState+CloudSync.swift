import Foundation
import SwiftData

enum CloudExclusionPolicy {
    static func matchingRule(title: String?, rules: [String]) -> String? {
        guard let title else { return nil }
        return rules.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && title.range(of: $0, options: [.caseInsensitive, .literal]) != nil }
    }

    static func excluded(privateMode: Bool, title: String?, rules: [String]) -> Bool {
        if privateMode { return true }
        return matchingRule(title: title, rules: rules) != nil
    }
}

struct MeetingCloudFeedback: Identifiable {
    let id = UUID()
    let meetingID: UUID
    let message: String
}

enum MeetingCloudPrivacyPresentation {
    static func uploadStatus(pause: CloudSyncPause?) -> String {
        switch pause {
        case nil: return "Waiting to put on the cloud"
        case .off: return "Cloud sync is off. This meeting can sync when you enable it."
        case .notManaged: return "This meeting can sync with a managed Pro account."
        case .notPro: return "This meeting can sync when this account has Pro."
        case .notEnrolled, .deviceRemoved: return "Sign in to sync this meeting."
        case .privateMode: return "Cloud sync is paused in private mode."
        case .offline: return "Waiting for a connection to sync this meeting."
        case .unavailable, .notAvailableYet: return "Cloud sync is currently unavailable."
        }
    }

    static func needsRemoval(knownCopy: Bool, uploadInFlight: Bool, canSync: Bool, finished: Bool) -> Bool {
        knownCopy || uploadInFlight || (canSync && finished)
    }
}

enum CloudRuleValidation {
    static func problem(_ input: String, existing: [String]) -> String? {
        let rule = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.isEmpty { return "Enter part of a calendar meeting title." }
        if rule.count > 120 { return "Use 120 characters or fewer." }
        if existing.contains(where: { $0.caseInsensitiveCompare(rule) == .orderedSame }) { return "That rule already exists." }
        if existing.count >= 30 { return "You can keep up to 30 rules. Remove one to add another." }
        return nil
    }
}

extension AppState {
    func cloudExclusionForNextMeeting(event: MinitiAPIService.CalendarEvent? = nil) -> Bool {
        CloudExclusionPolicy.excluded(privateMode: privateModeEnabled, title: event?.title, rules: cloudExclusionRules)
    }

    func applyLateCalendarCloudExclusion() {
        guard isRecording, activeMeetingCloudOverride == nil, let meeting = currentMeeting, !meeting.syncExcluded,
              let event = selectedCalendarEvent,
              CloudExclusionPolicy.excluded(privateMode: privateModeEnabled, title: event.title, rules: cloudExclusionRules) else { return }
        // The row is still live and ineligible for upload. Persist the sticky decision
        // through the same save path used by the History action, before finalisation.
        if modelContext != nil { setMeetingExcludedFromCloud(meeting, excluded: true) }
        else { meeting.syncExcluded = true }
    }
}
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cloud sync wiring (3.0.0): when the engine may run, what it reads and writes, and the
/// Settings → Cloud actions. Everything here is a no-op while `cloudSyncEnabled` is false.
extension AppState: CloudSyncHost {
    // MARK: Host

    var cloudModelContext: ModelContext? { modelContext }

    var liveMeetingID: UUID? { currentMeeting?.id }

    var cloudUploadProtectedMeetingID: UUID? {
        guard isStartingMeeting || isRecording || isResumingRecording || isFinalizingMeeting else { return nil }
        return currentMeeting?.id
    }

    func cloudProtectsIncoming(_ id: UUID) -> Bool {
        currentMeeting?.id == id || finalizingInsightMeetingIDs.contains(id)
    }

    var cloudAccountID: String? { clientAuthStatus.accountID }

    /// Nil when every gate is open: switch on, managed mode, enrolled, private mode off, Pro.
    var cloudPauseReason: CloudSyncPause? {
        if !cloudSyncEnabled { return .off }
        if appMode != .managed { return .notManaged }
        if !clientAuthStatus.isEnrolled { return .notEnrolled }
        if privateModeEnabled { return .privateMode }
        if !isPro { return .notPro }
        return nil
    }

    func cloudRemoveLocally(_ meeting: Meeting) {
        noteMeetingDeleted(meeting, createTombstone: false)
        modelContext?.delete(meeting)
    }

    func cloudCommit(_ mutate: @escaping () -> Void) -> Bool {
        commit(.cloudSync, mutate: mutate)
    }

    func cloudFetchMeetings(_ descriptor: FetchDescriptor<Meeting>) -> [Meeting]? {
        fetchMeetings(.cloudSync, descriptor: descriptor)
    }

    func cloudFetchTombstones() -> [MeetingTombstone]? {
        guard let modelContext else { return nil }
        return load(.cloudSync) { try modelContext.fetch(FetchDescriptor<MeetingTombstone>()) }
    }

    func cloudDidInsertMeetings(_ meetings: [Meeting]) {
        #if os(macOS)
        if autoExportMarkdown {
            for meeting in meetings where !isMeetingDeleted(meeting.id) {
                exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
            }
        }
        #endif
        NotificationCenter.default.post(name: .minitiMeetingsImported, object: nil)
    }

    func cloudDidChangeMeetings(_ updated: [Meeting]) {
        #if os(macOS)
        // Pulled edits refresh the markdown file the same way an insight update from History does.
        if autoExportMarkdown {
            for meeting in updated where !isMeetingDeleted(meeting.id) {
                exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
            }
        }
        #endif
        NotificationCenter.default.post(name: .minitiMeetingsImported, object: nil)
    }

    func cloudTierChanged(isPro: Bool) {
        if !isPro { Task { await refreshUsage() } }
    }

    // MARK: Lifecycle

    /// Called when the model context arrives; also safe to call again.
    func configureCloudSyncIfNeeded() {
        guard !ScreenshotMode.isActive else { return }
        // The test host is the real app on the real store, with the Mac's own credentials. Its
        // own instance must never sync that store from a second process while the installed
        // app is open (the engine tests drive `CloudSyncEngine` directly with a fake host).
        guard !Self.isRunningUnderXCTest else { return }
        cloudSync.host = self
        if cloudSync.transport == nil {
            if minitiAPIService == nil { minitiAPIService = MinitiAPIService() }
            cloudSync.transport = minitiAPIService
        }
        cloudSync.start()
        if cloudPauseReason == nil { cloudSync.kick(reason: "launch") }
    }

    /// Re-evaluate after any gate moved (switch, mode, enrollment, private mode, tier).
    func refreshCloudSyncState() {
        cloudSync.refreshPause()
    }

    /// App became active: push anything pending and pull what the other devices did.
    func kickCloudSync(reason: String) {
        guard cloudPauseReason == nil else { return }
        cloudSync.kick(reason: reason)
    }

    // MARK: Settings actions

    enum CloudSwitchSource { case user, account }

    /// The switch. A person's flip is also written to the account (3.3.0), so every other
    /// device follows; a flip that follows the account is not written back.
    func setCloudSyncEnabled(_ on: Bool, source: CloudSwitchSource = .user) {
        cloudSyncEnabled = on
        refreshCloudSyncState()
        if on {
            configureCloudSyncIfNeeded()
            cloudSync.kick(reason: "enabled")
        }
        DebugLogger.shared.log(.app, "Cloud sync \(on ? "on" : "off")\(source == .account ? " (follows the account)" : "")")
        if source == .account {
            cloudSync.note(.info, on ? "Cloud on" : "Cloud off", "turned \(on ? "on" : "off") on another device")
        } else if appMode == .managed {
            Task { await pushCloudAccountFlag(on) }
        }
    }

    // MARK: One switch per account (3.3.0)

    enum CloudAccountFlagAction: Equatable {
        case none
        /// The account already says what this device has; remember the version.
        case acknowledge
        /// Write this device's choice to the account.
        case push(Bool)
        /// Take the account's choice on this device.
        case follow(Bool)
    }

    /// What to do with the account's cloud switch after a usage check (`cloud_enabled`,
    /// `cloud_version` on `/api/usage`).
    ///
    /// - `pending` is a choice this device made that the account has not confirmed yet
    ///   (offline, failed write): it wins until it lands, so a flip made offline is never undone
    ///   by a stale server value.
    /// - An unset account (nil: created before 3.3.0, or new) learns this device's switch when
    ///   it is on; an off device teaches nothing, so a free account never writes anything.
    /// - A version this device has not applied means another device changed the switch:
    ///   follow it. "On" waits for Pro and the end of private mode, and leaves the version
    ///   unapplied so the next usage check tries again; "off" always applies.
    nonisolated static func cloudAccountFlagAction(
        localOn: Bool, pending: Bool?, serverEnabled: Bool?, serverVersion: Int, appliedVersion: Int,
        isPro: Bool, privateMode: Bool
    ) -> CloudAccountFlagAction {
        if let pending { return .push(pending) }
        guard let serverEnabled else { return localOn ? .push(true) : .none }
        guard serverVersion > appliedVersion else { return .none }
        if serverEnabled == localOn { return .acknowledge }
        if serverEnabled { return isPro && !privateMode ? .follow(true) : .none }
        return .follow(false)
    }

    /// Per account, so joining another account starts from "never applied" without any reset.
    private static func cloudFlagVersionKey(_ account: String) -> String { "cloudSync.accountFlag.version.\(account)" }
    private static func cloudFlagPendingKey(_ account: String) -> String { "cloudSync.accountFlag.pending.\(account)" }

    /// Runs after every successful usage check.
    func applyAccountCloudFlag() {
        guard appMode == .managed, let usage = usageInfo, let account = cloudAccountID else { return }
        let defaults = UserDefaults.standard
        let version = usage.cloudVersion ?? 0
        let action = Self.cloudAccountFlagAction(
            localOn: cloudSyncEnabled,
            pending: defaults.object(forKey: Self.cloudFlagPendingKey(account)) as? Bool,
            serverEnabled: usage.cloudEnabled,
            serverVersion: version,
            appliedVersion: defaults.integer(forKey: Self.cloudFlagVersionKey(account)),
            isPro: isPro,
            privateMode: privateModeEnabled
        )
        switch action {
        case .none:
            break
        case .acknowledge:
            defaults.set(version, forKey: Self.cloudFlagVersionKey(account))
        case .push(let on):
            Task { await pushCloudAccountFlag(on) }
        case .follow(let on):
            defaults.set(version, forKey: Self.cloudFlagVersionKey(account))
            setCloudSyncEnabled(on, source: .account)
        }
    }

    /// Write this device's choice to the account. The choice stays marked pending until the
    /// server confirms it, and `applyAccountCloudFlag` retries a pending one at every usage check.
    func pushCloudAccountFlag(_ on: Bool) async {
        guard appMode == .managed, let account = cloudAccountID else { return }
        let defaults = UserDefaults.standard
        defaults.set(on, forKey: Self.cloudFlagPendingKey(account))
        guard let api = minitiAPIService else { return }
        do {
            let version = try await api.setAccountCloud(enabled: on)
            // A newer flip made while this one was in flight keeps its own pending mark.
            if (defaults.object(forKey: Self.cloudFlagPendingKey(account)) as? Bool) == on {
                defaults.removeObject(forKey: Self.cloudFlagPendingKey(account))
                defaults.set(version, forKey: Self.cloudFlagVersionKey(account))
            }
            DebugLogger.shared.log(.app, "Cloud switch \(on ? "on" : "off") written to the account (version \(version))")
        } catch {
            DebugLogger.shared.log(.app, "Cloud switch not written to the account yet (\(error)); retrying at the next usage check", level: .warning)
        }
    }

    /// Per-meeting "Keep off the cloud". Turning it on removes the cloud copy; turning it off
    /// lets the next sync upload the meeting.
    private func meetingMayHaveCloudCopy(_ meeting: Meeting) -> Bool {
        MeetingCloudPrivacyPresentation.needsRemoval(
            knownCopy: meeting.cloudRevision > 0 || meeting.syncedAt != nil || meeting.syncFingerprint != nil
                || cloudFetchTombstones()?.contains(where: { $0.id == meeting.id }) == true,
            uploadInFlight: cloudSync.isUploading(meeting.id), canSync: cloudPauseReason == nil,
            finished: meeting.endTime != nil)
    }

    @discardableResult
    func setMeetingExcludedFromCloud(_ meeting: Meeting, excluded: Bool) -> Bool {
        guard !isMeetingDeleted(meeting.id), let modelContext else { return false }
        if currentMeeting?.id == meeting.id { activeMeetingCloudOverride = excluded }
        let needsRemoval = excluded && meetingMayHaveCloudCopy(meeting)
        let saved = commit(.cloudSync, mutate: {
            meeting.syncExcluded = excluded
            meeting.cloudRestoreRequested = !excluded
            if needsRemoval {
                if let pending = self.cloudFetchTombstones()?.first(where: { $0.id == meeting.id }) {
                    pending.cloudRevision = max(pending.cloudRevision, meeting.cloudRevision)
                } else {
                    modelContext.insert(MeetingTombstone(id: meeting.id, cloudRevision: meeting.cloudRevision))
                }
                meeting.cloudRevision = 0
                meeting.syncFingerprint = nil
                meeting.syncedAt = nil
            }
            if !excluded { meeting.syncFingerprint = nil }
        })
        DiagnosticTimeline.shared.record(.cloudChoice, fields: ["excluded": String(excluded), "reason": "manual", "outcome": saved ? "success" : "failed"])
        cloudSync.noteLocalChange()
        return saved
    }

    func toggleMeetingCloudStorage(_ meeting: Meeting) {
        if currentMeeting?.id == meeting.id, privateModeEnabled, privateModeLocked { return }
        let excluded = !meeting.syncExcluded
        let hadCloudCopy = meetingMayHaveCloudCopy(meeting)
        let saved = setMeetingExcludedFromCloud(meeting, excluded: excluded)
        let message: String
        if !saved {
            message = "This change could not be saved. Try again."
        } else if excluded {
            message = hadCloudCopy
                ? "This meeting won't be synced to your cloud. Cloud copy removal is pending."
                : "This meeting won't be synced to your cloud."
        } else if cloudPauseReason != nil {
            message = MeetingCloudPrivacyPresentation.uploadStatus(pause: cloudPauseReason)
        } else {
            message = "This meeting will be saved to the cloud."
        }
        meetingCloudFeedback = MeetingCloudFeedback(meetingID: meeting.id, message: message)
    }

    @discardableResult
    func addCloudExclusionRule(_ input: String) -> Bool {
        guard CloudRuleValidation.problem(input, existing: cloudExclusionRules) == nil else { return false }
        cloudExclusionRules.append(input.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }

    /// "Delete cloud copy": every meeting, token and connected app on the server. Local
    /// meetings stay and are re-uploaded if the switch is on.
    func deleteCloudCopy() async -> Bool {
        guard let api = minitiAPIService else { return false }
        do {
            try await api.deleteCloudCopy()
            cloudSync.resetBookkeeping()
            return true
        } catch {
            DebugLogger.shared.log(.app, "Delete cloud copy FAILED: \(error)", level: .warning)
            return false
        }
    }
}

// MARK: - Sign in by email (3.0.0)

extension AppState {
    /// Ask for the approval link. Returns the link id to poll, or nil with the error set.
    func startEmailSignIn(email: String) async -> String? {
        managedEnrollmentError = nil
        do {
            return try await clientAuthManager.startEmailSignIn(email: email)
        } catch {
            let (message, code) = Self.emailStartFailure(for: error)
            managedEnrollmentError = message
            enqueueDiagnosticEvent("email_signin_failed", category: .app, level: .warning, details: ["stage": "start", "code": code])
            return nil
        }
    }

    /// Sending the link can fail in ways that are not the person's fault; each gets its own
    /// copy instead of the raw server code (A2e).
    nonisolated static func emailStartFailure(for error: Error) -> (message: String, code: String) {
        switch error {
        case ClientAuthError.rateLimited:
            return ("Too many attempts. Wait a few minutes and try again.", "rate_limited")
        case ClientAuthError.unavailable:
            return ("Email sign-in is not available right now. Try again later.", "unavailable")
        case ClientAuthError.network(let detail):
            return ("Could not reach miniti's servers. Check your connection and try again.", "network:\(detail.prefix(40))")
        case ClientAuthError.server(let code, _):
            switch code {
            case "email_send_failed": return ("The email could not be sent. Try again in a minute.", code)
            case "email_unavailable", "cloud_unavailable": return ("Email sign-in is not available right now. Try again later.", code)
            case "invalid_email": return ("That does not look like an email address.", code)
            default: return ("Could not send the link (\(code)). Try again.", code)
            }
        default:
            return (error.localizedDescription, "unknown")
        }
    }

    enum EmailSignInPoll: Equatable {
        case pending, approved, expired
        /// The status could not be checked (network, server); the link may still be fine.
        case unreachable
    }

    /// Poll the link. A failed check is reported as such, never as an expired link (A2e).
    func emailSignInStatus(linkID: String) async -> EmailSignInPoll {
        do {
            switch try await clientAuthManager.emailSignInStatus(linkID: linkID) {
            case .pending: return .pending
            case .approved: return .approved
            case .expired: return .expired
            }
        } catch ClientAuthError.server(let code, _) where code.hasPrefix("login_link") {
            return .expired
        } catch {
            return .unreachable
        }
    }

    /// Why a join did not complete, in the person's words (A2e).
    nonisolated static func joinFailure(for error: Error, keyWasUnusable: Bool) -> (message: String, code: String) {
        switch error {
        case ClientAuthError.deviceAlreadyEnrolled where keyWasUnusable:
            return (recoveryBelongsElsewhereMessage, "device_already_enrolled")
        case ClientAuthError.deviceAlreadyEnrolled:
            return (ClientAuthError.deviceAlreadyEnrolled.localizedDescription, "device_already_enrolled")
        case ClientAuthError.deviceCapReached(let cap):
            return (ClientAuthError.deviceCapReached(cap).localizedDescription, "device_cap_reached")
        case ClientAuthError.subscriptionConflict:
            return (ClientAuthError.subscriptionConflict.localizedDescription, "subscription_conflict")
        case ClientAuthError.server(let code, _) where code.hasPrefix("login_link"):
            return ("The link expired or was already used. Send a new one.", code)
        case ClientAuthError.network:
            return ("Could not reach miniti's servers. Check your connection and try again.", "network")
        case let authError as ClientAuthError:
            return (authError.localizedDescription, String(describing: authError).prefix(40).description)
        default:
            return (error.localizedDescription, "unknown")
        }
    }

    /// The link was approved on the web: join that account. An enrolled device moves (keeps
    /// its meetings, usage and integrations); an unenrolled one restores into it.
    func joinAccount(approvedLinkID: String) async -> Bool {
        guard !ScreenshotMode.isActive else { return true }
        managedEnrollmentError = nil
        let manager = clientAuthManager
        let keyWasUnusable = manager.credentialState == .keyUnusable
        do {
            if manager.keyNeedsReauthentication {
                // The stored key failed: prove the link with a fresh key through restore, and
                // keep the old credential until the server accepts the new one.
                isEnrollingManagedDevice = true
                defer { isEnrollingManagedDevice = false }
                try await manager.reauthenticate(loginLinkID: approvedLinkID, label: Self.managedDeviceLabel)
            } else if manager.isEnrolled {
                _ = try await manager.attachToAccount(loginLinkID: approvedLinkID)
            } else {
                isEnrollingManagedDevice = true
                defer { isEnrollingManagedDevice = false }
                manager.discardDraft()
                try await manager.restoreAccount(loginLinkID: approvedLinkID, label: Self.managedDeviceLabel)
            }
            cloudSync.resetBookkeeping()
            refreshClientAuthStatus()
            await loadManagedDevices()
            if appMode == .managed { await refreshUsage() }
            return true
        } catch {
            // Includes the A2d case: the approved email belongs to another account while this
            // installation is still active on its own. Say so; keep the credential.
            let (message, code) = Self.joinFailure(for: error, keyWasUnusable: keyWasUnusable)
            managedEnrollmentError = message
            enqueueDiagnosticEvent("email_signin_failed", category: .app, level: .warning, details: ["stage": "complete", "code": code])
            refreshClientAuthStatus()
            return false
        }
    }

    nonisolated static var recoveryBelongsElsewhereMessage: String {
        #if os(macOS)
        return "That email belongs to another miniti account. This Mac is still on its current one. Remove it from that account on another device or the web, then sign in again."
        #else
        return "That email belongs to another miniti account. This device is still on its current one. Remove it from that account on another device or the web, then sign in again."
        #endif
    }

    /// True when this device joined by email and holds no recovery key of its own.
    var managedDeviceHasNoRecoveryKey: Bool {
        clientAuthStatus.isEnrolled && (clientAuthManager.revealRecoveryKey()?.isEmpty ?? true)
    }
}

// MARK: - Account email (B6a, docs/archive/account-sending-consent-ux-plan.md)

/// The addresses on the account as the server returns them: the verified one, and a
/// replacement awaiting its link. Both can be set at once; "protected by email" means
/// `verified` is set, whatever is pending.
struct AccountEmail: Equatable {
    var verified: String?
    var pending: String?

    var isProtected: Bool { verified != nil }
    var isEmpty: Bool { verified == nil && pending == nil }
}

enum AccountEmailState: Equatable {
    /// No answer yet for this account.
    case loading
    /// The last load failed; the message says why. Never read as "no email".
    case unavailable(String)
    case loaded(AccountEmail)

    var email: AccountEmail? {
        if case .loaded(let email) = self { return email }
        return nil
    }
}

/// The outcome of adding an email, for the control that asked.
enum AccountEmailAddOutcome: Equatable {
    /// A confirmation link went to the address; it is pending until opened.
    case sent(String)
    /// The address is already the verified one.
    case alreadyVerified
    /// Another account holds it; the account section offers Switch account.
    case inUse
    /// Delivery or the server failed; the previous state stands and the action can be retried.
    case failed(String)
    /// The account changed while the request ran: nothing was applied or shown (F1).
    case staleAccount
}

enum AccountEmailRemoveOutcome: Equatable {
    case removed
    case failed(String)
    /// The account changed while the request ran: nothing was applied or shown (F1).
    case staleAccount
}

/// A refresh that could not run at once and waits for the in-flight work (F2).
struct AccountEmailRefreshRequest: Equatable {
    var reason: String
    var force: Bool
}

/// One consumable request to show a Settings destination and scroll to a row (F4). iOS
/// consumes it once; the Mac goes through `jumpToSetting` directly.
struct SettingsNavigationRequest: Equatable {
    let id: UUID
    let destination: SettingsDestination
    let target: String?

    init(destination: SettingsDestination, target: String?) {
        self.id = UUID()
        self.destination = destination
        self.target = target
    }
}

extension AppState {
    /// The Home card shows only when it can help: an enrolled account with a meeting saved,
    /// whose email state is known and empty, whose recovery key has not been acknowledged, and
    /// which the person has not dismissed. Loading and unavailable states suppress it, so a
    /// failed fetch never nags.
    nonisolated static func accessCardVisible(
        enrolled: Bool,
        emailState: AccountEmailState,
        hasSavedMeeting: Bool,
        recoveryKeyAcknowledged: Bool,
        dismissed: Bool
    ) -> Bool {
        guard enrolled, hasSavedMeeting, !dismissed, !recoveryKeyAcknowledged else { return false }
        guard case .loaded(let email) = emailState else { return false }
        return !email.isProtected
    }

    /// Reads under 60 s old are fresh enough for an activation; a mutation or an account change
    /// clears the stamp so the next refresh always goes out.
    static let accountEmailFreshness: TimeInterval = 60

    /// Load the account's email (F2). One read in flight at a time; a refresh that arrives
    /// while a read or a mutation runs is kept as one pending request (force merged with OR)
    /// and run once the in-flight work ends, for the account current at that time. A forced
    /// request bypasses the freshness check. A response applies only if the account generation
    /// is unchanged and no newer read or mutation was issued meanwhile.
    func refreshAccountEmail(reason: String, force: Bool = false) async {
        guard appMode == .managed, clientAuthStatus.isEnrolled, minitiAPIService != nil else {
            accountEmailPending = nil
            return
        }
        if accountEmailInFlight || accountEmailMutationInFlight {
            accountEmailPending = AccountEmailRefreshRequest(reason: reason, force: force || (accountEmailPending?.force ?? false))
            return
        }
        if !force, let last = accountEmailLastLoaded, Date().timeIntervalSince(last) < Self.accountEmailFreshness, case .loaded = accountEmailState { return }
        await performAccountEmailRead(reason: reason)
        await runPendingAccountEmailRefresh()
    }

    private func performAccountEmailRead(reason: String) async {
        guard let api = minitiAPIService else { return }
        accountEmailInFlight = true
        defer { accountEmailInFlight = false }
        let generation = accountGeneration
        accountEmailSequence += 1
        let sequence = accountEmailSequence
        do {
            let answer = try await api.cloudEmail()
            guard generation == accountGeneration, sequence == accountEmailSequence else {
                DebugLogger.shared.log(.app, "Account email: dropped a stale read (\(reason))")
                return
            }
            accountEmailState = .loaded(AccountEmail(verified: answer.email, pending: answer.pending))
            accountEmailLastLoaded = Date()
        } catch {
            guard generation == accountGeneration, sequence == accountEmailSequence else { return }
            accountEmailState = .unavailable(Self.accountEmailMessage(for: error))
            accountEmailLastLoaded = nil
            DebugLogger.shared.log(.app, "Account email: load failed (\(reason)): \(error)")
        }
    }

    /// Consume the pending request, if any, and run it for the current account. Completion
    /// alone never requeues work: only a new event during the replacement can.
    private func runPendingAccountEmailRefresh() async {
        guard let next = accountEmailPending else { return }
        accountEmailPending = nil
        guard appMode == .managed, clientAuthStatus.isEnrolled, !accountEmailMutationInFlight else { return }
        await refreshAccountEmail(reason: next.reason, force: next.force)
    }

    /// Send a confirmation link for `raw` (F1). Mutations from this client run one at a time;
    /// the account context is captured before dispatch, revalidated when the turn comes, and
    /// checked again after the server answers. A result for an account that is no longer
    /// current is `.staleAccount`: nothing applied, nothing shown. After any completed
    /// mutation a forced read reconciles the state with the server.
    func addAccountEmail(_ raw: String) async -> AccountEmailAddOutcome {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), address.count >= 3 else { return .failed("Enter an email address.") }
        if case .loaded(let current) = accountEmailState, current.verified == address { return .alreadyVerified }
        return await withAccountEmailMutation(stale: .staleAccount) { [weak self] generation in
            guard let self, let api = self.minitiAPIService else { return .failed("Not signed in.") }
            do {
                try await api.setCloudEmail(address)
                guard generation == self.accountGeneration else { return .staleAccount }
                let verified = self.accountEmailState.email?.verified
                self.accountEmailState = .loaded(AccountEmail(verified: verified, pending: address))
                self.accountEmailLastLoaded = nil
                return .sent(address)
            } catch CloudSyncError.server(let code, _) where code == "email_in_use" {
                guard generation == self.accountGeneration else { return .staleAccount }
                return .inUse
            } catch {
                guard generation == self.accountGeneration else { return .staleAccount }
                return .failed(Self.accountEmailMessage(for: error))
            }
        }
    }

    /// Remove the email (F1 rules as for add). Every web session and connected app on the
    /// account goes with it.
    func removeAccountEmail() async -> AccountEmailRemoveOutcome {
        await withAccountEmailMutation(stale: .staleAccount) { [weak self] generation in
            guard let self, let api = self.minitiAPIService else { return .failed("Not signed in.") }
            do {
                try await api.removeCloudEmail()
                guard generation == self.accountGeneration else { return .staleAccount }
                self.accountEmailState = .loaded(AccountEmail())
                self.accountEmailLastLoaded = nil
                return .removed
            } catch {
                guard generation == self.accountGeneration else { return .staleAccount }
                return .failed(Self.accountEmailMessage(for: error))
            }
        }
    }

    /// Serialize one mutation behind the previous one, revalidate the account before dispatch,
    /// invalidate older reads, and reconcile afterwards through the F2 queue.
    private func withAccountEmailMutation<T>(stale: T, _ body: @escaping @MainActor (Int) async -> T) async -> T {
        let previous = accountEmailMutationTask
        let generation = accountGeneration
        let result = Task<T, Never> { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return stale }
            guard generation == self.accountGeneration, self.appMode == .managed, self.clientAuthStatus.isEnrolled else { return stale }
            self.accountEmailMutationInFlight = true
            self.accountEmailSequence += 1
            let value = await body(generation)
            self.accountEmailMutationInFlight = false
            if generation == self.accountGeneration {
                // The server's completed change must not be forgotten by any read that ran
                // alongside: read it back now, for this account.
                self.accountEmailLastLoaded = nil
                let queued = self.accountEmailPending
                self.accountEmailPending = nil
                await self.refreshAccountEmail(reason: queued?.reason ?? "after mutation", force: true)
            } else {
                await self.runPendingAccountEmailRefresh()
            }
            // The account may have changed during the reconciling read too: a result for
            // another account is never returned to a view that now shows this one.
            guard generation == self.accountGeneration else { return stale }
            return value
        }
        accountEmailMutationTask = Task { _ = await result.value }
        return await result.value
    }

    /// Refresh on the browser handoff (the link was opened) and on activation (a link may have
    /// been opened on another device, an address added elsewhere, or a failed load retried).
    func installAccountEmailObservers() {
        NotificationCenter.default.addObserver(forName: .minitiCloudCallback, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountEmail(reason: "browser callback", force: true) }
        }
        #if os(macOS)
        let activation = NSApplication.didBecomeActiveNotification
        #else
        let activation = UIApplication.didBecomeActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: activation, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountEmail(reason: "activate") }
        }
    }

    nonisolated static func accountEmailMessage(for error: Error) -> String {
        switch error {
        case CloudSyncError.offline: return "No connection."
        case CloudSyncError.rateLimited: return "Too many attempts. Try again in a minute."
        case CloudSyncError.unavailable: return "The account service is unavailable right now."
        case CloudSyncError.requiresManaged: return "Email needs the managed plan."
        case CloudSyncError.notEnrolled: return "Not signed in."
        case CloudSyncError.revoked: return "This device was signed out."
        case CloudSyncError.server(let code, let status):
            if code == "email_unavailable" { return "Email delivery is not available right now. Try again later." }
            if code == "email_send_failed" { return "The confirmation email could not be sent. Try again in a minute." }
            if code == "invalid_email" { return "Enter a valid email address." }
            return "Could not check this account's email (\(status == 0 ? code : String(status)))."
        default:
            return "Could not check this account's email."
        }
    }
}
