// Pr0gramm/Pr0gramm/Shared/CacheService.swift

import Foundation
import os

@MainActor // Wichtig für Updates von Published Properties, falls diese hier wären
class CacheService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CacheService")
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // Eindeutige Präfixe/Suffixe für Cache-Dateien
    private let cacheFilePrefix = "feed_cache_"
    private let cacheFileSuffix = ".json"

    init() {
        guard let cacheBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Caches directory.")
        }
        // Erstelle ein Unterverzeichnis für unseren App-Cache, um Ordnung zu halten
        cacheDirectory = cacheBaseURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.daranto.Pr0gramm.cache", isDirectory: true)
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

    /// Konstruiert den vollständigen Dateipfad für einen bestimmten Feed-Typ.
    private func getCacheFileURL(for feedType: FeedType) -> URL {
        let fileName = "\(cacheFilePrefix)\(feedType.rawValue)\(cacheFileSuffix)"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    /// Speichert ein Array von Items für einen bestimmten Feed-Typ. Überschreibt vorhandene Daten.
    func saveItems(_ items: [Item], for feedType: FeedType) async {
        let fileURL = getCacheFileURL(for: feedType)
        Self.logger.debug("Attempting to save \(items.count) items to cache file: \(fileURL.lastPathComponent)")

        // Kodierung muss im Hintergrund stattfinden
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
            Self.logger.debug("Successfully encoded \(items.count) items for feed \(feedType.displayName). Data size: \(data.count) bytes.")
        } catch {
            Self.logger.error("Failed to encode items for feed \(feedType.displayName): \(error.localizedDescription)")
            return
        }

        // Schreiben im Hintergrund
        do {
            try data.write(to: fileURL, options: .atomic) // .atomic für sichereres Schreiben
            Self.logger.info("Successfully saved cache for feed \(feedType.displayName) to \(fileURL.lastPathComponent).")
        } catch {
            Self.logger.error("Failed to write cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Lädt ein Array von Items für einen bestimmten Feed-Typ aus dem Cache.
    func loadItems(for feedType: FeedType) async -> [Item]? {
        let fileURL = getCacheFileURL(for: feedType)
        Self.logger.debug("Attempting to load items from cache file: \(fileURL.lastPathComponent)")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Cache file not found for feed \(feedType.displayName).")
            return nil
        }

        // Lesen und Dekodieren im Hintergrund
        do {
            let data = try Data(contentsOf: fileURL)
            Self.logger.debug("Read \(data.count) bytes from cache file \(fileURL.lastPathComponent).")
            let items = try JSONDecoder().decode([Item].self, from: data)
            Self.logger.info("Successfully loaded and decoded \(items.count) items for feed \(feedType.displayName) from cache.")
            return items
        } catch {
            Self.logger.error("Failed to load or decode cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
            // Bei Fehler den korrupten Cache löschen?
            await clearCache(for: feedType) // Optional: Remove corrupted file
            return nil
        }
    }

    /// Löscht die Cache-Datei für einen bestimmten Feed-Typ.
    func clearCache(for feedType: FeedType) async {
        let fileURL = getCacheFileURL(for: feedType)
        Self.logger.info("Attempting to clear cache file: \(fileURL.lastPathComponent)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Cache file \(fileURL.lastPathComponent) does not exist, nothing to clear.")
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            Self.logger.info("Successfully cleared cache file: \(fileURL.lastPathComponent)")
        } catch {
            Self.logger.error("Failed to clear cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Löscht alle Cache-Dateien, die von diesem Service verwaltet werden.
    func clearAllCache() async {
        Self.logger.info("Attempting to clear all cache files in directory: \(self.cacheDirectory.path)")
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            let cacheFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix(cacheFilePrefix) && $0.lastPathComponent.hasSuffix(cacheFileSuffix) }

            if cacheFiles.isEmpty {
                Self.logger.info("No cache files found to clear.")
                return
            }

            var clearedCount = 0
            for fileURL in cacheFiles {
                do {
                    try fileManager.removeItem(at: fileURL)
                    Self.logger.debug("Cleared cache file: \(fileURL.lastPathComponent)")
                    clearedCount += 1
                } catch {
                    Self.logger.error("Failed to clear cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Self.logger.info("Finished clearing cache. Cleared \(clearedCount) files.")

        } catch {
            Self.logger.error("Failed to list contents of cache directory \(self.cacheDirectory.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Size Calculation

    /// Berechnet die aktuelle Gesamtgröße aller Cache-Dateien in Bytes.
    func getCurrentCacheTotalSize() async -> Int64 {
        Self.logger.debug("Calculating total cache size...")
        var totalSize: Int64 = 0
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let cacheFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix(cacheFilePrefix) && $0.lastPathComponent.hasSuffix(cacheFileSuffix) }

            for fileURL in cacheFiles {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    totalSize += attributes[.size] as? Int64 ?? 0
                } catch {
                    Self.logger.warning("Could not get size for file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Self.logger.info("Total calculated cache size: \(totalSize) bytes.")
            return totalSize
        } catch {
            Self.logger.error("Failed to list contents or get attributes for cache size calculation: \(error.localizedDescription)")
            return 0
        }
    }

    // TODO: Implement cache pruning based on max size if needed later.
}
