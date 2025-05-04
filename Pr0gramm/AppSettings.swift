// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine // Needed for observer token
import os
import Kingfisher
import CloudKit // Needed for NSUbiquitousKeyValueStore

// FeedType and CommentSortOrder enums remain the same...
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

    private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")
    private let cacheService = CacheService()
    private let cloudStore = NSUbiquitousKeyValueStore.default

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
    private static let localSeenItemsCacheKey = "seenItems_v1"
    private static let iCloudSeenItemsKey = "seenItemIDs_iCloud_v2"
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
    @Published private(set) var seenItemIDs: Set<Int> = []

    // MARK: - Computed Properties for API Usage
    var apiFlags: Int {
        get { var flags = 0; if showSFW { flags |= 1 }; if showNSFW { flags |= 2 }; if showNSFL { flags |= 4 }; if showNSFP { flags |= 8 }; if showPOL { flags |= 16 }; return flags == 0 ? 1 : flags }
    }
    var apiPromoted: Int { get { return feedType.rawValue } }
    var hasActiveContentFilter: Bool { return showSFW || showNSFW || showNSFL || showNSFP || showPOL }

    // MARK: - Initializer
    init() {
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
        Self.logger.info("- hideSeenItems: \(self.hideSeenItems)")

        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        if UserDefaults.standard.object(forKey: Self.hideSeenItemsKey) == nil { UserDefaults.standard.set(self.hideSeenItems, forKey: Self.hideSeenItemsKey) }

        updateKingfisherCacheLimit()
        setupCloudKitKeyValueStoreObserver()

        Task {
            await loadSeenItemIDs()
            await updateCacheSizes()
        }
    }

    // MARK: - Cache Management Methods

    // --- NEW: Clear only seen items cache ---
    /// Clears the cache of seen item IDs both locally and in iCloud KVS.
    func clearSeenItemsCache() async {
        Self.logger.warning("Clearing Seen Items Cache (Local & iCloud) requested.")
        // Clear in-memory state
        // No need for MainActor.run as we are already on the MainActor
        self.seenItemIDs = []
        Self.logger.info("Cleared in-memory seen items set.")

        // Clear local cache file managed by CacheService
        await cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
        Self.logger.info("Cleared local seen items cache file via CacheService.")

        // Clear iCloud KVS
        cloudStore.removeObject(forKey: Self.iCloudSeenItemsKey)
        let syncSuccess = cloudStore.synchronize() // Request sync
        Self.logger.info("Removed seen items key from iCloud KVS. Synchronize requested: \(syncSuccess).")
    }
    // --- END NEW ---

    /// Clears ALL application caches including data, images, and seen items.
    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache, Kingfisher Image Cache, Seen Items Cache (Local & iCloud) requested.")
        // Clear data cache (feeds, favorites etc.)
        await cacheService.clearAllDataCache()
        // Clear seen items (uses the new dedicated method)
        await clearSeenItemsCache()
        // Clear Kingfisher image cache
        let logger = Self.logger // Capture logger for async block
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
            Task { await self.updateCacheSizes() } // Update sizes after clearing
        }
        // Update cache sizes immediately (data cache size might be 0 now)
        await updateCacheSizes()
    }

    func updateCacheSizes() async {
        Self.logger.debug("Updating both image and data cache sizes...")
        await updateDataCacheSize()
        await updateImageDataCacheSize()
    }
    private func updateDataCacheSize() async {
        let dataSizeBytes = await cacheService.getCurrentDataCacheTotalSize()
        let dataSizeMB = Double(dataSizeBytes) / (1024.0 * 1024.0)
        // Ensure UI update is on MainActor (already guaranteed by class annotation)
        self.currentDataCacheSizeMB = dataSizeMB
        Self.logger.info("Updated currentDataCacheSizeMB to: \(String(format: "%.2f", dataSizeMB)) MB")
    }
    private func updateImageDataCacheSize() async {
        let logger = Self.logger
        let imageSizeBytes: UInt = await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                switch result {
                case .success(let size): continuation.resume(returning: size)
                case .failure(let error): logger.error("Failed to calculate Kingfisher disk cache size: \(error.localizedDescription)"); continuation.resume(returning: 0)
                }
            }
        }
        let imageSizeMB = Double(imageSizeBytes) / (1024.0 * 1024.0)
        // Ensure UI update is on MainActor
        self.currentImageDataCacheSizeMB = imageSizeMB
        Self.logger.info("Updated currentImageDataCacheSizeMB to: \(String(format: "%.2f", imageSizeMB)) MB")
    }
    private func updateKingfisherCacheLimit() {
        let limitBytes = UInt(self.maxImageCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher (image) disk cache size limit to \(limitBytes) bytes (\(self.maxImageCacheSizeMB) MB).")
    }

    // MARK: - Data Cache Access Methods (Delegated to CacheService - Unchanged)
    func saveItemsToCache(_ items: [Item], forKey cacheKey: String) async {
        guard !cacheKey.isEmpty else { return }
        await cacheService.saveItems(items, forKey: cacheKey)
        await updateDataCacheSize()
    }
    func loadItemsFromCache(forKey cacheKey: String) async -> [Item]? {
         guard !cacheKey.isEmpty else { return nil }
         return await cacheService.loadItems(forKey: cacheKey)
    }
    func clearFavoritesCache() async {
        Self.logger.info("Clearing favorites data cache requested via AppSettings.")
        await cacheService.clearFavoritesCache()
        await updateDataCacheSize()
    }

    // MARK: - Seen Items Management Methods (Unchanged)
    func markItemAsSeen(id: Int) async {
        if !seenItemIDs.contains(id) {
             var idsToUpdate = seenItemIDs
             idsToUpdate.insert(id)
             seenItemIDs = idsToUpdate
             Self.logger.debug("Marked item \(id) as seen. Total seen: \(self.seenItemIDs.count)")
             await saveSeenItemIDsToCloudAndLocal()
        } else {
             Self.logger.trace("Item \(id) was already marked as seen.")
        }
    }
    func markItemsAsSeen(ids: Set<Int>) async {
         let newIDs = ids.subtracting(seenItemIDs)
         if !newIDs.isEmpty {
             Self.logger.debug("Marking \(newIDs.count) new items as seen.")
             var idsToUpdate = seenItemIDs
             idsToUpdate.formUnion(newIDs)
             seenItemIDs = idsToUpdate
             Self.logger.info("Marked \(newIDs.count) items as seen. Total seen: \(self.seenItemIDs.count)")
             await saveSeenItemIDsToCloudAndLocal()
         } else {
             Self.logger.trace("No new items to mark as seen from the provided batch.")
         }
    }
    private func saveSeenItemIDsToCloudAndLocal() async {
        let idsToSave = self.seenItemIDs
        Self.logger.debug("Saving \(idsToSave.count) seen item IDs to iCloud KVS (Key: \(Self.iCloudSeenItemsKey))...")
        do {
            let data = try JSONEncoder().encode(idsToSave)
            cloudStore.set(data, forKey: Self.iCloudSeenItemsKey)
            let syncSuccess = cloudStore.synchronize()
            Self.logger.info("Saved seen IDs to iCloud KVS. Synchronize requested: \(syncSuccess).")
        } catch {
            Self.logger.error("Failed to encode or save seen IDs to iCloud KVS: \(error.localizedDescription)")
        }
        Self.logger.debug("Saving \(idsToSave.count) seen item IDs to local cache (Key: \(Self.localSeenItemsCacheKey))...")
        await cacheService.saveSeenIDs(idsToSave, forKey: Self.localSeenItemsCacheKey)
    }
    private func loadSeenItemIDs() async {
        Self.logger.debug("Loading seen item IDs (iCloud first, then local cache)...")
        if let cloudData = cloudStore.data(forKey: Self.iCloudSeenItemsKey) {
            Self.logger.debug("Found data in iCloud KVS for key \(Self.iCloudSeenItemsKey).")
            do {
                let decodedIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData)
                self.seenItemIDs = decodedIDs // Direct update as we are already on MainActor
                Self.logger.info("Successfully loaded \(decodedIDs.count) seen item IDs from iCloud KVS.")
                Task.detached { await self.cacheService.saveSeenIDs(decodedIDs, forKey: Self.localSeenItemsCacheKey) }
                return
            } catch {
                Self.logger.error("Failed to decode seen item IDs from iCloud KVS data: \(error.localizedDescription). Falling back to local cache.")
            }
        } else {
            Self.logger.info("No data found in iCloud KVS for key \(Self.iCloudSeenItemsKey). Checking local cache...")
        }
        if let localIDs = await cacheService.loadSeenIDs(forKey: Self.localSeenItemsCacheKey) {
             self.seenItemIDs = localIDs // Direct update
             Self.logger.info("Loaded \(localIDs.count) seen item IDs from LOCAL cache.")
             Task.detached {
                  Self.logger.info("Syncing locally loaded seen IDs UP to iCloud...")
                  await self.saveSeenItemIDsToCloudAndLocal()
             }
        } else {
            Self.logger.warning("Could not load seen item IDs from iCloud or local cache. Starting with an empty set.")
             self.seenItemIDs = [] // Direct update
        }
    }


    // MARK: - iCloud KVS Synchronization Handling (Unchanged)
    private func setupCloudKitKeyValueStoreObserver() {
        if keyValueStoreChangeObserver != nil { NotificationCenter.default.removeObserver(keyValueStoreChangeObserver!); keyValueStoreChangeObserver = nil }
        keyValueStoreChangeObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloudStore, queue: .main) { [weak self] notification in // Use main queue
            Task { @MainActor [weak self] in await self?.handleCloudKitStoreChange(notification: notification) } // Ensure MainActor context
        }
        let syncSuccess = cloudStore.synchronize(); Self.logger.info("Setup iCloud KVS observer. Initial synchronize requested: \(syncSuccess)")
    }
    // Ensure handleCloudKitStoreChange is annotated or called within MainActor context correctly
    // (Current setup with Task { @MainActor ... } is correct)
    private func handleCloudKitStoreChange(notification: Notification) async {
        Self.logger.info("Received iCloud KVS didChangeExternallyNotification.")
        guard let userInfo = notification.userInfo, let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { Self.logger.warning("Could not get change reason from KVS notification."); return }
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String], changedKeys.contains(Self.iCloudSeenItemsKey) else { Self.logger.debug("KVS change notification did not contain our key (\(Self.iCloudSeenItemsKey)). Ignoring."); return }
        Self.logger.info("Change detected for our key (\(Self.iCloudSeenItemsKey)) in iCloud KVS.")

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            Self.logger.debug("Change reason: ServerChange or InitialSyncChange.")
            guard let cloudData = cloudStore.data(forKey: Self.iCloudSeenItemsKey) else {
                Self.logger.warning("Our key (\(Self.iCloudSeenItemsKey)) was reportedly changed, but no data found in KVS. Possibly deleted externally?")
                // Already on MainActor, update directly
                self.seenItemIDs = []
                await self.cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
                Self.logger.info("Cleared local seen items state because key was missing in iCloud after external change notification.")
                return
            }
            do {
                let incomingIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData); Self.logger.info("Successfully decoded \(incomingIDs.count) seen IDs from external iCloud KVS change.")
                let localIDs = self.seenItemIDs; let mergedIDs = localIDs.union(incomingIDs)
                if mergedIDs.count > localIDs.count {
                    // Already on MainActor, update directly
                    self.seenItemIDs = mergedIDs; Self.logger.info("Merged external seen IDs. New total: \(mergedIDs.count).")
                    Task.detached { await self.cacheService.saveSeenIDs(mergedIDs, forKey: Self.localSeenItemsCacheKey) } // Save merged back locally async
                } else {
                    Self.logger.debug("Incoming seen IDs did not add new items to the local set. No UI update needed.")
                    Task.detached { await self.cacheService.saveSeenIDs(localIDs, forKey: Self.localSeenItemsCacheKey) } // Ensure local still matches cloud
                }
            } catch { Self.logger.error("Failed to decode seen IDs from external iCloud KVS change data: \(error.localizedDescription)") }
        case NSUbiquitousKeyValueStoreAccountChange: Self.logger.warning("iCloud account changed. Reloading seen items state."); await loadSeenItemIDs()
        case NSUbiquitousKeyValueStoreQuotaViolationChange: Self.logger.error("iCloud KVS Quota Violation! Syncing might stop.")
        default: Self.logger.warning("Unhandled iCloud KVS change reason: \(changeReason)"); break
        }
    }

    // MARK: - Deinitializer (Unchanged)
    deinit { if let observer = keyValueStoreChangeObserver { NotificationCenter.default.removeObserver(observer); AppSettings.logger.debug("Removed iCloud KVS observer in deinit.") } }
}
// --- END OF COMPLETE FILE ---
