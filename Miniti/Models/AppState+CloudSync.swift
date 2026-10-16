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

    func setCloudSyncEnabled(_ on: Bool) {
        cloudSyncEnabled = on
        refreshCloudSyncState()
        if on {
            configureCloudSyncIfNeeded()
            cloudSync.kick(reason: "enabled")
        }
        DebugLogger.shared.log(.app, "Cloud sync \(on ? "on" : "off")")
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
