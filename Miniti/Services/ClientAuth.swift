import Foundation
import CryptoKit
import Security

// MARK: - Device-bound client authorization
//
// Replaces the shared backend key that used to ship inside the app. Each installation
// holds a P-256 key (Secure Enclave when available, Keychain otherwise) and an anonymous
// recovery key that stands in for an account. The backend issues short-lived access
// tokens bound to the key's thumbprint; every write carries an ES256 proof.
//
// Contract: ../miniti-api/docs/agents/04-api-reference.md § "Device-bound client
// authorization". Design: docs/roadmap.md P0.1. The Linux app (src-tauri/src/auth) is
// the reference implementation; the cross-language vectors live in the backend's
// test/fixtures/client-auth-vectors.json and are mirrored in ClientAuthTests.

// MARK: Primitives

enum ClientAuthCrypto {
    static let proofType = "miniti-proof+jwt"
    static let recoveryKeyVersion = "M1"
    private static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let recoveryRandomBytes = 16
    private static let recoveryChecksumBytes = 4
    private static let recoveryBodyChars = (16 + 4) * 8 / 5 // 32
    private static let recoveryChecksumDomain = Data("miniti-recovery-v1".utf8)

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func b64urlDecode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// base64url SHA-256, as used for the `ath` (access token) and `bh` (body) claims.
    static func hashB64(_ data: Data) -> String {
        b64url(sha256(data))
    }

    /// RFC 7638 thumbprint of a P-256 public JWK.
    static func jwkThumbprint(x: String, y: String) -> String {
        hashB64(Data("{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"\(x)\",\"y\":\"\(y)\"}".utf8))
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes
    }

    /// Unique request id for proofs (16 random bytes, base64url).
    static func newJTI() -> String {
        b64url(Data(randomBytes(16)))
    }

    /// Path + query of a URL, exactly as the server compares it (`htu`).
    static func requestTarget(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    // MARK: Recovery keys

    static func crockfordEncode(_ bytes: [UInt8]) -> String {
        var bits = 0
        var value: UInt64 = 0
        var out = ""
        for byte in bytes {
            value = (value << 8) | UInt64(byte)
            bits += 8
            while bits >= 5 {
                out.append(crockford[Int((value >> UInt64(bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 {
            out.append(crockford[Int((value << UInt64(5 - bits)) & 31)])
        }
        return out
    }

    static func crockfordDecode(_ text: String) -> [UInt8]? {
        var bits = 0
        var value: UInt64 = 0
        var out: [UInt8] = []
        for character in text {
            guard let index = crockford.firstIndex(of: character) else { return nil }
            value = (value << 5) | UInt64(index)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> UInt64(bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }

    private static func recoveryChecksum(_ random: [UInt8]) -> [UInt8] {
        var material = recoveryChecksumDomain
        material.append(contentsOf: random)
        return Array(sha256(material).prefix(recoveryChecksumBytes))
    }

    /// Canonical key (`M1` + 32 Crockford chars) from 16 random bytes.
    static func recoveryKey(fromRandom random: [UInt8]) -> String {
        precondition(random.count == recoveryRandomBytes)
        return recoveryKeyVersion + crockfordEncode(random + recoveryChecksum(random))
    }

    static func generateRecoveryKey() -> String {
        recoveryKey(fromRandom: randomBytes(recoveryRandomBytes))
    }

    /// Uppercase, drop separators, map `O→0` and `I/L→1`, optional `M1` prefix. No checksum check.
    static func normalizeRecoveryKey(_ input: String) -> String? {
        let stripped = String(input.uppercased().compactMap { character -> Character? in
            guard character.isASCII, character.isLetter || character.isNumber else { return nil }
            switch character {
            case "O": return "0"
            case "I", "L": return "1"
            default: return character
            }
        })
        let body: Substring
        if stripped.count == recoveryBodyChars + recoveryKeyVersion.count, stripped.hasPrefix(recoveryKeyVersion) {
            body = stripped.dropFirst(recoveryKeyVersion.count)
        } else {
            body = Substring(stripped)
        }
        guard body.count == recoveryBodyChars, body.allSatisfy({ crockford.contains($0) }) else { return nil }
        return recoveryKeyVersion + body
    }

    /// Normalize and verify the checksum. Returns the canonical key.
    static func parseRecoveryKey(_ input: String) -> String? {
        guard let canonical = normalizeRecoveryKey(input),
              let decoded = crockfordDecode(String(canonical.dropFirst(recoveryKeyVersion.count))),
              decoded.count == recoveryRandomBytes + recoveryChecksumBytes else { return nil }
        let random = Array(decoded.prefix(recoveryRandomBytes))
        let checksum = Array(decoded.suffix(recoveryChecksumBytes))
        return recoveryChecksum(random) == checksum ? canonical : nil
    }

    /// `M1-XXXX-XXXX-…` for display.
    static func formatRecoveryKey(_ canonical: String) -> String {
        let body = Array(canonical.dropFirst(min(recoveryKeyVersion.count, canonical.count)))
        var groups: [String] = [recoveryKeyVersion]
        var index = 0
        while index < body.count {
            groups.append(String(body[index..<min(index + 4, body.count)]))
            index += 4
        }
        return groups.joined(separator: "-")
    }
}

// MARK: Installation key

/// Per-installation P-256 key. The private scalar never leaves the device: it lives in the
/// Secure Enclave where the hardware has one, otherwise as a Keychain-stored software key.
struct InstallationKey {
    enum Backing {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)
    }

    struct Stored: Codable, Equatable {
        let kind: String  // "se" | "sw"
        let data: String  // base64url
    }

    let backing: Backing

    static func generate(preferSecureEnclave: Bool = true) -> InstallationKey {
        if preferSecureEnclave, SecureEnclave.isAvailable, let key = try? SecureEnclave.P256.Signing.PrivateKey() {
            return InstallationKey(backing: .secureEnclave(key))
        }
        return InstallationKey(backing: .software(P256.Signing.PrivateKey()))
    }

    init(backing: Backing) {
        self.backing = backing
    }

    init?(stored: Stored) {
        guard let data = ClientAuthCrypto.b64urlDecode(stored.data) else { return nil }
        switch stored.kind {
        case "se":
            guard let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) else { return nil }
            backing = .secureEnclave(key)
        case "sw":
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else { return nil }
            backing = .software(key)
        default:
            return nil
        }
    }

    var stored: Stored {
        switch backing {
        case .secureEnclave(let key): return Stored(kind: "se", data: ClientAuthCrypto.b64url(key.dataRepresentation))
        case .software(let key): return Stored(kind: "sw", data: ClientAuthCrypto.b64url(key.rawRepresentation))
        }
    }

    var isHardwareBacked: Bool {
        if case .secureEnclave = backing { return true }
        return false
    }

    var publicKey: P256.Signing.PublicKey {
        switch backing {
        case .secureEnclave(let key): return key.publicKey
        case .software(let key): return key.publicKey
        }
    }

    private var coordinates: (x: String, y: String) {
        let raw = publicKey.rawRepresentation // 64 bytes: X ‖ Y
        return (ClientAuthCrypto.b64url(raw.prefix(32)), ClientAuthCrypto.b64url(raw.suffix(32)))
    }

    /// Public JWK sent at enrollment.
    var publicJWK: [String: String] {
        let (x, y) = coordinates
        return ["kty": "EC", "crv": "P-256", "x": x, "y": y]
    }

    /// RFC 7638 thumbprint (the `cnf.jkt` the backend binds tokens to).
    var thumbprint: String {
        let (x, y) = coordinates
        return ClientAuthCrypto.jwkThumbprint(x: x, y: y)
    }

    /// Compact JWS, `{"alg":"ES256","typ":"miniti-proof+jwt"}`, raw `r‖s` signature.
    func signJWS(payload: [String: Any]) throws -> String {
        let header = ClientAuthCrypto.b64url(Data("{\"alg\":\"ES256\",\"typ\":\"\(ClientAuthCrypto.proofType)\"}".utf8))
        let body = ClientAuthCrypto.b64url(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let signingInput = "\(header).\(body)"
        let signature: P256.Signing.ECDSASignature
        switch backing {
        case .secureEnclave(let key): signature = try key.signature(for: Data(signingInput.utf8))
        case .software(let key): signature = try key.signature(for: Data(signingInput.utf8))
        }
        return "\(signingInput).\(ClientAuthCrypto.b64url(signature.rawRepresentation))"
    }

    /// Proof over an enrollment / token challenge.
    func challengeProof(nonce: String, purpose: String, deviceID: String, now: Int64) throws -> String {
        try signJWS(payload: [
            "purpose": purpose,
            "nonce": nonce,
            "device_id": deviceID,
            "jkt": thumbprint,
            "iat": now,
        ])
    }

    /// `X-Request-Proof` for an authenticated write. `target` is path + query.
    func requestProof(accessToken: String, method: String, target: String, body: Data, now: Int64, jti: String) throws -> String {
        try signJWS(payload: [
            "ath": ClientAuthCrypto.hashB64(Data(accessToken.utf8)),
            "htm": method.uppercased(),
            "htu": target,
            "bh": ClientAuthCrypto.hashB64(body),
            "iat": now,
            "jti": jti,
        ])
    }
}

// MARK: Credentials + storage

struct ClientAuthCredentials: Codable, Equatable {
    var installationKey: InstallationKey.Stored
    /// Canonical recovery key (`M1…`), shown only on explicit reveal.
    var recoveryKey: String
    var accountID: String
    var accessToken: String?
    var accessExpiresAt: Int64?
    var refreshToken: String?
    var deviceCap: Int?
    var enrolledAt: String
    /// "create" | "restore" | "migrate"
    var enrollmentPath: String
    /// The person confirmed they saved the recovery key (or explicitly declined the nudge).
    var recoveryKeyAcknowledged: Bool = false

    init(installationKey: InstallationKey.Stored, recoveryKey: String, accountID: String, accessToken: String?, accessExpiresAt: Int64?, refreshToken: String?, deviceCap: Int?, enrolledAt: String, enrollmentPath: String, recoveryKeyAcknowledged: Bool = false) {
        self.installationKey = installationKey
        self.recoveryKey = recoveryKey
        self.accountID = accountID
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.deviceCap = deviceCap
        self.enrolledAt = enrolledAt
        self.enrollmentPath = enrollmentPath
        self.recoveryKeyAcknowledged = recoveryKeyAcknowledged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installationKey = try c.decode(InstallationKey.Stored.self, forKey: .installationKey)
        recoveryKey = try c.decode(String.self, forKey: .recoveryKey)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID) ?? ""
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        accessExpiresAt = try c.decodeIfPresent(Int64.self, forKey: .accessExpiresAt)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        deviceCap = try c.decodeIfPresent(Int.self, forKey: .deviceCap)
        enrolledAt = try c.decodeIfPresent(String.self, forKey: .enrolledAt) ?? ""
        enrollmentPath = try c.decodeIfPresent(String.self, forKey: .enrollmentPath) ?? "create"
        // Older blobs predate the acknowledgement flag.
        recoveryKeyAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .recoveryKeyAcknowledged) ?? false
    }
}

enum ClientAuthEnrollmentPath: String {
    case create, restore, migrate
}

struct ClientAuthStatus: Equatable, Sendable {
    var isEnrolled: Bool
    var accountID: String?
    var deviceCap: Int?
    var enrolledAt: String?
    var enrollmentPath: String?
    var recoveryKeyAcknowledged: Bool
    var isHardwareBacked: Bool

    static let notEnrolled = ClientAuthStatus(isEnrolled: false, accountID: nil, deviceCap: nil, enrolledAt: nil, enrollmentPath: nil, recoveryKeyAcknowledged: false, isHardwareBacked: false)
}

struct ClientAuthDevice: Decodable, Identifiable, Equatable, Sendable {
    let installationID: String
    let platform: String?
    let appVersion: String?
    let label: String?
    let enrolledAt: String
    let lastAuthAt: String?
    let current: Bool

    var id: String { installationID }

    enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case platform
        case appVersion = "app_version"
        case label
        case enrolledAt = "enrolled_at"
        case lastAuthAt = "last_auth_at"
        case current
    }
}

struct ClientAuthDeviceList: Decodable, Sendable {
    let accountID: String
    let deviceCap: Int
    let recoveryVersion: Int?
    let devices: [ClientAuthDevice]

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case deviceCap = "device_cap"
        case recoveryVersion = "recovery_version"
        case devices
    }
}

/// Where credentials live. Keychain in the app; an in-memory store in tests.
protocol ClientAuthCredentialStore: AnyObject, Sendable {
    func load() -> ClientAuthCredentials?
    func save(_ credentials: ClientAuthCredentials) -> Bool
    func clear()
}

final class KeychainClientAuthStore: ClientAuthCredentialStore, @unchecked Sendable {
    private let service = "com.miniti.device-auth"
    private let account = "credentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() -> ClientAuthCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                // A locked or prompting keychain looks like "not enrolled" to the rest of
                // the app; the status makes that distinguishable in the debug log.
                DebugLogger.shared.log(.app, "Device auth keychain read failed: status=\(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(ClientAuthCredentials.self, from: data)
    }

    func save(_ credentials: ClientAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        // This-device-only: the installation key must never travel through iCloud Keychain.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            DebugLogger.shared.log(.app, "Device auth keychain save FAILED: status=\(status)")
        }
        return status == errSecSuccess
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

final class InMemoryClientAuthStore: ClientAuthCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClientAuthCredentials?

    init(_ value: ClientAuthCredentials? = nil) { self.value = value }

    func load() -> ClientAuthCredentials? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ credentials: ClientAuthCredentials) -> Bool { lock.lock(); defer { lock.unlock() }; value = credentials; return true }
    func clear() { lock.lock(); defer { lock.unlock() }; value = nil }
}

// MARK: Errors

enum ClientAuthError: LocalizedError, Equatable {
    case notEnrolled
    case alreadyEnrolled
    case invalidRecoveryKey
    case recoveryKeyUnknown
    case deviceAlreadyEnrolled
    case deviceCapReached(Int)
    case subscriptionConflict
    case notEligibleForMigration
    case revoked
    case unavailable
    case rateLimited
    case network(String)
    case server(code: String, status: Int)
    case storage

    var errorDescription: String? {
        switch self {
        case .notEnrolled: return "Managed mode needs an account on this device. Create or restore a recovery key in Settings → Account & Plan."
        case .alreadyEnrolled: return "This device already has an account."
        case .invalidRecoveryKey: return "That doesn't look like a recovery key. It starts with M1 and has eight groups of four characters."
        case .recoveryKeyUnknown: return "Recovery key not recognized."
        case .deviceAlreadyEnrolled: return "This device is already enrolled in another account. Sign it out first."
        case .subscriptionConflict: return "This device has its own Pro subscription and that account already has one on the same platform. Cancel one of them first."
        case .deviceCapReached(let cap): return "This account already has \(cap) devices. Remove one in Settings → Account & Plan on another device."
        case .notEligibleForMigration: return "This device is not eligible for automatic migration."
        case .revoked: return "This device was signed out of its account. Restore with your recovery key to continue."
        case .unavailable: return "Device authorization is temporarily unavailable. Try again shortly."
        case .rateLimited: return "Too many attempts. Please wait a moment."
        case .network(let message): return "Network error: \(message)"
        case .server(let code, let status): return "Server error (\(status)): \(code)"
        case .storage: return "Could not store credentials securely on this device."
        }
    }
}

// MARK: Manager

/// Owns the installation key, the recovery key, and the token lifecycle. Enrollment and
/// token grants talk to `/api/auth/*` directly (no bearer); `MinitiAPIService` asks this
/// object for a fresh access token and a request proof per authenticated call.
final class ClientAuthManager: @unchecked Sendable {
    static let shared = ClientAuthManager(store: KeychainClientAuthStore())

    /// Refresh the access token when within this many seconds of expiry.
    static let accessRefreshMargin: Int64 = 60

    private let store: ClientAuthCredentialStore
    private let lock = NSLock()
    private var credentials: ClientAuthCredentials?
    private var cachedKey: InstallationKey?
    private var refreshTask: Task<String, Error>?
    /// Server clock minus local clock, learned from `Date` response headers, so a wrong
    /// device clock does not make every proof fall outside the server's skew window.
    private var serverTimeOffset: TimeInterval = 0
    private let session: URLSession
    let baseURL: String
    let deviceIDProvider: @Sendable () -> String

    init(
        store: ClientAuthCredentialStore,
        baseURL: String = MinitiAPIService.baseURL,
        session: URLSession = .shared,
        deviceIDProvider: @escaping @Sendable () -> String = { DeviceIdentifier.getOrCreateDeviceId() }
    ) {
        self.store = store
        self.baseURL = baseURL
        self.session = session
        self.deviceIDProvider = deviceIDProvider
        self.credentials = store.load()
    }

    // MARK: State

    var isEnrolled: Bool {
        lock.lock(); defer { lock.unlock() }
        return credentials != nil
    }

    var status: ClientAuthStatus {
        lock.lock(); defer { lock.unlock() }
        guard let credentials else { return .notEnrolled }
        return ClientAuthStatus(
            isEnrolled: true,
            accountID: credentials.accountID.isEmpty ? nil : credentials.accountID,
            deviceCap: credentials.deviceCap,
            enrolledAt: credentials.enrolledAt.isEmpty ? nil : credentials.enrolledAt,
            enrollmentPath: credentials.enrollmentPath,
            recoveryKeyAcknowledged: credentials.recoveryKeyAcknowledged,
            isHardwareBacked: credentials.installationKey.kind == "se"
        )
    }

    /// Formatted recovery key for an explicit reveal.
    func revealRecoveryKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        return credentials.map { ClientAuthCrypto.formatRecoveryKey($0.recoveryKey) }
    }

    func markRecoveryKeyAcknowledged() {
        update { $0.recoveryKeyAcknowledged = true }
    }

    /// Forget local credentials (after sign out / delete, or when the server says revoked).
    func clearLocal() {
        lock.lock(); defer { lock.unlock() }
        credentials = nil
        cachedKey = nil
        store.clear()
    }

    private func installationKey() throws -> InstallationKey {
        lock.lock(); defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        guard let credentials, let key = InstallationKey(stored: credentials.installationKey) else {
            throw ClientAuthError.notEnrolled
        }
        cachedKey = key
        return key
    }

    private func persist(_ newValue: ClientAuthCredentials) throws {
        guard store.save(newValue) else { throw ClientAuthError.storage }
        lock.lock(); defer { lock.unlock() }
        credentials = newValue
        cachedKey = nil
    }

    private func update(_ change: (inout ClientAuthCredentials) -> Void) {
        lock.lock()
        guard var value = credentials else { lock.unlock(); return }
        lock.unlock()
        change(&value)
        try? persist(value)
    }

    private func now() -> Int64 {
        Int64((Date().timeIntervalSince1970 + serverTimeOffset).rounded(.down))
    }

    private func noteServerDate(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date") else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let serverDate = formatter.date(from: header) else { return }
        let offset = serverDate.timeIntervalSinceNow
        // Ignore sub-minute noise (latency); correct anything that would break the proof window.
        serverTimeOffset = abs(offset) > 30 ? offset : 0
    }

    // MARK: Unauthenticated calls

    private struct ChallengeResponse: Decodable {
        let challengeId: String
        let nonce: String
        enum CodingKeys: String, CodingKey { case challengeId = "challenge_id", nonce }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int64?
        let refreshToken: String?
        let accountId: String?
        let deviceCap: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
            case accountId = "account_id", deviceCap = "device_cap"
        }
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
        let deviceCap: Int?
        enum CodingKeys: String, CodingKey { case error, message, deviceCap = "device_cap" }
    }

    private func identityHeaders(_ request: inout URLRequest) {
        request.setValue(deviceIDProvider(), forHTTPHeaderField: "X-Device-ID")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forHTTPHeaderField: "X-App-Version")
        request.setValue(MinitiAPIService.platformHeader, forHTTPHeaderField: "X-Platform")
        request.setValue("managed", forHTTPHeaderField: "X-App-Mode")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func mapError(status: Int, data: Data) -> ClientAuthError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let code = body?.error ?? ""
        switch (status, code) {
        case (409, "device_cap_reached"): return .deviceCapReached(body?.deviceCap ?? 5)
        case (409, "subscription_conflict"): return .subscriptionConflict
        case (409, "device_already_enrolled"): return .deviceAlreadyEnrolled
        case (409, "recovery_key_in_use"): return .recoveryKeyUnknown
        case (404, "recovery_key_unknown"): return .recoveryKeyUnknown
        case (404, "device_not_eligible"): return .notEligibleForMigration
        case (400, "invalid_recovery_key"): return .invalidRecoveryKey
        case (401, "installation_revoked"), (401, "device_auth_required"): return .revoked
        case (429, _): return .rateLimited
        case (503, _): return .unavailable
        default: return .server(code: code.isEmpty ? "http_\(status)" : code, status: status)
        }
    }

    private func postPublic<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ClientAuthError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        identityHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientAuthError.network(error.localizedDescription)
        }
        noteServerDate(response)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let mapped = mapError(status: status, data: data)
            DebugLogger.shared.log(.app, "Device auth \(path) failed: status=\(status) error=\(mapped)")
            throw mapped
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientAuthError.network("could not decode \(path)")
        }
    }

    private func challenge(purpose: String) async throws -> ChallengeResponse {
        try await postPublic("/auth/challenge", body: ["device_id": deviceIDProvider(), "purpose": purpose])
    }

    private func enroll(path: String, key: InstallationKey, recoveryKey: String, label: String?) async throws -> TokenResponse {
        let challenge = try await challenge(purpose: "enroll")
        let proof = try key.challengeProof(nonce: challenge.nonce, purpose: "enroll", deviceID: deviceIDProvider(), now: now())
        var body: [String: Any] = [
            "device_id": deviceIDProvider(),
            "recovery_key": recoveryKey,
            "public_key_jwk": key.publicJWK,
            "challenge_id": challenge.challengeId,
            "proof": proof,
        ]
        if let label { body["label"] = label }
        return try await postPublic(path, body: body)
    }

    private func storeEnrollment(key: InstallationKey, recoveryKey: String, tokens: TokenResponse, path: ClientAuthEnrollmentPath, acknowledged: Bool) throws {
        try persist(ClientAuthCredentials(
            installationKey: key.stored,
            recoveryKey: recoveryKey,
            accountID: tokens.accountId ?? "",
            accessToken: tokens.accessToken,
            accessExpiresAt: now() + (tokens.expiresIn ?? 3600),
            refreshToken: tokens.refreshToken,
            deviceCap: tokens.deviceCap,
            enrolledAt: ISO8601DateFormatter().string(from: Date()),
            enrollmentPath: path.rawValue,
            recoveryKeyAcknowledged: acknowledged
        ))
    }

    /// A draft is written before any enrollment request so a lost response cannot lose the
    /// only copy of a freshly generated recovery key. A draft has no account yet.
    private func writeDraft(key: InstallationKey, recoveryKey: String, path: ClientAuthEnrollmentPath) {
        _ = store.save(ClientAuthCredentials(
            installationKey: key.stored,
            recoveryKey: recoveryKey,
            accountID: "",
            accessToken: nil,
            accessExpiresAt: nil,
            refreshToken: nil,
            deviceCap: nil,
            enrolledAt: "",
            enrollmentPath: path.rawValue
        ))
    }

    /// Resume a draft (key + recovery key generated, but the request never completed).
    private func draft() -> (InstallationKey, String)? {
        guard let stored = store.load(), stored.accountID.isEmpty, stored.accessToken == nil,
              let key = InstallationKey(stored: stored.installationKey) else { return nil }
        return (key, stored.recoveryKey)
    }

    // MARK: Enrollment

    /// Create a new anonymous account. Returns the formatted recovery key.
    @discardableResult
    func createAccount(label: String? = nil, acknowledged: Bool = false) async throws -> String {
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let (key, recoveryKey) = draft() ?? (InstallationKey.generate(), ClientAuthCrypto.generateRecoveryKey())
        writeDraft(key: key, recoveryKey: recoveryKey, path: .create)
        let tokens = try await enroll(path: "/auth/account/create", key: key, recoveryKey: recoveryKey, label: label)
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .create, acknowledged: acknowledged)
        DebugLogger.shared.log(.app, "Device auth: account created")
        return ClientAuthCrypto.formatRecoveryKey(recoveryKey)
    }

    /// Attach this installation to an existing account with its recovery key.
    func restoreAccount(recoveryKeyInput: String, label: String? = nil) async throws {
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        guard let recoveryKey = ClientAuthCrypto.parseRecoveryKey(recoveryKeyInput) else {
            throw ClientAuthError.invalidRecoveryKey
        }
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: recoveryKey, label: label)
        // Restoring means the person already holds the key; no nudge needed.
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .restore, acknowledged: true)
        DebugLogger.shared.log(.app, "Device auth: account restored")
    }

    /// Silent one-time migration for an installation whose device record predates the
    /// backend cutoff. Generates the recovery key locally first; the server binds the
    /// existing device record to a new anonymous account.
    func migrateLegacyDevice(label: String? = nil) async throws {
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let (key, recoveryKey) = draft() ?? (InstallationKey.generate(), ClientAuthCrypto.generateRecoveryKey())
        writeDraft(key: key, recoveryKey: recoveryKey, path: .migrate)
        let tokens: TokenResponse
        do {
            tokens = try await enroll(path: "/auth/migrate", key: key, recoveryKey: recoveryKey, label: label)
        } catch ClientAuthError.server(_, let status) where status == 404 {
            // A backend without the migration route at all: the device record (usage, tier,
            // subscription) is keyed by the same UUID either way, so creating an account
            // loses nothing. Treat it like "not eligible" and let the caller fall back.
            throw ClientAuthError.notEligibleForMigration
        }
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .migrate, acknowledged: false)
        DebugLogger.shared.log(.app, "Device auth: legacy device migrated")
    }

    /// Remove a draft that never completed (so a later create starts fresh).
    func discardDraft() {
        if draft() != nil { store.clear() }
    }

    // MARK: Tokens

    private func cachedToken() -> (String, Int64)? {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, let token = credentials.accessToken, let exp = credentials.accessExpiresAt else { return nil }
        return (token, exp)
    }

    /// A valid access token, refreshing when within the margin of expiry.
    func accessToken() async throws -> String {
        guard isEnrolled else { throw ClientAuthError.notEnrolled }
        if let (token, exp) = cachedToken(), exp - now() > Self.accessRefreshMargin {
            return token
        }
        return try await refresh(force: false)
    }

    /// Discard the cached token and obtain a new one (after a 401).
    func forceRefresh() async throws -> String {
        try await refresh(force: true)
    }

    private func refresh(force: Bool) async throws -> String {
        try await sharedRefreshTask(force: force).value
    }

    /// Collapse concurrent refreshes into one grant. Synchronous so the lock never spans a
    /// suspension point.
    private func sharedRefreshTask(force: Bool) -> Task<String, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = refreshTask { return existing }
        let task = Task { [self] in
            defer { clearRefreshTask() }
            return try await performRefresh(force: force)
        }
        refreshTask = task
        return task
    }

    private func clearRefreshTask() {
        lock.lock()
        refreshTask = nil
        lock.unlock()
    }

    private func performRefresh(force: Bool) async throws -> String {
        if !force, let (token, exp) = cachedToken(), exp - now() > Self.accessRefreshMargin {
            return token
        }
        let refreshToken: String? = {
            lock.lock(); defer { lock.unlock() }
            return credentials?.refreshToken
        }()
        do {
            let tokens: TokenResponse
            if let refreshToken {
                do {
                    tokens = try await grantRefresh(refreshToken)
                } catch ClientAuthError.server(_, let status) where status == 401 {
                    tokens = try await grantChallenge()
                }
            } else {
                tokens = try await grantChallenge()
            }
            update { credentials in
                credentials.accessToken = tokens.accessToken
                credentials.accessExpiresAt = now() + (tokens.expiresIn ?? 3600)
                if let refresh = tokens.refreshToken { credentials.refreshToken = refresh }
                if let cap = tokens.deviceCap { credentials.deviceCap = cap }
                if let account = tokens.accountId { credentials.accountID = account }
            }
            return tokens.accessToken
        } catch ClientAuthError.revoked {
            DebugLogger.shared.log(.app, "Device auth: installation revoked by the server; clearing local credentials")
            clearLocal()
            throw ClientAuthError.revoked
        }
    }

    private func grantRefresh(_ refreshToken: String) async throws -> TokenResponse {
        try await postPublic("/auth/token", body: ["grant_type": "refresh", "device_id": deviceIDProvider(), "refresh_token": refreshToken])
    }

    private func grantChallenge() async throws -> TokenResponse {
        let key = try installationKey()
        let challenge = try await challenge(purpose: "token")
        let proof = try key.challengeProof(nonce: challenge.nonce, purpose: "token", deviceID: deviceIDProvider(), now: now())
        return try await postPublic("/auth/token", body: [
            "grant_type": "challenge", "device_id": deviceIDProvider(),
            "challenge_id": challenge.challengeId, "proof": proof,
        ])
    }

    /// `X-Request-Proof` for an authenticated write.
    func requestProof(accessToken: String, method: String, url: URL, body: Data) throws -> String {
        let key = try installationKey()
        return try key.requestProof(
            accessToken: accessToken,
            method: method,
            target: ClientAuthCrypto.requestTarget(url),
            body: body,
            now: now(),
            jti: ClientAuthCrypto.newJTI()
        )
    }

    /// Attach bearer + proof to a request. Throws `notEnrolled` when there is no account.
    func authorize(_ request: inout URLRequest) async throws {
        let token = try await accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let method = request.httpMethod ?? "GET"
        if method != "GET", method != "HEAD", let url = request.url {
            let proof = try requestProof(accessToken: token, method: method, url: url, body: request.httpBody ?? Data())
            request.setValue(proof, forHTTPHeaderField: "X-Request-Proof")
        }
    }

    // MARK: Account management (authenticated)

    private func authorizedJSON<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ClientAuthError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        identityHeaders(&request)
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        try await authorize(&request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientAuthError.network(error.localizedDescription)
        }
        noteServerDate(response)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let mapped = mapError(status: status, data: data)
            if case .revoked = mapped { clearLocal() }
            throw mapped
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Empty: Decodable {}

    func listDevices() async throws -> ClientAuthDeviceList {
        try await authorizedJSON("GET", "/auth/account/devices")
    }

    /// Remove any device on the account. Removing the current one clears local credentials.
    func removeDevice(installationID: String) async throws {
        let _: Empty = try await authorizedJSON("DELETE", "/auth/account/devices/\(installationID)")
        if installationID.lowercased() == deviceIDProvider().lowercased() { clearLocal() }
    }

    /// Generate a new recovery key and ask the server to accept it. Returns the formatted key.
    func rotateRecoveryKey() async throws -> String {
        let newKey = ClientAuthCrypto.generateRecoveryKey()
        let _: Empty = try await authorizedJSON("POST", "/auth/account/recovery-key/rotate", body: ["new_recovery_key": newKey])
        update { $0.recoveryKey = newKey; $0.recoveryKeyAcknowledged = false }
        return ClientAuthCrypto.formatRecoveryKey(newKey)
    }

    /// Move this enrolled installation to the account that owns `recoveryKeyInput`
    /// (`POST /api/auth/account/attach`). The device keeps its id, usage, integrations,
    /// and local meetings; only the account membership changes, and the server issues
    /// fresh tokens because access tokens are bound to the account. Returns `true` when
    /// the device actually moved, `false` when it was already on that account.
    func attachToAccount(recoveryKeyInput: String) async throws -> Bool {
        guard isEnrolled else { throw ClientAuthError.notEnrolled }
        guard let recoveryKey = ClientAuthCrypto.parseRecoveryKey(recoveryKeyInput) else {
            throw ClientAuthError.invalidRecoveryKey
        }
        let response: AttachResponse = try await authorizedJSON("POST", "/auth/account/attach", body: ["recovery_key": recoveryKey])
        update { credentials in
            credentials.recoveryKey = recoveryKey
            credentials.accessToken = response.accessToken
            credentials.accessExpiresAt = now() + (response.expiresIn ?? 3600)
            if let refresh = response.refreshToken { credentials.refreshToken = refresh }
            if let cap = response.deviceCap { credentials.deviceCap = cap }
            if let account = response.accountId { credentials.accountID = account }
            // The person typed this key from their other device; no save-your-key nudge.
            credentials.recoveryKeyAcknowledged = true
        }
        DebugLogger.shared.log(.app, "Device auth: installation \(response.moved == true ? "moved to another account" : "already on that account")")
        return response.moved ?? true
    }

    private struct AttachResponse: Decodable {
        let accessToken: String
        let expiresIn: Int64?
        let refreshToken: String?
        let accountId: String?
        let deviceCap: Int?
        let moved: Bool?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
            case accountId = "account_id", deviceCap = "device_cap", moved
        }
    }

    /// Sign this installation out server-side, then forget it locally.
    func signOut() async throws {
        do {
            let _: Empty = try await authorizedJSON("POST", "/auth/revoke", body: [:])
        } catch ClientAuthError.revoked {
            // Already gone server-side; local clear below is all that matters.
        }
        clearLocal()
    }

    /// Delete the anonymous account (revokes every device). Does not cancel subscriptions.
    func deleteAccount() async throws {
        let _: Empty = try await authorizedJSON("DELETE", "/auth/account")
        clearLocal()
    }
}
