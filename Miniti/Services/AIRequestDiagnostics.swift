import Foundation

/// Content-free per-operation context. Task-local ownership isolates concurrent
/// live/final/saved requests; no global last-error or mutable service observer.
enum AIRequestDiagnostics {
    @TaskLocal static var current: AIRequestObservation?

    static func category(_ error: Error, status: Int? = nil) -> String {
        if case InsightsError.lunaAccessRequired = error { return "model_access" }
        let ns = error as NSError
        if error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) { return "cancelled" }
        if ns.domain == NSURLErrorDomain { return ns.code == NSURLErrorTimedOut ? "timeout" : "transport" }
        if error is DecodingError { return "decode" }
        if let status, !(200...299).contains(status) {
            if status == 401 || status == 403 { return "auth" }
            if status == 402 || status == 429 { return "admission" }
            if status == 408 || status == 504 { return "timeout" }
            return status >= 500 ? "provider" : "admission"
        }
        if let service = error as? MinitiAPIService.ServiceError {
            switch service {
            case .networkError(let cause): return category(cause)
            case .notEnrolled, .authRevoked, .deviceDisabled: return "auth"
            case .rateLimited, .limitReached: return "admission"
            case .invalidResponse: return "decode"
            case .classifierUnavailable: return "provider"
            case .apiError(_, _, let code): return (200...299).contains(code) ? "unknown" : category(error, status: code)
            case .serverError: return "unknown" // Never parse raw server text as evidence.
            }
        }
        if let insight = error as? InsightsError {
            switch insight {
            case .invalidResponse, .invalidJson, .noContent: return "decode"
            case .emptyTranscript: return "admission"
            case .httpError(let code): return (200...299).contains(code) ? "unknown" : category(error, status: code)
            case .apiError: return "provider"
            case .lunaAccessRequired: return "model_access"
            }
        }
        return "unknown"
    }
}

final class AIRequestObservation: @unchecked Sendable {
    let accountID: String?
    let credentialGeneration: Int
    let stage: String
    private let lock = NSLock()
    private var mode: String?
    private var requestID: UUID?
    private var status: Int?

    init(accountID: String?, credentialGeneration: Int, stage: String) {
        self.accountID = accountID; self.credentialGeneration = credentialGeneration; self.stage = stage
    }
    func start(mode: String) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = UUID()
        self.mode = mode; requestID = id; status = nil
        return id
    }
    func received(status: Int?, requestID: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard self.requestID == requestID else { return }
        self.status = status
    }
    var currentMode: String? { lock.lock(); defer { lock.unlock() }; return mode }
    func fields(mode: String, error: Error, category: String? = nil) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        let matching = self.mode == mode
        var result = ["schema_version": "1", "task_mode": mode, "ai_stage": stage,
                      "failure_category": category ?? AIRequestDiagnostics.category(error, status: matching ? status : nil)]
        if matching, let requestID { result["request_id"] = requestID.uuidString.lowercased() }
        if matching, let status, (100...599).contains(status) { result["status"] = String(status) }
        return result
    }
}
