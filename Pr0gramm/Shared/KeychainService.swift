// KeychainService.swift

import Foundation
import Security
import os

/// Ein einfacher Wrapper für Keychain-Operationen zum Speichern und Laden von Daten (Cookie, Username).
class KeychainService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "KeychainService")
    private let serviceName: String
    private let expiresDateTimestampKey = "expiresDateTimestamp" // Interner Key für konvertiertes Datum

    init() {
        guard let identifier = Bundle.main.bundleIdentifier else {
            fatalError("Could not retrieve bundle identifier for Keychain service.")
        }
        self.serviceName = identifier
        Self.logger.debug("KeychainService initialized with service name: \(self.serviceName)")
    }

    // MARK: - Cookie Handling

    /// Speichert die Eigenschaften eines Cookies als Data im Keychain.
    /// Wandelt Date-Objekte vorher in Unix-Timestamps um.
    func saveCookieProperties(_ properties: [HTTPCookiePropertyKey: Any], forKey key: String) -> Bool {
        var serializableProperties = properties
        if let expiresDate = properties[HTTPCookiePropertyKey.expires] as? Date {
            let timestamp = expiresDate.timeIntervalSince1970
            serializableProperties[HTTPCookiePropertyKey(expiresDateTimestampKey)] = timestamp
            serializableProperties.removeValue(forKey: HTTPCookiePropertyKey.expires)
            Self.logger.debug("Converted expiresDate to timestamp: \(timestamp) for key: \(key)")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: serializableProperties, options: []) else {
            Self.logger.error("Failed to serialize cleaned cookie properties for key: \(key)")
            return false
        }
        return saveData(data, forKey: key)
    }

    /// Lädt die Cookie-Eigenschaften (als Dictionary) aus dem Keychain.
    /// Wandelt Timestamps zurück in Date-Objekte.
    func loadCookieProperties(forKey key: String) -> [HTTPCookiePropertyKey: Any]? {
        guard let retrievedData = loadData(forKey: key) else { return nil }
        guard let loadedDict = try? JSONSerialization.jsonObject(with: retrievedData, options: []) as? [String: Any] else {
            Self.logger.error("Failed to deserialize keychain data to dictionary for key: \(key)")
            return nil
        }
        var cookieProperties: [HTTPCookiePropertyKey: Any] = [:]
        for (stringKey, value) in loadedDict {
            let propertyKey = HTTPCookiePropertyKey(stringKey)
            if stringKey == expiresDateTimestampKey, let timestamp = value as? TimeInterval {
                let date = Date(timeIntervalSince1970: timestamp)
                cookieProperties[HTTPCookiePropertyKey.expires] = date
                Self.logger.debug("Converted timestamp back to expiresDate: \(date) for key: \(key)")
            } else {
                cookieProperties[propertyKey] = value
            }
        }
        Self.logger.info("Successfully loaded and reconstructed cookie properties from keychain for key: \(key)")
        return cookieProperties
    }

    /// Löscht die Cookie-Eigenschaften aus dem Keychain.
    func deleteCookieProperties(forKey key: String) -> Bool {
        return deleteData(forKey: key)
    }

    // MARK: - Username Handling

    /// Speichert den Benutzernamen sicher im Keychain.
    func saveUsername(_ username: String, forKey key: String) -> Bool {
        guard let data = username.data(using: .utf8) else {
            Self.logger.error("Failed to encode username to data for key: \(key)")
            return false
        }
        return saveData(data, forKey: key)
    }

    /// Lädt den Benutzernamen aus dem Keychain.
    func loadUsername(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        guard let username = String(data: data, encoding: .utf8) else {
            Self.logger.error("Failed to decode username data from keychain for key: \(key)")
            return nil
        }
        Self.logger.info("Successfully loaded username from keychain for key: \(key)") // Log hinzugefügt
        return username
    }

    /// Löscht den Benutzernamen aus dem Keychain.
    func deleteUsername(forKey key: String) -> Bool {
        Self.logger.info("Deleting username from keychain for key: \(key)") // Log hinzugefügt
        return deleteData(forKey: key)
    }

    // MARK: - Private generische Keychain-Methoden

    private func saveData(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: key ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound { Self.logger.warning("Failed to delete existing keychain item for key '\(key)' (Error: \(deleteStatus)).") }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { Self.logger.info("Successfully saved data to keychain for key: \(key)"); return true }
        else { Self.logger.error("Failed to save data to keychain for key '\(key)' (Error: \(addStatus))"); return false }
    }

    private func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: key, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess {
            guard let retrievedData = dataTypeRef as? Data else { Self.logger.error("Failed to cast retrieved data for key: \(key)"); return nil }
            Self.logger.info("Successfully loaded data from keychain for key: \(key)")
            return retrievedData
        } else if status == errSecItemNotFound { Self.logger.info("No data found in keychain for key: \(key)"); return nil
        } else { Self.logger.error("Failed to load data from keychain for key '\(key)' (Error: \(status))"); return nil }
    }

    private func deleteData(forKey key: String) -> Bool {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: key ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess { Self.logger.info("Successfully deleted data from keychain for key: \(key)"); return true }
        else if status == errSecItemNotFound { Self.logger.info("Attempted to delete data for key '\(key)', but item was not found."); return true } // Nicht gefunden ist auch OK
        else { Self.logger.error("Failed to delete data from keychain for key '\(key)' (Error: \(status))"); return false }
    }
}
