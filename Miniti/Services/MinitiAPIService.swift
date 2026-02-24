import Foundation

/// Communicates with the Miniti backend for managed mode.
/// Handles usage checking, session management (temp Deepgram keys), and insights proxy.
final class MinitiAPIService: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Backend base URL. Override in debug with MINITI_API_URL environment variable
    /// (e.g. set to http://localhost:3000/api for local dev).
    static let baseURL: String = {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["MINITI_API_URL"] {
            return override
        }
        #endif
        return "https://miniti-api.vercel.app/api"
    }()
    
    /// Shared app secret — authenticates requests to the backend (not user-specific).
    /// XOR-obfuscated so it doesn't appear as a plain string in source or binary.
    private static let apiKey: String = {
        let mask: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let obfuscated: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        return zip(obfuscated, mask)
            .map { String(format: "%02x", $0 ^ $1) }
            .joined()
    }()
    
    /// Build a URLRequest with required auth headers (X-API-Key + X-Device-ID).
    private func makeRequest(
        path: String,
        method: String = "GET",
        deviceId: String,
        body: [String: Any]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)\(path)")!)
        request.httpMethod = method
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forHTTPHeaderField: "X-App-Version")
        #if os(iOS)
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        #else
        request.setValue("macos", forHTTPHeaderField: "X-Platform")
        #endif
        
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
    
    // MARK: - Response Types
    
    struct UsageInfo: Decodable {
        let minutesUsed: Double
        let minutesLimit: Double
        let resetsAt: Date
        let tier: String
        
        enum CodingKeys: String, CodingKey {
            case minutesUsed = "minutes_used"
            case minutesLimit = "minutes_limit"
            case resetsAt = "resets_at"
            case tier
        }
        
        /// Custom decoder: Vercel KV (Redis) may return numbers as strings.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tier = try container.decode(String.self, forKey: .tier)
            resetsAt = try container.decode(Date.self, forKey: .resetsAt)
            // Accept both Double and String for numeric fields (Redis returns strings)
            if let val = try? container.decode(Double.self, forKey: .minutesUsed) {
                minutesUsed = val
            } else {
                let str = try container.decode(String.self, forKey: .minutesUsed)
                minutesUsed = Double(str) ?? 0
            }
            if let val = try? container.decode(Double.self, forKey: .minutesLimit) {
                minutesLimit = val
            } else {
                let str = try container.decode(String.self, forKey: .minutesLimit)
                minutesLimit = Double(str) ?? 500
            }
        }
        
        var minutesRemaining: Double {
            max(0, minutesLimit - minutesUsed)
        }
        
        var isLimitReached: Bool {
            minutesUsed >= minutesLimit
        }
        
        var usagePercentage: Double {
            minutesLimit > 0 ? min(1.0, minutesUsed / minutesLimit) : 0
        }
        
        var formattedRemaining: String {
            let remaining = minutesRemaining
            let rounded = Int(remaining.rounded())
            if rounded >= 60 {
                let hours = rounded / 60
                let mins = rounded % 60
                return "\(hours)h \(mins)m"
            }
            return "\(rounded)m"
        }
    }
    
    struct SessionResponse: Codable {
        let tempApiKey: String
        let expiresAt: Date
        let sessionId: String
        
        enum CodingKeys: String, CodingKey {
            case tempApiKey = "temp_api_key"
            case expiresAt = "expires_at"
            case sessionId = "session_id"
        }
    }
    
    struct EndSessionResponse: Codable {
        let minutesUsed: Double
        let minutesRemaining: Double
        
        enum CodingKeys: String, CodingKey {
            case minutesUsed = "minutes_used"
            case minutesRemaining = "minutes_remaining"
        }
    }
    
    struct APIError: Codable {
        let error: String
        let message: String?
        let minutesUsed: Double?
        let limit: Double?
        let resetsAt: Date?
        
        enum CodingKeys: String, CodingKey {
            case error, message
            case minutesUsed = "minutes_used"
            case limit
            case resetsAt = "resets_at"
        }
    }

    // MARK: - Attio

    struct AttioConnectStartResponse: Decodable {
        let authURL: String
        let callbackScheme: String

        enum CodingKeys: String, CodingKey {
            case authURL = "auth_url"
            case callbackScheme = "callback_scheme"
        }
    }

    struct AttioStatusResponse: Decodable {
        let connected: Bool
        let accountLabel: String?

        enum CodingKeys: String, CodingKey {
            case connected
            case accountLabel = "account_label"
        }
    }

    struct AttioSearchRecord: Decodable, Identifiable {
        struct RecordID: Decodable {
            let workspaceID: String
            let objectID: String
            let recordID: String

            enum CodingKeys: String, CodingKey {
                case workspaceID = "workspace_id"
                case objectID = "object_id"
                case recordID = "record_id"
            }
        }

        let idPayload: RecordID
        let recordText: String
        let recordImage: String?
        let objectSlug: String
        let recordEmail: String?
        let recordDomain: String?

        enum CodingKeys: String, CodingKey {
            case idPayload = "id"
            case recordText = "record_text"
            case recordImage = "record_image"
            case objectSlug = "object_slug"
            case recordEmail = "record_email"
            case recordDomain = "record_domain"
        }

        var id: String { "\(objectSlug):\(idPayload.recordID)" }

        var secondaryIdentifier: String? {
            switch objectSlug.lowercased() {
            case "people":
                return recordEmail
            case "companies":
                return recordDomain
            default:
                return recordEmail ?? recordDomain
            }
        }
    }

    struct AttioSearchResponse: Decodable {
        let data: [AttioSearchRecord]
    }

    struct AttioSendResponse: Decodable {
        let success: Bool
        let noteIDs: [String]
        let taskIDs: [String]
        let taskError: String?
        let taskCount: Int?

        enum CodingKeys: String, CodingKey {
            case success
            case noteIDs = "note_ids"
            case taskIDs = "task_ids"
            case taskError = "task_error"
            case taskCount = "task_count"
            case tasksSynced = "tasks_synced"
            case tasksCreated = "tasks_created"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decode(Bool.self, forKey: .success)
            noteIDs = try container.decodeIfPresent([String].self, forKey: .noteIDs) ?? []
            taskIDs = try container.decodeIfPresent([String].self, forKey: .taskIDs) ?? []
            taskError = try container.decodeIfPresent(String.self, forKey: .taskError)
            taskCount =
                try container.decodeIfPresent(Int.self, forKey: .taskCount) ??
                (try container.decodeIfPresent(Int.self, forKey: .tasksSynced)) ??
                (try container.decodeIfPresent(Int.self, forKey: .tasksCreated))
        }
    }
    
    // MARK: - Errors
    
    enum ServiceError: LocalizedError {
        case limitReached(minutesUsed: Double, resetsAt: Date?)
        case deviceDisabled
        case networkError(Error)
        case invalidResponse
        case serverError(String)
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .limitReached(let used, _):
                return "Monthly limit reached (\(Int(used)) min used)."
            case .deviceDisabled:
                return "Your account has been disabled. Contact support."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server."
            case .serverError(let message):
                return "Server error: \(message)"
            case .rateLimited:
                return "Too many requests. Please wait a moment."
            }
        }
    }
    
    // MARK: - JSON Decoder
    
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    // MARK: - Version Check
    
    struct VersionInfo: Decodable {
        let latestVersion: String
        let downloadUrl: String
        let releaseNotes: String?
        
        enum CodingKeys: String, CodingKey {
            case latestVersion = "latest_version"
            case downloadUrl = "download_url"
            case releaseNotes = "release_notes"
        }
    }
    
    /// Check if a newer version is available. Lightweight — no device ID needed.
    func checkVersion() async throws -> VersionInfo {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/version")!)
        request.httpMethod = "GET"
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forHTTPHeaderField: "X-App-Version")
        #if os(iOS)
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        #else
        request.setValue("macos", forHTTPHeaderField: "X-Platform")
        #endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try Self.decoder.decode(VersionInfo.self, from: data)
    }
    
    // MARK: - API Methods
    
    /// Check current usage for a device.
    func checkUsage(deviceId: String) async throws -> UsageInfo {
        let request = makeRequest(path: "/usage", deviceId: deviceId)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try Self.decoder.decode(UsageInfo.self, from: data)
    }
    
    /// Request a new transcription session. Returns a temporary Deepgram API key.
    /// The backend validates the device, checks usage limits, and issues a scoped temp key.
    func requestSession(deviceId: String, model: String) async throws -> SessionResponse {
        let request = makeRequest(
            path: "/session",
            method: "POST",
            deviceId: deviceId,
            body: ["model": model]
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try Self.decoder.decode(SessionResponse.self, from: data)
    }
    
    /// End a transcription session and report duration. Backend increments usage counter.
    func endSession(deviceId: String, sessionId: String, durationMinutes: Double) async throws -> EndSessionResponse {
        let request = makeRequest(
            path: "/session/end",
            method: "POST",
            deviceId: deviceId,
            body: [
                "session_id": sessionId,
                "duration_minutes": durationMinutes
            ]
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try Self.decoder.decode(EndSessionResponse.self, from: data)
    }
    
    /// Proxy insights generation through the backend (managed mode).
    /// Backend calls OpenAI with its own API key and returns parsed insights.
    func generateInsights(
        deviceId: String,
        transcript: String,
        existingSummary: String?,
        existingTitle: String?,
        mode: String,
        model: String
    ) async throws -> ManagedInsightsResponse {
        var body: [String: Any] = [
            "transcript": transcript,
            "mode": mode,
            "model": model
        ]
        if let existingSummary { body["existing_summary"] = existingSummary }
        if let existingTitle { body["existing_title"] = existingTitle }
        
        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try Self.decoder.decode(ManagedInsightsResponse.self, from: data)
    }

    func attioConnectStart(deviceId: String, callbackScheme: String = "miniti-attio") async throws -> AttioConnectStartResponse {
        let request = makeRequest(
            path: "/attio/connect/start",
            method: "POST",
            deviceId: deviceId,
            body: ["callback_scheme": callbackScheme]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try Self.decoder.decode(AttioConnectStartResponse.self, from: data)
    }

    func attioStatus(deviceId: String) async throws -> AttioStatusResponse {
        let request = makeRequest(path: "/attio/status", deviceId: deviceId)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try Self.decoder.decode(AttioStatusResponse.self, from: data)
    }

    func attioSearch(deviceId: String, query: String, objects: [String]) async throws -> [AttioSearchRecord] {
        let request = makeRequest(
            path: "/attio/search",
            method: "POST",
            deviceId: deviceId,
            body: ["query": query, "objects": objects]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try Self.decoder.decode(AttioSearchResponse.self, from: data).data
    }

    func attioSendMeeting(
        deviceId: String,
        meetingPayload: AttioMeetingPayload,
        targetObject: String,
        targetRecordID: String,
        createTasksFromActionItems: Bool
    ) async throws -> AttioSendResponse {
        let request = makeRequest(
            path: "/attio/send",
            method: "POST",
            deviceId: deviceId,
            body: [
                "target_object": targetObject,
                "target_record_id": targetRecordID,
                "meeting": meetingPayload.dictionary,
                "create_tasks_from_action_items": createTasksFromActionItems
            ]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try Self.decoder.decode(AttioSendResponse.self, from: data)
    }
    
    // MARK: - Response Validation
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // OK
        case 402:
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.limitReached(
                    minutesUsed: apiError.minutesUsed ?? 500,
                    resetsAt: apiError.resetsAt
                )
            }
            throw ServiceError.limitReached(minutesUsed: 500, resetsAt: nil)
        case 403:
            if let apiError = try? Self.decoder.decode(APIError.self, from: data),
               apiError.error == "device_disabled" {
                throw ServiceError.deviceDisabled
            }
            throw ServiceError.serverError("Access denied")
        case 429:
            throw ServiceError.rateLimited
        default:
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.serverError(apiError.message ?? apiError.error)
            }
            throw ServiceError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Attio Meeting Payload

struct AttioMeetingPayload: Sendable {
    let title: String
    let startedAt: String
    let endedAt: String?
    let durationText: String
    let summary: String?
    let discussionFlow: [String]
    let actionItems: [String]
    let keyDecisions: [String]
    let topics: [String]
    let notes: String?
    let meddpicc: [String: String]

    static func normalizedActionItems(from items: [String]) -> [String] {
        let placeholders: Set<String> = [
            "none",
            "n/a",
            "na",
            "null",
            "no action items",
            "no action items mentioned",
            "no follow-up actions"
        ]

        var normalized: [String] = []
        var seen = Set<String>()

        for item in items {
            // Some persisted meetings store multiple bullets in one string; split and normalize each line.
            for rawLine in item.components(separatedBy: .newlines) {
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let withoutBullet = trimmed.replacingOccurrences(
                    of: #"^\s*(?:(?:[-*•])|(?:\d+[.)]))\s*(?:\[(?: |x|X)\]\s*)?"#,
                    with: "",
                    options: .regularExpression
                )

                let withoutCheckbox = withoutBullet.replacingOccurrences(
                    of: #"^\s*\[(?: |x|X)\]\s*"#,
                    with: "",
                    options: .regularExpression
                )

                let noControls = withoutCheckbox.unicodeScalars.filter { scalar in
                    !CharacterSet.controlCharacters.contains(scalar)
                }
                let collapsedWhitespace = String(String.UnicodeScalarView(noControls))
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !collapsedWhitespace.isEmpty else { continue }
                guard collapsedWhitespace.range(of: #"^[\-\*•\s]+$"#, options: .regularExpression) == nil else { continue }

                let lower = collapsedWhitespace.lowercased()
                guard !placeholders.contains(lower) else { continue }
                guard seen.insert(lower).inserted else { continue }

                normalized.append(collapsedWhitespace)
            }
        }

        return normalized
    }

    static func from(meeting: Meeting) -> AttioMeetingPayload {
        let iso = ISO8601DateFormatter()
        let meddpiccPairs: [(String, String?)] = [
            ("metrics", meeting.meddpiccMetrics),
            ("economic_buyer", meeting.meddpiccEconomicBuyer),
            ("decision_criteria", meeting.meddpiccDecisionCriteria),
            ("decision_process", meeting.meddpiccDecisionProcess),
            ("paper_process", meeting.meddpiccPaperProcess),
            ("identified_pain", meeting.meddpiccIdentifiedPain),
            ("champion", meeting.meddpiccChampion),
            ("competition", meeting.meddpiccCompetition),
        ]
        var meddpicc: [String: String] = [:]
        for (key, value) in meddpiccPairs {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                meddpicc[key] = trimmed
            }
        }

        let notesTrimmed = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryTrimmed = meeting.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionItems = normalizedActionItems(from: meeting.actionItems)

        return AttioMeetingPayload(
            title: meeting.title,
            startedAt: iso.string(from: meeting.startTime),
            endedAt: meeting.endTime.map { iso.string(from: $0) },
            durationText: meeting.formattedDuration,
            summary: (summaryTrimmed?.isEmpty == false) ? summaryTrimmed : nil,
            discussionFlow: meeting.discussionFlow,
            actionItems: actionItems,
            keyDecisions: meeting.keyDecisions,
            topics: meeting.topics,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            meddpicc: meddpicc
        )
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "title": title,
            "started_at": startedAt,
            "duration_text": durationText,
            "discussion_flow": discussionFlow,
            "action_items": actionItems,
            "key_decisions": keyDecisions,
            "topics": topics,
            "meddpicc": meddpicc,
        ]
        if let endedAt { result["ended_at"] = endedAt }
        if let summary { result["summary"] = summary }
        if let notes { result["notes"] = notes }
        return result
    }
}

// MARK: - Managed Insights Response

/// Mirrors the InsightsService.LiveInsights structure but is Codable for backend responses.
struct ManagedInsightsResponse: Codable {
    let summary: String
    let actionItems: [String]
    let topics: [String]
    let discussionFlow: [String]
    let title: String?
    let metrics: String?
    let economicBuyer: String?
    let decisionCriteria: String?
    let decisionProcess: String?
    let paperProcess: String?
    let identifiedPain: String?
    let champion: String?
    let competition: String?
    
    enum CodingKeys: String, CodingKey {
        case summary
        case actionItems = "action_items"
        case topics
        case discussionFlow = "discussion_flow"
        case title
        case metrics
        case economicBuyer = "economic_buyer"
        case decisionCriteria = "decision_criteria"
        case decisionProcess = "decision_process"
        case paperProcess = "paper_process"
        case identifiedPain = "identified_pain"
        case champion
        case competition
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        discussionFlow = try container.decodeIfPresent([String].self, forKey: .discussionFlow) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        metrics = try container.decodeIfPresent(String.self, forKey: .metrics)
        economicBuyer = try container.decodeIfPresent(String.self, forKey: .economicBuyer)
        decisionCriteria = try container.decodeIfPresent(String.self, forKey: .decisionCriteria)
        decisionProcess = try container.decodeIfPresent(String.self, forKey: .decisionProcess)
        paperProcess = try container.decodeIfPresent(String.self, forKey: .paperProcess)
        identifiedPain = try container.decodeIfPresent(String.self, forKey: .identifiedPain)
        champion = try container.decodeIfPresent(String.self, forKey: .champion)
        competition = try container.decodeIfPresent(String.self, forKey: .competition)
    }
    
    /// Convert to InsightsService.LiveInsights for use in AppState.
    func toLiveInsights() -> InsightsService.LiveInsights {
        InsightsService.LiveInsights(
            summary: summary,
            actionItems: actionItems,
            topics: topics,
            discussionFlow: discussionFlow,
            suggestedTitle: title,
            metrics: metrics,
            economicBuyer: economicBuyer,
            decisionCriteria: decisionCriteria,
            decisionProcess: decisionProcess,
            paperProcess: paperProcess,
            identifiedPain: identifiedPain,
            champion: champion,
            competition: competition
        )
    }
}
