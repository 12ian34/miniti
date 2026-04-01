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
        let subscriptionStatus: String?
        
        enum CodingKeys: String, CodingKey {
            case minutesUsed = "minutes_used"
            case minutesLimit = "minutes_limit"
            case resetsAt = "resets_at"
            case tier
            case subscriptionStatus = "subscription_status"
            case minutesUsedCamel = "minutesUsed"
            case minutesLimitCamel = "minutesLimit"
            case resetsAtCamel = "resetsAt"
            case subscriptionStatusCamel = "subscriptionStatus"
        }
        
        /// Custom decoder: Vercel KV (Redis) may return numbers as strings.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tier = (try? container.decode(String.self, forKey: .tier)) ?? "free"
            resetsAt =
                (try? container.decode(Date.self, forKey: .resetsAt)) ??
                (try? container.decode(Date.self, forKey: .resetsAtCamel)) ??
                MinitiAPIService.fallbackResetDate()
            subscriptionStatus =
                (try? container.decodeIfPresent(String.self, forKey: .subscriptionStatus)) ??
                (try? container.decodeIfPresent(String.self, forKey: .subscriptionStatusCamel))
            if let val = try? container.decode(Double.self, forKey: .minutesUsed) {
                minutesUsed = val
            } else if let val = try? container.decode(Double.self, forKey: .minutesUsedCamel) {
                minutesUsed = val
            } else {
                let str =
                    (try? container.decode(String.self, forKey: .minutesUsed)) ??
                    (try? container.decode(String.self, forKey: .minutesUsedCamel))
                minutesUsed = str.flatMap(Double.init) ?? 0
            }
            if let val = try? container.decode(Double.self, forKey: .minutesLimit) {
                minutesLimit = val
            } else if let val = try? container.decode(Double.self, forKey: .minutesLimitCamel) {
                minutesLimit = val
            } else {
                let str =
                    (try? container.decode(String.self, forKey: .minutesLimit)) ??
                    (try? container.decode(String.self, forKey: .minutesLimitCamel))
                minutesLimit = str.flatMap(Double.init) ?? 500
            }
        }
        
        var isPro: Bool { tier == "pro" }
        
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
    
    struct SessionResponse: Decodable {
        let tempApiKey: String
        let expiresAt: Date
        let sessionId: String
        
        enum CodingKeys: String, CodingKey {
            case tempApiKey = "temp_api_key"
            case expiresAt = "expires_at"
            case sessionId = "session_id"
            case tempApiKeyCamel = "tempApiKey"
            case expiresAtCamel = "expiresAt"
            case sessionIdCamel = "sessionId"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tempApiKey =
                (try? container.decode(String.self, forKey: .tempApiKey)) ??
                (try? container.decode(String.self, forKey: .tempApiKeyCamel)) ??
                ""
            expiresAt =
                (try? container.decode(Date.self, forKey: .expiresAt)) ??
                (try? container.decode(Date.self, forKey: .expiresAtCamel)) ??
                Date().addingTimeInterval(4 * 60 * 60)
            sessionId =
                (try? container.decode(String.self, forKey: .sessionId)) ??
                (try? container.decode(String.self, forKey: .sessionIdCamel)) ??
                {
                    if let intValue = try? container.decode(Int.self, forKey: .sessionId) {
                        return String(intValue)
                    }
                    if let intValue = try? container.decode(Int.self, forKey: .sessionIdCamel) {
                        return String(intValue)
                    }
                    return ""
                }()
            
            if tempApiKey.isEmpty || sessionId.isEmpty {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "Missing session token fields")
                )
            }
        }
    }
    
    struct EndSessionResponse: Decodable {
        let minutesUsed: Double
        let minutesRemaining: Double
        let sessionFinalized: Bool?
        let idempotentReplay: Bool?
        
        enum CodingKeys: String, CodingKey {
            case minutesUsed = "minutes_used"
            case minutesRemaining = "minutes_remaining"
            case sessionFinalized = "session_finalized"
            case idempotentReplay = "idempotent_replay"
            case minutesUsedCamel = "minutesUsed"
            case minutesRemainingCamel = "minutesRemaining"
            case sessionFinalizedCamel = "sessionFinalized"
            case idempotentReplayCamel = "idempotentReplay"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let val = try? container.decode(Double.self, forKey: .minutesUsed) {
                minutesUsed = val
            } else if let val = try? container.decode(Double.self, forKey: .minutesUsedCamel) {
                minutesUsed = val
            } else {
                let str =
                    (try? container.decode(String.self, forKey: .minutesUsed)) ??
                    (try? container.decode(String.self, forKey: .minutesUsedCamel))
                minutesUsed = str.flatMap(Double.init) ?? 0
            }
            
            if let val = try? container.decode(Double.self, forKey: .minutesRemaining) {
                minutesRemaining = val
            } else if let val = try? container.decode(Double.self, forKey: .minutesRemainingCamel) {
                minutesRemaining = val
            } else {
                let str =
                    (try? container.decode(String.self, forKey: .minutesRemaining)) ??
                    (try? container.decode(String.self, forKey: .minutesRemainingCamel))
                minutesRemaining = str.flatMap(Double.init) ?? 0
            }
            
            sessionFinalized =
                (try? container.decodeIfPresent(Bool.self, forKey: .sessionFinalized)) ??
                (try? container.decodeIfPresent(Bool.self, forKey: .sessionFinalizedCamel))
            idempotentReplay =
                (try? container.decodeIfPresent(Bool.self, forKey: .idempotentReplay)) ??
                (try? container.decodeIfPresent(Bool.self, forKey: .idempotentReplayCamel))
        }
    }
    
    struct APIError: Decodable {
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
            case minutesUsedCamel = "minutesUsed"
            case resetsAtCamel = "resetsAt"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = (try? container.decode(String.self, forKey: .error)) ?? "unknown_error"
            message = try? container.decodeIfPresent(String.self, forKey: .message)
            
            if let val = try? container.decode(Double.self, forKey: .minutesUsed) {
                minutesUsed = val
            } else if let val = try? container.decode(Double.self, forKey: .minutesUsedCamel) {
                minutesUsed = val
            } else {
                let str =
                    (try? container.decode(String.self, forKey: .minutesUsed)) ??
                    (try? container.decode(String.self, forKey: .minutesUsedCamel))
                minutesUsed = str.flatMap(Double.init)
            }
            
            if let val = try? container.decode(Double.self, forKey: .limit) {
                limit = val
            } else {
                let str = try? container.decode(String.self, forKey: .limit)
                limit = str.flatMap(Double.init)
            }
            
            resetsAt =
                (try? container.decode(Date.self, forKey: .resetsAt)) ??
                (try? container.decode(Date.self, forKey: .resetsAtCamel))
        }
    }

    struct IncrementalInsightsRollingState: Sendable {
        let summary: String?
        let discussionFlow: [String]
        let actionItems: [String]
        let topics: [String]
        let suggestedTitle: String?
        let meddpicc: [String: String]?

        var dictionary: [String: Any] {
            var result: [String: Any] = [
                "summary": summary ?? "",
                "discussion_flow": discussionFlow,
                "action_items": actionItems,
                "topics": topics,
                "suggested_title": suggestedTitle ?? NSNull()
            ]
            if let meddpicc {
                let meddpiccKeys = [
                    "metrics",
                    "economic_buyer",
                    "decision_criteria",
                    "decision_process",
                    "paper_process",
                    "identified_pain",
                    "champion",
                    "competition"
                ]
                var meddpiccResult: [String: Any] = [:]
                for key in meddpiccKeys {
                    meddpiccResult[key] = meddpicc[key] ?? NSNull()
                }
                result["meddpicc"] = meddpiccResult
            }
            return result
        }
    }

    struct IncrementalInsightsPayload: Sendable {
        let strategy: String
        let fullSegmentCount: Int
        let ackedSegmentCount: Int
        let deltaSegmentCount: Int
        let recentSegmentCount: Int
        let transcriptDelta: String
        let recentTranscript: String
        let rollingState: IncrementalInsightsRollingState

        var dictionary: [String: Any] {
            var result: [String: Any] = [
                "strategy": strategy,
                "full_segment_count": fullSegmentCount,
                "acked_segment_count": ackedSegmentCount,
                "delta_segment_count": deltaSegmentCount,
                "recent_segment_count": recentSegmentCount,
                "transcript_delta": transcriptDelta,
                "recent_transcript": recentTranscript
            ]
            let rollingStateDictionary = rollingState.dictionary
            if !rollingStateDictionary.isEmpty {
                result["rolling_state"] = rollingStateDictionary
            }
            return result
        }
    }

    struct ClientEventPayload: Codable {
        enum EventCategory: String, Codable {
            case app
            case audio
            case deepgram
            case insights
        }

        enum EventLevel: String, Codable {
            case info
            case warning
            case error
        }

        let name: String
        let category: EventCategory
        let level: EventLevel
        let occurredAt: Date
        let diagnosticsSessionId: String
        let appMode: String
        let meetingId: String?
        let details: [String: String]?

        enum CodingKeys: String, CodingKey {
            case name
            case category
            case level
            case occurredAt = "occurred_at"
            case diagnosticsSessionId = "diagnostics_session_id"
            case appMode = "app_mode"
            case meetingId = "meeting_id"
            case details
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
    
    // MARK: - Subscription Response Types
    
    struct SubscribeResponse: Decodable {
        let checkoutUrl: String
        
        enum CodingKeys: String, CodingKey {
            case checkoutUrl = "checkout_url"
        }
    }
    
    struct PortalResponse: Decodable {
        let portalUrl: String
        
        enum CodingKeys: String, CodingKey {
            case portalUrl = "portal_url"
        }
    }
    
    struct RestoreResponse: Decodable {
        let success: Bool
        let tier: String
        let minutesLimit: Double
        
        enum CodingKeys: String, CodingKey {
            case success
            case tier
            case minutesLimit = "minutes_limit"
        }
    }
    
    struct AppleVerifyResponse: Decodable {
        let success: Bool
        let tier: String
        let minutesLimit: Double
        let resetsAt: Date
        let subscriptionStatus: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case tier
            case minutesLimit = "minutes_limit"
            case resetsAt = "resets_at"
            case subscriptionStatus = "subscription_status"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decode(Bool.self, forKey: .success)
            tier = try container.decode(String.self, forKey: .tier)
            resetsAt = try container.decode(Date.self, forKey: .resetsAt)
            subscriptionStatus = try container.decodeIfPresent(String.self, forKey: .subscriptionStatus)
            if let val = try? container.decode(Double.self, forKey: .minutesLimit) {
                minutesLimit = val
            } else {
                let str = try container.decode(String.self, forKey: .minutesLimit)
                minutesLimit = Double(str) ?? 5000
            }
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
        decoder.dateDecodingStrategy = .custom { decoder in
            try MinitiAPIService.decodeFlexibleDate(from: decoder)
        }
        return decoder
    }()
    
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    static func decodeFlexibleDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        
        if let seconds = try? container.decode(Double.self) {
            return timestampToDate(seconds)
        }
        if let milliseconds = try? container.decode(Int64.self) {
            return timestampToDate(Double(milliseconds))
        }
        if let string = try? container.decode(String.self) {
            if let asDouble = Double(string) {
                return timestampToDate(asDouble)
            }
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let parsed = withFractional.date(from: string)
                ?? withoutFractional.date(from: string) {
                return parsed
            }
        }
        
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported date format"
        )
    }
    
    static func timestampToDate(_ value: Double) -> Date {
        // Accept both seconds and milliseconds timestamps.
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }
    
    private static func fallbackResetDate() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
    }
    
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
    
    /// Check if a newer version is available and optionally register the device.
    func checkVersion(deviceId: String? = nil, appMode: String? = nil) async throws -> VersionInfo {
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
        if let deviceId { request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID") }
        if let appMode { request.setValue(appMode, forHTTPHeaderField: "X-App-Mode") }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try decode(VersionInfo.self, from: data, endpoint: "/version")
    }
    
    // MARK: - API Methods
    
    /// Check current usage for a device.
    func checkUsage(deviceId: String) async throws -> UsageInfo {
        let request = makeRequest(path: "/usage", deviceId: deviceId)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try decode(UsageInfo.self, from: data, endpoint: "/usage")
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
        
        return try decode(SessionResponse.self, from: data, endpoint: "/session")
    }
    
    /// End a transcription session and report duration. Backend increments usage counter.
    func endSession(deviceId: String, sessionId: String, durationMinutes: Double) async throws -> EndSessionResponse {
        func sendRequest(path: String) async throws -> EndSessionResponse {
            let request = makeRequest(
                path: path,
                method: "POST",
                deviceId: deviceId,
                body: [
                    "session_id": sessionId,
                    "duration_minutes": durationMinutes
                ]
            )
            DebugLogger.shared.log(.app, "API request: POST \(Self.baseURL)\(path)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response, data: data)
            return try decode(EndSessionResponse.self, from: data, endpoint: path)
        }

        do {
            return try await sendRequest(path: "/session/end")
        } catch let error as ServiceError {
            if case .serverError(let message) = error, message == "HTTP 405" {
                DebugLogger.shared.log(.app, "API 405 on /session/end — retrying with trailing slash")
                return try await sendRequest(path: "/session/end/")
            }
            throw error
        }
    }
    
    /// Proxy insights generation through the backend (managed mode).
    /// Backend calls OpenAI with its own API key and returns parsed insights.
    func generateInsights(
        deviceId: String,
        transcript: String,
        existingSummary: String?,
        existingTitle: String?,
        mode: String,
        model: String,
        incrementalPayload: IncrementalInsightsPayload? = nil,
        requestSeq: Int? = nil,
        language: String = "en"
    ) async throws -> ManagedInsightsResponse {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var body: [String: Any] = [
            "transcript": transcript,
            "mode": mode,
            "model": model,
            "language": language
        ]
        if let existingSummary { body["existing_summary"] = existingSummary }
        if let existingTitle { body["existing_title"] = existingTitle }
        if let requestSeq { body["request_seq"] = requestSeq }
        if let incrementalPayload {
            body["incremental"] = true
            body["incremental_payload"] = incrementalPayload.dictionary
        }
        
        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        DebugLogger.shared.log(
            .app,
            "API insights request: mode=\(mode), model=\(model), transcriptChars=\(transcript.count), hasSummary=\(existingSummary != nil), hasTitle=\(existingTitle != nil), incremental=\(incrementalPayload != nil)"
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoded = try decode(ManagedInsightsResponse.self, from: data, endpoint: "/insights")
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        let meddpiccFieldCount = [
            decoded.metrics,
            decoded.economicBuyer,
            decoded.decisionCriteria,
            decoded.decisionProcess,
            decoded.paperProcess,
            decoded.identifiedPain,
            decoded.champion,
            decoded.competition
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0.lowercased() != "null" }
        .count
        DebugLogger.shared.log(
            .app,
            "API insights response: mode=\(mode), duration=\(String(format: "%.2fs", duration)), summaryChars=\(decoded.summary.count), actionItems=\(decoded.actionItems.count), topics=\(decoded.topics.count), meddpiccFields=\(meddpiccFieldCount)"
        )
        return decoded
    }

    func sendClientEvents(deviceId: String, events: [ClientEventPayload]) async throws {
        guard !events.isEmpty else { return }

        struct ClientEventsRequest: Encodable {
            let events: [ClientEventPayload]
        }

        var request = makeRequest(
            path: "/client-events",
            method: "POST",
            deviceId: deviceId
        )
        request.httpBody = try Self.encoder.encode(ClientEventsRequest(events: events))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Subscription
    
    /// Get a Polar checkout URL for upgrading to Pro.
    func getSubscribeURL(deviceId: String) async throws -> URL {
        let request = makeRequest(path: "/subscribe", deviceId: deviceId)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let result = try decode(SubscribeResponse.self, from: data, endpoint: "/subscribe")
        guard let url = URL(string: result.checkoutUrl) else {
            throw ServiceError.invalidResponse
        }
        return url
    }
    
    /// Get a Polar customer portal URL for managing an existing subscription.
    func getPortalURL(deviceId: String) async throws -> URL {
        let request = makeRequest(path: "/portal", deviceId: deviceId)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let result = try decode(PortalResponse.self, from: data, endpoint: "/portal")
        guard let url = URL(string: result.portalUrl) else {
            throw ServiceError.invalidResponse
        }
        return url
    }
    
    /// Restore a subscription on this device using a Polar license key.
    func restoreSubscription(deviceId: String, licenseKey: String) async throws -> RestoreResponse {
        let request = makeRequest(
            path: "/restore",
            method: "POST",
            deviceId: deviceId,
            body: ["license_key": licenseKey]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decode(RestoreResponse.self, from: data, endpoint: "/restore")
    }
    
    /// Verify an iOS App Store subscription transaction and link it to this device.
    func verifyAppleSubscription(deviceId: String, signedTransactionJWS: String) async throws -> AppleVerifyResponse {
        let request = makeRequest(
            path: "/apple/verify",
            method: "POST",
            deviceId: deviceId,
            body: ["signed_transaction_jws": signedTransactionJWS]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decode(AppleVerifyResponse.self, from: data, endpoint: "/apple/verify")
    }
    
    // MARK: - Attio
    
    func attioConnectStart(deviceId: String, callbackScheme: String = "miniti-attio") async throws -> AttioConnectStartResponse {
        let request = makeRequest(
            path: "/attio/connect/start",
            method: "POST",
            deviceId: deviceId,
            body: ["callback_scheme": callbackScheme]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decode(AttioConnectStartResponse.self, from: data, endpoint: "/attio/connect/start")
    }

    func attioStatus(deviceId: String) async throws -> AttioStatusResponse {
        let request = makeRequest(path: "/attio/status", deviceId: deviceId)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decode(AttioStatusResponse.self, from: data, endpoint: "/attio/status")
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
        return try decode(AttioSearchResponse.self, from: data, endpoint: "/attio/search").data
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
        return try decode(AttioSendResponse.self, from: data, endpoint: "/attio/send")
    }
    
    // MARK: - Response Validation
    
    private func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            let responseSnippet = Self.redactedBodySnippet(from: data)
            let errorSummary = Self.describeDecodingError(error)
            DebugLogger.shared.log(
                .app,
                "API decode FAILED: endpoint=\(endpoint), type=\(String(describing: type)), error=\(errorSummary), body=\(responseSnippet)"
            )
            
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.serverError(apiError.message ?? apiError.error)
            }
            throw ServiceError.invalidResponse
        }
    }
    
    private static func redactedBodySnippet(from data: Data) -> String {
        guard var text = String(data: data, encoding: .utf8) else {
            return "<non-utf8 body (\(data.count) bytes)>"
        }
        
        text = text.replacingOccurrences(
            of: #""temp_api_key"\s*:\s*"[^"]+""#,
            with: #""temp_api_key":"<redacted>""#,
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #""api_key"\s*:\s*"[^"]+""#,
            with: #""api_key":"<redacted>""#,
            options: .regularExpression
        )
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(220))
    }
    
    private static func describeDecodingError(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "keyNotFound(\(key.stringValue)) path=\(format(codingPath: context.codingPath)) \(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "typeMismatch(\(type)) path=\(format(codingPath: context.codingPath)) \(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "valueNotFound(\(type)) path=\(format(codingPath: context.codingPath)) \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "dataCorrupted path=\(format(codingPath: context.codingPath)) \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
    
    private static func format(codingPath: [CodingKey]) -> String {
        if codingPath.isEmpty { return "<root>" }
        return codingPath.map { $0.stringValue }.joined(separator: ".")
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let bodySnippet = Self.redactedBodySnippet(from: data)
            let urlString = httpResponse.url?.absoluteString ?? "unknown_url"
            DebugLogger.shared.log(.app, "API response error: status=\(httpResponse.statusCode), url=\(urlString), body=\(bodySnippet)")
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

/// Meta from backend insights response. When degraded is true, client must NOT advance ack cursor.
struct ManagedInsightsMeta: Codable {
    let degraded: Bool
    let fallbackReason: String?
    let requestSeq: Int?

    enum CodingKeys: String, CodingKey {
        case degraded
        case fallbackReason = "fallback_reason"
        case requestSeq = "request_seq"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        degraded = try container.decodeIfPresent(Bool.self, forKey: .degraded) ?? false
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
        requestSeq = try container.decodeIfPresent(Int.self, forKey: .requestSeq)
    }
}

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
    let meta: ManagedInsightsMeta?

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
        case meta
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
        meta = try container.decodeIfPresent(ManagedInsightsMeta.self, forKey: .meta)
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
