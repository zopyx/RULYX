import Foundation
import Security

/// Errors that can occur during Keychain operations.
enum KeychainError: Error {
    /// The Keychain operation returned an unexpected OSStatus.
    case unexpectedStatus(OSStatus)
    /// The data retrieved from the Keychain could not be decoded as a UTF-8 string.
    case invalidData
}

/// Provides secure credential storage via the iOS Keychain (Security framework).
/// Implementations handle save, read, and delete operations for generic passwords
/// using service/account key pairs.
protocol KeychainServicing: Sendable {
    /// Saves a string value to the Keychain, replacing any existing entry
    /// for the same service and account combination.
    /// - Parameters:
    ///   - value: The string value to store.
    ///   - service: The Keychain service identifier (e.g. `"com.ajung.RULYX.session"`).
    ///   - account: The account identifier associated with this value.
    /// - Throws: `KeychainError.unexpectedStatus` if the save operation fails.
    func save(_ value: String, service: String, account: String) throws

    /// Reads a string value from the Keychain.
    /// - Parameters:
    ///   - service: The Keychain service identifier.
    ///   - account: The account identifier associated with the value.
    /// - Returns: The stored string if found, or `nil` if no entry exists.
    /// - Throws: `KeychainError.unexpectedStatus` or `KeychainError.invalidData` if reading fails or data is corrupt.
    func read(service: String, account: String) throws -> String?

    /// Deletes an entry from the Keychain.
    /// - Parameters:
    ///   - service: The Keychain service identifier.
    ///   - account: The account identifier associated with the value.
    /// - Throws: `KeychainError.unexpectedStatus` if deletion fails for a reason other than "not found".
    func delete(service: String, account: String) throws
}

final class KeychainService: KeychainServicing, @unchecked Sendable {
    func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
