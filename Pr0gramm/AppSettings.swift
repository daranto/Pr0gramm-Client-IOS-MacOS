// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine
import os
import Kingfisher

/// Defines the available feed types (new vs. popular).
enum FeedType: Int, CaseIterable, Identifiable {
    case new = 0
    case promoted = 1

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .new: return "Neu"
        case .promoted: return "Beliebt"
        }
    }
}

/// Manages application-wide settings, persists them to UserDefaults, and provides access to cache services.
@MainActor
class AppSettings: ObservableObject {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")
    private let cacheService = CacheService()

    // UserDefaults Keys for persistence
    private static let isVideoMutedPreferenceKey = "isVideoMutedPreference_v1"
    private static let feedTypeKey = "feedTypePreference_v1"
    private static let showSFWKey = "showSFWPreference_v1"
    private static let showNSFWKey = "showNSFWPreference_v1"
    private static let showNSFLKey = "showNSFLPreference_v1"
    private static let showNSFPKey = "showNSFPPreference_v1"
    private static let showPOLKey = "showPOLPreference_v1"
    private static let maxImageCacheSizeMBKey = "maxImageCacheSizeMB_v1"

    // MARK: - Published User Settings (Persisted)
    /// Whether videos should start muted. Persisted in UserDefaults.
    @Published var isVideoMuted: Bool { didSet { UserDefaults.standard.set(isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) } }
    /// The currently selected feed type (New or Promoted). Persisted in UserDefaults.
    @Published var feedType: FeedType { didSet { UserDefaults.standard.set(feedType.rawValue, forKey: Self.feedTypeKey) } }
    /// Whether to show SFW content. Persisted in UserDefaults.
    @Published var showSFW: Bool { didSet { UserDefaults.standard.set(showSFW, forKey: Self.showSFWKey) } }
    /// Whether to show NSFW content. Persisted in UserDefaults.
    @Published var showNSFW: Bool { didSet { UserDefaults.standard.set(showNSFW, forKey: Self.showNSFWKey) } }
    /// Whether to show NSFL content. Persisted in UserDefaults.
    @Published var showNSFL: Bool { didSet { UserDefaults.standard.set(showNSFL, forKey: Self.showNSFLKey) } }
    /// Whether to show NSFP content. Persisted in UserDefaults.
    @Published var showNSFP: Bool { didSet { UserDefaults.standard.set(showNSFP, forKey: Self.showNSFPKey) } }
    /// Whether to show Political content. Persisted in UserDefaults.
    @Published var showPOL: Bool { didSet { UserDefaults.standard.set(showPOL, forKey: Self.showPOLKey) } }
    /// The maximum size (in MB) allocated for the Kingfisher image disk cache. Persisted in UserDefaults.
    @Published var maxImageCacheSizeMB: Int {
        didSet {
            UserDefaults.standard.set(maxImageCacheSizeMB, forKey: Self.maxImageCacheSizeMBKey)
            updateKingfisherCacheLimit()
        }
    }

    // MARK: - Published Session State (Not Persisted)
    /// Stores the user's desired mute state *for the current app session*.
    /// Updated by player interaction. Reset to nil when app becomes active.
    /// If nil, `isVideoMuted` (persisted setting) is used.
    @Published var transientSessionMuteState: Bool? = nil

    // MARK: - Published Cache Information
    /// The current size (in MB) of the Kingfisher image disk cache. Updated periodically.
    @Published var currentImageDataCacheSizeMB: Double = 0.0
    /// The current size (in MB) of the app's data disk cache (e.g., feeds, favorites). Updated periodically.
    @Published var currentDataCacheSizeMB: Double = 0.0

    // MARK: - Computed Properties for API Usage
    /// Calculates the integer flag value required by the API based on the current content filter settings.
    /// Defaults to 1 (SFW) if no flags are selected.
    var apiFlags: Int {
        get {
            var flags = 0
            if showSFW { flags |= 1 }
            if showNSFW { flags |= 2 }
            if showNSFL { flags |= 4 }
            if showNSFP { flags |= 8 }
            if showPOL { flags |= 16 }
            return flags == 0 ? 1 : flags // API requires at least SFW if nothing else is selected
        }
    }

    /// Returns the integer value required by the API for the selected feed type (0 for New, 1 for Promoted).
    var apiPromoted: Int {
        get {
            return feedType.rawValue
        }
    }

    /// Indicates if at least one content filter (SFW, NSFW, etc.) is currently active.
    var hasActiveContentFilter: Bool {
        return showSFW || showNSFW || showNSFL || showNSFP || showPOL
    }

    // MARK: - Initializer
    init() {
        // Load settings from UserDefaults or set defaults
        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.isVideoMutedPreferenceKey)
        self.feedType = FeedType(rawValue: UserDefaults.standard.integer(forKey: Self.feedTypeKey)) ?? .promoted
        self.showSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.showSFWKey)
        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        self.showNSFP = UserDefaults.standard.bool(forKey: Self.showNSFPKey)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)
        self.maxImageCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) == nil ? 100 : UserDefaults.standard.integer(forKey: Self.maxImageCacheSizeMBKey)
        // transientSessionMuteState starts as nil intentionally

        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        Self.logger.info("- Content Flags: SFW(\(self.showSFW)) NSFW(\(self.showNSFW)) NSFL(\(self.showNSFL)) NSFP(\(self.showNSFP)) POL(\(self.showPOL)) -> API Flags: \(self.apiFlags)")
        Self.logger.info("- maxImageCacheSizeMB: \(self.maxImageCacheSizeMB)")

        // Ensure defaults are written if they were missing
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil { UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey) }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil { UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey) }
        if UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) == nil { UserDefaults.standard.set(self.maxImageCacheSizeMB, forKey: Self.maxImageCacheSizeMBKey) }

        updateKingfisherCacheLimit()
        Task { await updateCacheSizes() } // Fetch initial cache sizes
    }

    // MARK: - Cache Management Methods

    /// Clears both the app's data cache (feeds, favorites etc.) and the Kingfisher image cache.
    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache and Kingfisher Image Cache requested.")
        await cacheService.clearAllDataCache()
        let logger = Self.logger // Capture logger for async context
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
            Task { await self.updateCacheSizes() } // Update sizes after clearing
        }
    }

    /// Asynchronously updates the published properties for both data and image cache sizes.
    func updateCacheSizes() async {
        Self.logger.debug("Updating both image and data cache sizes...")
        await updateDataCacheSize()
        await updateImageDataCacheSize()
    }

    /// Updates the `currentDataCacheSizeMB` by fetching the size from `CacheService`.
    private func updateDataCacheSize() async {
        let dataSizeBytes = await cacheService.getCurrentDataCacheTotalSize()
        let dataSizeMB = Double(dataSizeBytes) / (1024.0 * 1024.0)
        await MainActor.run {
            self.currentDataCacheSizeMB = dataSizeMB
            Self.logger.info("Updated currentDataCacheSizeMB to: \(String(format: "%.2f", dataSizeMB)) MB")
        }
    }

    /// Updates the `currentImageDataCacheSizeMB` by fetching the size from `KingfisherManager`.
    private func updateImageDataCacheSize() async {
        let logger = Self.logger // Capture logger for async context
        let imageSizeBytes: UInt = await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    logger.debug("Kingfisher disk cache size: \(size) bytes.")
                    continuation.resume(returning: size)
                case .failure(let error):
                    logger.error("Failed to calculate Kingfisher disk cache size: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                }
            }
        }
        let imageSizeMB = Double(imageSizeBytes) / (1024.0 * 1024.0)
        await MainActor.run {
            self.currentImageDataCacheSizeMB = imageSizeMB
            Self.logger.info("Updated currentImageDataCacheSizeMB to: \(String(format: "%.2f", imageSizeMB)) MB")
        }
    }

    /// Applies the `maxImageCacheSizeMB` setting to the Kingfisher disk storage configuration.
    private func updateKingfisherCacheLimit() {
        let limitBytes = UInt(self.maxImageCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher (image) disk cache size limit to \(limitBytes) bytes (\(self.maxImageCacheSizeMB) MB).")
    }

    // MARK: - Data Cache Access Methods (Delegated to CacheService)

    /// Saves an array of `Item` objects to the data cache under a specific key.
    /// - Parameters:
    ///   - items: The array of `Item` objects to save.
    ///   - cacheKey: The key under which to store the items.
    func saveItemsToCache(_ items: [Item], forKey cacheKey: String) async {
        guard !cacheKey.isEmpty else { return }
        await cacheService.saveItems(items, forKey: cacheKey)
        await updateDataCacheSize() // Update size after saving
    }

    /// Loads an array of `Item` objects from the data cache associated with a specific key.
    /// - Parameter cacheKey: The key for the items to load.
    /// - Returns: An array of `Item` objects if found and successfully decoded, otherwise `nil`.
    func loadItemsFromCache(forKey cacheKey: String) async -> [Item]? {
         guard !cacheKey.isEmpty else { return nil }
         return await cacheService.loadItems(forKey: cacheKey)
    }

    /// Clears only the cached data related to user favorites.
    func clearFavoritesCache() async {
        Self.logger.info("Clearing favorites data cache requested via AppSettings.")
        await cacheService.clearFavoritesCache()
        await updateDataCacheSize() // Update size after clearing
    }
}
// --- END OF COMPLETE FILE ---
