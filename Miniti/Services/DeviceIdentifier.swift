import Foundation
import Security

/// Manages a persistent device UUID stored in the macOS Keychain.
/// Survives app reinstalls (unlike UserDefaults), used as the "account" ID for managed mode.
enum DeviceIdentifier {
    private static let service = "com.miniti.device-id"
    private static let account = "device-uuid"
    private static let fallbackDefaultsKey = "device-uuid-fallback"
    
    /// Returns existing device ID or creates and persists a new one.
    static func getOrCreateDeviceId() -> String {
        if let existing = getFromKeychain() {
            clearFallbackFromDefaults()
            return existing
        }
        if let fallback = getFromDefaultsFallback() {
            if saveToKeychain(fallback) {
                clearFallbackFromDefaults()
            } else {
                DebugLogger.shared.log(.app, "Using fallback device ID because keychain persistence is unavailable")
            }
            return fallback
        }
        let newId = UUID().uuidString
        if saveToKeychain(newId) {
            clearFallbackFromDefaults()
        } else {
            saveToDefaultsFallback(newId)
            DebugLogger.shared.log(.app, "Persisted fallback device ID in UserDefaults because keychain save failed")
        }
        DebugLogger.shared.log(.app, "Created new device ID (\(newId.prefix(8))...)")
        return newId
    }
    
    /// Read the device ID without creating one (returns nil if not yet registered).
    static func existingDeviceId() -> String? {
        getFromKeychain() ?? getFromDefaultsFallback()
    }
    
    // MARK: - Keychain Operations
    
    private static func getFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
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
