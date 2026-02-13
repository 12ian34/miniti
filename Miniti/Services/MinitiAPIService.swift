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
    
    // MARK: - Errors
    
    enum ServiceError: LocalizedError {
        case limitReached(minutesUsed: Double, resetsAt: Date?)
        case networkError(Error)
        case invalidResponse
        case serverError(String)
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .limitReached(let used, _):
                return "Monthly limit reached (\(Int(used)) min used)."
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
    
    // MARK: - Response Validation
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // OK
        case 402:
            // Payment required — limit reached
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.limitReached(
                    minutesUsed: apiError.minutesUsed ?? 500,
                    resetsAt: apiError.resetsAt
                )
            }
            throw ServiceError.limitReached(minutesUsed: 500, resetsAt: nil)
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
