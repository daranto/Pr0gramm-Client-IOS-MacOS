// Pr0gramm/Pr0gramm/Shared/CacheService.swift
// --- START OF MODIFIED FILE ---

// Pr0gramm/Pr0gramm/Shared/CacheService.swift

import Foundation
import os

@MainActor // Wichtig für Updates von Published Properties, falls diese hier wären
class CacheService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CacheService")
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // --- GEÄNDERT: Keine festen Präfixe/Suffixe mehr hier ---
    // private let cacheFilePrefix = "feed_cache_"
    // private let cacheFileSuffix = ".json"
    private let cacheFileExtension = ".json" // Nur die Endung

    init() {
        guard let cacheBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Caches directory.")
        }
        // Erstelle ein Unterverzeichnis für unseren App-Cache, um Ordnung zu halten
        cacheDirectory = cacheBaseURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.daranto.Pr0gramm.datadiskcache", isDirectory: true) // Eindeutiger Name
        Self.logger.info("Cache directory set to: \(self.cacheDirectory.path)")

        // Stelle sicher, dass das Verzeichnis existiert
        createCacheDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    private func createCacheDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: cacheDirectory.path) else {
             Self.logger.debug("Cache directory already exists.")
             return
        }
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
            Self.logger.info("Successfully created cache directory.")
        } catch {
            Self.logger.error("Failed to create cache directory at \(self.cacheDirectory.path): \(error.localizedDescription)")
            // Optional: Handle error more gracefully, maybe disable caching?
        }
    }

    // MARK: - Cache File Operations

    /// Konstruiert den vollständigen Dateipfad für einen bestimmten Cache-Schlüssel.
    /// Stellt sicher, dass der Schlüssel für Dateinamen gültig ist.
    private func getCacheFileURL(forKey key: String) -> URL? {
        // Bereinige den Schlüssel, um ungültige Zeichen für Dateinamen zu entfernen/ersetzen
        let sanitizedKey = key.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        guard !sanitizedKey.isEmpty else {
            Self.logger.error("Cannot create cache file URL: Sanitized key is empty (Original: '\(key)')")
            return nil
        }
        let fileName = "\(sanitizedKey)\(cacheFileExtension)"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    /// Speichert ein Array von Items für einen bestimmten Schlüssel. Überschreibt vorhandene Daten.
    func saveItems(_ items: [Item], forKey key: String) async {
        guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not save cache for key '\(key)': Invalid file URL.")
            return
        }
        Self.logger.debug("Attempting to save \(items.count) items to cache file: \(fileURL.lastPathComponent) (Key: \(key))")

        // Kodierung muss im Hintergrund stattfinden
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
            Self.logger.debug("Successfully encoded \(items.count) items for key '\(key)'. Data size: \(data.count) bytes.")
        } catch {
            Self.logger.error("Failed to encode items for key '\(key)': \(error.localizedDescription)")
            return
        }

        // Schreiben im Hintergrund
        do {
            try data.write(to: fileURL, options: .atomic) // .atomic für sichereres Schreiben
            Self.logger.info("Successfully saved cache for key '\(key)' to \(fileURL.lastPathComponent).")
        } catch {
            Self.logger.error("Failed to write cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
        }
    }

    /// Lädt ein Array von Items für einen bestimmten Schlüssel aus dem Cache.
    func loadItems(forKey key: String) async -> [Item]? {
        guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not load cache for key '\(key)': Invalid file URL.")
            return nil
        }
        Self.logger.debug("Attempting to load items from cache file: \(fileURL.lastPathComponent) (Key: \(key))")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Cache file not found for key '\(key)'.")
            return nil
        }

        // Lesen und Dekodieren im Hintergrund
        do {
            let data = try Data(contentsOf: fileURL)
            Self.logger.debug("Read \(data.count) bytes from cache file \(fileURL.lastPathComponent).")
            let items = try JSONDecoder().decode([Item].self, from: data)
            Self.logger.info("Successfully loaded and decoded \(items.count) items for key '\(key)' from cache.")
            return items
        } catch {
            Self.logger.error("Failed to load or decode cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
            // Bei Fehler den korrupten Cache löschen?
            await clearCache(forKey: key) // Optional: Remove corrupted file
            return nil
        }
    }

    /// Löscht die Cache-Datei für einen bestimmten Schlüssel.
    func clearCache(forKey key: String) async {
         guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not clear cache for key '\(key)': Invalid file URL.")
            return
        }
        Self.logger.info("Attempting to clear cache file: \(fileURL.lastPathComponent) (Key: \(key))")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Cache file \(fileURL.lastPathComponent) (Key: \(key)) does not exist, nothing to clear.")
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            Self.logger.info("Successfully cleared cache file: \(fileURL.lastPathComponent) (Key: \(key))")
        } catch {
            Self.logger.error("Failed to clear cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
        }
    }

    /// Löscht alle Feed-Cache-Dateien (die mit "feed_" beginnen).
    func clearFeedCache() async {
        let prefix = "feed_" // Definiere den Präfix für Feed-Caches hier
        Self.logger.info("Attempting to clear all FEED cache files (prefix: '\(prefix)') in directory: \(self.cacheDirectory.path)")
        // --- KORRIGIERT: self. hinzugefügt ---
        await clearCacheFiles(matching: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Löscht alle Favoriten-Cache-Dateien (die mit "favorites_" beginnen).
    func clearFavoritesCache() async {
        let prefix = "favorites_" // Definiere den Präfix für Favoriten-Caches hier
        Self.logger.info("Attempting to clear all FAVORITES cache files (prefix: '\(prefix)') in directory: \(self.cacheDirectory.path)")
         // --- KORRIGIERT: self. hinzugefügt ---
        await clearCacheFiles(matching: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Löscht ALLE Cache-Dateien, die von diesem Service verwaltet werden (Endung .json im Verzeichnis).
    func clearAllDataCache() async {
        Self.logger.warning("Attempting to clear ALL data cache files (extension: '\(self.cacheFileExtension)') in directory: \(self.cacheDirectory.path)")
        // --- KORRIGIERT: self. hinzugefügt ---
        await clearCacheFiles(matching: { $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Interne Hilfsfunktion zum Löschen von Dateien basierend auf einem Prädikat.
    private func clearCacheFiles(matching predicate: (URL) -> Bool) async {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            let cacheFilesToDelete = fileURLs.filter(predicate)

            if cacheFilesToDelete.isEmpty {
                Self.logger.info("No cache files matching the criteria found to clear.")
                return
            }

            Self.logger.info("Found \(cacheFilesToDelete.count) cache files matching criteria to clear.")
            var clearedCount = 0
            for fileURL in cacheFilesToDelete {
                do {
                    try fileManager.removeItem(at: fileURL)
                    Self.logger.debug("Cleared cache file: \(fileURL.lastPathComponent)")
                    clearedCount += 1
                } catch {
                    Self.logger.error("Failed to clear cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Self.logger.info("Finished clearing cache. Cleared \(clearedCount) files matching criteria.")

        } catch {
            Self.logger.error("Failed to list contents of cache directory \(self.cacheDirectory.path) for clearing: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Size Calculation

    /// Berechnet die aktuelle Gesamtgröße aller .json Cache-Dateien in Bytes.
    func getCurrentDataCacheTotalSize() async -> Int64 {
        Self.logger.debug("Calculating total data cache size...")
        var totalSize: Int64 = 0
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            // Nur .json Dateien berücksichtigen, die von diesem Service stammen
            // --- KORRIGIERT: self. hinzugefügt ---
            let cacheFiles = fileURLs.filter { $0.pathExtension == self.cacheFileExtension.dropFirst() }

            for fileURL in cacheFiles {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    totalSize += attributes[.size] as? Int64 ?? 0
                } catch {
                    Self.logger.warning("Could not get size for file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Self.logger.info("Total calculated data cache size: \(totalSize) bytes.")
            return totalSize
        } catch {
            Self.logger.error("Failed to list contents or get attributes for data cache size calculation: \(error.localizedDescription)")
            return 0
        }
    }
}
// --- END OF MODIFIED FILE ---
