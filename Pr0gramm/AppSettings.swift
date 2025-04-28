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

/// Defines the available sorting orders for comments.
enum CommentSortOrder: Int, CaseIterable, Identifiable {
    case date = 0
    case score = 1

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .date: return "Datum / Zeit"
        case .score: return "Benis (Score)"
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
    private static let commentSortOrderKey = "commentSortOrder_v1"
    private static let hideSeenItemsKey = "hideSeenItems_v1" // <-- Key für neue Einstellung
    // Cache Key for seen items
    private static let seenItemsCacheKey = "seenItems_v1"

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
    /// The preferred sorting order for comments. Persisted in UserDefaults.
    @Published var commentSortOrder: CommentSortOrder {
        didSet {
            UserDefaults.standard.set(commentSortOrder.rawValue, forKey: Self.commentSortOrderKey)
            Self.logger.info("Comment sort order changed to: \(self.commentSortOrder.displayName)")
        }
    }
    /// Whether to hide items marked as seen in grid views. Persisted in UserDefaults. <-- NEUE EINSTELLUNG
    @Published var hideSeenItems: Bool {
        didSet {
            UserDefaults.standard.set(hideSeenItems, forKey: Self.hideSeenItemsKey)
            Self.logger.info("Hide seen items setting changed to: \(self.hideSeenItems)")
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

    // MARK: - Published Seen Items State (Persisted via CacheService)
    /// Set containing the IDs of items that the user has viewed in the detail view.
    @Published var seenItemIDs: Set<Int> = []


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
        self.commentSortOrder = CommentSortOrder(rawValue: UserDefaults.standard.integer(forKey: Self.commentSortOrderKey)) ?? .date
        // Load new hide seen items setting or default to false <-- NEU
        self.hideSeenItems = UserDefaults.standard.bool(forKey: Self.hideSeenItemsKey)

        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        Self.logger.info("- Content Flags: SFW(\(self.showSFW)) NSFW(\(self.showNSFW)) NSFL(\(self.showNSFL)) NSFP(\(self.showNSFP)) POL(\(self.showPOL)) -> API Flags: \(self.apiFlags)")
        Self.logger.info("- maxImageCacheSizeMB: \(self.maxImageCacheSizeMB)")
        Self.logger.info("- commentSortOrder: \(self.commentSortOrder.displayName)")
        Self.logger.info("- hideSeenItems: \(self.hideSeenItems)") // <-- Loggen

        // Ensure defaults are written if they were missing
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil { UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey) }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil { UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey) }
        if UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) == nil { UserDefaults.standard.set(self.maxImageCacheSizeMB, forKey: Self.maxImageCacheSizeMBKey) }
        if UserDefaults.standard.object(forKey: Self.commentSortOrderKey) == nil { UserDefaults.standard.set(self.commentSortOrder.rawValue, forKey: Self.commentSortOrderKey) }
        // Write default for hideSeenItems if missing <-- NEU
        if UserDefaults.standard.object(forKey: Self.hideSeenItemsKey) == nil { UserDefaults.standard.set(self.hideSeenItems, forKey: Self.hideSeenItemsKey) }


        updateKingfisherCacheLimit()
        Task {
            // Load seen items first, then update sizes
            await loadSeenItemIDs()
            await updateCacheSizes() // Fetch initial cache sizes
        }
    }

    // MARK: - Cache Management Methods

    /// Clears both the app's data cache (feeds, favorites etc.) and the Kingfisher image cache.
    /// Also clears the seen items cache.
    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache, Kingfisher Image Cache, and Seen Items Cache requested.")
        // Clear data cache (feeds, favorites, etc.)
        await cacheService.clearAllDataCache()
        // Clear seen items cache
        await cacheService.clearCache(forKey: Self.seenItemsCacheKey)
        // Reset the in-memory set
        await MainActor.run { self.seenItemIDs = [] }
        Self.logger.info("Cleared seen items cache and reset in-memory set.")

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

    // MARK: - Seen Items Management Methods

    /// Marks an item as seen by adding its ID to the `seenItemIDs` set and saving the set to cache.
    /// - Parameter id: The ID of the item to mark as seen.
    func markItemAsSeen(id: Int) async {
        // Check if the item is already marked as seen to avoid unnecessary writes
        if !seenItemIDs.contains(id) {
            await MainActor.run {
                _ = seenItemIDs.insert(id) // Use insert and discard result
                 Self.logger.debug("Marked item \(id) as seen. Total seen: \(self.seenItemIDs.count)")
            }
            // Persist the updated set to the cache
            await saveSeenItemIDs()
        } else {
             Self.logger.trace("Item \(id) was already marked as seen.")
        }
    }

    /// Saves the current `seenItemIDs` set to the cache using `CacheService`.
    private func saveSeenItemIDs() async {
        let idsToSave = self.seenItemIDs // Capture the current set
        Self.logger.debug("Saving \(idsToSave.count) seen item IDs to cache (Key: \(Self.seenItemsCacheKey))...")
        await cacheService.saveSeenIDs(idsToSave, forKey: Self.seenItemsCacheKey)
    }

    /// Loads the seen item IDs from the cache during initialization.
    private func loadSeenItemIDs() async {
        Self.logger.debug("Loading seen item IDs from cache (Key: \(Self.seenItemsCacheKey))...")
        if let loadedIDs = await cacheService.loadSeenIDs(forKey: Self.seenItemsCacheKey) {
            await MainActor.run {
                 self.seenItemIDs = loadedIDs
                 Self.logger.info("Loaded \(loadedIDs.count) seen item IDs from cache.")
            }
        } else {
            Self.logger.warning("Could not load seen item IDs from cache (or cache was empty). Starting with an empty set.")
             await MainActor.run {
                 self.seenItemIDs = [] // Ensure it's an empty set if loading fails
            }
        }
    }

}
// --- END OF COMPLETE FILE ---
