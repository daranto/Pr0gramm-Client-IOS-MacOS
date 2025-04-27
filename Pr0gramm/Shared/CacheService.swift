import Foundation
import os

/// Provides services for saving, loading, and managing structured data (like `[Item]`) in a dedicated disk cache directory.
/// Handles cache size enforcement using an LRU (Least Recently Used) strategy for the data cache.
@MainActor
class CacheService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CacheService")
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let cacheFileExtension = ".json"
    /// The maximum size allowed for the data cache directory (feeds, favorites etc.) in bytes.
    private let maxDataCacheSizeBytes: Int64 = 50 * 1024 * 1024 // 50 MB

    init() {
        // Determine the base cache directory URL
        guard let cacheBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("CacheService Error: Could not access Caches directory.")
        }

        // Get the bundle identifier to create a unique subdirectory
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError("CacheService Error: Could not retrieve Bundle Identifier. Check project configuration.")
        }

        // Construct the full path for the data cache directory
        cacheDirectory = cacheBaseURL.appendingPathComponent(bundleIdentifier + ".datadiskcache", isDirectory: true)

        Self.logger.info("Data cache directory set to: \(self.cacheDirectory.path)")
        Self.logger.info("Data cache max size set to: \(self.maxDataCacheSizeBytes / (1024 * 1024)) MB")
        createCacheDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    /// Creates the cache directory if it doesn't already exist.
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
        }
    }

    // MARK: - Cache File Operations

    /// Generates a sanitized file URL within the cache directory for a given key.
    /// Replaces non-alphanumeric characters (except '-' and '_') in the key with underscores.
    /// - Parameter key: The cache key.
    /// - Returns: A valid file URL or `nil` if the sanitized key is empty.
    private func getCacheFileURL(forKey key: String) -> URL? {
        let sanitizedKey = key.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        guard !sanitizedKey.isEmpty else {
            Self.logger.error("Cannot create cache file URL: Sanitized key is empty (Original: '\(key)')")
            return nil
        }
        let fileName = "\(sanitizedKey)\(cacheFileExtension)"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    /// Encodes an array of `Item` objects to JSON and saves it to a file in the cache directory.
    /// Enforces the cache size limit after saving.
    /// - Parameters:
    ///   - items: The items to save.
    ///   - key: The cache key to associate with these items.
    func saveItems(_ items: [Item], forKey key: String) async {
        guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not save cache for key '\(key)': Invalid file URL.")
            return
        }
        Self.logger.debug("Attempting to save \(items.count) items to data cache file: \(fileURL.lastPathComponent) (Key: \(key))")

        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            Self.logger.error("Failed to encode items for key '\(key)': \(error.localizedDescription)")
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic) // Atomic write for safety
            Self.logger.info("Successfully saved data cache for key '\(key)' to \(fileURL.lastPathComponent).")
            await enforceSizeLimit() // Check and potentially prune cache after saving
        } catch {
            Self.logger.error("Failed to write data cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
        }
    }

    /// Loads and decodes an array of `Item` objects from a cache file associated with the given key.
    /// Updates the file's modification date upon successful loading (for LRU).
    /// Deletes the cache file if loading or decoding fails.
    /// - Parameter key: The cache key for the items to load.
    /// - Returns: An array of `Item` objects if found and valid, otherwise `nil`.
    func loadItems(forKey key: String) async -> [Item]? {
        guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not load cache for key '\(key)': Invalid file URL.")
            return nil
        }
        Self.logger.debug("Attempting to load items from data cache file: \(fileURL.lastPathComponent) (Key: \(key))")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Data cache file not found for key '\(key)'.")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let items = try JSONDecoder().decode([Item].self, from: data)
            Self.logger.info("Successfully loaded and decoded \(items.count) items for key '\(key)' from data cache.")
            updateFileAccessDate(for: fileURL) // Mark as recently used
            return items
        } catch {
            Self.logger.error("Failed to load or decode data cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
            // Corrupted cache file, remove it
            await clearCache(forKey: key)
            return nil
        }
    }

    /// Deletes the cache file associated with the given key.
    /// - Parameter key: The cache key of the file to delete.
    func clearCache(forKey key: String) async {
         guard let fileURL = getCacheFileURL(forKey: key) else {
            Self.logger.error("Could not clear cache for key '\(key)': Invalid file URL.")
            return
        }
        Self.logger.info("Attempting to clear data cache file: \(fileURL.lastPathComponent) (Key: \(key))")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.logger.info("Cache file \(fileURL.lastPathComponent) (Key: \(key)) does not exist, nothing to clear.")
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            Self.logger.info("Successfully cleared data cache file: \(fileURL.lastPathComponent) (Key: \(key))")
        } catch {
            Self.logger.error("Failed to clear data cache file \(fileURL.lastPathComponent) (Key: \(key)): \(error.localizedDescription)")
        }
    }

    /// Clears all cache files starting with the "feed_" prefix.
    func clearFeedCache() async {
        let prefix = "feed_"
        Self.logger.info("Attempting to clear all FEED cache files (prefix: '\(prefix)') in directory: \(self.cacheDirectory.path)")
        await clearCacheFiles(matching: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Clears all cache files starting with the "favorites_" prefix.
    func clearFavoritesCache() async {
        let prefix = "favorites_"
        Self.logger.info("Attempting to clear all FAVORITES cache files (prefix: '\(prefix)') in directory: \(self.cacheDirectory.path)")
        await clearCacheFiles(matching: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Clears all `.json` files within the data cache directory.
    func clearAllDataCache() async {
        Self.logger.warning("Attempting to clear ALL data cache files (extension: '\(self.cacheFileExtension)') in directory: \(self.cacheDirectory.path)")
        await clearCacheFiles(matching: { $0.pathExtension == self.cacheFileExtension.dropFirst() })
    }

    /// Helper function to delete cache files matching a specific predicate.
    /// - Parameter predicate: A closure that takes a file URL and returns `true` if the file should be deleted.
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

    // MARK: - Cache Size Calculation & Management

    /// Calculates the total size of all `.json` files in the data cache directory.
    /// - Returns: The total size in bytes.
    func getCurrentDataCacheTotalSize() async -> Int64 {
        Self.logger.debug("Calculating total data cache size...")
        var totalSize: Int64 = 0
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let cacheFiles = fileURLs.filter { $0.pathExtension == self.cacheFileExtension.dropFirst() }

            for fileURL in cacheFiles {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    totalSize += attributes[.size] as? Int64 ?? 0
                } catch {
                    Self.logger.warning("Could not get size for data file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Self.logger.info("Total calculated data cache size: \(totalSize) bytes.")
            return totalSize
        } catch {
            Self.logger.error("Failed to list contents or get attributes for data cache size calculation: \(error.localizedDescription)")
            return 0
        }
    }

    /// Updates the modification date of a file to the current time. Used for LRU cache eviction.
    /// - Parameter fileURL: The URL of the file to update.
    private func updateFileAccessDate(for fileURL: URL) {
        do {
            // Setting modification date effectively marks it as "just accessed"
            let attributes = [FileAttributeKey.modificationDate: Date()]
            try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
            Self.logger.trace("Updated access date for data cache file: \(fileURL.lastPathComponent)")
        } catch {
            Self.logger.warning("Failed to update access date for data cache file \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Checks if the current data cache size exceeds the `maxDataCacheSizeBytes` limit.
    /// If exceeded, it deletes the oldest files (based on modification date) until the size is within the limit (LRU).
    private func enforceSizeLimit() async {
        Self.logger.debug("Enforcing data cache size limit (\(self.maxDataCacheSizeBytes / (1024*1024)) MB)...")
        var currentSize: Int64 = 0
        var filesWithSizeAndDate: [(url: URL, size: Int64, date: Date)] = []

        do {
            // Get all cache files with their size and modification date
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            let cacheFiles = fileURLs.filter { $0.pathExtension == self.cacheFileExtension.dropFirst() }

            for fileURL in cacheFiles {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let modDate = attributes[.modificationDate] as? Date ?? Date.distantPast // Use distantPast if date missing
                    currentSize += fileSize
                    filesWithSizeAndDate.append((url: fileURL, size: fileSize, date: modDate))
                } catch { Self.logger.warning("Could not get attributes for data cache file \(fileURL.lastPathComponent) during size enforcement.") }
            }

            Self.logger.debug("Current data cache size: \(currentSize / (1024*1024)) MB (\(filesWithSizeAndDate.count) files). Limit: \(self.maxDataCacheSizeBytes / (1024*1024)) MB.")

            // Perform cleanup if limit is exceeded
            if currentSize > self.maxDataCacheSizeBytes {
                Self.logger.info("Data cache size limit exceeded. Starting LRU cleanup...")
                // Sort files by date, oldest first
                filesWithSizeAndDate.sort { $0.date < $1.date }

                var removedCount = 0
                var sizeReduced: Int64 = 0
                // Remove oldest files until size is below the limit
                for fileInfo in filesWithSizeAndDate {
                    if currentSize <= self.maxDataCacheSizeBytes { break } // Stop if we are within limit
                    do {
                        try fileManager.removeItem(at: fileInfo.url)
                        currentSize -= fileInfo.size
                        sizeReduced += fileInfo.size
                        removedCount += 1
                        Self.logger.debug("LRU Cleanup: Removed \(fileInfo.url.lastPathComponent) (Size: \(fileInfo.size), Date: \(fileInfo.date))")
                    } catch { Self.logger.error("LRU Cleanup: Failed to remove data cache file \(fileInfo.url.lastPathComponent): \(error.localizedDescription)") }
                }
                Self.logger.info("LRU Cleanup finished. Removed \(removedCount) files, reduced size by \(sizeReduced / (1024*1024)) MB. New size: \(currentSize / (1024*1024)) MB.")
            } else {
                Self.logger.debug("Data cache size is within limit.")
            }

        } catch { Self.logger.error("Failed to list contents or get attributes for data cache size enforcement: \(error.localizedDescription)") }
    }
}
