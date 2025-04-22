// KeychainService.swift

import Foundation
import Security
import os

class KeychainService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "KeychainService")
    private let serviceName: String

    // NEU: Key für den umgewandelten Timestamp
    private let expiresDateTimestampKey = "expiresDateTimestamp"

    init() {
        guard let identifier = Bundle.main.bundleIdentifier else { fatalError("...") }
        self.serviceName = identifier
        Self.logger.debug("KeychainService initialized...")
    }

    /// Speichert die Eigenschaften eines Cookies als Data im Keychain.
    /// Wandelt Date-Objekte vorher in Unix-Timestamps um.
    func saveCookieProperties(_ properties: [HTTPCookiePropertyKey: Any], forKey key: String) -> Bool {

        // 1. Kopiere die Properties und konvertiere Date -> Timestamp
        var serializableProperties = properties // Kopie erstellen
        if let expiresDate = properties[HTTPCookiePropertyKey.expires] as? Date {
            let timestamp = expiresDate.timeIntervalSince1970
            serializableProperties[HTTPCookiePropertyKey(expiresDateTimestampKey)] = timestamp // Timestamp unter neuem Key speichern
            serializableProperties.removeValue(forKey: HTTPCookiePropertyKey.expires) // Original-Date entfernen
            Self.logger.debug("Converted expiresDate to timestamp: \(timestamp) for key: \(key)")
        }

        // 2. Konvertiere das BEREINIGTE Dictionary in Data
        guard let data = try? JSONSerialization.data(withJSONObject: serializableProperties, options: []) else {
            Self.logger.error("Failed to serialize cleaned cookie properties for key: \(key)")
            return false
        }

        // 3. Keychain Query (wie zuvor)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // 4. Vorhandenes Item löschen (wie zuvor)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            Self.logger.warning("Failed to delete existing keychain item for key '\(key)' (Error: \(deleteStatus)). Proceeding...")
        }

        // 5. Neues Item hinzufügen (wie zuvor, aber mit konvertierten Daten)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            Self.logger.info("Successfully saved cleaned cookie properties to keychain for key: \(key)")
            return true
        } else {
            Self.logger.error("Failed to save cleaned cookie properties to keychain for key '\(key)' (Error: \(addStatus))")
            return false
        }
    }

    /// Lädt die Cookie-Eigenschaften aus dem Keychain und wandelt Timestamps zurück in Date-Objekte.
    func loadCookieProperties(forKey key: String) -> [HTTPCookiePropertyKey: Any]? {
        // 1. Query (wie zuvor)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // 2. Suche (wie zuvor)
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        // 3. Ergebnis auswerten
        if status == errSecSuccess {
            guard let retrievedData = dataTypeRef as? Data else { /* Log Error */ return nil }

            // 4. Deserialisieren (wie zuvor)
            guard let loadedDict = try? JSONSerialization.jsonObject(with: retrievedData, options: []) as? [String: Any] else {
                Self.logger.error("Failed to deserialize keychain data for key: \(key)")
                return nil
            }

            // 5. Konvertiere [String: Any] zu [HTTPCookiePropertyKey: Any] UND wandle Timestamp zurück
            var cookieProperties: [HTTPCookiePropertyKey: Any] = [:]
            for (stringKey, value) in loadedDict {
                let propertyKey = HTTPCookiePropertyKey(stringKey)

                // Prüfe, ob es unser spezieller Timestamp-Key ist
                if stringKey == expiresDateTimestampKey, let timestamp = value as? TimeInterval {
                    let date = Date(timeIntervalSince1970: timestamp)
                    cookieProperties[HTTPCookiePropertyKey.expires] = date // Füge als .expires Date hinzu
                    Self.logger.debug("Converted timestamp back to expiresDate: \(date) for key: \(key)")
                } else {
                    // Übernehme andere Werte direkt
                    cookieProperties[propertyKey] = value
                }
            }

            Self.logger.info("Successfully loaded and reconstructed cookie properties from keychain for key: \(key)")
            return cookieProperties

        } else if status == errSecItemNotFound { /* Log Info */ return nil
        } else { /* Log Error */ return nil }
    }

    /// Löscht die Cookie-Eigenschaften aus dem Keychain. (Unverändert)
    func deleteCookieProperties(forKey key: String) -> Bool {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: key ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { /* Log Info/Success */ return true }
        else { /* Log Error */ return false }
    }
}
