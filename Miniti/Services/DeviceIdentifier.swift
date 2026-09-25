import Foundation
import Security

/// Manages a persistent device UUID stored in the Apple Keychain.
/// Survives app reinstalls (unlike UserDefaults), used as the "account" ID for managed mode.
enum DeviceIdentifier {
    private static let service = "com.miniti.device-id"
    private static let account = "device-uuid"
    private static let fallbackDefaultsKey = "device-uuid-fallback"
    private static let keychainLock = NSLock()
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
    
    // MARK: - Keychain Operations
    
    private static func getFromKeychain() -> KeychainReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                return .unreadable(status)
            }
            return .found(string)
        case errSecItemNotFound:
            return .missing
        default:
            return .unreadable(status)
        }
    }
    
    private static func saveToKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item — accessible after first unlock so it works during login
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            DebugLogger.shared.log(.app, "Device ID keychain save FAILED: status=\(status)")
            return false
        }
        return true
    }

    private static func getFromDefaultsFallback() -> String? {
        let value = UserDefaults.standard.string(forKey: fallbackDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func saveToDefaultsFallback(_ value: String) {
        UserDefaults.standard.set(value, forKey: fallbackDefaultsKey)
    }

    private static func clearFallbackFromDefaults() {
        UserDefaults.standard.removeObject(forKey: fallbackDefaultsKey)
    }
}
