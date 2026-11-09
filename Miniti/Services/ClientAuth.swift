import Foundation
import CryptoKit
import CryptoTokenKit
import Security

// MARK: - Device-bound client authorization
//
// Replaces the shared backend key that used to ship inside the app. Each installation
// holds a P-256 key (Secure Enclave when available, Keychain otherwise) and an anonymous
// recovery key that stands in for an account. The backend issues short-lived access
// tokens bound to the key's thumbprint; every write carries an ES256 proof.
//
// Contract: ../miniti-api/docs/agents/04-api-reference.md § "Device-bound client
// authorization". Design: docs/reference/accounts.md. The Linux app (src-tauri/src/auth) is
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
    /// Test seam: a key that loads but whose every signature throws this error, the shape
    /// of a Secure Enclave key copied to another machine. Never set in production.
    let signingFault: Error?

    enum LoadError: Error, Equatable {
        case corruptData
        case unknownKind(String)
    }

    static func generate(preferSecureEnclave: Bool = true) -> InstallationKey {
        #if !MINITI_TEST_HOST
        if preferSecureEnclave, SecureEnclave.isAvailable, let key = try? SecureEnclave.P256.Signing.PrivateKey() {
            return InstallationKey(backing: .secureEnclave(key))
        }
        #endif
        return InstallationKey(backing: .software(P256.Signing.PrivateKey()))
    }

    init(backing: Backing, signingFault: Error? = nil) {
        self.backing = backing
        self.signingFault = signingFault
    }

    init?(stored: Stored) {
        guard case .success(let key) = Self.load(stored: stored) else { return nil }
        self = key
    }

    /// Load a stored key and keep the underlying error, so the caller can tell a key that
    /// belongs to another machine from one that cannot be used right now (A2d).
    static func load(stored: Stored) -> Result<InstallationKey, Error> {
        guard let data = ClientAuthCrypto.b64urlDecode(stored.data) else { return .failure(LoadError.corruptData) }
        switch stored.kind {
        case "se":
            do { return .success(InstallationKey(backing: .secureEnclave(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)))) }
            catch { return .failure(error) }
        case "sw":
            do { return .success(InstallationKey(backing: .software(try P256.Signing.PrivateKey(rawRepresentation: data)))) }
            catch { return .failure(error) }
        default:
            return .failure(LoadError.unknownKind(stored.kind))
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
        if let signingFault { throw signingFault }
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

/// What a failure to load or use the stored installation key means (enrollment-identity-plan A2d).
/// Only the allow-list below replaces a credential; everything else keeps it and retries.
enum InstallationKeyFailure: Equatable {
    /// The key belongs to another machine (a Secure Enclave blob moved by Migration Assistant or
    /// a backup). The stored recovery key, when there is one, can replace it.
    case unusable(reason: String)
    /// Locked, denied, cancelled, or a code we have not seen. Nothing is replaced.
    case temporary(reason: String)

    /// Signing errors that establish a foreign key, each with the date and reason it was added.
    /// Matched on domain and code, never on the message.
    static let unusableSigningCodes: [(domain: String, code: Int, added: String)] = [
        // 2026-10-26: Ian's work Mac after Migration Assistant. The SDK names this
        // TKErrorCodeInvalidatedDeviceKey (available from macOS 27 and iOS 27); an older
        // system may surface another code, which stays temporary until it is seen and added.
        (TKErrorDomain, -10, "2026-10-26"),
    ]

    /// Loading is classified as conservatively as signing. Only bytes that cannot be a key
    /// (`LoadError`) are unusable. A Secure Enclave refusal at load is kept temporary until
    /// its code has been observed on a real migrated machine and added to the list: an
    /// unknown load error must never replace a credential on its own (review 2026-10-26).
    static func classify(loadError error: Error) -> InstallationKeyFailure {
        if error is InstallationKey.LoadError { return .unusable(reason: "load:\(describe(error))") }
        let ns = error as NSError
        if unusableLoadCodes.contains(where: { $0.domain == ns.domain && $0.code == ns.code }) {
            return .unusable(reason: "load:\(describe(error))")
        }
        return .temporary(reason: "load:\(describe(error))")
    }

    /// Load errors that establish a foreign key. Empty until the A5 device QA records one.
    static let unusableLoadCodes: [(domain: String, code: Int, added: String)] = []

    static func classify(signingError error: Error) -> InstallationKeyFailure {
        let ns = error as NSError
        if unusableSigningCodes.contains(where: { $0.domain == ns.domain && $0.code == ns.code }) {
            return .unusable(reason: "sign:\(describe(error))")
        }
        return .temporary(reason: "sign:\(describe(error))")
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain):\(ns.code)"
    }
}

/// Stored as JSON in the Keychain. **Format rule (enrollment-identity-plan A2b):** a blob written
/// by any shipped version must keep decoding. Every new field is optional with a default in
/// `init(from:)`, and that is a coding habit, not the guarantee: the guarantee is
/// `ClientAuthTests` `CredentialFixtures`, one captured blob per shipped format, never edited,
/// each decoded and asserted field by field. A format change adds a fixture and a test that
/// the old fixtures still decode and migrate to the expected values.
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
    var absenceConfirmed: Bool?

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

    /// The device id the access token was issued to (its `sub`), when there is one. This is the
    /// identity the server binds the installation key to, so it outranks a Keychain device id
    /// that disagrees with it (see `ClientAuthManager.reconcileDeviceIdentity`).
    var tokenDeviceID: String? {
        guard let accessToken else { return nil }
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3,
              let payload = ClientAuthCrypto.b64urlDecode(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = claims["sub"] as? String, UUID(uuidString: sub) != nil else { return nil }
        return sub
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
        absenceConfirmed = try c.decodeIfPresent(Bool.self, forKey: .absenceConfirmed)
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
    /// The credential is present but its key cannot sign here and no recovery key can replace it
    /// (A2d). `isEnrolled` is false; `accountID` still names the account for the copy.
    var keyUnusable: Bool = false
    /// A key failure happened (load or signing, outside the permanent allow-list) and nothing
    /// has signed since: signed actions are disabled with "temporarily unavailable" rather
    /// than hidden, and nothing says the key is broken (B6a).
    var keyTemporarilyUnavailable: Bool = false
    /// A permanent key failure is active (allow-listed or malformed key), whether or not a
    /// recovery key can repair it. The account section shows Sign in again and hides signed
    /// actions on this alone (review 2026-10-27).
    var keyPermanentlyUnavailable: Bool = false

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
/// What a `load()` could not deliver. Absence (`.missing`) is not a diagnostic: it is the
/// normal first-use state. These two are the cases that today look like absence to the
/// rest of the app and must not (docs/archive/enrollment-identity-plan.md, fragilities 1 and 2).
enum ClientAuthStoreDiagnostic: Equatable, Sendable {
    /// The Keychain answered something other than "found" or "not found" (locked, denied, prompting).
    case unreadable(status: OSStatus)
    /// An item was found but its bytes do not decode as `ClientAuthCredentials`.
    case undecodable(bytes: Int)
}

enum ClientAuthCredentialRead {
    case found(ClientAuthCredentials), missing, unreadable(ClientAuthStoreDiagnostic)
    var value: ClientAuthCredentials? { if case .found(let value) = self { return value }; return nil }
}

protocol ClientAuthCredentialStore: AnyObject, Sendable {
    func load() -> ClientAuthCredentials?
    func loadResult() -> ClientAuthCredentialRead
    func retryLoadResult() -> ClientAuthCredentialRead
    func save(_ credentials: ClientAuthCredentials) -> Bool
    func clear()
    /// What the most recent `load()` could not deliver, or nil when it found an item or
    /// found nothing. Read right after `load()`; stores that cannot fail return nil.
    var lastLoadDiagnostic: ClientAuthStoreDiagnostic? { get }
}

extension ClientAuthCredentialStore {
    func retryLoadResult() -> ClientAuthCredentialRead { loadResult() }
    func loadResult() -> ClientAuthCredentialRead {
        if let value = load() { return .found(value) }
        if let diagnostic = lastLoadDiagnostic { return .unreadable(diagnostic) }
        return .missing
    }
    var lastLoadDiagnostic: ClientAuthStoreDiagnostic? { nil }
}

/// The managed credential in one `KeychainSlot` (`DeviceIdentifier.swift`): the data protection
/// keychain where this build can use it, the login keychain otherwise, updated in place and
/// never deleted before its replacement is written. This-device-only: the installation key
/// must never travel through iCloud Keychain.
final class KeychainClientAuthStore: ClientAuthCredentialStore, @unchecked Sendable {
    private let slot: KeychainSlot
    private let diagnosticLock = NSLock()
    private var diagnostic: ClientAuthStoreDiagnostic?

    var lastLoadDiagnostic: ClientAuthStoreDiagnostic? {
        diagnosticLock.lock(); defer { diagnosticLock.unlock() }
        return diagnostic
    }

    private func setDiagnostic(_ value: ClientAuthStoreDiagnostic?) {
        diagnosticLock.lock(); defer { diagnosticLock.unlock() }
        diagnostic = value
    }

    init(backend: KeychainBackend = DefaultKeychainBackend.make) {
        slot = KeychainSlot(
            service: "com.miniti.device-auth",
            account: "credentials",
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            synchronizable: false,
            backend: backend
        )
    }

    func load() -> ClientAuthCredentials? { load(allowInteraction: false) }

    func retryLoadResult() -> ClientAuthCredentialRead {
        if let value = load(allowInteraction: true) { return .found(value) }
        if let diagnostic = lastLoadDiagnostic { return .unreadable(diagnostic) }
        return .missing
    }

    private func load(allowInteraction: Bool) -> ClientAuthCredentials? {
        switch slot.read(allowInteraction: allowInteraction) {
        case .found(let data):
            if let decoded = try? JSONDecoder().decode(ClientAuthCredentials.self, from: data) {
                setDiagnostic(nil)
                return decoded
            }
            // Found but not ours to read: a format we no longer decode would turn every
            // upgraded user into "not enrolled". The manager reports it; A3 will stop
            // treating it as absence.
            DebugLogger.shared.log(.app, "Device auth keychain item does not decode (\(data.count) bytes)")
            setDiagnostic(.undecodable(bytes: data.count))
            return nil
        case .missing:
            setDiagnostic(nil)
            return nil
        case .unreadable(let status):
            // A locked or prompting keychain looks like "not enrolled" to the rest of
            // the app; the status makes that distinguishable in the debug log and, through
            // the manager's events, in admin client events.
            DebugLogger.shared.log(.app, "Device auth keychain read failed: status=\(status)")
            setDiagnostic(.unreadable(status: status))
            return nil
        }
    }

    func save(_ credentials: ClientAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let saved = slot.write(data)
        if !saved { DebugLogger.shared.log(.app, "Device auth keychain save FAILED") }
        return saved
    }

    func clear() {
        slot.delete()
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
    /// The stored key cannot sign on this machine and nothing can replace it automatically.
    case keyUnusable
    /// The stored key could not be used right now (locked, denied, unknown); nothing replaced.
    case keyUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notEnrolled: return "Managed mode needs an account on this device. Create or restore a recovery key in Settings → Account."
        case .alreadyEnrolled: return "This device already has an account."
        case .invalidRecoveryKey: return "That doesn't look like a recovery key. It starts with M1 and has eight groups of four characters."
        case .recoveryKeyUnknown: return "Recovery key not recognized."
        case .deviceAlreadyEnrolled: return "This device is already enrolled in another account. Sign it out first."
        case .subscriptionConflict: return "This device has its own Pro subscription and that account already has one on the same platform. Cancel one of them first."
        case .deviceCapReached(let cap): return "This account already has \(cap) devices. Remove one in Settings → Account on another device."
        case .notEligibleForMigration: return "This device is not eligible for automatic migration."
        case .revoked: return "This device was signed out of its account. Restore with your recovery key to continue."
        case .unavailable: return "Device authorization is temporarily unavailable. Try again shortly."
        case .rateLimited: return "Too many attempts. Please wait a moment."
        case .network(let message): return "Network error: \(message)"
        case .server(let code, let status): return "Server error (\(status)): \(code)"
        case .storage: return "miniti could not save its sign-in on this device. Try again."
        case .keyUnusable:
            #if os(macOS)
            return "This Mac can no longer sign in with its saved key. Sign in by email or with your recovery key to keep this Mac on its account."
            #else
            return "This device can no longer sign in with its saved key. Sign in by email or with your recovery key to keep it on its account."
            #endif
        case .keyUnavailable: return "miniti could not use its saved sign-in right now. Try again, or sign in again from Settings, Account."
        }
    }
}

// MARK: Manager

/// Owns the installation key, the recovery key, and the token lifecycle. Enrollment and
/// One thing the manager wants counted in admin client events (opt-in diagnostics, same
/// queue as every other event). Bounded fields only: status codes, paths, 8-character id
/// prefixes; never a device id, key or token (roadmap P1.4; enrollment-identity-plan A1).
struct ClientAuthEvent: Equatable, Sendable {
    let name: String
    let level: MinitiAPIService.ClientEventPayload.EventLevel
    let details: [String: String]
}

/// token grants talk to `/api/auth/*` directly (no bearer); `MinitiAPIService` asks this
/// object for a fresh access token and a request proof per authenticated call.
final class ClientAuthManager: @unchecked Sendable {
    static let shared = ClientAuthManager(
        store: KeychainClientAuthStore(),
        deviceLabelProvider: { AppState.managedDeviceLabel },
        deviceIDRotator: { DeviceIdentifier.rotate() },
        deviceIDAdopter: { DeviceIdentifier.adopt($0, reason: "credentials") },
        deviceIDIsNewThisLaunch: { DeviceIdentifier.createdThisLaunch }
    )

    typealias EventSink = @Sendable (ClientAuthEvent) -> Void
    /// Events raised before `AppState` exists (the credential is read in `init`) wait here
    /// and are replayed, in order, when the sink is attached.
    static let pendingEventLimit = 16
    private var eventSink: EventSink?
    private var pendingEvents: [ClientAuthEvent] = []
    private var emittedEventKeys: Set<String> = []
    /// Why `clearLocal` last ran in this process, for the silent re-create count.
    private var localClearReason: String?
    /// Bumped by every local clear and every stored enrolment. A credential replacement that
    /// started under an older epoch (a key repair, a reauthentication) must not write back
    /// what the person has since signed out of (review 2026-10-27).
    private var credentialEpoch = 0

    /// Refresh the access token when within this many seconds of expiry.
    static let accessRefreshMargin: Int64 = 60

    private let store: ClientAuthCredentialStore
    private let lock = NSLock()
    private var credentials: ClientAuthCredentials?
    private var unreadableCredential: ClientAuthStoreDiagnostic?
    private var retryAfterDate: Date?
    var enrollmentRetryAfter: Date? { lock.lock(); defer { lock.unlock() }; return retryAfterDate }
    private var cachedKey: InstallationKey?
    private var refreshTask: Task<String, Error>?
    /// One repair at a time; concurrent callers await it (A2d).
    private var repairTask: Task<Int, Error>?
    /// The generation the in-flight repair replaces.
    private var repairGeneration = 0
    /// Set when the stored key is unusable here and the credential holds no recovery key:
    /// the person must sign in again; nothing is created or rotated meanwhile.
    private var keyUnusableWithoutRecovery = false
    private var temporaryKeyFailureSeenThisLaunch = false
    /// A key failure (either kind) happened and no signature has succeeded since: the stored
    /// key must not be relied on, and "Sign in again" takes the fresh-key route.
    private var keyFailureActive = false
    /// The active failure was classified permanent (allow-listed or malformed key). The status
    /// reports a temporary failure only when this is false (F3).
    private var keyFailurePermanent = false
    static let keyUnavailableLaunchesKey = "clientAuth.keyUnavailableLaunches"
    /// Server clock minus local clock, learned from `Date` response headers, so a wrong
    /// device clock does not make every proof fall outside the server's skew window.
    private var serverTimeOffset: TimeInterval = 0
    private let session: URLSession
    let baseURL: String
    let deviceIDProvider: @Sendable () -> String
    /// Label sent when the installation is re-bound to its account (see `rebindInstallation`),
    /// so the server keeps a readable device name instead of clearing it.
    let deviceLabelProvider: @Sendable () -> String?
    /// Mints and persists a new device id (see `createAccount`). `nil` means the install
    /// cannot change identity; the conflict is then surfaced instead.
    let deviceIDRotator: (@Sendable () -> String)?
    /// Makes a given id this install's device identity (see `reconcileDeviceIdentity`). Returns
    /// false when the identity cannot be changed right now. `nil` means never reconcile.
    let deviceIDAdopter: (@Sendable (String) -> Bool)?
    /// True when the device id was minted in this process (a genuinely new install). An
    /// enrollment that starts with an older id and no credential is a device that used to
    /// be someone, counted as `client_auth_silent_recreate`.
    let deviceIDIsNewThisLaunch: @Sendable () -> Bool
    /// Loads the stored key; the default keeps the underlying error for classification.
    let keyLoader: @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error>
    /// Where the temporary-failure launch count lives (prominence only, never classification).
    private let defaults: UserDefaults

    init(
        store: ClientAuthCredentialStore,
        baseURL: String = MinitiAPIService.baseURL,
        session: URLSession = .shared,
        deviceIDProvider: @escaping @Sendable () -> String = { DeviceIdentifier.getOrCreateDeviceId() },
        deviceLabelProvider: @escaping @Sendable () -> String? = { nil },
        deviceIDRotator: (@Sendable () -> String)? = nil,
        deviceIDAdopter: (@Sendable (String) -> Bool)? = nil,
        // Defaults to "new": a caller that does not track the id (tests, tools) must not report
        // a re-create it cannot know about. The shared instance passes the real flag.
        deviceIDIsNewThisLaunch: @escaping @Sendable () -> Bool = { true },
        keyLoader: @escaping @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error> = { InstallationKey.load(stored: $0) },
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.baseURL = baseURL
        self.session = session
        self.deviceIDProvider = deviceIDProvider
        self.deviceLabelProvider = deviceLabelProvider
        self.deviceIDRotator = deviceIDRotator
        self.deviceIDAdopter = deviceIDAdopter
        self.deviceIDIsNewThisLaunch = deviceIDIsNewThisLaunch
        self.keyLoader = keyLoader
        self.defaults = defaults
        let read = store.loadResult()
        self.credentials = read.value
        if case .unreadable(let reason) = read { unreadableCredential = reason }
        if case .missing = read, defaults.string(forKey: "managedAccessChoice") == nil,
           deviceIDIsNewThisLaunch() || (!defaults.bool(forKey: "hasCompletedOnboarding") && !defaults.bool(forKey: "hasAcceptedTerms")) {
            defaults.set("awaitingChoice", forKey: "managedAccessChoice")
        }
        if self.credentials != nil { DiagnosticTimeline.shared.record(.credentialLoaded) }
        else if store.lastLoadDiagnostic == nil { DiagnosticTimeline.shared.record(.credentialMissing) }
        reportLoadDiagnostic(phase: "launch")
        reconcileDeviceIdentity()
    }

    // MARK: Events

    /// Attach the diagnostics sink and replay anything raised before it existed. Later
    /// events go straight through. Attaching again replaces the sink; nothing is replayed twice.
    func attachEventSink(_ sink: @escaping EventSink) {
        lock.lock()
        eventSink = sink
        let replay = pendingEvents
        pendingEvents.removeAll()
        lock.unlock()
        for event in replay { sink(event) }
    }

    /// Raise an event. Deduplicated per process on name plus details, so a retry loop does
    /// not flood the queue. The sink is never called while `lock` is held.
    private func emit(_ name: String, level: MinitiAPIService.ClientEventPayload.EventLevel, details: [String: String] = [:]) {
        if let code = DiagnosticTimeline.Code(rawValue: name) { DiagnosticTimeline.shared.record(code, fields: details) }
        let event = ClientAuthEvent(name: name, level: level, details: details)
        let key = name + "|" + details.keys.sorted().map { "\($0)=\(details[$0] ?? "")" }.joined(separator: ",")
        lock.lock()
        if emittedEventKeys.contains(key) { lock.unlock(); return }
        emittedEventKeys.insert(key)
        let sink = eventSink
        if sink == nil {
            if pendingEvents.count >= Self.pendingEventLimit { pendingEvents.removeFirst() }
            pendingEvents.append(event)
        }
        lock.unlock()
        sink?(event)
    }

    /// Turn what the store could not deliver into an event. `phase` says when the read ran.
    private func reportLoadDiagnostic(phase: String) {
        switch store.lastLoadDiagnostic {
        case .unreadable(let status):
            emit("client_auth_credential_unreadable", level: .warning, details: ["status": String(status), "phase": phase])
        case .undecodable(let bytes):
            emit("client_auth_credential_undecodable", level: .error, details: ["bytes": String(bytes), "phase": phase])
        case nil:
            break
        }
    }

    /// An enrollment is starting on a device id that existed before this launch, with no
    /// credential: a sign-out, a server revoke, a wiped credential, or a legacy or BYOK
    /// install enrolling for the first time. `after` says which when the manager knows.
    private func reportEnrollmentStart(path: String) {
        guard !deviceIDIsNewThisLaunch() else { return }
        let reason: String = { lock.lock(); defer { lock.unlock() }; return localClearReason ?? "unknown" }()
        emit("client_auth_silent_recreate", level: .warning, details: ["after": reason, "path": path])
    }

    /// The credential and the device id are two Keychain items, and 3.2.1 on macOS lost the
    /// second while keeping the first: the app then minted a new id, and the server answered
    /// every call with `device_mismatch` because the token names the old one. The token's
    /// device id is the one the server binds this installation key to, so when the two
    /// disagree the id is restored from the token before any request goes out.
    private func reconcileDeviceIdentity() {
        guard let deviceIDAdopter else { return }
        let stored: ClientAuthCredentials? = { lock.lock(); defer { lock.unlock() }; return credentials }()
        guard let stored, !Self.isDraft(stored), let tokenDevice = stored.tokenDeviceID else { return }
        let current = deviceIDProvider()
        guard tokenDevice.caseInsensitiveCompare(current) != .orderedSame else { return }
        if deviceIDAdopter(tokenDevice) {
            DebugLogger.shared.log(.app, "Device auth: device id restored from the stored access token (was \(current.prefix(8))...)")
        } else {
            DebugLogger.shared.log(.app, "Device auth: device id differs from the stored access token; keychain unreadable, left as is")
        }
    }

    // MARK: State

    /// True only for credentials the server has confirmed. A draft (key and recovery key
    /// written before the enrollment request, no account yet) is not an enrollment: treating
    /// it as one made every token grant sign with a key the server never saw, and the device
    /// answered `invalid_proof` until it was wiped (2026-10-10).
    var isEnrolled: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let credentials else { return false }
        return !Self.isDraft(credentials) && !keyUnusableWithoutRecovery
    }

    enum CredentialState: Equatable {
        case notEnrolled, draft, enrolled
        /// Credential present, key unusable on this machine, no recovery key to replace it.
        case keyUnusable
        case unreadable(ClientAuthStoreDiagnostic)
    }

    var credentialState: CredentialState {
        lock.lock(); defer { lock.unlock() }
        if let unreadableCredential { return .unreadable(unreadableCredential) }
        guard let credentials else { return .notEnrolled }
        if Self.isDraft(credentials) { return .draft }
        return keyUnusableWithoutRecovery ? .keyUnusable : .enrolled
    }

    private var credentialRereadInFlight = false

    /// Read outside the state lock: Security may wait for the keychain service.
    func rereadUnreadableCredential(allowInteraction: Bool = false) {
        lock.lock()
        guard unreadableCredential != nil, !credentialRereadInFlight else { lock.unlock(); return }
        credentialRereadInFlight = true
        let generation = credentialEpoch
        lock.unlock()
        let read = allowInteraction ? store.retryLoadResult() : store.loadResult()
        lock.lock()
        credentialRereadInFlight = false
        guard credentialEpoch == generation, unreadableCredential != nil else { lock.unlock(); return }
        credentials = read.value
        if case .unreadable(let reason) = read { unreadableCredential = reason }
        else {
            unreadableCredential = nil; cachedKey = nil
            if case .missing = read { defaults.set("awaitingChoice", forKey: "managedAccessChoice") }
        }
        lock.unlock()
        reconcileDeviceIdentity()
    }

    var accessChoiceRequired: Bool {
        !isEnrolled && ["awaitingChoice", "signout", "revoke", "removed", "delete", "deviceAlreadyEnrolled"].contains(defaults.string(forKey: "managedAccessChoice") ?? "")
    }
    var accessChoiceReason: String? { defaults.string(forKey: "managedAccessChoice") }
    var enrollmentDeviceID: String { deviceIDProvider() }
    var enrollmentDefaults: UserDefaults { defaults }
    func chooseAnonymousAccess() { defaults.set("continue", forKey: "managedAccessChoice") }
    func requireAccessChoice(reason: String = "awaitingChoice") { defaults.set(reason, forKey: "managedAccessChoice") }
    var canResetUnreadableCredentialByChoice: Bool {
        if accessChoiceReason == "deviceAlreadyEnrolled" { return true }
        if case .unreadable(.undecodable) = credentialState { return true }
        return false
    }
    func resetUnreadableCredentialByChoice() {
        guard canResetUnreadableCredentialByChoice else { return }
        clearLocal(reason: "signout")
        defaults.set("continueAfterReset", forKey: "managedAccessChoice")
    }
    var unreadableCredentialMessage: String? {
        guard case .unreadable(let reason) = credentialState else { return nil }
        if case .undecodable = reason {
            return "miniti could not read its saved sign-in. Restore with your recovery key or email in Settings, Account, or set this device up again."
        }
        #if os(macOS)
        return "miniti's saved sign-in is in a locked keychain. Unlock it and try again."
        #else
        return "miniti could not read its saved sign-in. Unlock your device and try again."
        #endif
    }

    /// True when the stored key cannot load here and the stored recovery key can replace it
    /// (the coordinator repairs eagerly so the person never sees the failure).
    var needsKeyRepair: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials), !credentials.recoveryKey.isEmpty, cachedKey == nil else { return false }
        guard case .failure(let error) = keyLoader(credentials.installationKey) else { return false }
        if case .unusable = InstallationKeyFailure.classify(loadError: error) { return true }
        return false
    }

    /// How many launches in a row saw a temporary key failure (prominence of the offer only).
    var keyUnavailableLaunches: Int { defaults.integer(forKey: Self.keyUnavailableLaunchesKey) }

    /// True when "Sign in again" must not use the stored key: it failed (temporarily or for
    /// good) and nothing has signed since. `reauthenticate` is the route then; attach and
    /// the enrolled-only guards would need the key that just failed (review 2026-10-26).
    var keyNeedsReauthentication: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials) else { return false }
        return keyUnusableWithoutRecovery || keyFailureActive
    }

    private static func isDraft(_ credentials: ClientAuthCredentials) -> Bool {
        credentials.accountID.isEmpty && credentials.accessToken == nil
    }

    var status: ClientAuthStatus {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials) else { return .notEnrolled }
        return ClientAuthStatus(
            isEnrolled: !keyUnusableWithoutRecovery,
            accountID: credentials.accountID.isEmpty ? nil : credentials.accountID,
            deviceCap: credentials.deviceCap,
            enrolledAt: credentials.enrolledAt.isEmpty ? nil : credentials.enrolledAt,
            enrollmentPath: credentials.enrollmentPath,
            recoveryKeyAcknowledged: credentials.recoveryKeyAcknowledged,
            isHardwareBacked: credentials.installationKey.kind == "se",
            keyUnusable: keyUnusableWithoutRecovery,
            keyTemporarilyUnavailable: keyFailureActive && !keyFailurePermanent && !keyUnusableWithoutRecovery,
            keyPermanentlyUnavailable: keyFailureActive && keyFailurePermanent
        )
    }

    /// Formatted recovery key for an explicit reveal.
    func revealRecoveryKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials) else { return nil }
        // A device that joined by email has no key of its own until it rotates one.
        if credentials.recoveryKey.isEmpty { return "" }
        return ClientAuthCrypto.formatRecoveryKey(credentials.recoveryKey)
    }

    func markRecoveryKeyAcknowledged() {
        update { $0.recoveryKeyAcknowledged = true }
    }

    /// Forget local credentials (after sign out / delete, or when the server says revoked).
    /// `reason` is remembered for the silent re-create count: `signout`, `delete`,
    /// `removed` (this device removed itself) or `revoke` (the server refused the key).
    func clearLocal(reason: String = "revoke") {
        lock.lock(); defer { lock.unlock() }
        credentials = nil
        cachedKey = nil
        localClearReason = reason
        unreadableCredential = nil
        defaults.set(reason, forKey: "managedAccessChoice")
        credentialEpoch += 1
        store.clear()
    }

    /// Clear only if the credential is still the one a request was made with: a revocation
    /// answered to an old credential says nothing about the one enrolled since (review
    /// 2026-10-27). Returns whether anything was cleared.
    @discardableResult
    func clearLocal(reason: String, ifGeneration generation: Int) -> Bool {
        lock.lock()
        guard credentialEpoch == generation else {
            lock.unlock()
            DebugLogger.shared.log(.app, "Device auth: stale \(reason) answer ignored; the credential has changed since")
            return false
        }
        credentials = nil
        cachedKey = nil
        localClearReason = reason
        unreadableCredential = nil
        defaults.set(reason, forKey: "managedAccessChoice")
        credentialEpoch += 1
        store.clear()
        lock.unlock()
        return true
    }



    private func installationKey() throws -> InstallationKey {
        let loaded: Result<InstallationKey, Error>
        lock.lock()
        if let cachedKey { lock.unlock(); return cachedKey }
        guard let credentials else { lock.unlock(); throw ClientAuthError.notEnrolled }
        loaded = keyLoader(credentials.installationKey)
        if case .success(let key) = loaded { cachedKey = key }
        lock.unlock()
        switch loaded {
        case .success(let key):
            DiagnosticTimeline.shared.record(.keyLoaded, fields: ["key_kind": key.isHardwareBacked ? "enclave" : "software"])
            return key
        case .failure(let error): throw keyFailure(InstallationKeyFailure.classify(loadError: error), phase: "load")
        }
    }

    /// Record a key failure and produce the error the caller propagates. Never under `lock`.
    private func keyFailure(_ failure: InstallationKeyFailure, phase: String) -> ClientAuthError {
        let hasRecovery: Bool = { lock.lock(); defer { lock.unlock() }; return !(credentials?.recoveryKey.isEmpty ?? true) }()
        lock.lock(); keyFailureActive = true; keyFailurePermanent = { if case .unusable = failure { return true }; return false }(); cachedKey = nil; lock.unlock()
        switch failure {
        case .unusable(let reason):
            if !hasRecovery { lock.withLock { keyUnusableWithoutRecovery = true } }
            emit("client_auth_key_unusable", level: .error, details: Self.keyFailureDetails(reason: reason, phase: phase, recovery: hasRecovery))
            return .keyUnusable
        case .temporary(let reason):
            noteTemporaryKeyFailure()
            emit("client_auth_key_unavailable", level: .warning, details: Self.keyFailureDetails(reason: reason, phase: phase, recovery: hasRecovery))
            return .keyUnavailable(reason)
        }
    }

    private static func keyFailureDetails(reason: String, phase: String, recovery: Bool) -> [String: String] {
        var details = ["phase": phase, "recovery": recovery ? "yes" : "no"]
        let parts = reason.split(separator: ":")
        if parts.count == 3, let code = Int(parts[2]) {
            details["error_domain"] = String(parts[1]); details["error_code"] = String(code)
        }
        return details
    }

    /// Whether `installationID` names this installation (the Devices row's own entry).
    func isCurrentDevice(_ installationID: String) -> Bool {
        deviceIDProvider().lowercased() == installationID.lowercased()
    }

    // MARK: Signing probe (F3, docs/archive/account-sending-consent-ux-plan.md)

    /// Local key-usability check behind Try again: load the stored key and sign a labelled
    /// probe through the same classification as a real signature. No request leaves, no token
    /// or credential changes; a success clears the temporary failure through the ordinary
    /// successful-signature rule, a failure is classified as usual. It says the key can sign
    /// here, not that the server still accepts this installation.
    @discardableResult
    func retrySigningProbe() -> Bool {
        do {
            let key = try installationKey()
            _ = try signing { try key.signJWS(payload: ["probe": "miniti-signing-probe", "iat": Int(Date().timeIntervalSince1970)]) }
            return true
        } catch {
            return false
        }
    }

    // MARK: Reauthentication with a fresh key (review 2026-10-26)

    /// Sign this installation in again without using the stored key: a fresh key proves an
    /// approved email link or a typed recovery key to the restore route, which re-binds the
    /// same installation on the same account (no cap slot). The old credential stays until
    /// the server has accepted the new key. An email or key for a different account is
    /// refused by the server (`device_already_enrolled`) because this installation is still
    /// active, and nothing changes locally.
    func reauthenticate(loginLinkID: String, label: String? = nil) async throws {
        let (recoveryKey, path, acknowledged, accountID, epoch) = try reauthenticationBasis()
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: nil, loginLinkID: loginLinkID, label: label ?? deviceLabelProvider())
        // The server may land a revoked installation in the link's account rather than the
        // one this credential names. The old recovery key proves the old account only, so
        // it stays solely when the account is the same; otherwise this is an ordinary switch
        // by email, which holds no key of its own (review 2026-10-26).
        let sameAccount = tokens.accountId == nil || tokens.accountId == accountID
        try storeEnrollment(key: key, recoveryKey: sameAccount ? recoveryKey : "", tokens: tokens, path: sameAccount ? path : .restore, acknowledged: sameAccount ? acknowledged : true, expectedEpoch: epoch)
        DebugLogger.shared.log(.app, "Device auth: installation re-authenticated by email with a fresh key\(sameAccount ? "" : " and moved to the link's account")")
        emit("client_auth_key_repaired", level: .info, details: ["via": "email", "switched": sameAccount ? "no" : "yes"])
    }

    func reauthenticate(recoveryKeyInput: String, label: String? = nil) async throws {
        guard let typed = ClientAuthCrypto.parseRecoveryKey(recoveryKeyInput) else { throw ClientAuthError.invalidRecoveryKey }
        let (_, path, _, _, epoch) = try reauthenticationBasis()
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: typed, label: label ?? deviceLabelProvider())
        try storeEnrollment(key: key, recoveryKey: typed, tokens: tokens, path: path, acknowledged: true, expectedEpoch: epoch)
        DebugLogger.shared.log(.app, "Device auth: installation re-authenticated with a recovery key and a fresh key")
        emit("client_auth_key_repaired", level: .info, details: ["via": "recovery_key"])
    }

    /// The credential snapshot a reauthentication replaces, with the epoch it was read under.
    private func reauthenticationBasis() throws -> (String, ClientAuthEnrollmentPath, Bool, String, Int) {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials) else { throw ClientAuthError.notEnrolled }
        return (credentials.recoveryKey, ClientAuthEnrollmentPath(rawValue: credentials.enrollmentPath) ?? .restore, credentials.recoveryKeyAcknowledged, credentials.accountID, credentialEpoch)
    }

    /// Run a signature with the key; a thrown signing error is classified like a load error.
    private func signing<T>(_ body: () throws -> T) throws -> T {
        do {
            let value = try body()
            clearTemporaryKeyFailures()
            lock.lock(); let recovered = keyFailureActive; keyFailureActive = false; lock.unlock()
            if recovered { DiagnosticTimeline.shared.record(.signingRecovered) }
            return value
        } catch let error as ClientAuthError {
            throw error
        } catch {
            throw keyFailure(InstallationKeyFailure.classify(signingError: error), phase: "sign")
        }
    }

    private func noteTemporaryKeyFailure() {
        lock.lock()
        let first = !temporaryKeyFailureSeenThisLaunch
        temporaryKeyFailureSeenThisLaunch = true
        lock.unlock()
        if first { defaults.set(defaults.integer(forKey: Self.keyUnavailableLaunchesKey) + 1, forKey: Self.keyUnavailableLaunchesKey) }
    }

    private func clearTemporaryKeyFailures() {
        if defaults.object(forKey: Self.keyUnavailableLaunchesKey) != nil { defaults.removeObject(forKey: Self.keyUnavailableLaunchesKey) }
    }

    private var canRepairKey: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let credentials, !Self.isDraft(credentials) else { return false }
        return !credentials.recoveryKey.isEmpty
    }

    // MARK: Key repair (A2d)

    /// Replace a key this machine cannot use with a fresh one, proving the account with the
    /// stored recovery key: same device id, same installation, no cap slot, no new account.
    /// Concurrent callers share one repair. Without a recovery key the credential enters
    /// `keyUnusable` and the person signs in again instead.
    /// Repair the credential that is current right now (the coordinator's eager repair).
    @discardableResult
    func repairUnusableKey() async throws -> Int {
        guard let (_, generation) = snapshot() else { throw ClientAuthError.notEnrolled }
        return try await repairUnusableKey(expecting: generation)
    }

    /// Repair the credential at generation `expecting`, the one whose signing just failed. A
    /// repair never adopts an unrelated credential: if the device has since signed out or
    /// switched, the failing operation ends with `notEnrolled` instead of being carried onto
    /// the new account (review 2026-10-27). Concurrent callers for the same generation share
    /// one repair; a caller for another generation is refused.
    /// Returns the generation of the replacement credential, captured at its commit, so the
    /// operation that caused the repair continues under exactly that credential and never
    /// under whatever is current when it resumes (review 2026-10-27).
    func repairUnusableKey(expecting generation: Int) async throws -> Int {
        try await sharedRepairTask(expecting: generation).value
    }

    private func sharedRepairTask(expecting generation: Int) throws -> Task<Int, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let repairTask {
            guard repairGeneration == generation else { throw ClientAuthError.notEnrolled }
            return repairTask
        }
        guard credentialEpoch == generation else { throw ClientAuthError.notEnrolled }
        let task = Task<Int, Error> { [self] in
            defer { lock.withLock { repairTask = nil } }
            let attempt = UUID().uuidString
            emit("client_auth_repair_attempt", level: .info, details: ["attempt_id": attempt])
            do {
                let replacement = try await performRepair(expecting: generation)
                emit("client_auth_repair_outcome", level: .info, details: ["attempt_id": attempt, "outcome": "success"])
                return replacement
            } catch {
                let stale = lock.withLock { credentialEpoch != generation }
                let ns = error as NSError
                emit("client_auth_repair_outcome", level: .warning, details: ["attempt_id": attempt, "outcome": stale ? "stale" : "failed", "error_domain": ns.domain, "error_code": String(ns.code)])
                throw error
            }
        }
        repairTask = task
        repairGeneration = generation
        return task
    }

    private func performRepair(expecting generation: Int) async throws -> Int {
        // The snapshot must still be the credential whose signing failed: the commit below
        // replaces exactly this credential, or nothing.
        let (recoveryKey, path, acknowledged, epoch): (String, String, Bool, Int) = try {
            lock.lock(); defer { lock.unlock() }
            guard let credentials, !Self.isDraft(credentials), credentialEpoch == generation else { throw ClientAuthError.notEnrolled }
            return (credentials.recoveryKey, credentials.enrollmentPath, credentials.recoveryKeyAcknowledged, credentialEpoch)
        }()
        guard !recoveryKey.isEmpty else {
            lock.withLock { keyUnusableWithoutRecovery = true }
            throw ClientAuthError.keyUnusable
        }
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: recoveryKey, label: deviceLabelProvider())
        // Signed out (or switched) while the restore was in flight: the answer belongs to a
        // credential the person no longer holds, and the atomic commit refuses it.
        let replacement = try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: ClientAuthEnrollmentPath(rawValue: path) ?? .restore, acknowledged: acknowledged, expectedEpoch: epoch)
        DebugLogger.shared.log(.app, "Device auth: the stored installation key cannot be used on this machine; re-bound with a fresh key")
        emit("client_auth_key_repaired", level: .info, details: [:])
        return replacement
    }

    // MARK: Credential commit contract (review 2026-10-27)
    //
    // Every credential write goes through `commit`: under the one lock that `clearLocal`
    // also holds, the generation is checked against the value captured when the writer
    // started, the store is written and memory updated. A write whose generation has moved
    // (a sign-out, a revoke, a replacement) is refused, so a late answer can never resurrect
    // a cleared credential or land on a newer one. Writers that replace the credential's
    // identity (a new key, a new account, a new recovery key, a clear) bump the generation;
    // token-only updates keep it, so they never invalidate unrelated valid work and never
    // touch the key-failure state (that is `storeEnrollment`'s job alone).

    /// A first enrolment: no credential to replace, so no expectation; bumps the generation.
    @discardableResult
    private func persist(_ newValue: ClientAuthCredentials) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard store.save(newValue) else { throw ClientAuthError.storage }
        credentials = newValue
        unreadableCredential = nil
        if !Self.isDraft(newValue) {
            defaults.removeObject(forKey: "managedAccessChoice")
            defaults.removeObject(forKey: "managedEnrollmentNotBefore")
            defaults.removeObject(forKey: "managedMigrationIneligible")
        }
        cachedKey = nil
        credentialEpoch += 1
        return credentialEpoch
    }

    /// Commit `newValue` if the generation is still `expectedEpoch`. `replaces` says whether
    /// the write changes the credential's identity and so moves the generation on.
    /// Returns the generation the written credential lives at, captured in the same critical
    /// section, so a replacement can hand its exact result to the operation that caused it.
    @discardableResult
    private func commit(_ newValue: ClientAuthCredentials, expectedEpoch: Int, replaces: Bool) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard credentialEpoch == expectedEpoch else {
            DiagnosticTimeline.shared.record(.credentialStale)
            DebugLogger.shared.log(.app, "Device auth: a credential write finished after a sign-out or replacement; discarded")
            throw ClientAuthError.notEnrolled
        }
        guard store.save(newValue) else { throw ClientAuthError.storage }
        credentials = newValue
        unreadableCredential = nil
        if !Self.isDraft(newValue) {
            defaults.removeObject(forKey: "managedAccessChoice")
            defaults.removeObject(forKey: "managedEnrollmentNotBefore")
            defaults.removeObject(forKey: "managedMigrationIneligible")
        }
        cachedKey = nil
        if replaces { credentialEpoch += 1 }
        return credentialEpoch
    }

    /// The credential generation, for hosts that fence work on it (cloud sync, R3).
    var credentialGeneration: Int {
        lock.lock(); defer { lock.unlock() }
        return credentialEpoch
    }

    /// The current credential and the generation it was read under, for a writer that is
    /// about to await something.
    private func snapshot() -> (credentials: ClientAuthCredentials, epoch: Int)? {
        lock.lock(); defer { lock.unlock() }
        guard let credentials else { return nil }
        return (credentials, credentialEpoch)
    }

    /// A credential replacement (a new key the server accepted) is what ends a key failure;
    /// a token-only update through `persist` is not (review 2026-10-26: an unsigned refresh
    /// used to clear the flag and send "Sign in again" back through the broken key).
    private func clearKeyFailure() {
        lock.lock(); defer { lock.unlock() }
        keyUnusableWithoutRecovery = false
        keyFailureActive = false
    }

    /// Mutate the stored credential as one committed operation. `expectedEpoch` is the
    /// generation the caller captured before its await (nil for a synchronous change: the
    /// current generation is used). Returns false when nothing was written: no credential, a
    /// stale generation, or a storage failure.
    @discardableResult
    private func update(expectedEpoch: Int? = nil, replaces: Bool = false, _ change: (inout ClientAuthCredentials) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var value = credentials else { return false }
        if let expectedEpoch, expectedEpoch != credentialEpoch {
            DiagnosticTimeline.shared.record(.credentialStale)
            DebugLogger.shared.log(.app, "Device auth: a credential update finished after a sign-out or replacement; discarded")
            return false
        }
        change(&value)
        guard store.save(value) else { return false }
        credentials = value
        cachedKey = nil
        if replaces { credentialEpoch += 1 }
        return true
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

    private static func diagnosticPhase(_ path: String) -> String {
        switch path {
        case "/auth/token", "/auth/challenge": return "refresh"
        case "/auth/account/create": return "create"
        case "/auth/migrate": return "migrate"
        case "/auth/account/restore": return "restore"
        case "/auth/account/attach": return "attach"
        case "/auth/account/recovery-key/rotate": return "rotate"
        case "/auth/revoke": return "sign_out"
        case "/auth/account": return "delete"
        default: return "read"
        }
    }

    private static func diagnosticServerCode(_ error: ClientAuthError) -> String {
        switch error {
        case .server(let code, _): return DiagnosticTimeline.sanitize(["server_code": code])["server_code"] ?? "unknown"
        case .revoked: return "installation_revoked"
        case .notEnrolled: return "not_enrolled"
        case .deviceAlreadyEnrolled: return "device_already_enrolled"
        case .deviceCapReached: return "device_cap_reached"
        case .subscriptionConflict: return "subscription_conflict"
        case .invalidRecoveryKey: return "invalid_recovery_key"
        case .recoveryKeyUnknown: return "recovery_key_unknown"
        case .notEligibleForMigration: return "device_not_eligible"
        case .rateLimited: return "rate_limited"
        default: return "unknown"
        }
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

    static func retryDate(_ value: String?, now: Date) -> Date {
        if let value, let seconds = Double(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds > 0 {
            return now.addingTimeInterval(min(seconds, 31_536_000))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let value, let date = formatter.date(from: value), date > now { return date }
        return now.addingTimeInterval(60)
    }

    private func rememberEnrollmentRetryAfter(_ value: String?, epoch: Int) {
        lock.lock(); defer { lock.unlock() }
        guard credentialEpoch == epoch else { return }
        retryAfterDate = Self.retryDate(value, now: Date())
    }

    private func postPublic<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ClientAuthError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        identityHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let requestEpoch = credentialGeneration
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            DiagnosticTimeline.shared.record(.authRefused, fields: DiagnosticTimeline.errorFields(error).merging(["phase": Self.diagnosticPhase(path)]) { _, new in new })
            throw ClientAuthError.network(error.localizedDescription)
        }
        noteServerDate(response)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let mapped = mapError(status: status, data: data)
            if status == 429 {
                rememberEnrollmentRetryAfter((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), epoch: requestEpoch)
            }
            DiagnosticTimeline.shared.record(.authRefused, fields: ["phase": Self.diagnosticPhase(path), "status": String(status), "server_code": Self.diagnosticServerCode(mapped)])
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

    private func enroll(path: String, key: InstallationKey, recoveryKey: String?, loginLinkID: String? = nil, label: String?) async throws -> TokenResponse {
        let challenge = try await challenge(purpose: "enroll")
        let proof = try key.challengeProof(nonce: challenge.nonce, purpose: "enroll", deviceID: deviceIDProvider(), now: now())
        var body: [String: Any] = [
            "device_id": deviceIDProvider(),
            "public_key_jwk": key.publicJWK,
            "challenge_id": challenge.challengeId,
            "proof": proof,
        ]
        if let recoveryKey { body["recovery_key"] = recoveryKey }
        if let loginLinkID { body["login_link_id"] = loginLinkID }
        if let label { body["label"] = label }
        return try await postPublic(path, body: body)
    }

    // MARK: Sign-in by email (3.0.0)

    /// Where an email sign-in stands. `expired` also covers refused and already used.
    enum EmailSignInStatus: String, Decodable { case pending, approved, expired }

    /// Ask for an approval link to be sent to the account's email (`POST /api/auth/email/start`).
    /// Always answers with a link id, even for an unknown email, so nothing is revealed.
    func startEmailSignIn(email: String) async throws -> String {
        struct Started: Decodable { let linkId: String; enum CodingKeys: String, CodingKey { case linkId = "link_id" } }
        let started: Started = try await postPublic("/auth/email/start", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "device_id": deviceIDProvider(),
            "platform": Self.platformName,
        ])
        return started.linkId
    }

    static var platformName: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    /// Poll the link (`GET /api/auth/email/status`).
    func emailSignInStatus(linkID: String) async throws -> EmailSignInStatus {
        struct Status: Decodable { let status: EmailSignInStatus }
        guard let url = URL(string: "\(baseURL)/auth/email/status?link_id=\(linkID)") else { throw ClientAuthError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        identityHeaders(&request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            DiagnosticTimeline.shared.record(.authRefused, fields: DiagnosticTimeline.errorFields(error).merging(["phase": "read"]) { _, new in new })
            throw ClientAuthError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else { throw mapError(status: status, data: data) }
        do {
            return try JSONDecoder().decode(Status.self, from: data).status
        } catch {
            throw ClientAuthError.network("could not decode email status")
        }
    }

    /// Join the account that approved `loginLinkID` from an already enrolled device
    /// (`POST /api/auth/account/attach` with the link instead of a recovery key). The device
    /// ends up without a recovery key of its own; Settings offers to rotate one.
    func attachToAccount(loginLinkID: String) async throws -> Bool {
        guard isEnrolled else { throw ClientAuthError.notEnrolled }
        let (response, epoch): (AttachResponse, Int) = try await authorizedJSONTracking("POST", "/auth/account/attach", body: ["login_link_id": loginLinkID])
        let written = update(expectedEpoch: epoch, replaces: true) { credentials in
            credentials.recoveryKey = ""
            credentials.accessToken = response.accessToken
            credentials.accessExpiresAt = now() + (response.expiresIn ?? 3600)
            if let refresh = response.refreshToken { credentials.refreshToken = refresh }
            if let cap = response.deviceCap { credentials.deviceCap = cap }
            if let account = response.accountId { credentials.accountID = account }
            credentials.recoveryKeyAcknowledged = true
        }
        guard written else { throw ClientAuthError.notEnrolled }
        DebugLogger.shared.log(.app, "Device auth: installation \(response.moved == true ? "moved to another account by email" : "already on that account")")
        return response.moved ?? true
    }

    /// Enroll an unenrolled device into the account that approved `loginLinkID`.
    func restoreAccount(loginLinkID: String, label: String? = nil) async throws {
        rereadUnreadableCredential()
        if case .unreadable(.unreadable) = credentialState {
            throw ClientAuthError.keyUnavailable("credential_unreadable")
        }
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let enrollmentEpoch = credentialGeneration
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: nil, loginLinkID: loginLinkID, label: label)
        try storeEnrollment(key: key, recoveryKey: "", tokens: tokens, path: .restore, acknowledged: true, expectedEpoch: enrollmentEpoch)
        DebugLogger.shared.log(.app, "Device auth: account restored by email")
    }

    /// `expectedEpoch` makes the write a replacement of the credential that was current when
    /// the request started (repair, reauthentication); a first enrolment passes nil.
    @discardableResult
    private func storeEnrollment(key: InstallationKey, recoveryKey: String, tokens: TokenResponse, path: ClientAuthEnrollmentPath, acknowledged: Bool, expectedEpoch: Int? = nil) throws -> Int {
        defer { if credentialsHold(key: key) { clearKeyFailure() } }
        let value = ClientAuthCredentials(
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
        )
        if let expectedEpoch {
            return try commit(value, expectedEpoch: expectedEpoch, replaces: true)
        } else {
            return try persist(value)
        }
    }

    private func credentialsHold(key: InstallationKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return credentials?.installationKey == key.stored
    }

    /// A draft is written before any enrollment request so a lost response cannot lose the
    /// only copy of a freshly generated recovery key. A draft has no account yet.
    @discardableResult
    private func writeDraft(key: InstallationKey, recoveryKey: String, path: ClientAuthEnrollmentPath, absenceConfirmed: Bool = false) -> Bool {
        var value = ClientAuthCredentials(
            installationKey: key.stored,
            recoveryKey: recoveryKey,
            accountID: "",
            accessToken: nil,
            accessExpiresAt: nil,
            refreshToken: nil,
            deviceCap: nil,
            enrolledAt: "",
            enrollmentPath: path.rawValue
        )
        value.absenceConfirmed = absenceConfirmed
        let saved = store.save(value)
        if !saved { emit("client_auth_draft_write_failed", level: .warning, details: ["path": path.rawValue]) }
        return saved
    }

    /// Resume a draft (key + recovery key generated, but the request never completed).
    private func draft() -> (InstallationKey, String)? {
        let stored = store.load()
        reportLoadDiagnostic(phase: "retry")
        guard let stored, stored.accountID.isEmpty, stored.accessToken == nil,
              let key = InstallationKey(stored: stored.installationKey) else { return nil }
        return (key, stored.recoveryKey)
    }

    // MARK: Enrollment

    /// Create a new anonymous account. Returns the formatted recovery key.
    @discardableResult
    func createAccount(label: String? = nil, acknowledged: Bool = false, allowDeviceRotation: Bool = false) async throws -> String {
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let enrollmentEpoch = credentialGeneration
        let read = store.loadResult()
        if case .unreadable = read { throw ClientAuthError.keyUnavailable("credential_unreadable") }
        let absenceConfirmed: Bool
        switch read {
        case .missing: absenceConfirmed = true
        case .found(let value): absenceConfirmed = value.absenceConfirmed == true
        case .unreadable: absenceConfirmed = false
        }
        reportEnrollmentStart(path: "create")
        let (key, recoveryKey) = draft() ?? (InstallationKey.generate(), ClientAuthCrypto.generateRecoveryKey())
        // A credential this device cannot store is one the person cannot recover from later:
        // creating the account first would leave an orphan installation holding a cap slot
        // and a recovery key nobody has (enrollment-identity-plan A2c). Stop before any request.
        guard writeDraft(key: key, recoveryKey: recoveryKey, path: .create, absenceConfirmed: absenceConfirmed) else { throw ClientAuthError.storage }
        let tokens: TokenResponse
        do {
            tokens = try await enroll(path: "/auth/account/create", key: key, recoveryKey: recoveryKey, label: label)
        } catch ClientAuthError.deviceAlreadyEnrolled {
            emit("client_auth_create_conflict", level: .info, details: ["path": "create", "rotator": deviceIDRotator == nil ? "no" : "yes"])
            // The server already has an active installation under this device id with a key
            // this Keychain does not hold: a phone restored from a backup keeps the device id
            // item but not the device-only credentials. No request from here can prove the
            // old account. Only the explicit device-reset confirmation permits a new
            // identity. Usage, calendar and CRM
            // connections were keyed by the old id; a person who kept the recovery key can
            // move the device back with it (2026-10-10).
            guard allowDeviceRotation, absenceConfirmed, let deviceIDRotator else { throw ClientAuthError.deviceAlreadyEnrolled }
            let previous = deviceIDProvider()
            let rotated = deviceIDRotator()
            DebugLogger.shared.log(.app, "Device auth: device id already enrolled with another key; rotated to \(rotated.prefix(8))... and creating a fresh account")
            emit("client_auth_device_rotated", level: .warning, details: ["from": String(previous.prefix(8)), "to": String(rotated.prefix(8)), "path": "create"])
            tokens = try await enroll(path: "/auth/account/create", key: key, recoveryKey: recoveryKey, label: label)
        }
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .create, acknowledged: acknowledged, expectedEpoch: enrollmentEpoch)
        DebugLogger.shared.log(.app, "Device auth: account created")
        return ClientAuthCrypto.formatRecoveryKey(recoveryKey)
    }

    /// Attach this installation to an existing account with its recovery key.
    func restoreAccount(recoveryKeyInput: String, label: String? = nil) async throws {
        rereadUnreadableCredential()
        if case .unreadable(.unreadable) = credentialState { throw ClientAuthError.keyUnavailable("credential_unreadable") }
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let enrollmentEpoch = credentialGeneration
        guard let recoveryKey = ClientAuthCrypto.parseRecoveryKey(recoveryKeyInput) else {
            throw ClientAuthError.invalidRecoveryKey
        }
        let key = InstallationKey.generate()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: recoveryKey, label: label)
        // Restoring means the person already holds the key; no nudge needed.
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .restore, acknowledged: true, expectedEpoch: enrollmentEpoch)
        DebugLogger.shared.log(.app, "Device auth: account restored")
    }

    /// Silent one-time migration for an installation whose device record predates the
    /// backend cutoff. Generates the recovery key locally first; the server binds the
    /// existing device record to a new anonymous account.
    func migrateLegacyDevice(label: String? = nil) async throws {
        if isEnrolled { throw ClientAuthError.alreadyEnrolled }
        let enrollmentEpoch = credentialGeneration
        let read = store.loadResult()
        if case .unreadable = read { throw ClientAuthError.keyUnavailable("credential_unreadable") }
        let absenceConfirmed: Bool
        if case .missing = read { absenceConfirmed = true } else { absenceConfirmed = read.value?.absenceConfirmed == true }
        reportEnrollmentStart(path: "migrate")
        let (key, recoveryKey) = draft() ?? (InstallationKey.generate(), ClientAuthCrypto.generateRecoveryKey())
        guard writeDraft(key: key, recoveryKey: recoveryKey, path: .migrate, absenceConfirmed: absenceConfirmed) else { throw ClientAuthError.storage }
        let tokens: TokenResponse
        do {
            tokens = try await enroll(path: "/auth/migrate", key: key, recoveryKey: recoveryKey, label: label)
        } catch ClientAuthError.deviceAlreadyEnrolled {
            emit("client_auth_create_conflict", level: .info, details: ["path": "migrate", "rotator": deviceIDRotator == nil ? "no" : "yes"])
            throw ClientAuthError.deviceAlreadyEnrolled
        } catch ClientAuthError.server(_, let status) where status == 404 {
            // A backend without the migration route at all: the device record (usage, tier,
            // subscription) is keyed by the same UUID either way, so creating an account
            // loses nothing. Treat it like "not eligible" and let the caller fall back.
            throw ClientAuthError.notEligibleForMigration
        }
        try storeEnrollment(key: key, recoveryKey: recoveryKey, tokens: tokens, path: .migrate, acknowledged: false, expectedEpoch: enrollmentEpoch)
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
        guard let (snapshotCredentials, epoch) = snapshot() else { throw ClientAuthError.notEnrolled }
        let diagnosticID = UUID().uuidString
        var refreshed = false
        DiagnosticTimeline.shared.record(.refreshStarted, fields: ["attempt_id": diagnosticID])
        defer { DiagnosticTimeline.shared.record(refreshed ? .refreshSucceeded : .refreshFailed, fields: ["attempt_id": diagnosticID]) }
        let refreshToken: String? = snapshotCredentials.refreshToken
        do {
            let tokens: TokenResponse
            if let refreshToken {
                do {
                    tokens = try await grantRefresh(refreshToken)
                } catch ClientAuthError.server(_, let status) where status == 401 {
                    tokens = try await grantChallengeOrRebind()
                }
            } else {
                tokens = try await grantChallengeOrRebind()
            }
            let written = update(expectedEpoch: epoch) { credentials in
                credentials.accessToken = tokens.accessToken
                credentials.accessExpiresAt = now() + (tokens.expiresIn ?? 3600)
                if let refresh = tokens.refreshToken { credentials.refreshToken = refresh }
                if let cap = tokens.deviceCap { credentials.deviceCap = cap }
                if let account = tokens.accountId { credentials.accountID = account }
            }
            // Signed out, revoked or replaced while the grant was in flight: the token belongs
            // to a credential this device no longer holds, so it is not a usable result.
            guard written else { throw ClientAuthError.notEnrolled }
            refreshed = true
            return tokens.accessToken
        } catch ClientAuthError.revoked {
            // Only the credential that was refused is cleared; a newer one stays.
            guard clearLocal(reason: "revoke", ifGeneration: epoch) else { throw ClientAuthError.notEnrolled }
            DebugLogger.shared.log(.app, "Device auth: installation revoked by the server; clearing local credentials")
            throw ClientAuthError.revoked
        } catch ClientAuthError.keyUnusable where canRepairKey {
            // The challenge grant needed the stored key and this machine cannot use it: the
            // repair restores with a fresh key and brings its own tokens (A2d). It repairs the
            // credential this refresh started with, never one enrolled since.
            let replacement = try await repairUnusableKey(expecting: epoch)
            guard let (repaired, generation) = snapshot(), generation == replacement, let token = repaired.accessToken else { throw ClientAuthError.notEnrolled }
            refreshed = true
            return token
        }
    }

    private func grantRefresh(_ refreshToken: String) async throws -> TokenResponse {
        try await postPublic("/auth/token", body: ["grant_type": "refresh", "device_id": deviceIDProvider(), "refresh_token": refreshToken])
    }

    private func grantChallenge() async throws -> TokenResponse {
        let key = try installationKey()
        let challenge = try await challenge(purpose: "token")
        let proof = try signing { try key.challengeProof(nonce: challenge.nonce, purpose: "token", deviceID: deviceIDProvider(), now: now()) }
        return try await postPublic("/auth/token", body: [
            "grant_type": "challenge", "device_id": deviceIDProvider(),
            "challenge_id": challenge.challengeId, "proof": proof,
        ])
    }

    /// A challenge grant the server answers with `invalid_proof` means the key it holds for
    /// this device id is not the one in this Keychain (a backup restored onto a device that
    /// kept its device UUID, or a second install carrying the same UUID). Nothing else the
    /// app does can recover from that: sign-out and every write need a token first, and a
    /// restore is refused while credentials exist. The stored recovery key proves the account,
    /// so re-bind the installation to the current key through the restore route, which the
    /// backend accepts for the same account without using a device slot (2026-10-10).
    private func grantChallengeOrRebind() async throws -> TokenResponse {
        do {
            return try await grantChallenge()
        } catch ClientAuthError.server(let code, let status) where status == 401 && code == "invalid_proof" {
            DebugLogger.shared.log(.app, "Device auth: server rejected this installation's key; re-binding with the stored recovery key")
            return try await rebindInstallation()
        }
    }

    private func rebindInstallation() async throws -> TokenResponse {
        let key = try installationKey()
        let recoveryKey: String = try {
            lock.lock(); defer { lock.unlock() }
            guard let credentials else { throw ClientAuthError.notEnrolled }
            return credentials.recoveryKey
        }()
        let tokens = try await enroll(path: "/auth/account/restore", key: key, recoveryKey: recoveryKey, label: deviceLabelProvider())
        emit("client_auth_key_rebound", level: .info, details: [:])
        DebugLogger.shared.log(.app, "Device auth: installation re-bound to its account")
        return tokens
    }

    /// `X-Request-Proof` for an authenticated write.
    func requestProof(accessToken: String, method: String, url: URL, body: Data) throws -> String {
        let key = try installationKey()
        return try signing {
            try key.requestProof(
                accessToken: accessToken,
                method: method,
                target: ClientAuthCrypto.requestTarget(url),
                body: body,
                now: now(),
                jti: ClientAuthCrypto.newJTI()
            )
        }
    }

    /// Attach bearer + proof to a request. Throws `notEnrolled` when there is no account.
    /// Attach the bearer and, on writes, the request proof. Returns the credential generation
    /// of the snapshot that actually signed: the bearer is the snapshot's token and the proof
    /// its key, and the snapshot is checked to be still current after signing, so the value
    /// never names a credential enrolled while the signature was being made (review
    /// 2026-10-27). Callers carry it through sending, retries and commits and never re-read
    /// the current generation in its place. An automatic same-account repair inside this call
    /// yields the repaired credential's generation, which is then the request's own.
    @discardableResult
    func authorize(_ request: inout URLRequest) async throws -> Int {
        let token = try await accessToken()
        // The snapshot that signs: its token must be the one we were handed, or the token came
        // from a credential that has since been replaced.
        guard let (credentials, generation) = snapshot(), credentials.accessToken == token else { throw ClientAuthError.notEnrolled }
        do {
            return try authorizeOnce(&request, token: token, generation: generation)
        } catch ClientAuthError.keyUnusable where canRepairKey {
            // A valid cached bearer skipped the refresh and only the proof failed: repair the
            // credential whose signing failed (never one enrolled meanwhile), then sign the same
            // request with its replacement key and token (A2d).
            let replacement = try await repairUnusableKey(expecting: generation)
            // Continue under the repair's exact result: if anything else replaced it meanwhile,
            // this request has no credential of its own any more.
            guard let (repaired, repairedGeneration) = snapshot(), repairedGeneration == replacement, let repairedToken = repaired.accessToken else {
                throw ClientAuthError.notEnrolled
            }
            return try authorizeOnce(&request, token: repairedToken, generation: repairedGeneration)
        }
    }

    private func authorizeOnce(_ request: inout URLRequest, token: String, generation: Int) throws -> Int {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let method = request.httpMethod ?? "GET"
        if method != "GET", method != "HEAD", let url = request.url {
            let proof = try requestProof(accessToken: token, method: method, url: url, body: request.httpBody ?? Data())
            request.setValue(proof, forHTTPHeaderField: "X-Request-Proof")
        }
        // Signing took time; a sign-out or switch meanwhile means this signature belongs to a
        // credential the device no longer holds.
        guard credentialGeneration == generation else { throw ClientAuthError.notEnrolled }
        return generation
    }

    // MARK: Account management (authenticated)

    private func authorizedJSON<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        try await authorizedJSONTracking(method, path, body: body).value
    }

    /// The same request, also returning the credential generation it was actually signed
    /// under. That is read after `authorize`, so an automatic same-account key repair inside
    /// it (new key, same account and recovery key) is part of the request's own lineage, while
    /// a sign-out or account change after the send still makes the answer stale (review
    /// 2026-10-27). Mutations commit against this generation.
    private func authorizedJSONTracking<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (value: T, generation: Int) {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ClientAuthError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        identityHeaders(&request)
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let generation = try await authorize(&request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            DiagnosticTimeline.shared.record(.authRefused, fields: DiagnosticTimeline.errorFields(error).merging(["phase": Self.diagnosticPhase(path)]) { _, new in new })
            throw ClientAuthError.network(error.localizedDescription)
        }
        noteServerDate(response)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let mapped = mapError(status: status, data: data)
            DiagnosticTimeline.shared.record(.authRefused, fields: ["phase": Self.diagnosticPhase(path), "status": String(status), "server_code": Self.diagnosticServerCode(mapped)])
            if case .revoked = mapped {
                guard clearLocal(reason: "revoke", ifGeneration: generation) else { throw ClientAuthError.notEnrolled }
            }
            throw mapped
        }
        return (try JSONDecoder().decode(T.self, from: data), generation)
    }

    private struct Empty: Decodable {}

    func renameDevice(installationID: String, label: String?) async throws {
        struct Renamed: Decodable { let installation_id: String; let label: String? }
        let (_, generation): (Renamed, Int) = try await authorizedJSONTracking("PATCH", "/auth/account/devices/\(installationID)", body: ["label": label as Any? ?? NSNull()])
        guard credentialGeneration == generation else { throw ClientAuthError.notEnrolled }
    }

    func listDevices() async throws -> ClientAuthDeviceList {
        try await authorizedJSON("GET", "/auth/account/devices")
    }

    /// Remove any device on the account. Removing the current one clears local credentials.
    func removeDevice(installationID: String) async throws {
        let (_, generation): (Empty, Int) = try await authorizedJSONTracking("DELETE", "/auth/account/devices/\(installationID)")
        if installationID.lowercased() == deviceIDProvider().lowercased() { clearLocal(reason: "removed", ifGeneration: generation) }
    }

    /// Generate a new recovery key and ask the server to accept it. Returns the formatted key.
    func rotateRecoveryKey() async throws -> String {
        let newKey = ClientAuthCrypto.generateRecoveryKey()
        guard isEnrolled else { throw ClientAuthError.notEnrolled }
        let (_, epoch): (Empty, Int) = try await authorizedJSONTracking("POST", "/auth/account/recovery-key/rotate", body: ["new_recovery_key": newKey])
        // The server now knows only the new key. The write belongs to the credential the request
        // was signed under (after any automatic repair); a sign-out or switch since makes it stale.
        guard update(expectedEpoch: epoch, replaces: true, { $0.recoveryKey = newKey; $0.recoveryKeyAcknowledged = false }) else {
            throw ClientAuthError.notEnrolled
        }
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
        let (response, epoch): (AttachResponse, Int) = try await authorizedJSONTracking("POST", "/auth/account/attach", body: ["recovery_key": recoveryKey])
        let written = update(expectedEpoch: epoch, replaces: true) { credentials in
            credentials.recoveryKey = recoveryKey
            credentials.accessToken = response.accessToken
            credentials.accessExpiresAt = now() + (response.expiresIn ?? 3600)
            if let refresh = response.refreshToken { credentials.refreshToken = refresh }
            if let cap = response.deviceCap { credentials.deviceCap = cap }
            if let account = response.accountId { credentials.accountID = account }
            // The person typed this key from their other device; no save-your-key nudge.
            credentials.recoveryKeyAcknowledged = true
        }
        guard written else { throw ClientAuthError.notEnrolled }
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
    /// Sign this installation out. Returns true when this call cleared the local credential;
    /// false when the credential it started with had already been replaced (a sign-out that
    /// completes for an old credential leaves the newer one alone, review 2026-10-27).
    @discardableResult
    func signOut() async throws -> Bool {
        guard let (_, generation) = snapshot() else { throw ClientAuthError.notEnrolled }
        if keyNeedsReauthentication {
            // The stored key failed and nothing has signed since: the revoke cannot be proved.
            // Signing out is how the person leaves that state, so it clears locally at once
            // (review 2026-10-26: after the unusable state is established, every authorized
            // call throws notEnrolled, which the catches below never saw).
            return clearLocal(reason: "signout", ifGeneration: generation)
        }
        var signed = generation
        do {
            let (_, under): (Empty, Int) = try await authorizedJSONTracking("POST", "/auth/revoke", body: [:])
            signed = under
        } catch ClientAuthError.revoked {
            // Already gone server-side, and the request handler cleared exactly this
            // credential (a stale revoked answer throws notEnrolled instead): the sign-out is
            // complete and its bookkeeping may run.
            return true
        } catch ClientAuthError.notEnrolled {
            // The credential this sign-out was for is no longer the one held: superseded.
            return false
        } catch ClientAuthError.server(_, let status) where status == 401 {
            // The server no longer accepts this installation's key and the re-bind did not
            // help either. Signing out is how the person escapes that state, so it must not
            // itself depend on a token.
        } catch ClientAuthError.deviceAlreadyEnrolled, ClientAuthError.recoveryKeyUnknown {
            // The re-bind was refused because the device id now belongs to another account
            // or the stored recovery key no longer resolves: forget it locally.
        } catch ClientAuthError.keyUnusable, ClientAuthError.keyUnavailable {
            // The stored key cannot sign here, so the revoke cannot be proved. Signing out is
            // how the person leaves that state; it must not depend on the key (A2d).
        }
        // Only the credential this sign-out was for is cleared; a same-account repair inside the
        // request moved `signed` on to its replacement, a sign-out or switch since did not.
        return clearLocal(reason: "signout", ifGeneration: signed)
    }

    /// Delete the anonymous account (revokes every device). Does not cancel subscriptions.
    /// Returns true when this call cleared the local credential (see `signOut`).
    @discardableResult
    func deleteAccount() async throws -> Bool {
        do {
            let (_, generation): (Empty, Int) = try await authorizedJSONTracking("DELETE", "/auth/account")
            return clearLocal(reason: "delete", ifGeneration: generation)
        } catch ClientAuthError.revoked {
            // The handler cleared this credential already: the account is gone for this device.
            return true
        }
    }
}

// MARK: - Enrollment policy

/// The managed enrollment policy, moved out of `AppState` so it can be tested without a host
/// app (docs/archive/enrollment-identity-plan.md, A2). Behaviour is the 3.3.0 `AppState` policy
/// ported line for line: enrolled → nothing to do; device id session-only → defer; migrate,
/// then create on `notEligibleForMigration` or `deviceAlreadyEnrolled`; concurrent callers
/// share one attempt; a failure is remembered and the next trigger retries. The screenshot
/// and XCTest guards, the mode check and the published mirrors stay in `AppState`, which
/// hands this object closures for them so the order of every side effect is unchanged.
@MainActor
final class ManagedEnrollmentCoordinator {
    typealias EventLevel = MinitiAPIService.ClientEventPayload.EventLevel

    /// What the coordinator needs from its host, as closures so a test can observe each one.
    struct Hooks {
        /// `DeviceIdentifier.isUsingSessionOnlyID`: the real id exists but cannot be read now.
        var deviceIDIsSessionOnly: () -> Bool
        /// Label sent with an enrollment ("Mac", "iPhone or iPad").
        var deviceLabel: () -> String?
        /// The host's published status says enrolled (it may lag the manager).
        var statusIsEnrolled: () -> Bool
        /// Mirror of `AppState.isEnrollingManagedDevice`.
        var setEnrolling: (Bool) -> Void
        /// Mirror of `AppState.managedEnrollmentError`.
        var setError: (String?) -> Void
        /// `AppState.refreshClientAuthStatus()`.
        var refreshStatus: () -> Void
        /// `AppState.enqueueDiagnosticEvent` (category app).
        var event: (_ name: String, _ level: EventLevel, _ details: [String: String]) -> Void
        /// `DebugLogger.shared.log(.app, …)`.
        var log: (String) -> Void
    }

    private let manager: ClientAuthManager
    private let hooks: Hooks
    private var task: Task<Bool, Never>?

    init(manager: ClientAuthManager, hooks: Hooks) {
        self.manager = manager
        self.hooks = hooks
        // The old backend could reject an uppercase legacy device record. Retry that
        // negative verdict once with the corrected lookup, without undoing sign-out.
        let defaults = manager.enrollmentDefaults
        if defaults.integer(forKey: "managedMigrationProbeRevision") < 2 {
            if defaults.string(forKey: "managedMigrationIneligible") == manager.enrollmentDeviceID,
               manager.accessChoiceReason == "awaitingChoice", defaults.bool(forKey: "hasCompletedOnboarding") {
                defaults.removeObject(forKey: "managedAccessChoice")
            }
            defaults.removeObject(forKey: "managedMigrationIneligible")
            defaults.set(2, forKey: "managedMigrationProbeRevision")
        }
    }

    /// True while an attempt is running (for tests and for the host's retry button).
    var isAttemptInFlight: Bool { task != nil }

    /// Make sure this installation holds device-bound credentials before a managed request.
    /// Existing installations migrate silently (their device record predates the backend
    /// cutoff); anything else gets a fresh anonymous account. Failures are retried on the
    /// next managed action rather than surfaced as a gate, since managed features need the
    /// network anyway. Concurrent callers share one attempt.
    @discardableResult
    func ensure(trigger: String) async -> Bool {
        manager.rereadUnreadableCredential(allowInteraction: trigger == "settings" || trigger == "explicit choice")
        if let message = manager.unreadableCredentialMessage {
            hooks.setError(message)
            hooks.refreshStatus()
            return false
        }
        if manager.credentialState == .keyUnusable {
            // Credential present, key unusable here, nothing to replace it with: the person
            // signs in again. Nothing is migrated, created or rotated meanwhile (A2d).
            hooks.setError(ClientAuthError.keyUnusable.errorDescription)
            hooks.log("enrollment_blocked_key_unusable trigger=\(trigger)")
            hooks.refreshStatus()
            return false
        }
        if manager.isEnrolled {
            if manager.needsKeyRepair {
                do {
                    try await manager.repairUnusableKey()
                    hooks.setError(nil)
                } catch {
                    hooks.setError(error.localizedDescription)
                    hooks.log("Managed enrollment: key repair FAILED (trigger=\(trigger)): \(error.localizedDescription)")
                    hooks.refreshStatus()
                    return false
                }
            }
            hooks.setError(nil)
            if !hooks.statusIsEnrolled() { hooks.refreshStatus() }
            return true
        }
        if manager.accessChoiceRequired {
            hooks.setError(nil)
            hooks.refreshStatus()
            return false
        }
        if let until = deferredUntil, until > Date() {
            hooks.setError(deferralMessage(until))
            hooks.refreshStatus()
            return false
        }
        if hooks.deviceIDIsSessionOnly() {
            // The real device ID exists but the Keychain could not be read right now
            // (locked, prompting). Enrolling would bind a new account and stored
            // credentials to a temporary identity; wait for the next trigger instead.
            hooks.log("enrollment_deferred_session_only_device_id trigger=\(trigger)")
            hooks.setError("Your saved device identity is temporarily unavailable. Unlock your device and try again. Your existing account has not been replaced.")
            hooks.refreshStatus()
            return false
        }
        if let task { return await task.value }
        let attempt = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            defer { self.task = nil }
            return await self.perform(trigger: trigger)
        }
        task = attempt
        return await attempt.value
    }

    var deferredUntil: Date? {
        guard manager.enrollmentDefaults.string(forKey: "managedEnrollmentDeferredDevice") == manager.enrollmentDeviceID else { return nil }
        return manager.enrollmentDefaults.object(forKey: "managedEnrollmentNotBefore") as? Date
    }

    private func deferralMessage(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
        formatter.timeStyle = .short
        return "Too many sign-in attempts from this network. Try again after \(formatter.string(from: date))."
    }

    private func perform(trigger: String) async -> Bool {
        hooks.setEnrolling(true)
        defer { hooks.setEnrolling(false) }
        let label = hooks.deviceLabel()
        let device = manager.enrollmentDeviceID
        let generation = manager.credentialGeneration
        let defaults = manager.enrollmentDefaults
        var path = "migrate"
        do {
            if manager.accessChoiceReason != "continueAfterReset",
               defaults.string(forKey: "managedMigrationIneligible") != device || manager.accessChoiceReason == "continue" {
                do {
                    try await manager.migrateLegacyDevice(label: label)
                    hooks.event("client_auth_migrated", .info, [:])
                } catch ClientAuthError.notEligibleForMigration {
                    guard manager.enrollmentDeviceID == device, manager.credentialGeneration == generation else { return false }
                    defaults.set(device, forKey: "managedMigrationIneligible")
                }
            }
            if !manager.isEnrolled {
                guard manager.enrollmentDeviceID == device, manager.credentialGeneration == generation else { return false }
                guard ["continue", "continueAfterReset"].contains(manager.accessChoiceReason ?? "") else {
                    manager.requireAccessChoice()
                    hooks.refreshStatus()
                    return false
                }
                path = "create"
                try await manager.createAccount(label: label, allowDeviceRotation: manager.accessChoiceReason == "continueAfterReset")
                hooks.event("client_auth_created", .info, [:])
            }
            hooks.setError(nil)
        } catch ClientAuthError.alreadyEnrolled {
            hooks.setError(nil)
        } catch ClientAuthError.rateLimited {
            guard manager.enrollmentDeviceID == device, manager.credentialGeneration == generation else { return false }
            let until = manager.enrollmentRetryAfter ?? Date().addingTimeInterval(60)
            defaults.set(until, forKey: "managedEnrollmentNotBefore")
            defaults.set(device, forKey: "managedEnrollmentDeferredDevice")
            hooks.setError(deferralMessage(until))
            hooks.event("client_auth_enrollment_deferred", .info, ["until": ISO8601DateFormatter().string(from: until)])
        } catch ClientAuthError.deviceAlreadyEnrolled {
            defaults.set(device, forKey: "managedMigrationIneligible")
            manager.requireAccessChoice(reason: "deviceAlreadyEnrolled")
            hooks.setError("This device already belongs to an account. Sign in to restore it, or choose to set up this device again.")
        } catch {
            hooks.setError(error.localizedDescription)
            hooks.log("Managed enrollment FAILED (\(path), trigger=\(trigger)): \(error.localizedDescription)")
            hooks.event("client_auth_enrollment_failed", .warning, ["path": path])
        }
        hooks.refreshStatus()
        return manager.isEnrolled
    }
}
