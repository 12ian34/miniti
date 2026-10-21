import Foundation
import SwiftData

/// Cloud sync wiring (3.0.0): when the engine may run, what it reads and writes, and the
/// Settings → Cloud actions. Everything here is a no-op while `cloudSyncEnabled` is false.
extension AppState: CloudSyncHost {
    // MARK: Host

    var cloudModelContext: ModelContext? { modelContext }

    var liveMeetingID: UUID? { currentMeeting?.id }

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
    func setMeetingExcludedFromCloud(_ meeting: Meeting, excluded: Bool) {
        guard !isMeetingDeleted(meeting.id), let modelContext else { return }
        commit(.cloudSync, mutate: {
            meeting.syncExcluded = excluded
            if excluded, meeting.cloudRevision > 0 {
                modelContext.insert(MeetingTombstone(id: meeting.id, cloudRevision: meeting.cloudRevision))
                meeting.cloudRevision = 0
                meeting.syncFingerprint = nil
                meeting.syncedAt = nil
            }
            if !excluded { meeting.syncFingerprint = nil }
        })
        cloudSync.noteLocalChange()
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
            return try await ClientAuthManager.shared.startEmailSignIn(email: email)
        } catch {
            managedEnrollmentError = error.localizedDescription
            return nil
        }
    }

    func emailSignInStatus(linkID: String) async -> ClientAuthManager.EmailSignInStatus? {
        try? await ClientAuthManager.shared.emailSignInStatus(linkID: linkID)
    }

    /// The link was approved on the web: join that account. An enrolled device moves (keeps
    /// its meetings, usage and integrations); an unenrolled one restores into it.
    func joinAccount(approvedLinkID: String) async -> Bool {
        guard !ScreenshotMode.isActive else { return true }
        managedEnrollmentError = nil
        let manager = ClientAuthManager.shared
        do {
            if manager.isEnrolled {
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
            managedEnrollmentError = error.localizedDescription
            refreshClientAuthStatus()
            return false
        }
    }

    /// True when this device joined by email and holds no recovery key of its own.
    var managedDeviceHasNoRecoveryKey: Bool {
        clientAuthStatus.isEnrolled && (ClientAuthManager.shared.revealRecoveryKey()?.isEmpty ?? true)
    }
}
