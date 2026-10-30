import Foundation
import SwiftData

/// One user-visible action that writes to or reads from the meeting store.
enum PersistenceOperation: String, CaseIterable {
    case pin
    case delete
    case discard
    case rename
    case speakerEdit = "speaker_edit"
    case transcriptTrim = "transcript_trim"
    case transcriptRestore = "transcript_restore"
    case correction
    case insights
    case finalInsights = "final_insights"
    case insightsRegeneration = "insights_regeneration"
    case templateChange = "template_change"
    case docsTopics = "docs_topics"
    case docsLookup = "docs_lookup"
    case staleMeetingFinalize = "stale_meeting_finalize"
    case sessionReference = "session_reference"
    case liveTranscript = "live_transcript"
    case historyLoad = "history_load"
    case interruptedMeetingCheck = "interrupted_meeting_check"
    case exportAll = "export_all"
    case cloudSync = "cloud_sync"
    case watchImport = "watch_import"

    /// Lowercase noun for the banner: "<label> didn't save".
    var userLabel: String {
        switch self {
        case .pin: return "pin"
        case .delete: return "delete"
        case .discard: return "discard"
        case .rename: return "rename"
        case .speakerEdit: return "speaker change"
        case .transcriptTrim: return "transcript edit"
        case .transcriptRestore: return "transcript undo"
        case .correction: return "correction"
        case .insights: return "insights"
        case .finalInsights: return "final insights"
        case .insightsRegeneration: return "insights update"
        case .templateChange: return "template change"
        case .docsTopics: return "docs topics"
        case .docsLookup: return "docs lookup"
        case .staleMeetingFinalize: return "finishing an interrupted meeting"
        case .sessionReference: return "session record"
        case .liveTranscript: return "live transcript"
        case .historyLoad: return "history"
        case .interruptedMeetingCheck: return "interrupted meeting check"
        case .exportAll: return "export"
        case .cloudSync: return "cloud sync"
        case .watchImport: return "watch recording"
        }
    }

    /// Whether re-running the same commit is safe. Stale finalization is retried by the next
    /// launch and the live transcript queue retries itself on the next checkpoint; everything
    /// else, including a delete that is still pending in the context, can simply be saved again.
    var isRetryable: Bool {
        switch self {
        case .staleMeetingFinalize, .liveTranscript:
            return false
        default:
            return true
        }
    }
}

/// What the root banner shows. Content-free: the operation name and a timestamp only.
struct PersistenceIssue: Identifiable, Equatable {
    enum Kind: String {
        case save
        case load
    }

    let id: UUID
    let operation: PersistenceOperation
    let kind: Kind
    let occurredAt: Date

    init(operation: PersistenceOperation, kind: Kind, occurredAt: Date = Date()) {
        self.id = UUID()
        self.operation = operation
        self.kind = kind
        self.occurredAt = occurredAt
    }

    var message: String {
        switch (kind, operation) {
        case (.load, .historyLoad):
            return "couldn't load your meetings"
        case (.load, _):
            return "couldn't read your meetings for \(operation.userLabel)"
        case (.save, .liveTranscript):
            return "the live transcript isn't saving. miniti keeps trying every minute"
        case (.save, .delete), (.save, .discard):
            return "\(operation.userLabel) didn't save yet. it goes through with the next successful save"
        case (.save, _):
            return "\(operation.userLabel) didn't save"
        }
    }
}

/// Roadmap P0.3: one observable save and load policy.
///
/// Every user-initiated SwiftData mutation goes through `commit`, every fetch whose failure
/// must not look like "no meetings" goes through `load`/`fetchMeetings`. A failure is logged
/// (domain and code only, never `localizedDescription`, which can echo attribute values),
/// sent as a diagnostics event when the user shares them, and surfaced once at the app root.
///
/// Deliberately no `ModelContext.rollback()` anywhere in this policy: the live-transcript
/// queue shares `mainContext`, so a rollback would discard its unsaved work, and SwiftData
/// traps when a pending cascade delete is rolled back (`ModelSnapshot.swift:46`, seen in the
/// delete tests). Sites that need to undo pass an explicit `revert`; a failed delete stays
/// pending in the context and is committed by the retry or by the next successful save.
extension AppState {
    /// Run `mutate`, then save. On failure run `revert`, report, and return false.
    /// `mutate` and `revert` are stored for the retry action, so they must not capture
    /// anything that outlives the operation unsafely.
    @discardableResult
    func commit(
        _ operation: PersistenceOperation,
        in context: ModelContext? = nil,
        mutate: @escaping () -> Void = {},
        revert: (() -> Void)? = nil
    ) -> Bool {
        guard let context = context ?? modelContext else {
            DebugLogger.shared.log(.app, "Persistence skipped: no model context op=\(operation.rawValue)", level: .warning)
            return false
        }
        mutate()
        do {
            try persistenceSaveHandler(context)
            clearPersistenceIssue(for: operation)
            if operation != .cloudSync { cloudSync.noteLocalChange() }
            // F6: a finalisation or import that produced a finished meeting can make the Home
            // card eligible; the recompute checks the cheap conditions before fetching.
            if operation != .cloudSync, operation != .liveTranscript, !showAccessCard { refreshAccessCard() }
            return true
        } catch {
            revert?()
            let retry: (() -> Void)? = operation.isRetryable
                ? { [weak self] in _ = self?.commit(operation, in: context, mutate: mutate, revert: revert) }
                : nil
            reportPersistenceFailure(operation, kind: .save, error: error, retry: retry)
            return false
        }
    }

    /// Run a read. Returns nil on failure so callers can tell "failed" from "empty".
    func load<T>(_ operation: PersistenceOperation, _ body: () throws -> T) -> T? {
        do {
            let value = try body()
            clearPersistenceIssue(for: operation)
            return value
        } catch {
            reportPersistenceFailure(operation, kind: .load, error: error, retry: nil)
            return nil
        }
    }

    /// Fetch meetings through the injectable seam. Nil means the fetch failed, not that the
    /// store is empty.
    func fetchMeetings(
        _ operation: PersistenceOperation,
        in context: ModelContext? = nil,
        descriptor: FetchDescriptor<Meeting> = FetchDescriptor<Meeting>()
    ) -> [Meeting]? {
        guard let context = context ?? modelContext else {
            DebugLogger.shared.log(.app, "Persistence fetch skipped: no model context op=\(operation.rawValue)", level: .warning)
            return nil
        }
        return load(operation) { try persistenceFetchHandler(context, descriptor) }
    }

    // MARK: Reporting

    /// Log, diagnostics event, banner. Only the operation and the error's domain/code leave
    /// the process.
    func reportPersistenceFailure(_ operation: PersistenceOperation, kind: PersistenceIssue.Kind, error: Error, retry: (() -> Void)?) {
        let nsError = error as NSError
        DebugLogger.shared.log(
            .app,
            "Persistence \(kind.rawValue) FAILED op=\(operation.rawValue) domain=\(nsError.domain) code=\(nsError.code)",
            level: .error
        )
        enqueueDiagnosticEvent(
            "persistence_\(kind.rawValue)_failed",
            category: .app,
            level: .error,
            details: ["op": operation.rawValue, "domain": nsError.domain, "code": String(nsError.code)]
        )
        setPersistenceIssue(PersistenceIssue(operation: operation, kind: kind))
        persistenceRetryAction = retry
    }

    /// A later success for the same operation retires the banner.
    func clearPersistenceIssue(for operation: PersistenceOperation) {
        guard persistenceIssue?.operation == operation else { return }
        setPersistenceIssue(nil)
        persistenceRetryAction = nil
    }

    func dismissPersistenceIssue() {
        setPersistenceIssue(nil)
        persistenceRetryAction = nil
    }

    func retryPersistence() {
        persistenceRetryAction?()
    }
}

extension Notification.Name {
    /// Posted when meetings were inserted or changed outside the main window's own flows
    /// (Granola CSV import in Settings, cloud sync) so the macOS history sidebar refreshes.
    /// iOS history is a `@Query` and updates on its own.
    static let minitiMeetingsImported = Notification.Name("minitiMeetingsImported")
    /// A `miniti-cloud://` link opened the app (the web confirmed an email); Settings → Cloud reloads.
    static let minitiCloudCallback = Notification.Name("minitiCloudCallback")
}

/// A request may only write back to the exact saved inputs it read. Fingerprints are
/// in-process checks, not persisted identities or wire revisions.
struct SavedAIRequest {
    let id: UUID
    let key: String
    let meetingID: UUID
    var input: Int
    let appMode: String
    let credentialGeneration: Int?
    let accountID: String?
    let resolvedNames: Bool
}

extension AppState {
    func savedAIInput(_ meeting: Meeting, resolvedNames: Bool = true) -> Int {
        var hash = Hasher()
        hash.combine(meeting.transcriptRevision)
        if resolvedNames { hash.combine(meeting.fullTranscript) }
        else {
            for segment in meeting.segments.sorted(by: { $0.timestamp < $1.timestamp }) where segment.isFinal {
                hash.combine(segment.id); hash.combine(segment.text); hash.combine(segment.speaker); hash.combine(segment.timestamp)
            }
            for key in meeting.speakerOverrides.sorted() { hash.combine(key); hash.combine(meeting.speakerNames[key]) }
        }
        hash.combine(meeting.language)
        hash.combine(meeting.endTime)
        hash.combine(meeting.speakerOverridesJSON)
        hash.combine(meeting.insightTemplateID)
        hash.combine(meeting.templateDefinitionJSON)
        // Deleting/editing a selected custom definition invalidates an older fill too.
        hash.combine(insightTemplate(id: meeting.insightTemplateID))
        if meeting.insightTemplateID == nil { hash.combine(selectedInsightTemplate) }
        return hash.finalize()
    }

    func beginSavedAIRequest(_ meeting: Meeting, scope: String, resolvedNames: Bool = true) -> SavedAIRequest {
        let id = UUID()
        let key = meeting.id.uuidString + ":" + scope
        savedAIRequests[key] = id
        return SavedAIRequest(id: id, key: key, meetingID: meeting.id,
                              input: savedAIInput(meeting, resolvedNames: resolvedNames), appMode: appMode.rawValue,
                              credentialGeneration: appMode == .managed ? clientAuthManager.credentialGeneration : nil,
                              accountID: appMode == .managed ? clientAuthManager.status.accountID : nil, resolvedNames: resolvedNames)
    }

    func savedAIRequestIsCurrent(_ request: SavedAIRequest, meeting: Meeting) -> Bool {
        guard savedAIRequests[request.key] == request.id,
              !isMeetingDeleted(request.meetingID),
              request.appMode == appMode.rawValue,
              request.accountID == (appMode == .managed ? clientAuthManager.status.accountID : nil),
              request.credentialGeneration == (appMode == .managed ? clientAuthManager.credentialGeneration : nil)
        else { return false }
        return meeting.id == request.meetingID && request.input == savedAIInput(meeting, resolvedNames: request.resolvedNames)
    }

    func finishSavedAIRequest(_ request: SavedAIRequest) {
        if savedAIRequests[request.key] == request.id { savedAIRequests.removeValue(forKey: request.key) }
    }
}

struct WebhookCompletion: Codable {
    enum Phase: String, Codable { case processing, ready, handedOff, cancelled }
    var id: UUID
    var phase: Phase
    var revision: Int
    var createdAt: Date
    var accountID: String?
    var processing: WebhookService.Processing?
    var requestedModes: [String]? = nil
}

extension Meeting {
    var webhookCompletion: WebhookCompletion? {
        get { webhookCompletionJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(WebhookCompletion.self, from: $0) } }
        set { webhookCompletionJSON = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } }
    }
}

extension AppState {
    @discardableResult
    func beginMeetingCompletion(_ meeting: Meeting, persist: Bool = true) -> UUID? {
        guard !webhookURL.isEmpty, !isMeetingDeleted(meeting.id) else { return nil }
        if let marker = meeting.webhookCompletion, marker.phase == .processing,
           marker.revision == meeting.transcriptRevision { return marker.id }
        if let old = meeting.webhookCompletion, old.phase != .handedOff {
            guard deliveryOutbox.discard(id: old.id) else { return nil }
        }
        let marker = WebhookCompletion(id: UUID(), phase: .processing, revision: meeting.transcriptRevision,
                                       createdAt: Date(), accountID: appMode == .managed ? clientAuthManager.status.accountID : nil)
        meeting.webhookCompletion = marker
        if persist { _ = commit(.finalInsights) }
        return marker.id
    }

    func settleMeetingCompletion(_ meeting: Meeting, id: UUID?, outcomes: [String: WebhookService.Processing.Outcome], interrupted: Bool) {
        guard let id, !isMeetingDeleted(meeting.id), var marker = meeting.webhookCompletion,
              marker.id == id, marker.phase == .processing else { return }
        guard marker.accountID == (appMode == .managed ? clientAuthManager.status.accountID : nil),
              !(currentMeeting?.id == meeting.id && (isRecording || isStartingMeeting || isResumingRecording)) else {
            marker.phase = .cancelled
            meeting.webhookCompletion = marker
            _ = commit(.finalInsights)
            return
        }
        let changed = interrupted || marker.revision != meeting.transcriptRevision
        let successes = outcomes.values.filter { $0 == .complete }.count
        let failures = outcomes.values.filter { $0 == .failed }.count
        let result: WebhookService.Processing.State = changed ? .interrupted :
            (failures > 0 ? (successes > 0 ? .partial : .failed) : (successes > 0 ? .complete : .skipped))
        marker.processing = .init(inputTranscriptRevision: marker.revision, state: result, outcomes: outcomes)
        marker.phase = .ready
        meeting.webhookCompletion = marker
        guard commit(.finalInsights) else {
            persistenceRetryAction = { [weak self, weak meeting] in
                guard let self, let meeting else { return }
                self.handOffWebhookCompletion(meeting)
            }
            return
        }
        handOffWebhookCompletion(meeting)
    }

    /// Reconcile only the marker just committed. Dispatch stays held until both stores agree.
    func handOffWebhookCompletion(_ meeting: Meeting) {
        guard deliveryOutbox.isStoreReadable, !isMeetingDeleted(meeting.id),
              var marker = meeting.webhookCompletion else { return }
        guard marker.accountID == (appMode == .managed ? clientAuthManager.status.accountID : nil), !webhookURL.isEmpty else {
            if marker.phase != .handedOff { marker.phase = .cancelled; meeting.webhookCompletion = marker; _ = commit(.finalInsights) }
            _ = deliveryOutbox.discard(id: marker.id)
            return
        }
        if marker.phase == .handedOff {
            if deliveryOutbox.item(id: marker.id)?.held == true { _ = deliveryOutbox.releaseWebhook(id: marker.id) }
            return
        }
        guard marker.phase == .ready else { return }
        // Also retries a ready marker left unsaved by an earlier failure.
        guard commit(.finalInsights) else {
            persistenceRetryAction = { [weak self, weak meeting] in
                guard let self, let meeting else { return }
                self.handOffWebhookCompletion(meeting)
            }
            return
        }
        // A held, unattempted snapshot invalidated by editing is replaced under a fresh ID.
        if marker.revision != meeting.transcriptRevision {
            guard deliveryOutbox.discard(id: marker.id) else { return }
            marker.id = UUID()
            marker.revision = meeting.transcriptRevision
            marker.processing = .init(inputTranscriptRevision: marker.revision, state: .interrupted, outcomes: [:])
            meeting.webhookCompletion = marker
            guard commit(.finalInsights) else { return }
        }
        do {
            let payload = WebhookService.payloadFromMeeting(meeting, event: "meeting.saved", processing: marker.processing,
                                                           insightsStale: marker.processing?.state == .interrupted)
            let body = try WebhookService.encode(payload)
            if let held = deliveryOutbox.item(id: marker.id), held.held == true,
               let oldBody = held.body,
               (try JSONSerialization.jsonObject(with: oldBody) as? NSDictionary) != (try JSONSerialization.jsonObject(with: body) as? NSDictionary) {
                guard deliveryOutbox.discard(id: marker.id) else { return }
                marker.id = UUID()
                meeting.webhookCompletion = marker
                guard commit(.finalInsights) else { return }
            }
            if deliveryOutbox.item(id: marker.id) == nil {
                guard deliveryOutbox.stageWebhook(id: marker.id, meetingID: meeting.id, event: payload.event, body: body,
                                                  destination: webhookURL, createdAt: marker.createdAt) else { return }
            }
            marker.phase = .handedOff
            let previous = meeting.webhookCompletionJSON
            meeting.webhookCompletion = marker
            guard commit(.finalInsights, revert: { meeting.webhookCompletionJSON = previous }) else {
                persistenceRetryAction = { [weak self, weak meeting] in
                    guard let self, let meeting else { return }
                    self.handOffWebhookCompletion(meeting)
                }
                return
            }
            _ = deliveryOutbox.releaseWebhook(id: marker.id)
        } catch {
            webhookResendError = "The webhook could not be prepared. Try again."
        }
    }

    /// Called once the local store is available; old meetings have no marker and are untouched.
    func reconcileWebhookCompletions() {
        guard deliveryOutbox.isStoreReadable, let meetings = fetchMeetings(.exportAll) else { return }
        for meeting in meetings {
            guard let marker = meeting.webhookCompletion else { continue }
            if marker.phase == .processing, !finalizingInsightMeetingIDs.contains(meeting.id) {
                settleMeetingCompletion(meeting, id: marker.id, outcomes: [:], interrupted: true)
            } else {
                handOffWebhookCompletion(meeting)
            }
        }
    }

    func resendFailedWebhooks() {
        webhookResendError = nil
        var resent: Set<UUID> = []
        for item in deliveryOutbox.failed(.webhook) {
            guard resent.insert(item.meetingID).inserted else { continue }
            guard let meeting = fetchMeetings(.exportAll)?.first(where: { $0.id == item.meetingID }),
                  !isMeetingDeleted(item.meetingID) else {
                webhookResendError = "This meeting is no longer available. Discard its failed delivery."
                continue
            }
            guard !webhookURL.isEmpty else {
                webhookResendError = "Add a webhook URL before resending."
                return
            }
            guard !finalizingInsightMeetingIDs.contains(meeting.id),
                  !savedAIRequests.keys.contains(where: { $0.hasPrefix(meeting.id.uuidString + ":") }),
                  meeting.webhookCompletion?.phase != .processing else {
                webhookResendError = "This meeting is still processing. Try again when it finishes."
                continue
            }
            guard commit(.insightsRegeneration) else { return }
            do {
                let metadata = meeting.webhookCompletion?.processing
                let payload = WebhookService.payloadFromMeeting(meeting, processing: metadata,
                    insightsStale: metadata.map { $0.inputTranscriptRevision != meeting.transcriptRevision || $0.state == .interrupted } ?? false)
                let body = try WebhookService.encode(payload)
                guard deliveryOutbox.replaceFailedWebhook(id: item.id, replacementID: UUID(), meetingID: meeting.id,
                                                          event: "meeting.updated", body: body, destination: webhookURL) else {
                    webhookResendError = "The delivery could not be saved. Try again."
                    continue
                }
            } catch { webhookResendError = "The webhook could not be prepared. Try again." }
        }
    }
}

extension AppState {
    func savedInsightRevert(_ meeting: Meeting) -> () -> Void {
        let title = meeting.title
        let summaryText = meeting.summaryText
        let actionItems = meeting.actionItems
        let keyDecisions = meeting.keyDecisions
        let topics = meeting.topics
        let discussionFlow = meeting.discussionFlow
        let meddpiccMetrics = meeting.meddpiccMetrics
        let meddpiccEconomicBuyer = meeting.meddpiccEconomicBuyer
        let meddpiccDecisionCriteria = meeting.meddpiccDecisionCriteria
        let meddpiccDecisionProcess = meeting.meddpiccDecisionProcess
        let meddpiccPaperProcess = meeting.meddpiccPaperProcess
        let meddpiccIdentifiedPain = meeting.meddpiccIdentifiedPain
        let meddpiccChampion = meeting.meddpiccChampion
        let meddpiccCompetition = meeting.meddpiccCompetition
        let suggestedQuestionsJSON = meeting.suggestedQuestionsJSON
        let templateSectionsJSON = meeting.templateSectionsJSON
        let templateDefinitionJSON = meeting.templateDefinitionJSON
        let insightTemplateID = meeting.insightTemplateID
        let insightsUpdatedAt = meeting.insightsUpdatedAt
        let freshness = lastInsightsUpdatedAt
        let restoreLive = liveInsightRevert(for: meeting.id)
        return { [weak self, weak meeting] in
            guard let meeting else { return }
            meeting.title = title
            meeting.summaryText = summaryText
            meeting.actionItems = actionItems
            meeting.keyDecisions = keyDecisions
            meeting.topics = topics
            meeting.discussionFlow = discussionFlow
            meeting.meddpiccMetrics = meddpiccMetrics
            meeting.meddpiccEconomicBuyer = meddpiccEconomicBuyer
            meeting.meddpiccDecisionCriteria = meddpiccDecisionCriteria
            meeting.meddpiccDecisionProcess = meddpiccDecisionProcess
            meeting.meddpiccPaperProcess = meddpiccPaperProcess
            meeting.meddpiccIdentifiedPain = meddpiccIdentifiedPain
            meeting.meddpiccChampion = meddpiccChampion
            meeting.meddpiccCompetition = meddpiccCompetition
            meeting.suggestedQuestionsJSON = suggestedQuestionsJSON
            meeting.templateSectionsJSON = templateSectionsJSON
            meeting.templateDefinitionJSON = templateDefinitionJSON
            meeting.insightTemplateID = insightTemplateID
            meeting.insightsUpdatedAt = insightsUpdatedAt
            self?.restoreInsightFreshness(freshness)
            restoreLive()
        }
    }
}

extension AppState {
    func noteSavedProcessingSuccess(_ meeting: Meeting, mode: String) {
        guard var marker = meeting.webhookCompletion else { return }
        let takesOverInitial = marker.phase == .processing
        var outcomes = marker.processing?.inputTranscriptRevision == meeting.transcriptRevision ? (marker.processing?.outcomes ?? [:]) : [:]
        if takesOverInitial {
            outcomes = Dictionary(uniqueKeysWithValues: (marker.requestedModes ?? [mode]).map { ($0, .interrupted) })
            marker.phase = .ready
        }
        outcomes[mode] = .complete
        let otherFailures = outcomes.values.contains { $0 == .failed || $0 == .interrupted || $0 == .stale }
        marker.processing = .init(inputTranscriptRevision: meeting.transcriptRevision, state: otherFailures ? .partial : .complete, outcomes: outcomes)
        marker.revision = meeting.transcriptRevision
        meeting.webhookCompletion = marker
        _ = commit(.insightsRegeneration)
    }
}

extension AppState {
    func retryWebhookDeliveries() {
        guard deliveryOutbox.retryStorage() else { return }
        reconcileWebhookCompletions()
        deliveryOutbox.retryNow(.webhook)
    }
}
