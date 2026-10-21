import Foundation
import Security

// MARK: - Keychain backend

/// The four Security.framework calls the app's two keychain items use, behind a protocol so
/// tests can run the storage policy against a fake instead of the Mac's own keychain.
protocol KeychainBackend: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SecurityKeychainBackend: KeychainBackend {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// One generic-password item (the device id, the managed credential) and where it lives.
///
/// The data protection keychain (`kSecUseDataProtectionKeychain`) is preferred: access is by
/// team and bundle id, so a differently signed build never prompts. On macOS it needs the
/// `com.apple.application-identifier` entitlement, which a Developer ID build only carries with
/// a provisioning profile; miniti's release build has none, so every write there fails with
/// `errSecMissingEntitlement` (-34018) and reads answer "not found". 3.2.1 assumed the data
/// protection keychain always worked, deleted the login-keychain device id before the new write
/// and left every Mac on a fresh identity at the second launch (docs/distribution.md). So:
///
/// - reads try the data protection keychain, then (macOS) the login keychain;
/// - a login-keychain item is moved only after the data protection add succeeded;
/// - writes update in place (the item keeps its access list, so an Always Allow sticks) and
///   fall back to the login keychain when the data protection keychain refuses;
/// - nothing is deleted until its replacement exists.
final class KeychainSlot: @unchecked Sendable {
    enum ReadResult: Equatable {
        case found(Data)
        case missing
        case unreadable(OSStatus)
    }

    static let missingEntitlement: OSStatus = -34018  // errSecMissingEntitlement

    let service: String
    let account: String
    private let accessible: CFString
    private let synchronizable: Bool?
    private let backend: KeychainBackend
    private let lock = NSLock()
    private var loggedUnavailable = false

    init(service: String, account: String, accessible: CFString, synchronizable: Bool? = nil, backend: KeychainBackend = SecurityKeychainBackend()) {
        self.service = service
        self.account = account
        self.accessible = accessible
        self.synchronizable = synchronizable
        self.backend = backend
    }

    private func query(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let synchronizable { query[kSecAttrSynchronizable as String] = synchronizable }
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    private func read(dataProtection: Bool) -> ReadResult {
        var query = query(dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = backend.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data else { return .unreadable(status) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .unreadable(status)
        }
    }

    /// Update in place, add when absent. Returns the Security status of the attempt that decided.
    private func upsert(_ data: Data, dataProtection: Bool) -> OSStatus {
        let status = backend.update(query(dataProtection: dataProtection), [kSecValueData as String: data])
        guard status == errSecItemNotFound else { return status }
        var add = query(dataProtection: dataProtection)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        return backend.add(add)
    }

    private func noteUnavailable(_ status: OSStatus) {
        lock.lock(); defer { lock.unlock() }
        guard !loggedUnavailable else { return }
        loggedUnavailable = true
        DebugLogger.shared.log(.app, "keychain_data_protection_unavailable service=\(service) status=\(status); using the login keychain")
    }

    func read() -> ReadResult {
        let primary = read(dataProtection: true)
        if case .found = primary { return primary }
        #if os(macOS)
        let legacy = read(dataProtection: false)
        if case .found(let data) = legacy {
            if case .missing = primary {
                let moved = upsert(data, dataProtection: true)
                if moved == errSecSuccess {
                    _ = backend.delete(query(dataProtection: false))
                    DebugLogger.shared.log(.app, "keychain_item_moved service=\(service)")
                } else {
                    noteUnavailable(moved)
                }
            }
            return legacy
        }
        if case .unreadable(let status) = primary, status == Self.missingEntitlement {
            // This build cannot use the data protection keychain at all: the login keychain's
            // answer is the real one.
            return legacy
        }
        #endif
        return primary
    }

    func write(_ data: Data) -> Bool {
        let primary = upsert(data, dataProtection: true)
        if primary == errSecSuccess {
            #if os(macOS)
            _ = backend.delete(query(dataProtection: false))
            #endif
            return true
        }
        #if os(macOS)
        noteUnavailable(primary)
        let fallback = upsert(data, dataProtection: false)
        if fallback != errSecSuccess {
            DebugLogger.shared.log(.app, "keychain_write_failed service=\(service) status=\(fallback)")
        }
        return fallback == errSecSuccess
        #else
        DebugLogger.shared.log(.app, "keychain_write_failed service=\(service) status=\(primary)")
        return false
        #endif
    }

    func delete() {
        _ = backend.delete(query(dataProtection: true))
        #if os(macOS)
        _ = backend.delete(query(dataProtection: false))
        #endif
    }
}

// MARK: - Device identifier

/// Manages a persistent device UUID stored in the Apple Keychain.
/// Survives app reinstalls (unlike UserDefaults), used as the "account" ID for managed mode.
enum DeviceIdentifier {
    private static let service = "com.miniti.device-id"
    private static let account = "device-uuid"
    private static let fallbackDefaultsKey = "device-uuid-fallback"
    private static let keychainLock = NSLock()
    /// Accessible after first unlock so it works during login. Tests swap in a fake backend.
    nonisolated(unsafe) static var slot = KeychainSlot(service: service, account: account, accessible: kSecAttrAccessibleAfterFirstUnlock)
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    // Every access is serialized by keychainLock. Cache the successful resolution
    // so routine API calls do not repeatedly cross into Security.framework.
    nonisolated(unsafe) private static var cachedDeviceId: String?
    /// Identity used while the Keychain item exists but cannot be read (locked, ACL
    /// prompt pending, transient Security error). Never persisted: the next successful
    /// read restores the real ID. Minting and saving a new ID here would silently
    /// replace the device identity, which also disconnects Google Calendar, CRM and
    /// managed usage on the backend (2026-09-25).
    nonisolated(unsafe) private static var sessionOnlyDeviceId: String?
    
    enum KeychainReadResult {
        case found(String)
        case missing
        case unreadable(OSStatus)
    }

    /// What to do when no ID could be read from the Keychain.
    enum MissingIDResolution: Equatable {
        /// Reuse the UserDefaults fallback (persist it to the Keychain only if the item is absent).
        case useFallback
        /// The item is genuinely absent: create a new ID and persist it.
        case createAndPersist
        /// The item may exist but is unreadable right now: use a session-only ID, write nothing.
        case sessionOnly
    }

    /// True while the app is running on a session-only ID because the Keychain item could
    /// not be read. Callers that would bind durable state to the device identity (managed
    /// enrollment, backend-keyed integrations) should wait rather than proceed.
    static var isUsingSessionOnlyID: Bool {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        return cachedDeviceId == nil && sessionOnlyDeviceId != nil
    }

    nonisolated static func resolution(afterReadStatus status: OSStatus, hasFallback: Bool) -> MissingIDResolution {
        if hasFallback { return .useFallback }
        return status == errSecItemNotFound ? .createAndPersist : .sessionOnly
    }
    
    /// Returns existing device ID or creates and persists a new one.
    static func getOrCreateDeviceId() -> String {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        if let cachedDeviceId { return cachedDeviceId }
        let readStatus: OSStatus
        switch getFromKeychain() {
        case .found(let existing):
            clearFallbackFromDefaults()
            if sessionOnlyDeviceId != nil {
                DebugLogger.shared.log(.app, "device_id_keychain_recovered")
                sessionOnlyDeviceId = nil
            }
            cachedDeviceId = existing
            return existing
        case .missing:
            readStatus = errSecItemNotFound
        case .unreadable(let status):
            readStatus = status
        }
        let fallback = getFromDefaultsFallback()
        switch resolution(afterReadStatus: readStatus, hasFallback: fallback != nil) {
        case .useFallback:
            let fallback = fallback!
            if readStatus == errSecItemNotFound, saveToKeychain(fallback) {
                clearFallbackFromDefaults()
            } else {
                DebugLogger.shared.log(.app, "Using fallback device ID because keychain persistence is unavailable (status=\(readStatus))")
            }
            cachedDeviceId = fallback
            return fallback
        case .createAndPersist:
            let newId = UUID().uuidString
            if saveToKeychain(newId) {
                clearFallbackFromDefaults()
            } else {
                saveToDefaultsFallback(newId)
                DebugLogger.shared.log(.app, "Persisted fallback device ID in UserDefaults because keychain save failed")
            }
            DebugLogger.shared.log(.app, "Created new device ID (\(newId.prefix(8))...)")
            cachedDeviceId = newId
            return newId
        case .sessionOnly:
            if let sessionOnlyDeviceId { return sessionOnlyDeviceId }
            let temporary = UUID().uuidString
            sessionOnlyDeviceId = temporary
            DebugLogger.shared.log(.app, "device_id_keychain_unreadable status=\(readStatus); using a session-only ID until the keychain item can be read")
            return temporary
        }
    }
    
    /// Read the device ID without creating one (returns nil if not yet registered).
    static func existingDeviceId() -> String? {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        if let cachedDeviceId { return cachedDeviceId }
        let existing: String?
        if case .found(let value) = getFromKeychain() {
            existing = value
        } else {
            existing = getFromDefaultsFallback()
        }
        cachedDeviceId = existing
        return existing
    }
    
    /// Replace the device identity with a fresh UUID. Only for the case where the server
    /// already holds an installation under the current id with a key this device does not
    /// have (`device_already_enrolled` on create). Persisted the same way as a first id, so
    /// the old backend records (usage, calendar, CRM, enrollment) are simply left behind.
    static func rotate() -> String {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        let previous = cachedDeviceId ?? sessionOnlyDeviceId ?? "none"
        let newId = UUID().uuidString
        if saveToKeychain(newId) {
            clearFallbackFromDefaults()
        } else {
            saveToDefaultsFallback(newId)
            DebugLogger.shared.log(.app, "Persisted rotated device ID in UserDefaults because keychain save failed")
        }
        sessionOnlyDeviceId = nil
        cachedDeviceId = newId
        DebugLogger.shared.log(.app, "device_id_rotated from=\(previous.prefix(8))... to=\(newId.prefix(8))...")
        return newId
    }

    /// Make `id` this install's identity because something more authoritative than the Keychain
    /// item names it: the managed access token is issued to one device id, and the server binds
    /// this installation key to that id. 3.2.1 lost the Keychain item while the credential
    /// survived, so the app minted a fresh id and every request was answered `device_mismatch`.
    /// Refused (returns false) while the real item exists but cannot be read, since a locked
    /// Keychain is not a lost one.
    @discardableResult
    static func adopt(_ id: String, reason: String) -> Bool {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        if cachedDeviceId == nil, sessionOnlyDeviceId != nil {
            DebugLogger.shared.log(.app, "device_id_adopt_deferred reason=\(reason); keychain item unreadable")
            return false
        }
        if let cachedDeviceId, cachedDeviceId.caseInsensitiveCompare(id) == .orderedSame { return true }
        let previous = cachedDeviceId ?? "none"
        if saveToKeychain(id) {
            clearFallbackFromDefaults()
        } else {
            saveToDefaultsFallback(id)
            DebugLogger.shared.log(.app, "Persisted adopted device ID in UserDefaults because keychain save failed")
        }
        cachedDeviceId = id
        DebugLogger.shared.log(.app, "device_id_adopted reason=\(reason) from=\(previous.prefix(8))... to=\(id.prefix(8))...")
        return true
    }

    /// Forget the in-memory resolution so the next call reads storage again (tests only).
    static func resetForTesting() {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        cachedDeviceId = nil
        sessionOnlyDeviceId = nil
    }
    
    // MARK: - Keychain Operations

    private static func getFromKeychain() -> KeychainReadResult {
        switch slot.read() {
        case .found(let data):
            guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return .unreadable(errSecDecode) }
            return .found(string)
        case .missing:
            return .missing
        case .unreadable(let status):
            return .unreadable(status)
        }
    }

    private static func saveToKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return slot.write(data)
    }

    private static func getFromDefaultsFallback() -> String? {
        let value = defaults.string(forKey: fallbackDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func saveToDefaultsFallback(_ value: String) {
        defaults.set(value, forKey: fallbackDefaultsKey)
    }

    private static func clearFallbackFromDefaults() {
        defaults.removeObject(forKey: fallbackDefaultsKey)
    }
}
