import Foundation
import Security

/// A simple helper class for interacting with the iOS Keychain.
final class KeychainHelper {

    static let standard = KeychainHelper()

    private init() {}

    /// Saves a string to the Keychain.
    /// - Parameters:
    ///   - string: The string to save.
    ///   - service: The service name (usually the app bundle ID).
    ///   - account: The account name or key.
    func save(_ string: String, service: String, account: String) {
        guard let data = string.data(using: .utf8) else { return }

        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [CFString: Any]

        // Delete any existing item before adding a new one
        SecItemDelete(query as CFDictionary)

        // Add the new item
        var addQuery = query
        addQuery[kSecValueData] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error saving to Keychain: \(status)")
        }
    }

    /// Reads a string from the Keychain.
    /// - Parameters:
    ///   - service: The service name.
    ///   - account: The account name or key.
    /// - Returns: The stored string, or nil if not found.
    func read(service: String, account: String) -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes a string from the Keychain.
    /// - Parameters:
    ///   - service: The service name.
    ///   - account: The account name or key.
    func delete(service: String, account: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [CFString: Any]

        SecItemDelete(query as CFDictionary)
    }
}
