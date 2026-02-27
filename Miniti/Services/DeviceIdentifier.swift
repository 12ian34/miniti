import Foundation
import Security

/// Manages a persistent device UUID stored in the macOS Keychain.
/// Survives app reinstalls (unlike UserDefaults), used as the "account" ID for managed mode.
enum DeviceIdentifier {
    private static let service = "com.miniti.device-id"
    private static let account = "device-uuid"
    
    /// Returns existing device ID or creates and persists a new one.
    static func getOrCreateDeviceId() -> String {
        if let existing = getFromKeychain() {
            return existing
        }
        let newId = UUID().uuidString
        saveToKeychain(newId)
        DebugLogger.shared.log(.app, "Created new device ID (\(newId.prefix(8))...)")
        return newId
    }
    
    /// Read the device ID without creating one (returns nil if not yet registered).
    static func existingDeviceId() -> String? {
        getFromKeychain()
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
    
    private static func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
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
        }
    }
}
