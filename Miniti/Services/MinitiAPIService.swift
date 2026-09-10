import Foundation

/// Communicates with the Miniti backend for managed mode.
/// Handles usage checking, session management (Deepgram grant JWTs), and insights proxy.
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
        return "https://api.miniti.app/api"
    }()
    
    /// `X-Platform` value for this build.
    static let platformHeader: String = {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }()

    /// Build a URLRequest with the identity headers. Authorization (device-bound bearer
    /// token + request proof) is attached by `send(_:)`; nothing secret is embedded here.
    private func makeRequest(
        path: String,
        method: String = "GET",
        deviceId: String,
        body: [String: Any]? = nil,
        timeoutInterval: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)\(path)")!)
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.httpMethod = method
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forHTTPHeaderField: "X-App-Version")
        request.setValue(Self.platformHeader, forHTTPHeaderField: "X-Platform")
        request.setValue("managed", forHTTPHeaderField: "X-App-Mode")
        
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Send a request with device-bound authorization: bearer token plus a request proof on
    /// writes, one silent retry after an expired token, and local sign-out when the server
    /// says this installation was revoked. `requiresAuth: false` lets public metadata
    /// (`/version`) go out without an account.
    private func send(_ original: URLRequest, requiresAuth: Bool = true) async throws -> (Data, URLResponse) {
        let auth = ClientAuthManager.shared
        var request = original
        if auth.isEnrolled {
            do {
                try await auth.authorize(&request)
            } catch ClientAuthError.revoked {
                throw ServiceError.authRevoked
            } catch let error as ClientAuthError {
                throw ServiceError.serverError(error.localizedDescription)
            }
        } else if requiresAuth {
            throw ServiceError.notEnrolled
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 401, auth.isEnrolled else {
            return (data, response)
        }
        let code = (try? Self.decoder.decode(APIError.self, from: data))?.error ?? ""
        switch code {
        case "token_expired", "invalid_token":
            var retry = original
            do {
                _ = try await auth.forceRefresh()
                try await auth.authorize(&retry)
            } catch ClientAuthError.revoked {
                throw ServiceError.authRevoked
            } catch let error as ClientAuthError {
                throw ServiceError.serverError(error.localizedDescription)
            }
            return try await URLSession.shared.data(for: retry)
        case "installation_revoked", "device_auth_required":
            auth.clearLocal()
            throw ServiceError.authRevoked
        default:
            return (data, response)
        }
    }
    
    // MARK: - Response Types
    
    struct UsageInfo: Decodable {
        let minutesUsed: Double
        let minutesLimit: Double
        let resetsAt: Date
        let tier: String
        let subscriptionStatus: String?
        /// Docs lookups consumed this period, metered server-side on the same rail
        /// as minutes. Nil until the backend reports it (older deployments).
        let docsLookupsUsed: Int?
        /// Monthly docs-lookup allowance. Nil = backend hasn't reported a cap yet.
        let docsLookupsLimit: Int?

        enum CodingKeys: String, CodingKey {
            case minutesUsed = "minutes_used"
            case minutesLimit = "minutes_limit"
            case resetsAt = "resets_at"
            case tier
            case subscriptionStatus = "subscription_status"
            case docsLookupsUsed = "docs_lookups_used"
            case docsLookupsLimit = "docs_lookups_limit"
            case minutesUsedCamel = "minutesUsed"
            case minutesLimitCamel = "minutesLimit"
            case resetsAtCamel = "resetsAt"
            case subscriptionStatusCamel = "subscriptionStatus"
            case docsLookupsUsedCamel = "docsLookupsUsed"
            case docsLookupsLimitCamel = "docsLookupsLimit"
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
            docsLookupsUsed = MinitiAPIService.decodeOptionalInt(container, .docsLookupsUsed, .docsLookupsUsedCamel)
            docsLookupsLimit = MinitiAPIService.decodeOptionalInt(container, .docsLookupsLimit, .docsLookupsLimitCamel)
        }

        var isPro: Bool { tier == "pro" }

        /// Remaining docs lookups this period, or nil if the backend hasn't
        /// reported a cap (in which case the client shouldn't gate on it).
        var docsLookupsRemaining: Int? {
            guard let limit = docsLookupsLimit else { return nil }
            return max(0, limit - (docsLookupsUsed ?? 0))
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
    
    struct SessionResponse: Decodable {
        /// Canonical Deepgram JWT from `/api/session`.
        let accessToken: String
        /// Always `"Bearer"` for managed grant tokens.
        let tokenType: String
        /// Lifetime in seconds when provided by the API (max 3600).
        let expiresIn: Int?
        let expiresAt: Date
        let sessionId: String
        
        /// Deprecated alias for `accessToken` (older clients / transitional responses).
        var tempApiKey: String { accessToken }
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accessTokenCamel = "accessToken"
            case tempApiKey = "temp_api_key"
            case tempApiKeyCamel = "tempApiKey"
            case tokenType = "token_type"
            case tokenTypeCamel = "tokenType"
            case expiresIn = "expires_in"
            case expiresInCamel = "expiresIn"
            case expiresAt = "expires_at"
            case expiresAtCamel = "expiresAt"
            case sessionId = "session_id"
            case sessionIdCamel = "sessionId"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Prefer access_token; fall back to deprecated temp_api_key during cutover.
            let token =
                (try? container.decode(String.self, forKey: .accessToken)) ??
                (try? container.decode(String.self, forKey: .accessTokenCamel)) ??
                (try? container.decode(String.self, forKey: .tempApiKey)) ??
                (try? container.decode(String.self, forKey: .tempApiKeyCamel)) ??
                ""
            
            tokenType =
                (try? container.decode(String.self, forKey: .tokenType)) ??
                (try? container.decode(String.self, forKey: .tokenTypeCamel)) ??
                "Bearer"
            
            if let value = try? container.decode(Int.self, forKey: .expiresIn) {
                expiresIn = value
            } else if let value = try? container.decode(Int.self, forKey: .expiresInCamel) {
                expiresIn = value
            } else if let string =
                        (try? container.decode(String.self, forKey: .expiresIn)) ??
                        (try? container.decode(String.self, forKey: .expiresInCamel)),
                      let value = Int(string) {
                expiresIn = value
            } else {
                expiresIn = nil
            }
            
            // expires_at is authoritative; otherwise derive from expires_in. No long default TTL.
            if let date =
                (try? container.decode(Date.self, forKey: .expiresAt)) ??
                (try? container.decode(Date.self, forKey: .expiresAtCamel)) {
                expiresAt = date
            } else if let expiresIn, expiresIn > 0 {
                expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "Missing session expiry (expires_at / expires_in)")
                )
            }
            
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
            
            if token.isEmpty || sessionId.isEmpty {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "Missing session token fields")
                )
            }
            accessToken = token
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
        struct QuestionState: Sendable {
            let question: String
            let type: String
            let context: String
            let priority: String?

            var dictionary: [String: Any] {
                var result: [String: Any] = [
                    "question": question,
                    "type": type,
                    "context": context
                ]
                if let priority, !priority.isEmpty {
                    result["priority"] = priority
                }
                return result
            }
        }

        let summary: String?
        let discussionFlow: [String]
        let actionItems: [String]
        let topics: [String]
        let suggestedTitle: String?
        let meddpicc: [String: String]?
        let questions: [QuestionState]?

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
            if let questions, !questions.isEmpty {
                result["questions"] = questions.map(\.dictionary)
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

    // MARK: - Google Calendar

    struct GoogleConnectStartResponse: Decodable {
        let authURL: String
        let callbackScheme: String

        enum CodingKeys: String, CodingKey {
            case authURL = "auth_url"
            case callbackScheme = "callback_scheme"
        }
    }

    struct GoogleStatusResponse: Decodable {
        let connected: Bool
        let email: String?
    }

    struct GoogleDisconnectResponse: Decodable {
        let disconnected: Bool
    }

    struct CalendarEvent: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let start: String
        let end: String
        let isAllDay: Bool
        let status: String
        let meetLink: String?
        let conferenceUrl: String?
        let attendees: [CalendarAttendee]
        let organizer: CalendarOrganizer?

        // The wire format from `miniti-api` (`lib/google.ts`) is camelCase, the same
        // shape the Linux client reads. The snake_case keys are a fallback for the
        // screenshot fixture and older test data only. Decoding the wrong case
        // silently produced nil links, nil display names, and "needsAction" for
        // every attendee for months, because every field has a default.
        enum CodingKeys: String, CodingKey {
            case id, title, start, end, status, attendees, organizer
            case isAllDay
            case isAllDaySnake = "is_all_day"
            case meetLink
            case meetLinkSnake = "meet_link"
            case conferenceUrl
            case conferenceUrlSnake = "conference_url"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
            start = try c.decode(String.self, forKey: .start)
            end = try c.decode(String.self, forKey: .end)
            isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay)
                ?? c.decodeIfPresent(Bool.self, forKey: .isAllDaySnake)
                ?? false
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "confirmed"
            meetLink = try c.decodeIfPresent(String.self, forKey: .meetLink)
                ?? c.decodeIfPresent(String.self, forKey: .meetLinkSnake)
            conferenceUrl = try c.decodeIfPresent(String.self, forKey: .conferenceUrl)
                ?? c.decodeIfPresent(String.self, forKey: .conferenceUrlSnake)
            attendees = (try? c.decodeIfPresent([CalendarAttendee].self, forKey: .attendees)) ?? []
            organizer = try c.decodeIfPresent(CalendarOrganizer.self, forKey: .organizer)
        }

        var startDate: Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: start) ?? {
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: start)
            }()
        }

        var endDate: Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: end) ?? {
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: end)
            }()
        }

        var externalAttendees: [CalendarAttendee] {
            attendees.filter { !$0.isSelf }
        }

        var attendeeDomains: Set<String> {
            Set(externalAttendees.map(\.domain).filter { !$0.isEmpty })
        }

        /// Prefer `conference_url`, then `meet_link`. Third-party calendar data is
        /// allowlisted to `https` only before any surface hands it to the system opener.
        var joinURL: URL? {
            for raw in [conferenceUrl, meetLink] {
                let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let url = URL(string: trimmed),
                      url.scheme?.lowercased() == "https" else {
                    continue
                }
                return url
            }
            return nil
        }
    }

    struct CalendarAttendee: Decodable, Identifiable, Sendable {
        var id: String { email }
        let email: String
        let displayName: String?
        let responseStatus: String
        let organizer: Bool
        let isSelf: Bool
        let domain: String

        enum CodingKeys: String, CodingKey {
            case email, organizer, domain
            case displayName
            case displayNameSnake = "display_name"
            case responseStatus
            case responseStatusSnake = "response_status"
            case isSelf = "self"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            email = try c.decode(String.self, forKey: .email)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .displayNameSnake)
            responseStatus = try c.decodeIfPresent(String.self, forKey: .responseStatus)
                ?? c.decodeIfPresent(String.self, forKey: .responseStatusSnake)
                ?? "needsAction"
            organizer = try c.decodeIfPresent(Bool.self, forKey: .organizer) ?? false
            isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
            let rawDomain = try c.decodeIfPresent(String.self, forKey: .domain)
            if let rawDomain, !rawDomain.isEmpty {
                domain = rawDomain
            } else {
                let parts = email.split(separator: "@")
                domain = parts.count == 2 ? String(parts[1]) : ""
            }
        }

        func toMeetingAttendee() -> MeetingAttendee {
            MeetingAttendee(
                email: email,
                displayName: displayName,
                domain: domain,
                responseStatus: responseStatus,
                isOrganizer: organizer,
                isSelf: isSelf
            )
        }
    }

    struct CalendarOrganizer: Decodable, Sendable {
        let email: String
        let displayName: String?
        let isSelf: Bool

        enum CodingKeys: String, CodingKey {
            case email
            case displayName
            case displayNameSnake = "display_name"
            case isSelf = "self"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            email = try c.decode(String.self, forKey: .email)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .displayNameSnake)
            isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
        }
    }

    struct GoogleEventsResponse: Decodable {
        let events: [CalendarEvent]
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
        let recordDetail: String?

        enum CodingKeys: String, CodingKey {
            case idPayload = "id"
            case recordText = "record_text"
            case recordImage = "record_image"
            case objectSlug = "object_slug"
            case recordEmail = "record_email"
            case recordDomain = "record_domain"
            case recordDetail = "record_detail"
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

        var objectLabel: String {
            switch objectSlug.lowercased() {
            case "people": return "person"
            case "companies": return "company"
            case "opportunities": return "opportunity"
            default: return objectSlug
            }
        }

        var detailLabel: String {
            let slug = objectSlug.lowercased()
            if let recordDetail = recordDetail?.trimmingCharacters(in: .whitespaces), !recordDetail.isEmpty {
                return "\(objectLabel) · \(recordDetail)"
            }
            let value = secondaryIdentifier?.trimmingCharacters(in: .whitespaces)
            if let value, !value.isEmpty {
                return "\(objectLabel) · \(value)"
            }
            switch slug {
            case "people": return "person · no email"
            case "companies": return "company · no domain"
            case "opportunities": return "opportunity"
            default: return objectLabel
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
        /// Managed mode has no device account yet (enrollment pending or failed).
        case notEnrolled
        /// The server revoked this installation; local credentials were cleared.
        case authRevoked
        
        var errorDescription: String? {
            switch self {
            case .notEnrolled:
                return "Miniti is still setting up this device. Check your connection and try again."
            case .authRevoked:
                return "This device was signed out of its Miniti account. Restore it with your recovery key in Settings → Account & Plan."
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

    /// Decode an optional integer that Vercel KV may return as an Int or a String,
    /// under either a snake_case or camelCase key.
    fileprivate static func decodeOptionalInt<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K,
        _ camelKey: K
    ) -> Int? {
        if let val = try? container.decode(Int.self, forKey: key) { return val }
        if let val = try? container.decode(Int.self, forKey: camelKey) { return val }
        if let val = try? container.decode(Double.self, forKey: key) { return Int(val) }
        if let val = try? container.decode(Double.self, forKey: camelKey) { return Int(val) }
        if let str = (try? container.decode(String.self, forKey: key)) ??
            (try? container.decode(String.self, forKey: camelKey)) {
            return Int(str)
        }
        return nil
    }
    
    // MARK: - Version Check
    
    struct VersionInfo: Decodable {
        let latestVersion: String
        let minVersion: String?
        let downloadUrl: String
        let releaseNotes: String?
        
        enum CodingKeys: String, CodingKey {
            case latestVersion = "latest_version"
            case minVersion = "min_version"
            case downloadUrl = "download_url"
            case releaseNotes = "release_notes"
        }
    }
    
    /// Check if a newer version is available and optionally register the device.
    func checkVersion(deviceId: String? = nil, appMode: String? = nil) async throws -> VersionInfo {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/version")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forHTTPHeaderField: "X-App-Version")
        request.setValue(Self.platformHeader, forHTTPHeaderField: "X-Platform")
        if let deviceId { request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID") }
        if let appMode { request.setValue(appMode, forHTTPHeaderField: "X-App-Mode") }
        
        // Public metadata: works before enrollment (and for BYOK); enrolled devices send
        // their bearer so the dashboard sees them, exactly like the Linux client.
        let (data, response) = try await send(request, requiresAuth: false)
        try validateResponse(response, data: data)
        
        return try decode(VersionInfo.self, from: data, endpoint: "/version")
    }
    
    // MARK: - API Methods
    
    /// Check current usage for a device.
    func checkUsage(deviceId: String) async throws -> UsageInfo {
        let request = makeRequest(path: "/usage", deviceId: deviceId)
        
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        
        return try decode(UsageInfo.self, from: data, endpoint: "/usage")
    }
    
    /// Request a new transcription session. Returns a short-lived Deepgram grant JWT.
    /// The backend validates the device, checks usage limits, and mints `access_token` (Bearer).
    func requestSession(deviceId: String, model: String) async throws -> SessionResponse {
        let request = makeRequest(
            path: "/session",
            method: "POST",
            deviceId: deviceId,
            body: ["model": model]
        )
        
        let (data, response) = try await send(request)
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
            
            let (data, response) = try await send(request)
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
        language: String = "en",
        attendees: [[String: String]]? = nil,
        template: InsightTemplate? = nil,
        previousTemplateSections: [String: String]? = nil
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
        if let attendees, !attendees.isEmpty { body["attendees"] = attendees }
        if let incrementalPayload {
            body["incremental"] = true
            body["incremental_payload"] = incrementalPayload.dictionary
        }
        if let template {
            body["template"] = template.requestDictionary
            if let previousTemplateSections, !previousTemplateSections.isEmpty {
                // The backend treats a baseline as its lightweight incremental mode.
                body["previous_sections"] = previousTemplateSections
                body["incremental"] = true
            }
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
        
        let (data, response) = try await send(request)
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

    /// Managed-mode docs playbook: backend retrieves from user MCP URL then grounds answers.
    /// Managed docs lookup for a single topic. The backend uses `topic` as the MCP
    /// search query (falling back to the transcript for older deployments) and
    /// grounds an answer. This request counts against the docs-lookup quota.
    func generateDocsPlaybook(
        deviceId: String,
        transcript: String,
        docsMcpURL: String,
        model: String,
        topic: String? = nil,
        requestSeq: Int? = nil,
        language: String = "en"
    ) async throws -> ManagedDocsPlaybookResponse {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var body: [String: Any] = [
            "transcript": transcript,
            "mode": "docs",
            "model": model,
            "language": language,
            "docs_mcp_url": docsMcpURL,
        ]
        if let topic, !topic.isEmpty { body["topic"] = topic }
        if let requestSeq { body["request_seq"] = requestSeq }

        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        DebugLogger.shared.log(
            .app,
            "API docs playbook request: transcriptChars=\(transcript.count), topic=\(topic ?? "-"), mcpURL=\(docsMcpURL)"
        )

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        let decoded = try decode(ManagedDocsPlaybookResponse.self, from: data, endpoint: "/insights docs")
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "API docs playbook response: duration=\(String(format: "%.2fs", duration)), cards=\(decoded.docs.count), degraded=\(decoded.meta?.degraded ?? false)"
        )
        return decoded
    }

    /// Managed extraction of lookup-worthy docs topics (`mode: "docs_topics"`).
    /// Topic extraction is free — it does not count against the docs-lookup quota.
    /// Older backend deployments that don't know this mode decode to empty topics
    /// and the caller no-ops gracefully.
    func extractDocsTopics(
        deviceId: String,
        transcript: String,
        docsMcpURL: String,
        model: String,
        language: String = "en"
    ) async throws -> ManagedDocsTopicsResponse {
        let body: [String: Any] = [
            "transcript": transcript,
            "mode": "docs_topics",
            "model": model,
            "language": language,
            "docs_mcp_url": docsMcpURL,
        ]

        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(ManagedDocsTopicsResponse.self, from: data, endpoint: "/insights docs_topics")
    }

    /// Managed-mode proxy for the "i zoned out" catch-up feature.
    /// Posts to /api/insights with mode="catchup" and expects a dedicated catchup payload back.
    /// If the backend hasn't been updated to support this mode yet, the response will decode
    /// with empty fields and the caller should surface a graceful "not available" state.
    func generateCatchUp(
        deviceId: String,
        recentTranscript: String,
        fullTranscript: String?,
        model: String,
        language: String = "en"
    ) async throws -> CatchUpResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var body: [String: Any] = [
            "transcript": recentTranscript,
            "mode": "catchup",
            "model": model,
            "language": language
        ]
        if let fullTranscript, !fullTranscript.isEmpty, fullTranscript != recentTranscript {
            body["full_transcript"] = fullTranscript
        }

        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        DebugLogger.shared.log(
            .app,
            "API catchup request: model=\(model), recentChars=\(recentTranscript.count), fullChars=\(fullTranscript?.count ?? 0), language=\(language)"
        )

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        let decoded = try decode(CatchUpResult.self, from: data, endpoint: "/insights catchup")
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "API catchup response: duration=\(String(format: "%.2fs", duration)), topicChars=\(decoded.currentTopic.count), questions=\(decoded.questionsForYou.count), discussion=\(decoded.recentDiscussion.count), decisions=\(decoded.keyDecisions.count)"
        )
        return decoded
    }

    /// Managed-mode OpenAI investigation. Web scope enables server-side web
    /// search; codebase scope sends only the bounded local excerpts selected by
    /// the macOS client.
    func generateInvestigation(
        deviceId: String,
        focus: String,
        meetingContext: String,
        scope: InvestigationScope,
        codebaseContext: String?,
        referencedFiles: [String],
        model: String,
        language: String = "en"
    ) async throws -> InvestigationResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var body: [String: Any] = [
            "transcript": meetingContext,
            "mode": "investigation",
            "investigation_scope": scope.rawValue,
            "focus": focus,
            "referenced_files": referencedFiles,
            "model": model,
            "language": language
        ]
        if let codebaseContext, !codebaseContext.isEmpty {
            body["codebase_context"] = codebaseContext
        }

        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        DebugLogger.shared.log(
            .app,
            "API investigation request: scope=\(scope.rawValue), meetingChars=\(meetingContext.count), codeChars=\(codebaseContext?.count ?? 0), files=\(referencedFiles.count)"
        )

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        let decoded = try decode(InvestigationResult.self, from: data, endpoint: "/insights investigation")
        DebugLogger.shared.log(
            .app,
            "API investigation response: duration=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - startedAt)), answerChars=\(decoded.answer.count), sources=\(decoded.sources.count)"
        )
        return decoded
    }

    /// Managed-mode speaker name inference. Posts to /api/insights with mode="speaker_names".
    /// Transcript is expected to include `[SpeakerID:N] ...` tags so the backend prompt can
    /// map internal IDs to real names. `candidates` is a list of known attendee names used
    /// to bias the model. If the backend hasn't been updated to support this mode yet, the
    /// response decodes with an empty speakers map and callers should treat that as a no-op.
    func inferSpeakerNames(
        deviceId: String,
        transcript: String,
        candidates: [String],
        model: String,
        language: String = "en"
    ) async throws -> [String: String] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var body: [String: Any] = [
            "transcript": transcript,
            "mode": "speaker_names",
            "model": model,
            "language": language
        ]
        let cleanedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanedCandidates.isEmpty {
            body["candidates"] = cleanedCandidates
        }

        let request = makeRequest(
            path: "/insights",
            method: "POST",
            deviceId: deviceId,
            body: body
        )
        DebugLogger.shared.log(
            .app,
            "API speaker-names request: model=\(model), transcriptChars=\(transcript.count), candidates=\(cleanedCandidates.count), language=\(language)"
        )

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        let decoded = try decode(ManagedSpeakerNamesResponse.self, from: data, endpoint: "/insights speaker_names")
        let cleaned = SpeakerNamesResponse.sanitize(decoded.speakers)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "API speaker-names response: duration=\(String(format: "%.2fs", duration)), identified=\(cleaned.count)/\(decoded.speakers.count)"
        )
        return cleaned
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

        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
    }

    // MARK: - Subscription
    
    /// Get a Polar checkout URL for upgrading to Pro.
    func getSubscribeURL(deviceId: String) async throws -> URL {
        let request = makeRequest(path: "/subscribe", deviceId: deviceId)
        let (data, response) = try await send(request)
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
        let (data, response) = try await send(request)
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
        let (data, response) = try await send(request)
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
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AppleVerifyResponse.self, from: data, endpoint: "/apple/verify")
    }
    
    // MARK: - Google Calendar
    
    func googleConnectStart(deviceId: String, callbackScheme: String = "miniti-google") async throws -> GoogleConnectStartResponse {
        let request = makeRequest(
            path: "/google/connect/start",
            method: "POST",
            deviceId: deviceId,
            body: ["callback_scheme": callbackScheme]
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(GoogleConnectStartResponse.self, from: data, endpoint: "/google/connect/start")
    }

    func googleStatus(deviceId: String) async throws -> GoogleStatusResponse {
        let request = makeRequest(path: "/google/status", deviceId: deviceId)
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(GoogleStatusResponse.self, from: data, endpoint: "/google/status")
    }

    func googleEvents(deviceId: String, timeMin: String? = nil, timeMax: String? = nil, maxResults: Int = 20) async throws -> [CalendarEvent] {
        var path = "/google/events?max_results=\(maxResults)"
        if let timeMin { path += "&time_min=\(timeMin)" }
        if let timeMax { path += "&time_max=\(timeMax)" }
        let request = makeRequest(path: path, deviceId: deviceId)
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(GoogleEventsResponse.self, from: data, endpoint: "/google/events").events
    }

    func googleDisconnect(deviceId: String) async throws -> GoogleDisconnectResponse {
        let request = makeRequest(
            path: "/google/disconnect",
            method: "POST",
            deviceId: deviceId
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(GoogleDisconnectResponse.self, from: data, endpoint: "/google/disconnect")
    }

    // MARK: - Attio
    
    func attioConnectStart(deviceId: String, callbackScheme: String = "miniti-attio") async throws -> AttioConnectStartResponse {
        let request = makeRequest(
            path: "/attio/connect/start",
            method: "POST",
            deviceId: deviceId,
            body: ["callback_scheme": callbackScheme],
            timeoutInterval: 15
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioConnectStartResponse.self, from: data, endpoint: "/attio/connect/start")
    }

    func attioStatus(deviceId: String) async throws -> AttioStatusResponse {
        let request = makeRequest(path: "/attio/status", deviceId: deviceId, timeoutInterval: 10)
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioStatusResponse.self, from: data, endpoint: "/attio/status")
    }

    func attioSearch(deviceId: String, query: String, objects: [String]) async throws -> [AttioSearchRecord] {
        let request = makeRequest(
            path: "/attio/search",
            method: "POST",
            deviceId: deviceId,
            body: ["query": query, "objects": objects],
            timeoutInterval: 15
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioSearchResponse.self, from: data, endpoint: "/attio/search").data
    }

    func attioSendMeeting(
        deviceId: String,
        meetingPayload: AttioMeetingPayload,
        targetObject: String,
        targetRecordID: String,
        createTasksFromActionItems: Bool,
        tasks: [CRMTaskPayload]? = nil
    ) async throws -> AttioSendResponse {
        var body: [String: Any] = [
            "target_object": targetObject,
            "target_record_id": targetRecordID,
            "meeting": meetingPayload.dictionary,
            "create_tasks_from_action_items": createTasksFromActionItems
        ]
        if let tasks {
            // Explicit tasks are backward-safe: an older backend ignores `tasks`
            // and sees the legacy switch disabled, so it cannot create deselected items.
            body["create_tasks_from_action_items"] = false
            body["tasks"] = tasks.map(\.dictionary)
        }
        let request = makeRequest(
            path: "/attio/send",
            method: "POST",
            deviceId: deviceId,
            body: body,
            timeoutInterval: 30
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioSendResponse.self, from: data, endpoint: "/attio/send")
    }

    // Twenty deliberately mirrors the Attio response contract so the macOS CRM
    // send surface can share connection, record-selection, and result handling.
    func twentyConnectStart(deviceId: String, callbackScheme: String = "miniti-twenty") async throws -> AttioConnectStartResponse {
        let request = makeRequest(
            path: "/twenty/connect/start",
            method: "POST",
            deviceId: deviceId,
            body: ["callback_scheme": callbackScheme],
            timeoutInterval: 15
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioConnectStartResponse.self, from: data, endpoint: "/twenty/connect/start")
    }

    func twentyStatus(deviceId: String) async throws -> AttioStatusResponse {
        let request = makeRequest(path: "/twenty/status", deviceId: deviceId, timeoutInterval: 10)
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioStatusResponse.self, from: data, endpoint: "/twenty/status")
    }

    func twentySearch(deviceId: String, query: String, objects: [String]) async throws -> [AttioSearchRecord] {
        let request = makeRequest(
            path: "/twenty/search",
            method: "POST",
            deviceId: deviceId,
            body: ["query": query, "objects": objects],
            timeoutInterval: 15
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioSearchResponse.self, from: data, endpoint: "/twenty/search").data
    }

    func twentySendMeeting(
        deviceId: String,
        meetingPayload: AttioMeetingPayload,
        targetObject: String,
        targetRecordID: String,
        createTasksFromActionItems: Bool,
        tasks: [CRMTaskPayload]? = nil
    ) async throws -> AttioSendResponse {
        var body: [String: Any] = [
            "target_object": targetObject,
            "target_record_id": targetRecordID,
            "meeting": meetingPayload.dictionary,
            "create_tasks_from_action_items": createTasksFromActionItems
        ]
        if let tasks {
            body["create_tasks_from_action_items"] = false
            body["tasks"] = tasks.map(\.dictionary)
        }
        let request = makeRequest(
            path: "/twenty/send",
            method: "POST",
            deviceId: deviceId,
            body: body,
            timeoutInterval: 30
        )
        let (data, response) = try await send(request)
        try validateResponse(response, data: data)
        return try decode(AttioSendResponse.self, from: data, endpoint: "/twenty/send")
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
            of: #""access_token"\s*:\s*"[^"]+""#,
            with: #""access_token":"<redacted>""#,
            options: .regularExpression
        )
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
        case 401:
            if let apiError = try? Self.decoder.decode(APIError.self, from: data),
               ["installation_revoked", "device_auth_required"].contains(apiError.error) {
                throw ServiceError.authRevoked
            }
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.serverError(apiError.message ?? apiError.error)
            }
            throw ServiceError.serverError("HTTP 401")
        default:
            if let apiError = try? Self.decoder.decode(APIError.self, from: data) {
                throw ServiceError.serverError(apiError.message ?? apiError.error)
            }
            throw ServiceError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - CRM Task + Meeting Payload

struct CRMTaskPayload: Equatable, Sendable {
    let content: String
    let deadlineAt: String?

    static func fromActionItems(_ items: [String], deadlineAt: String?) -> [CRMTaskPayload] {
        AttioMeetingPayload.normalizedActionItems(from: items).map {
            CRMTaskPayload(content: $0, deadlineAt: deadlineAt)
        }
    }

    static func localISODate(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = ["content": content]
        if let deadlineAt { result["deadline_at"] = deadlineAt }
        return result
    }
}

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
    let transcriptEditedAt: Date?
    let transcriptRevision: Int?
    let insightsStale: Bool

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
            meddpicc: meddpicc,
            transcriptEditedAt: meeting.transcriptEditedAt,
            transcriptRevision: meeting.hasTranscriptEdits ? meeting.transcriptRevision : nil,
            insightsStale: false
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
        if let transcriptEditedAt {
            result["transcript_edited_at"] = ISO8601DateFormatter().string(from: transcriptEditedAt)
        }
        if let transcriptRevision {
            result["transcript_revision"] = transcriptRevision
        }
        result["insights_stale"] = insightsStale
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
    let questions: [SuggestedQuestion]
    let docs: [DocPlaybookCard]
    let templateID: String?
    let templateSections: [String: String?]?
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
        case questions
        case docs
        case templateID = "template_id"
        case templateSections = "template_sections"
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
        questions = try container.decodeIfPresent([SuggestedQuestion].self, forKey: .questions) ?? []
        docs = try container.decodeIfPresent([DocPlaybookCard].self, forKey: .docs) ?? []
        templateID = try container.decodeIfPresent(String.self, forKey: .templateID)
        templateSections = try container.decodeIfPresent([String: String?].self, forKey: .templateSections)
        meta = try container.decodeIfPresent(ManagedInsightsMeta.self, forKey: .meta)
    }
    
    func toLiveInsights(template: InsightTemplate? = nil) -> InsightsService.LiveInsights {
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
            competition: competition,
            questions: questions,
            docs: docs,
            templateID: templateID ?? template?.id,
            templateSections: template.map {
                InsightTemplateSections.normalize(templateSections ?? [:], for: $0)
            } ?? [:]
        )
    }
}

/// Backend response for `mode: "docs"` on `/api/insights`.
struct ManagedDocsPlaybookResponse: Codable {
    let docs: [DocPlaybookCard]
    let meta: ManagedInsightsMeta?

    enum CodingKeys: String, CodingKey {
        case docs
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        docs = try container.decodeIfPresent([DocPlaybookCard].self, forKey: .docs) ?? []
        meta = try container.decodeIfPresent(ManagedInsightsMeta.self, forKey: .meta)
    }
}

/// Backend response for `mode: "docs_topics"`. Older deployments that don't know
/// this mode return no `topics` and decode to an empty list.
struct ManagedDocsTopicsResponse: Codable {
    let topics: [String]
    let meta: ManagedInsightsMeta?

    enum CodingKeys: String, CodingKey {
        case topics
        case meta
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            topics = []
            meta = nil
            return
        }
        topics = (try? container.decodeIfPresent([String].self, forKey: .topics)) ?? nil ?? []
        meta = (try? container.decodeIfPresent(ManagedInsightsMeta.self, forKey: .meta)) ?? nil
    }
}

/// Backend response for `mode: "speaker_names"` on `/api/insights`.
/// Older backend deployments that don't know about this mode may return `{}` or a standard
/// insights response — in both cases we decode to an empty `speakers` map and no-op.
struct ManagedSpeakerNamesResponse: Decodable {
    let speakers: [String: String]

    enum CodingKeys: String, CodingKey {
        case speakers
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let map = try? container?.decodeIfPresent([String: String].self, forKey: .speakers) {
            speakers = map
        } else {
            speakers = [:]
        }
    }
}
