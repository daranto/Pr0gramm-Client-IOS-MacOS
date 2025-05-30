import Foundation
import Security
import os

/// A service for securely storing and retrieving sensitive data like session cookies and usernames using the iOS Keychain.
class KeychainService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "KeychainService")
    private let serviceName: String
    /// Internal key used to store the cookie expiration date as a timestamp, as `Date` objects are not directly serializable for Keychain storage.
    private let expiresDateTimestampKey = "expiresDateTimestamp"

    init() {
        // Use the app's bundle identifier to create a unique service name for Keychain isolation.
        guard let identifier = Bundle.main.bundleIdentifier else {
            fatalError("Could not retrieve bundle identifier for Keychain service.")
        }
        self.serviceName = identifier
        Self.logger.debug("KeychainService initialized with service name: \(self.serviceName)")
    }

    // MARK: - Cookie Handling

    /// Serializes HTTPCookie properties to Data and saves it securely in the Keychain.
    /// Converts the `expiresDate` (Date) to a `TimeInterval` (Double) before serialization.
    /// - Parameters:
    ///   - properties: The dictionary of cookie properties to save.
    ///   - key: The Keychain key under which to store the cookie data.
    /// - Returns: `true` if saving was successful, `false` otherwise.
    func saveCookieProperties(_ properties: [HTTPCookiePropertyKey: Any], forKey key: String) -> Bool {
        var serializableProperties = properties
        // Convert Date to TimeInterval (Double) for JSON serialization
        if let expiresDate = properties[HTTPCookiePropertyKey.expires] as? Date {
            let timestamp = expiresDate.timeIntervalSince1970
            serializableProperties[HTTPCookiePropertyKey(expiresDateTimestampKey)] = timestamp
            serializableProperties.removeValue(forKey: HTTPCookiePropertyKey.expires) // Remove original Date object
            Self.logger.debug("Converted expiresDate to timestamp: \(timestamp) for key: \(key)")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: serializableProperties, options: []) else {
            Self.logger.error("Failed to serialize cleaned cookie properties for key: \(key)")
            return false
        }
        return saveData(data, forKey: key)
    }

    /// Loads cookie properties data from the Keychain and deserializes it back into a dictionary.
    /// Converts the stored timestamp back into a `Date` object for the `expiresDate`.
    /// - Parameter key: The Keychain key from which to load the cookie data.
    /// - Returns: A dictionary of cookie properties if found and successfully deserialized, `nil` otherwise.
    func loadCookieProperties(forKey key: String) -> [HTTPCookiePropertyKey: Any]? {
        guard let retrievedData = loadData(forKey: key) else { return nil }
        guard let loadedDict = try? JSONSerialization.jsonObject(with: retrievedData, options: []) as? [String: Any] else {
            Self.logger.error("Failed to deserialize keychain data to dictionary for key: \(key)")
            return nil
        }

        var cookieProperties: [HTTPCookiePropertyKey: Any] = [:]
        for (stringKey, value) in loadedDict {
            let propertyKey = HTTPCookiePropertyKey(stringKey)
            // Convert timestamp back to Date
            if stringKey == expiresDateTimestampKey, let timestamp = value as? TimeInterval {
                let date = Date(timeIntervalSince1970: timestamp)
                cookieProperties[HTTPCookiePropertyKey.expires] = date
                Self.logger.debug("Converted timestamp back to expiresDate: \(date) for key: \(key)")
            } else {
                // Store other properties as they are
                cookieProperties[propertyKey] = value
            }
        }
        Self.logger.info("Successfully loaded and reconstructed cookie properties from keychain for key: \(key)")
        return cookieProperties
    }

    /// Deletes the cookie properties associated with the given key from the Keychain.
    /// - Parameter key: The Keychain key to delete.
    /// - Returns: `true` if deletion was successful or the item didn't exist, `false` on error.
    func deleteCookieProperties(forKey key: String) -> Bool {
        return deleteData(forKey: key)
    }

    // MARK: - Username Handling

    /// Saves a username string securely in the Keychain.
    /// - Parameters:
    ///   - username: The username string to save.
    ///   - key: The Keychain key under which to store the username.
    /// - Returns: `true` if saving was successful, `false` otherwise.
    func saveUsername(_ username: String, forKey key: String) -> Bool {
        guard let data = username.data(using: .utf8) else {
            Self.logger.error("Failed to encode username to data for key: \(key)")
            return false
        }
        return saveData(data, forKey: key)
    }

    /// Loads a username string from the Keychain.
    /// - Parameter key: The Keychain key from which to load the username.
    /// - Returns: The username string if found and successfully decoded, `nil` otherwise.
    func loadUsername(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        guard let username = String(data: data, encoding: .utf8) else {
            Self.logger.error("Failed to decode username data from keychain for key: \(key)")
            return nil
        }
        Self.logger.info("Successfully loaded username from keychain for key: \(key)")
        return username
    }

    /// Deletes the username associated with the given key from the Keychain.
    /// - Parameter key: The Keychain key to delete.
    /// - Returns: `true` if deletion was successful or the item didn't exist, `false` on error.
    func deleteUsername(forKey key: String) -> Bool {
        Self.logger.info("Deleting username from keychain for key: \(key)")
        return deleteData(forKey: key)
    }

    // MARK: - Private Generic Keychain Methods

    /// Generic function to save Data to the Keychain. Overwrites existing items with the same key.
    /// Sets item accessibility.
    /// - Parameters:
    ///   - data: The `Data` object to save.
    ///   - key: The Keychain key (account) to associate with the data.
    /// - Returns: `true` on success, `false` on failure.
    private func saveData(_ data: Data, forKey key: String) -> Bool {
        // Base query to identify the item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // Attempt to delete any existing item first to prevent add conflicts
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            Self.logger.warning("Failed to delete existing keychain item for key '\(key)' (Error: \(deleteStatus)). Continuing add attempt.")
        }

        // Prepare query for adding the new item
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // --- MODIFIED: Accessibility für Background-Zugriff ---
        // Daten sind zugänglich, nachdem das Gerät einmal entsperrt wurde, auch wenn es später gesperrt ist.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        Self.logger.info("Setting Keychain accessibility to kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly for key: \(key)")
        // --- END MODIFICATION ---

        // Add the item to the Keychain
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            Self.logger.info("Successfully saved data to keychain for key: \(key)")
            return true
        } else {
            Self.logger.error("Failed to save data to keychain for key '\(key)' (Error: \(addStatus))")
            // --- NEW: Log detailed error for kSecAttrAccessible ---
            if let osStatusError = addStatus as? OSStatus {
                 let errorDescription = SecCopyErrorMessageString(osStatusError, nil) as String? ?? "Unknown OSStatus error"
                 Self.logger.error("Detailed OSStatus error for keychain save failure: \(errorDescription) (Code: \(osStatusError))")
            }
            // --- END NEW ---
            return false
        }
    }

    /// Generic function to load Data from the Keychain.
    /// - Parameter key: The Keychain key (account) of the data to load.
    /// - Returns: The `Data` object if found, `nil` otherwise or on error.
    private func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            guard let retrievedData = dataTypeRef as? Data else {
                Self.logger.error("Failed to cast retrieved data for key: \(key)")
                return nil
            }
            Self.logger.info("Successfully loaded data from keychain for key: \(key)")
            return retrievedData
        } else if status == errSecItemNotFound {
            Self.logger.info("No data found in keychain for key: \(key)")
            return nil
        } else {
            Self.logger.error("Failed to load data from keychain for key '\(key)' (Error: \(status))")
             // --- NEW: Log detailed error for kSecAttrAccessible ---
            if let osStatusError = status as? OSStatus {
                 let errorDescription = SecCopyErrorMessageString(osStatusError, nil) as String? ?? "Unknown OSStatus error"
                 Self.logger.error("Detailed OSStatus error for keychain load failure: \(errorDescription) (Code: \(osStatusError))")
            }
            // --- END NEW ---
            return nil
        }
    }

    /// Generic function to delete Data from the Keychain.
    /// - Parameter key: The Keychain key (account) of the data to delete.
    /// - Returns: `true` if deletion succeeded or the item was not found, `false` on error.
    private func deleteData(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            Self.logger.info("Successfully deleted data from keychain for key: \(key)")
            return true
        } else if status == errSecItemNotFound {
            Self.logger.info("Attempted to delete data for key '\(key)', but item was not found.")
            return true
        } else {
            Self.logger.error("Failed to delete data from keychain for key '\(key)' (Error: \(status))")
             // --- NEW: Log detailed error for kSecAttrAccessible ---
            if let osStatusError = status as? OSStatus {
                 let errorDescription = SecCopyErrorMessageString(osStatusError, nil) as String? ?? "Unknown OSStatus error"
                 Self.logger.error("Detailed OSStatus error for keychain delete failure: \(errorDescription) (Code: \(osStatusError))")
            }
            // --- END NEW ---
            return false
        }
    }
}
