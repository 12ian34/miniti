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
