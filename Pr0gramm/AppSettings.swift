// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine // Needed for observer token
import os
import Kingfisher
import CloudKit // Needed for NSUbiquitousKeyValueStore

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
/// Also manages synchronization of 'seen' items via iCloud Key-Value Store.
@MainActor
class AppSettings: ObservableObject {

    // --- MODIFIED: Add nonisolated to logger ---
    private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")
    // --- END MODIFICATION ---
    private let cacheService = CacheService()
    private let cloudStore = NSUbiquitousKeyValueStore.default // iCloud KVS instance

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
    private static let hideSeenItemsKey = "hideSeenItems_v1"

    // Cache Key for local seen items fallback/backup
    private static let localSeenItemsCacheKey = "seenItems_v1"
    // iCloud Key-Value Store Key
    private static let iCloudSeenItemsKey = "seenItemIDs_iCloud_v2" // v2 to ensure clean sync if format changes

    // Observer token for iCloud KVS changes
    private var keyValueStoreChangeObserver: NSObjectProtocol?

    // MARK: - Published User Settings (Persisted via UserDefaults)
    @Published var isVideoMuted: Bool { didSet { UserDefaults.standard.set(isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) } }
    @Published var feedType: FeedType { didSet { UserDefaults.standard.set(feedType.rawValue, forKey: Self.feedTypeKey) } }
    @Published var showSFW: Bool { didSet { UserDefaults.standard.set(showSFW, forKey: Self.showSFWKey) } }
    @Published var showNSFW: Bool { didSet { UserDefaults.standard.set(showNSFW, forKey: Self.showNSFWKey) } }
    @Published var showNSFL: Bool { didSet { UserDefaults.standard.set(showNSFL, forKey: Self.showNSFLKey) } }
    @Published var showNSFP: Bool { didSet { UserDefaults.standard.set(showNSFP, forKey: Self.showNSFPKey) } }
    @Published var showPOL: Bool { didSet { UserDefaults.standard.set(showPOL, forKey: Self.showPOLKey) } }
    @Published var maxImageCacheSizeMB: Int {
        didSet {
            UserDefaults.standard.set(maxImageCacheSizeMB, forKey: Self.maxImageCacheSizeMBKey)
            updateKingfisherCacheLimit()
        }
    }
    @Published var commentSortOrder: CommentSortOrder {
        didSet {
            UserDefaults.standard.set(commentSortOrder.rawValue, forKey: Self.commentSortOrderKey)
            Self.logger.info("Comment sort order changed to: \(self.commentSortOrder.displayName)")
        }
    }
    @Published var hideSeenItems: Bool {
        didSet {
            UserDefaults.standard.set(hideSeenItems, forKey: Self.hideSeenItemsKey)
            Self.logger.info("Hide seen items setting changed to: \(self.hideSeenItems)")
        }
    }

    // MARK: - Published Session State (Not Persisted)
    @Published var transientSessionMuteState: Bool? = nil

    // MARK: - Published Cache Information
    @Published var currentImageDataCacheSizeMB: Double = 0.0
    @Published var currentDataCacheSizeMB: Double = 0.0

    // MARK: - Published Seen Items State (Synced via iCloud KVS, backed up locally)
    @Published var seenItemIDs: Set<Int> = []


    // MARK: - Computed Properties for API Usage
    var apiFlags: Int { /* ... unchanged ... */
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
    var apiPromoted: Int { /* ... unchanged ... */
        get {
            return feedType.rawValue
        }
    }
    var hasActiveContentFilter: Bool { /* ... unchanged ... */
        return showSFW || showNSFW || showNSFL || showNSFP || showPOL
    }

    // MARK: - Initializer
    init() {
        // Load UserDefaults settings or set defaults (unchanged)
        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.isVideoMutedPreferenceKey)
        self.feedType = FeedType(rawValue: UserDefaults.standard.integer(forKey: Self.feedTypeKey)) ?? .promoted
        self.showSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.showSFWKey)
        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        self.showNSFP = UserDefaults.standard.bool(forKey: Self.showNSFPKey)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)
        self.maxImageCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) == nil ? 100 : UserDefaults.standard.integer(forKey: Self.maxImageCacheSizeMBKey)
        self.commentSortOrder = CommentSortOrder(rawValue: UserDefaults.standard.integer(forKey: Self.commentSortOrderKey)) ?? .date
        self.hideSeenItems = UserDefaults.standard.bool(forKey: Self.hideSeenItemsKey)

        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        // ... (other logs unchanged) ...
        Self.logger.info("- hideSeenItems: \(self.hideSeenItems)")

        // Ensure UserDefaults defaults are written (unchanged)
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        // ... (other checks unchanged) ...
        if UserDefaults.standard.object(forKey: Self.hideSeenItemsKey) == nil { UserDefaults.standard.set(self.hideSeenItems, forKey: Self.hideSeenItemsKey) }

        updateKingfisherCacheLimit() // Unchanged

        // --- Setup iCloud KVS observer ---
        setupCloudKitKeyValueStoreObserver()
        // --------------------------------

        // --- Load seen items (now checks iCloud first) and update cache sizes ---
        Task {
            await loadSeenItemIDs() // This now includes iCloud logic
            await updateCacheSizes() // Fetch initial cache sizes
        }
        // ----------------------------------------------------------------------
    }

    // MARK: - Cache Management Methods (Unchanged EXCEPT clearAllAppCache)

    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache, Kingfisher Image Cache, Seen Items Cache (Local & iCloud) requested.")
        // Clear data cache (feeds, favorites, etc.)
        await cacheService.clearAllDataCache()
        // Clear *local* seen items cache
        await cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
        // --- Clear iCloud seen items ---
        cloudStore.removeObject(forKey: Self.iCloudSeenItemsKey)
        cloudStore.synchronize() // Suggest immediate sync
        Self.logger.info("Removed seen items from iCloud KVS.")
        // -----------------------------
        // Reset the in-memory set
        await MainActor.run { self.seenItemIDs = [] }
        Self.logger.info("Cleared local seen items cache and reset in-memory set.")

        let logger = Self.logger // Capture logger for async context
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
            Task { await self.updateCacheSizes() } // Update sizes after clearing
        }
    }

    func updateCacheSizes() async { /* ... unchanged ... */
        Self.logger.debug("Updating both image and data cache sizes...")
        await updateDataCacheSize()
        await updateImageDataCacheSize()
    }

    private func updateDataCacheSize() async { /* ... unchanged ... */
        let dataSizeBytes = await cacheService.getCurrentDataCacheTotalSize()
        let dataSizeMB = Double(dataSizeBytes) / (1024.0 * 1024.0)
        await MainActor.run {
            self.currentDataCacheSizeMB = dataSizeMB
            Self.logger.info("Updated currentDataCacheSizeMB to: \(String(format: "%.2f", dataSizeMB)) MB")
        }
    }

    private func updateImageDataCacheSize() async { /* ... unchanged ... */
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

    private func updateKingfisherCacheLimit() { /* ... unchanged ... */
        let limitBytes = UInt(self.maxImageCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher (image) disk cache size limit to \(limitBytes) bytes (\(self.maxImageCacheSizeMB) MB).")
    }

    // MARK: - Data Cache Access Methods (Delegated to CacheService - Unchanged)

    func saveItemsToCache(_ items: [Item], forKey cacheKey: String) async { /* ... unchanged ... */
        guard !cacheKey.isEmpty else { return }
        await cacheService.saveItems(items, forKey: cacheKey)
        await updateDataCacheSize() // Update size after saving
    }

    func loadItemsFromCache(forKey cacheKey: String) async -> [Item]? { /* ... unchanged ... */
         guard !cacheKey.isEmpty else { return nil }
         return await cacheService.loadItems(forKey: cacheKey)
    }

    func clearFavoritesCache() async { /* ... unchanged ... */
        Self.logger.info("Clearing favorites data cache requested via AppSettings.")
        await cacheService.clearFavoritesCache()
        await updateDataCacheSize() // Update size after clearing
    }

    // MARK: - Seen Items Management Methods (Modified for iCloud)

    /// Marks an item as seen by adding its ID to the `seenItemIDs` set and saving the set to iCloud KVS and local cache.
    /// - Parameter id: The ID of the item to mark as seen.
    func markItemAsSeen(id: Int) async {
        // Check if the item is already marked as seen to avoid unnecessary writes/syncs
        if !seenItemIDs.contains(id) {
            await MainActor.run {
                _ = seenItemIDs.insert(id) // Use insert and discard result
                 Self.logger.debug("Marked item \(id) as seen. Total seen: \(self.seenItemIDs.count)")
            }
            // Persist the updated set to iCloud and local cache
            await saveSeenItemIDsToCloudAndLocal() // <-- Use the combined save function
        } else {
             Self.logger.trace("Item \(id) was already marked as seen.")
        }
    }

    /// Encodes the current `seenItemIDs` set to Data and saves it to both iCloud KVS and the local cache.
    // --- MODIFIED: Make async ---
    private func saveSeenItemIDsToCloudAndLocal() async {
        let idsToSave = self.seenItemIDs // Capture the current set

        // 1. Save to iCloud Key-Value Store
        Self.logger.debug("Saving \(idsToSave.count) seen item IDs to iCloud KVS (Key: \(Self.iCloudSeenItemsKey))...")
        do {
            let data = try JSONEncoder().encode(idsToSave)
            cloudStore.set(data, forKey: Self.iCloudSeenItemsKey)
            let syncSuccess = cloudStore.synchronize() // Suggest immediate sync
            Self.logger.info("Saved seen IDs to iCloud KVS. Synchronize requested: \(syncSuccess).")
        } catch {
            Self.logger.error("Failed to encode or save seen IDs to iCloud KVS: \(error.localizedDescription)")
            // Continue to save locally even if iCloud fails
        }

        // 2. Save to Local Cache (as backup/for offline)
        Self.logger.debug("Saving \(idsToSave.count) seen item IDs to local cache (Key: \(Self.localSeenItemsCacheKey))...")
        await cacheService.saveSeenIDs(idsToSave, forKey: Self.localSeenItemsCacheKey)
    }

    /// Loads the seen item IDs, prioritizing iCloud KVS and falling back to local cache.
    // --- MODIFIED: Make async ---
    private func loadSeenItemIDs() async {
        Self.logger.debug("Loading seen item IDs (iCloud first, then local cache)...")

        // 1. Try loading from iCloud KVS
        if let cloudData = cloudStore.data(forKey: Self.iCloudSeenItemsKey) {
            Self.logger.debug("Found data in iCloud KVS for key \(Self.iCloudSeenItemsKey).")
            do {
                let decodedIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData)
                await MainActor.run {
                     self.seenItemIDs = decodedIDs
                     Self.logger.info("Successfully loaded \(decodedIDs.count) seen item IDs from iCloud KVS.")
                     // Save to local cache as well to ensure consistency after iCloud load
                     Task { // Use Task for async call
                          Self.logger.debug("Saving iCloud-loaded seen IDs to local cache for consistency...")
                          await self.cacheService.saveSeenIDs(decodedIDs, forKey: Self.localSeenItemsCacheKey)
                     }
                 }
                return // Successfully loaded from iCloud
            } catch {
                Self.logger.error("Failed to decode seen item IDs from iCloud KVS data: \(error.localizedDescription). Falling back to local cache.")
                // Proceed to check local cache
            }
        } else {
            Self.logger.info("No data found in iCloud KVS for key \(Self.iCloudSeenItemsKey). Checking local cache...")
        }

        // 2. Fallback to loading from local cache
        if let localIDs = await cacheService.loadSeenIDs(forKey: Self.localSeenItemsCacheKey) { // Use await
            await MainActor.run {
                 self.seenItemIDs = localIDs
                 Self.logger.info("Loaded \(localIDs.count) seen item IDs from LOCAL cache.")
                 // IMPORTANT: Sync local cache data up to iCloud if iCloud was empty
                 Task { // Use Task for async call
                      Self.logger.info("Syncing locally loaded seen IDs UP to iCloud...")
                      await self.saveSeenItemIDsToCloudAndLocal()
                 }
             }
        } else {
            // 3. If both fail, start with an empty set
            Self.logger.warning("Could not load seen item IDs from iCloud or local cache. Starting with an empty set.")
             await MainActor.run {
                 self.seenItemIDs = [] // Ensure it's an empty set if loading fails
            }
        }
    }

    // MARK: - iCloud KVS Synchronization Handling

    /// Sets up the observer for changes in the iCloud Key-Value Store.
    private func setupCloudKitKeyValueStoreObserver() {
        // Ensure observer isn't added multiple times
        if keyValueStoreChangeObserver != nil {
            NotificationCenter.default.removeObserver(keyValueStoreChangeObserver!)
            keyValueStoreChangeObserver = nil
        }

        keyValueStoreChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: nil // Process on a background thread initially
        ) { [weak self] notification in
            // --- MODIFIED: Dispatch to main actor ---
            Task { @MainActor [weak self] in
                // Use optional chaining for safety
                await self?.handleCloudKitStoreChange(notification: notification) // Use await
            }
            // --- END MODIFICATION ---
        }
        // Trigger an initial sync request when the app starts observing
        let syncSuccess = cloudStore.synchronize()
        Self.logger.info("Setup iCloud KVS observer. Initial synchronize requested: \(syncSuccess)")
    }

    /// Handles incoming changes from the iCloud Key-Value Store.
    // --- MODIFIED: Make async ---
    private func handleCloudKitStoreChange(notification: Notification) async {
        Self.logger.info("Received iCloud KVS didChangeExternallyNotification.")
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            Self.logger.warning("Could not get change reason from KVS notification.")
            return
        }

        // Check if the change affects our specific key
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
              changedKeys.contains(Self.iCloudSeenItemsKey) else {
            Self.logger.debug("KVS change notification did not contain our key (\(Self.iCloudSeenItemsKey)). Ignoring.")
            return
        }

        Self.logger.info("Change detected for our key (\(Self.iCloudSeenItemsKey)) in iCloud KVS.")

        // Handle different change reasons (optional, but good practice)
        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            Self.logger.debug("Change reason: ServerChange or InitialSyncChange.")
            // Refetch the data from the store
            guard let cloudData = cloudStore.data(forKey: Self.iCloudSeenItemsKey) else {
                Self.logger.warning("Our key (\(Self.iCloudSeenItemsKey)) was reportedly changed, but no data found in KVS. Possibly deleted externally?")
                // If deleted externally, clear local state too? Or keep local as master?
                // Let's clear local to reflect the deletion sync.
                self.seenItemIDs = [] // Already on MainActor
                await self.cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
                Self.logger.info("Cleared local seen items state because key was missing in iCloud after external change notification.")
                return
            }

            // Decode the incoming data
            do {
                let incomingIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData)
                Self.logger.info("Successfully decoded \(incomingIDs.count) seen IDs from external iCloud KVS change.")

                // Merge with local data (Union is appropriate for 'seen' status)
                let localIDs = self.seenItemIDs // Capture current local state (already on MainActor)
                let mergedIDs = localIDs.union(incomingIDs)

                if mergedIDs.count > localIDs.count {
                    // Update the published property if changes occurred
                    self.seenItemIDs = mergedIDs // Already on MainActor
                    Self.logger.info("Merged external seen IDs. New total: \(mergedIDs.count).")
                    // Save merged set back to local cache
                    Self.logger.debug("Saving merged seen IDs back to local cache...")
                    await self.cacheService.saveSeenIDs(mergedIDs, forKey: Self.localSeenItemsCacheKey)

                } else {
                    Self.logger.debug("Incoming seen IDs did not add new items to the local set. No UI update needed.")
                    // Even if no *new* items, ensure local cache matches the (potentially identical) cloud state
                    await self.cacheService.saveSeenIDs(localIDs, forKey: Self.localSeenItemsCacheKey)
                }
            } catch {
                Self.logger.error("Failed to decode seen IDs from external iCloud KVS change data: \(error.localizedDescription)")
            }

        case NSUbiquitousKeyValueStoreAccountChange:
            Self.logger.warning("iCloud account changed. Reloading seen items state.")
            // The account changed (logged in/out of iCloud). Reload everything from the new account's KVS or local cache.
            await loadSeenItemIDs() // Use await

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            Self.logger.error("iCloud KVS Quota Violation! Syncing might stop.")
            // Inform the user or handle appropriately

        default:
            Self.logger.warning("Unhandled iCloud KVS change reason: \(changeReason)")
            break
        }
    }

    // MARK: - Deinitializer

    deinit {
        // Clean up the observer when AppSettings is deallocated
        if let observer = keyValueStoreChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            // Accessing nonisolated logger is safe
            AppSettings.logger.debug("Removed iCloud KVS observer in deinit.")
        }
    }
}
// --- END OF COMPLETE FILE ---
