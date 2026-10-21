import Foundation

// MARK: - Cloud sync transport (3.0.0)
//
// The `/api/sync/*` routes and the Settings → Cloud management routes. Every call goes
// through `send(_:)` so bearer tokens, request proofs, token refresh and revocation
// handling stay in one place. Documents travel as raw JSON data so the proof is computed
// over the exact bytes the server hashes.

/// What the server holds for one meeting, as returned on a conflict or a fetch.
struct CloudMeetingState: Equatable {
    let id: UUID
    let revision: Int
    let deleted: Bool
    let updatedAt: Date?
    let document: [String: Any]?

    static func == (lhs: CloudMeetingState, rhs: CloudMeetingState) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision && lhs.deleted == rhs.deleted && lhs.updatedAt == rhs.updatedAt
    }

    init(id: UUID, revision: Int, deleted: Bool, updatedAt: Date?, document: [String: Any]?) {
        self.id = id
        self.revision = revision
        self.deleted = deleted
        self.updatedAt = updatedAt
        self.document = document
    }

    init?(json: [String: Any], fallbackID: UUID?) {
        guard let id = (json["id"] as? String).flatMap(UUID.init(uuidString:)) ?? fallbackID else { return nil }
        self.id = id
        self.revision = (json["server_revision"] as? NSNumber)?.intValue ?? (json["revision"] as? NSNumber)?.intValue ?? 0
        self.deleted = json["deleted"] as? Bool ?? false
        self.updatedAt = MeetingSyncDocument.date(json["updated_at"])
        self.document = json["document"] as? [String: Any]
    }
}

struct CloudManifestEntry: Equatable {
    let id: UUID
    let revision: Int
    let updatedAt: Date?
    let deleted: Bool
}

struct CloudManifest {
    let entries: [CloudManifestEntry]
    let latestSeq: Int
}

struct CloudChange {
    let seq: Int
    let id: UUID
    let revision: Int
    let deleted: Bool
    let updatedAt: Date?
    let document: [String: Any]?
}

struct CloudChangesPage {
    let changes: [CloudChange]
    let nextSince: Int
    let hasMore: Bool
    let latestSeq: Int
}

enum CloudPutResult {
    case ok(revision: Int)
    case conflict(CloudMeetingState)
    case externalDuplicate(existing: CloudMeetingState)
    case tooLarge
}

enum CloudDeleteResult {
    case ok(revision: Int)
    case conflict(CloudMeetingState)
}

struct CloudStatus: Equatable {
    let tier: String
    let syncAllowed: Bool
    let bytes: Int
    let meetingCount: Int
    let latestSeq: Int
    let email: String?
    let connectedApps: Int
    let tokens: Int
}

struct CloudToken: Identifiable, Equatable {
    let id: String
    let name: String
    let prefix: String
    let createdAt: Date?
    let lastUsedAt: Date?
}

struct CloudConnectedApp: Identifiable, Equatable {
    let id: String
    let clientName: String
    let scopes: [String]
    let createdAt: Date?
    let lastUsedAt: Date?
}

/// Why a cloud call was refused, mapped from the server's error codes.
enum CloudSyncError: Error, Equatable {
    /// `410 cursor_expired`: reconcile from the manifest.
    case cursorExpired
    /// `402 pro_required`.
    case proRequired
    /// `503 cloud_unavailable`: the feature is off on the server.
    case unavailable
    /// `403 cloud_not_available_yet`: allowlisted rollout.
    case notAvailableYet
    /// `403 cloud_requires_managed`.
    case requiresManaged
    /// `429`.
    case rateLimited
    /// No account on this device yet.
    case notEnrolled
    /// The server revoked this installation (credentials were cleared locally).
    case revoked
    case offline
    case server(code: String, status: Int)
}

/// Sendable so the main-actor engine can call it across isolation; `MinitiAPIService` is
/// `@unchecked Sendable` and the test fake is too. Documents travel as encoded JSON data.
protocol CloudSyncTransport: AnyObject, Sendable {
    func manifest() async throws -> CloudManifest
    func changes(since: Int, limit: Int) async throws -> CloudChangesPage
    func fetchMeeting(id: UUID) async throws -> CloudMeetingState?
    func fetchMeetings(ids: [UUID]) async throws -> [CloudMeetingState]
    func putMeeting(id: UUID, baseRevision: Int, document: Data) async throws -> CloudPutResult
    func deleteMeeting(id: UUID, baseRevision: Int) async throws -> CloudDeleteResult
    func status() async throws -> CloudStatus
    func deleteCloudCopy() async throws
    /// The account's cloud switch (3.3.0). Returns the new version.
    func setAccountCloud(enabled: Bool) async throws -> Int
}

extension MinitiAPIService: CloudSyncTransport {
    private var cloudDeviceID: String { DeviceIdentifier.getOrCreateDeviceId() }

    private func cloudRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = makeRequest(path: path, method: method, deviceId: cloudDeviceID, timeoutInterval: 30)
        request.httpBody = body
        return request
    }

    /// Run a cloud call, mapping the shared error codes; returns the status and parsed body.
    private func cloudCall(_ request: URLRequest) async throws -> (Int, [String: Any]) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch ServiceError.notEnrolled {
            throw CloudSyncError.notEnrolled
        } catch ServiceError.authRevoked {
            throw CloudSyncError.revoked
        } catch let error as URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code) {
                throw CloudSyncError.offline
            }
            throw CloudSyncError.server(code: "url_error_\(error.code.rawValue)", status: 0)
        }
        guard let http = response as? HTTPURLResponse else { throw CloudSyncError.server(code: "invalid_response", status: 0) }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = json["error"] as? String ?? ""
        switch http.statusCode {
        case 200..<300:
            return (http.statusCode, json)
        case 410 where code == "cursor_expired":
            throw CloudSyncError.cursorExpired
        case 402:
            throw CloudSyncError.proRequired
        case 503 where code == "cloud_unavailable":
            throw CloudSyncError.unavailable
        case 403 where code == "cloud_not_available_yet":
            throw CloudSyncError.notAvailableYet
        case 403 where code == "cloud_requires_managed":
            throw CloudSyncError.requiresManaged
        case 429:
            throw CloudSyncError.rateLimited
        case 401:
            // `send` already refreshed once and clears local credentials on a revocation,
            // so a 401 that still reaches here is transient: try again next pass.
            throw CloudSyncError.server(code: code.isEmpty ? "http_401" : code, status: 401)
        case 409, 413, 404:
            // Handled by the caller from the parsed body.
            return (http.statusCode, json)
        default:
            throw CloudSyncError.server(code: code.isEmpty ? "http_\(http.statusCode)" : code, status: http.statusCode)
        }
    }

    func manifest() async throws -> CloudManifest {
        let (_, json) = try await cloudCall(cloudRequest(path: "/sync/manifest"))
        let entries = ((json["entries"] as? [[String: Any]]) ?? []).compactMap { e -> CloudManifestEntry? in
            guard let id = (e["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return CloudManifestEntry(id: id, revision: (e["revision"] as? NSNumber)?.intValue ?? 0, updatedAt: MeetingSyncDocument.date(e["updated_at"]), deleted: e["deleted"] as? Bool ?? false)
        }
        return CloudManifest(entries: entries, latestSeq: (json["latest_seq"] as? NSNumber)?.intValue ?? 0)
    }

    func changes(since: Int, limit: Int) async throws -> CloudChangesPage {
        let (_, json) = try await cloudCall(cloudRequest(path: "/sync/changes?since=\(since)&limit=\(limit)"))
        let changes = ((json["changes"] as? [[String: Any]]) ?? []).compactMap { c -> CloudChange? in
            guard let id = (c["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return CloudChange(
                seq: (c["seq"] as? NSNumber)?.intValue ?? 0,
                id: id,
                revision: (c["revision"] as? NSNumber)?.intValue ?? 0,
                deleted: (c["kind"] as? String) == "delete",
                updatedAt: MeetingSyncDocument.date(c["updated_at"]),
                document: c["document"] as? [String: Any]
            )
        }
        return CloudChangesPage(
            changes: changes,
            nextSince: (json["next_since"] as? NSNumber)?.intValue ?? since,
            hasMore: json["has_more"] as? Bool ?? false,
            latestSeq: (json["latest_seq"] as? NSNumber)?.intValue ?? since
        )
    }

    func fetchMeeting(id: UUID) async throws -> CloudMeetingState? {
        let (status, json) = try await cloudCall(cloudRequest(path: "/sync/meetings/\(id.uuidString.lowercased())"))
        if status == 404 { return nil }
        return CloudMeetingState(json: json, fallbackID: id)
    }

    func fetchMeetings(ids: [UUID]) async throws -> [CloudMeetingState] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let (_, json) = try await cloudCall(cloudRequest(path: "/sync/meetings?ids=\(list)"))
        return ((json["meetings"] as? [[String: Any]]) ?? []).compactMap { CloudMeetingState(json: $0, fallbackID: nil) }
    }

    func putMeeting(id: UUID, baseRevision: Int, document: Data) async throws -> CloudPutResult {
        var body = Data("{\"base_revision\":\(baseRevision),\"document\":".utf8)
        body.append(document)
        body.append(Data("}".utf8))
        let (status, json) = try await cloudCall(cloudRequest(path: "/sync/meetings/\(id.uuidString.lowercased())", method: "PUT", body: body))
        switch status {
        case 200..<300:
            return .ok(revision: (json["revision"] as? NSNumber)?.intValue ?? baseRevision + 1)
        case 413:
            return .tooLarge
        case 409:
            if json["error"] as? String == "external_duplicate", let existing = CloudMeetingState(json: json, fallbackID: (json["existing_id"] as? String).flatMap(UUID.init(uuidString:))) {
                return .externalDuplicate(existing: existing)
            }
            guard let state = CloudMeetingState(json: json, fallbackID: id) else { throw CloudSyncError.server(code: "conflict_unreadable", status: 409) }
            return .conflict(state)
        default:
            throw CloudSyncError.server(code: json["error"] as? String ?? "http_\(status)", status: status)
        }
    }

    func deleteMeeting(id: UUID, baseRevision: Int) async throws -> CloudDeleteResult {
        let body = try JSONSerialization.data(withJSONObject: ["base_revision": baseRevision])
        let (status, json) = try await cloudCall(cloudRequest(path: "/sync/meetings/\(id.uuidString.lowercased())", method: "DELETE", body: body))
        switch status {
        case 200..<300:
            return .ok(revision: (json["revision"] as? NSNumber)?.intValue ?? baseRevision + 1)
        case 409:
            guard let state = CloudMeetingState(json: json, fallbackID: id) else { throw CloudSyncError.server(code: "conflict_unreadable", status: 409) }
            return .conflict(state)
        default:
            throw CloudSyncError.server(code: json["error"] as? String ?? "http_\(status)", status: status)
        }
    }

    func status() async throws -> CloudStatus {
        let (_, json) = try await cloudCall(cloudRequest(path: "/sync/status"))
        return CloudStatus(
            tier: json["tier"] as? String ?? "free",
            syncAllowed: json["sync_allowed"] as? Bool ?? false,
            bytes: (json["bytes"] as? NSNumber)?.intValue ?? 0,
            meetingCount: (json["meeting_count"] as? NSNumber)?.intValue ?? 0,
            latestSeq: (json["latest_seq"] as? NSNumber)?.intValue ?? 0,
            email: json["email"] as? String,
            connectedApps: (json["connected_apps"] as? NSNumber)?.intValue ?? 0,
            tokens: (json["tokens"] as? NSNumber)?.intValue ?? 0
        )
    }

    func deleteCloudCopy() async throws {
        _ = try await cloudCall(cloudRequest(path: "/sync/account", method: "DELETE", body: Data("{}".utf8)))
    }

    func setAccountCloud(enabled: Bool) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
        let (status, json) = try await cloudCall(cloudRequest(path: "/account/cloud", method: "PUT", body: body))
        // A backend without the route (404) must leave the choice pending, not confirm it.
        guard (200..<300).contains(status) else { throw CloudSyncError.server(code: "http_\(status)", status: status) }
        return (json["version"] as? NSNumber)?.intValue ?? 0
    }

    // MARK: Settings → Cloud management

    func listCloudTokens() async throws -> [CloudToken] {
        let (_, json) = try await cloudCall(cloudRequest(path: "/account/tokens"))
        return ((json["tokens"] as? [[String: Any]]) ?? []).compactMap(Self.token(from:))
    }

    /// Returns the token itself (shown once) plus its row.
    func createCloudToken(name: String) async throws -> (secret: String, token: CloudToken) {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, json) = try await cloudCall(cloudRequest(path: "/account/tokens", method: "POST", body: body))
        guard let secret = json["token"] as? String, let token = Self.token(from: (json["row"] as? [String: Any]) ?? json) else {
            throw CloudSyncError.server(code: "token_unreadable", status: 200)
        }
        return (secret, token)
    }

    func revokeCloudToken(id: String) async throws {
        _ = try await cloudCall(cloudRequest(path: "/account/tokens/\(id)", method: "DELETE", body: Data("{}".utf8)))
    }

    private static func token(from json: [String: Any]) -> CloudToken? {
        guard let id = json["id"] as? String else { return nil }
        return CloudToken(id: id, name: json["name"] as? String ?? "", prefix: json["prefix"] as? String ?? "", createdAt: MeetingSyncDocument.date(json["created_at"]), lastUsedAt: MeetingSyncDocument.date(json["last_used_at"]))
    }

    func cloudEmail() async throws -> (email: String?, pending: String?) {
        let (_, json) = try await cloudCall(cloudRequest(path: "/account/email"))
        return (json["email"] as? String, json["pending"] as? String)
    }

    func setCloudEmail(_ email: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        let (status, json) = try await cloudCall(cloudRequest(path: "/account/email", method: "POST", body: body))
        if status == 409 { throw CloudSyncError.server(code: json["error"] as? String ?? "email_in_use", status: 409) }
    }

    func removeCloudEmail() async throws {
        _ = try await cloudCall(cloudRequest(path: "/account/email", method: "DELETE", body: Data("{}".utf8)))
    }

    func listConnectedApps() async throws -> [CloudConnectedApp] {
        let (_, json) = try await cloudCall(cloudRequest(path: "/account/connected"))
        return ((json["connected"] as? [[String: Any]]) ?? []).compactMap { g in
            guard let id = g["id"] as? String else { return nil }
            return CloudConnectedApp(id: id, clientName: g["client_name"] as? String ?? g["clientName"] as? String ?? "App", scopes: g["scopes"] as? [String] ?? [], createdAt: MeetingSyncDocument.date(g["created_at"]), lastUsedAt: MeetingSyncDocument.date(g["last_used_at"]))
        }
    }

    func revokeConnectedApp(id: String) async throws {
        _ = try await cloudCall(cloudRequest(path: "/account/connected/\(id)", method: "DELETE", body: Data("{}".utf8)))
    }
}
