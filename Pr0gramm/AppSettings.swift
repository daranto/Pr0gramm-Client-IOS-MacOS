// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine // Needed for observer token
import os
import Kingfisher
import CloudKit // Needed for NSUbiquitousKeyValueStore
import SwiftUI // Needed for ColorScheme

// --- MODIFIED: FeedType Enum erweitert ---
enum FeedType: Int, CaseIterable, Identifiable {
    case new = 0
    case promoted = 1
    case junk = 2 // Neuer Typ für Müll

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .new: return "Neu"
        case .promoted: return "Beliebt"
        case .junk: return "Müll" // Anzeigename für Müll
        }
    }
}
// --- END MODIFICATION ---

enum CommentSortOrder: Int, CaseIterable, Identifiable {
    case date = 0, score = 1
    var id: Int { self.rawValue }
    var displayName: String {
        switch self { case .date: return "Datum / Zeit"; case .score: return "Benis (Score)"}
    }
}

enum SubtitleActivationMode: Int, CaseIterable, Identifiable {
    case disabled = 0
    case automatic = 1
    case alwaysOn = 2
    var id: Int { self.rawValue }
    var displayName: String {
        switch self {
        case .disabled: return "Deaktiviert"
        case .automatic: return "Automatisch"
        case .alwaysOn: return "Immer an"
        }
    }
}

enum ColorSchemeSetting: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .system: return "Systemeinstellung"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    var swiftUIScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum GridSizeSetting: Int, CaseIterable, Identifiable {
    case small = 3
    case medium = 4
    case large = 5

    var id: Int { self.rawValue }

    var displayName: String {
        return "\(self.rawValue)"
    }

    func columns(for horizontalSizeClass: UserInterfaceSizeClass?, isMac: Bool) -> Int {
        let baseCount = self.rawValue
        if isMac {
            return baseCount + 2
        } else {
            if horizontalSizeClass == .regular {
                return baseCount + 1
            } else {
                return baseCount
            }
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

    // UserDefaults Keys
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
    private static let enableExperimentalHideSeenKey = "enableExperimentalHideSeen_v1"
    private static let subtitleActivationModeKey = "subtitleActivationMode_v1"
    private static let selectedCollectionIdForFavoritesKey = "selectedCollectionIdForFavorites_v1"
    private static let colorSchemeSettingKey = "colorSchemeSetting_v1"
    private static let gridSizeSettingKey = "gridSizeSetting_v1"
    private static let resetFiltersOnAppOpenKey = "resetFiltersOnAppOpen_v1"
    private static let localSeenItemsCacheKey = "seenItems_v1"
    private static let iCloudSeenItemsKey = "seenItemIDs_iCloud_v2"
    private var keyValueStoreChangeObserver: NSObjectProtocol?

    // MARK: - Published User Settings (Persisted via UserDefaults)
    @Published var isVideoMuted: Bool { didSet { UserDefaults.standard.set(isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) } }
    @Published var feedType: FeedType {
        didSet {
            UserDefaults.standard.set(feedType.rawValue, forKey: Self.feedTypeKey)
            Self.logger.info("Feed type changed to: \(self.feedType.displayName)")
        }
    }
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
            if enableExperimentalHideSeen {
                 UserDefaults.standard.set(hideSeenItems, forKey: Self.hideSeenItemsKey)
                 Self.logger.info("Hide seen items setting changed to: \(self.hideSeenItems)")
            } else if hideSeenItems {
                 Self.logger.warning("Attempted to set hideSeenItems to true while experimental feature is disabled. Forcing back to false.")
                 Task { @MainActor in self.hideSeenItems = false }
            }
        }
    }
    @Published var enableExperimentalHideSeen: Bool {
        didSet {
            UserDefaults.standard.set(enableExperimentalHideSeen, forKey: Self.enableExperimentalHideSeenKey)
            Self.logger.info("Setting 'Enable Experimental Hide Seen' changed to: \(self.enableExperimentalHideSeen)")
            if !enableExperimentalHideSeen {
                self.hideSeenItems = false
                Self.logger.info("Experimental 'Hide Seen' disabled. Forcing 'hideSeenItems' setting to false.")
                 UserDefaults.standard.removeObject(forKey: Self.hideSeenItemsKey)
            }
        }
    }
    @Published var subtitleActivationMode: SubtitleActivationMode {
        didSet {
            UserDefaults.standard.set(subtitleActivationMode.rawValue, forKey: Self.subtitleActivationModeKey)
            Self.logger.info("Subtitle activation mode changed to: \(self.subtitleActivationMode.displayName)")
        }
    }
    @Published var selectedCollectionIdForFavorites: Int? {
        didSet {
            if let newId = selectedCollectionIdForFavorites {
                UserDefaults.standard.set(newId, forKey: Self.selectedCollectionIdForFavoritesKey)
                Self.logger.info("Selected Collection ID for Favorites changed to: \(newId)")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedCollectionIdForFavoritesKey)
                Self.logger.info("Selected Collection ID for Favorites cleared (set to nil).")
            }
        }
    }
    @Published var colorSchemeSetting: ColorSchemeSetting {
        didSet {
            UserDefaults.standard.set(colorSchemeSetting.rawValue, forKey: Self.colorSchemeSettingKey)
            Self.logger.info("Color scheme setting changed to: \(self.colorSchemeSetting.displayName)")
        }
    }
    @Published var gridSize: GridSizeSetting {
        didSet {
            // Nur schreiben, wenn der neue Wert sich vom alten unterscheidet, um unnötige didSet-Ketten zu vermeiden
            if oldValue != gridSize {
                UserDefaults.standard.set(gridSize.rawValue, forKey: Self.gridSizeSettingKey)
                Self.logger.info("Grid size setting changed to: \(self.gridSize.displayName) (rawValue: \(self.gridSize.rawValue))")
            }
        }
    }
    @Published var resetFiltersOnAppOpen: Bool {
        didSet {
            if oldValue != resetFiltersOnAppOpen {
                UserDefaults.standard.set(resetFiltersOnAppOpen, forKey: Self.resetFiltersOnAppOpenKey)
                Self.logger.info("Reset filters on app open setting changed to: \(self.resetFiltersOnAppOpen)")
            }
        }
    }


    // MARK: - Published Session State (Not Persisted)
    @Published var transientSessionMuteState: Bool? = nil

    // MARK: - Published Cache Information
    @Published var currentImageDataCacheSizeMB: Double = 0.0
    @Published var currentDataCacheSizeMB: Double = 0.0

    // MARK: - Published Seen Items State (Synced via iCloud KVS, backed up locally)
    @Published private(set) var seenItemIDs: Set<Int> = []

    private var saveSeenItemsTask: Task<Void, Never>?
    private let saveSeenItemsDebounceDelay: Duration = .seconds(2)

    var favoritesSettingsChangedPublisher: AnyPublisher<Void, Never> {
        let sfwPublisher = $showSFW.map { _ in () }.eraseToAnyPublisher()
        let nsfwPublisher = $showNSFW.map { _ in () }.eraseToAnyPublisher()
        let nsflPublisher = $showNSFL.map { _ in () }.eraseToAnyPublisher()
        let nsfpPublisher = $showNSFP.map { _ in () }.eraseToAnyPublisher()
        let polPublisher = $showPOL.map { _ in () }.eraseToAnyPublisher()
        let collectionIdPublisher = $selectedCollectionIdForFavorites.map { _ in () }.eraseToAnyPublisher()

        return Publishers.MergeMany([
            sfwPublisher,
            nsfwPublisher,
            nsflPublisher,
            nsfpPublisher,
            polPublisher,
            collectionIdPublisher
        ])
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .eraseToAnyPublisher()
    }


    // MARK: - Computed Properties for API Usage
    var apiFlags: Int {
        get {
            if feedType == .junk {
                return 9
            } else {
                var flags = 0
                if showSFW { flags |= 1 }
                if showNSFW { flags |= 2 }
                if showNSFL { flags |= 4 }
                if showNSFP { flags |= 8 }
                if showPOL { flags |= 16 }
                return flags == 0 ? 1 : flags
            }
        }
    }

    var apiPromoted: Int? {
        get {
            switch feedType {
            case .new: return 0
            case .promoted: return 1
            case .junk: return nil
            }
        }
    }

    var apiShowJunk: Bool {
        return feedType == .junk
    }

    var hasActiveContentFilter: Bool {
        return feedType == .junk || showSFW || showNSFW || showNSFL || showNSFP || showPOL
    }

    // MARK: - Initializer
    init() {
        // 1. Lese alle Werte aus UserDefaults, ohne didSet auszulösen (oder stelle sicher, dass didSet sicher ist)
        let initialIsVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) as? Bool ?? true
        let initialRawFeedType = UserDefaults.standard.integer(forKey: Self.feedTypeKey)
        let initialFeedType = FeedType(rawValue: initialRawFeedType) ?? .promoted
        let initialShowSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) as? Bool ?? true
        let initialShowNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        let initialShowNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        let initialShowNSFP = UserDefaults.standard.bool(forKey: Self.showNSFPKey)
        let initialShowPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)
        let initialMaxImageCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) as? Int ?? 100
        let initialRawCommentSortOrder = UserDefaults.standard.integer(forKey: Self.commentSortOrderKey)
        let initialCommentSortOrder = CommentSortOrder(rawValue: initialRawCommentSortOrder) ?? .date
        let initialEnableExperimentalHideSeen = UserDefaults.standard.bool(forKey: Self.enableExperimentalHideSeenKey)
        var initialHideSeenItems = false
        if initialEnableExperimentalHideSeen {
            initialHideSeenItems = UserDefaults.standard.bool(forKey: Self.hideSeenItemsKey)
        }
        let initialRawSubtitleActivationMode = UserDefaults.standard.integer(forKey: Self.subtitleActivationModeKey)
        let initialSubtitleActivationMode = SubtitleActivationMode(rawValue: initialRawSubtitleActivationMode) ?? .automatic
        let initialSelectedCollectionId = UserDefaults.standard.object(forKey: Self.selectedCollectionIdForFavoritesKey) as? Int
        let initialRawColorScheme = UserDefaults.standard.integer(forKey: Self.colorSchemeSettingKey)
        let initialColorScheme = ColorSchemeSetting(rawValue: initialRawColorScheme) ?? .system
        let initialRawGridSize = UserDefaults.standard.integer(forKey: Self.gridSizeSettingKey)
        var initialGridSize = GridSizeSetting(rawValue: initialRawGridSize) ?? .small
        if initialGridSize.rawValue > 5 { // Korrektur für alte gespeicherte Werte
            initialGridSize = .large
        }
        let initialResetFiltersOnAppOpen = UserDefaults.standard.bool(forKey: Self.resetFiltersOnAppOpenKey)

        // 2. Initialisiere alle @Published Properties. Dies löst didSet NICHT aus, wenn der Wert derselbe ist.
        // Wenn wir jedoch einen Default-Wert hier setzen, der sich vom UserDefaults-Wert unterscheidet,
        // würde didSet ausgelöst. Daher ist es wichtig, die Werte aus UserDefaults zuerst zu lesen.
        self.isVideoMuted = initialIsVideoMuted
        self.feedType = initialFeedType
        self.showSFW = initialShowSFW
        self.showNSFW = initialShowNSFW
        self.showNSFL = initialShowNSFL
        self.showNSFP = initialShowNSFP
        self.showPOL = initialShowPOL
        self.maxImageCacheSizeMB = initialMaxImageCacheSizeMB
        self.commentSortOrder = initialCommentSortOrder
        self.enableExperimentalHideSeen = initialEnableExperimentalHideSeen
        self.hideSeenItems = initialHideSeenItems // Wird korrekt behandelt, da enableExperimentalHideSeen schon gesetzt ist
        self.subtitleActivationMode = initialSubtitleActivationMode
        self.selectedCollectionIdForFavorites = initialSelectedCollectionId
        self.colorSchemeSetting = initialColorScheme
        self.gridSize = initialGridSize
        self.resetFiltersOnAppOpen = initialResetFiltersOnAppOpen
        
        // Logging und UserDefaults-Initialisierung (falls Werte nicht vorhanden waren)
        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        // ... (restliches Logging) ...
        Self.logger.info("- gridSize: \(self.gridSize.displayName)")
        Self.logger.info("- resetFiltersOnAppOpen: \(self.resetFiltersOnAppOpen)")

        // Stelle sicher, dass UserDefaults geschrieben werden, falls sie vorher nicht existierten
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil { UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey) }
        // ... (restliche UserDefaults-Checks) ...
        if UserDefaults.standard.object(forKey: Self.gridSizeSettingKey) == nil { UserDefaults.standard.set(self.gridSize.rawValue, forKey: Self.gridSizeSettingKey) }
        if UserDefaults.standard.object(forKey: Self.resetFiltersOnAppOpenKey) == nil { UserDefaults.standard.set(self.resetFiltersOnAppOpen, forKey: Self.resetFiltersOnAppOpenKey) }

        // Aktionen, die nach vollständiger Initialisierung sicher sind
        updateKingfisherCacheLimit() // Hängt von maxImageCacheSizeMB ab
        setupCloudKitKeyValueStoreObserver()
        Task {
            await loadSeenItemIDs()
            await updateCacheSizes()
        }
    }

    // MARK: - Cache Management Methods
    func clearSeenItemsCache() async {
        Self.logger.warning("Clearing Seen Items Cache (Local & iCloud) requested.")
        self.seenItemIDs = []
        Self.logger.info("Cleared in-memory seen items set.")
        await cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
        Self.logger.info("Cleared local seen items cache file via CacheService.")
        cloudStore.removeObject(forKey: Self.iCloudSeenItemsKey)
        let syncSuccess = cloudStore.synchronize()
        Self.logger.info("Removed seen items key from iCloud KVS. Synchronize requested: \(syncSuccess).")
    }
    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache, Kingfisher Image Cache, Seen Items Cache (Local & iCloud) requested.")
        await cacheService.clearAllDataCache()
        await clearSeenItemsCache()
        let logger = Self.logger
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
            Task { await self.updateCacheSizes() }
        }
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
        self.currentImageDataCacheSizeMB = imageSizeMB
        Self.logger.info("Updated currentImageDataCacheSizeMB to: \(String(format: "%.2f", imageSizeMB)) MB")
    }
    private func updateKingfisherCacheLimit() {
        let limitBytes = UInt(self.maxImageCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher (image) disk cache size limit to \(limitBytes) bytes (\(self.maxImageCacheSizeMB) MB).")
    }

    // MARK: - Data Cache Access Methods (Delegated to CacheService)
    func saveItemsToCache(_ items: [Item], forKey cacheKey: String) async {
        guard !cacheKey.isEmpty else { return }
        await cacheService.saveItems(items, forKey: cacheKey)
        await updateDataCacheSize()
    }
    func loadItemsFromCache(forKey cacheKey: String) async -> [Item]? {
         guard !cacheKey.isEmpty else { return nil }
         return await cacheService.loadItems(forKey: cacheKey)
    }
    func clearFavoritesCache(username: String?, collectionId: Int?) async {
        guard let user = username, let colId = collectionId else {
            Self.logger.warning("Cannot clear favorites cache: username or collectionId is nil.")
            return
        }
        let cacheKey = "favorites_\(user.lowercased())_collection_\(colId)"
        Self.logger.info("Clearing favorites data cache requested via AppSettings for key: \(cacheKey).")
        await cacheService.clearCache(forKey: cacheKey)
        await updateDataCacheSize()
    }

    // MARK: - Seen Items Management Methods
    func markItemAsSeen(id: Int) {
        if !seenItemIDs.contains(id) {
             var idsToUpdate = seenItemIDs
             idsToUpdate.insert(id)
             seenItemIDs = idsToUpdate
             Self.logger.debug("Marked item \(id) as seen (in-memory). Total seen: \(self.seenItemIDs.count)")
             saveSeenItemsTask?.cancel()
             saveSeenItemsTask = Task {
                 do {
                     try await Task.sleep(for: saveSeenItemsDebounceDelay)
                     guard !Task.isCancelled else {
                         Self.logger.info("Debounced save task for seen items cancelled during sleep.")
                         return
                     }
                     await self.saveSeenItemIDsToCloudAndLocal()
                 } catch is CancellationError {
                      Self.logger.info("Debounced save task for seen items cancelled.")
                 } catch {
                     Self.logger.error("Error in debounced save task for seen items: \(error.localizedDescription)")
                 }
             }
        } else {
             Self.logger.trace("Item \(id) was already marked as seen.")
        }
    }

    func markItemsAsSeen(ids: Set<Int>) {
         let newIDs = ids.subtracting(seenItemIDs)
         if !newIDs.isEmpty {
             Self.logger.debug("Marking \(newIDs.count) new items as seen (in-memory).")
             var idsToUpdate = seenItemIDs
             idsToUpdate.formUnion(newIDs)
             seenItemIDs = idsToUpdate
             Self.logger.info("Marked \(newIDs.count) items as seen (in-memory). Total seen: \(self.seenItemIDs.count)")
             saveSeenItemsTask?.cancel()
             saveSeenItemsTask = Task {
                 do {
                     try await Task.sleep(for: saveSeenItemsDebounceDelay)
                     guard !Task.isCancelled else {
                         Self.logger.info("Debounced save task for multiple seen items cancelled during sleep.")
                         return
                     }
                     await self.saveSeenItemIDsToCloudAndLocal()
                 } catch is CancellationError {
                     Self.logger.info("Debounced save task for multiple seen items cancelled.")
                 } catch {
                     Self.logger.error("Error in debounced save task for multiple seen items: \(error.localizedDescription)")
                 }
             }
         } else {
             Self.logger.trace("No new items to mark as seen from the provided batch.")
         }
    }

    public func forceSaveSeenItems() async {
        saveSeenItemsTask?.cancel()
        Self.logger.info("Force save seen items requested. Current debounced task (if any) cancelled.")
        await saveSeenItemIDsToCloudAndLocal()
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
                self.seenItemIDs = decodedIDs
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
             self.seenItemIDs = localIDs
             Self.logger.info("Loaded \(localIDs.count) seen item IDs from LOCAL cache.")
             Task.detached {
                  Self.logger.info("Syncing locally loaded seen IDs UP to iCloud...")
                  await self.saveSeenItemIDsToCloudAndLocal()
             }
        } else {
            Self.logger.warning("Could not load seen item IDs from iCloud or local cache. Starting with an empty set.")
             self.seenItemIDs = []
        }
    }

    // MARK: - iCloud KVS Synchronization Handling
    private func setupCloudKitKeyValueStoreObserver() {
        if keyValueStoreChangeObserver != nil { NotificationCenter.default.removeObserver(keyValueStoreChangeObserver!); keyValueStoreChangeObserver = nil }
        keyValueStoreChangeObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloudStore, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in await self?.handleCloudKitStoreChange(notification: notification) }
        }
        let syncSuccess = cloudStore.synchronize(); Self.logger.info("Setup iCloud KVS observer. Initial synchronize requested: \(syncSuccess)")
    }
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
                self.seenItemIDs = []
                await self.cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
                Self.logger.info("Cleared local seen items state because key was missing in iCloud after external change notification.")
                return
            }
            do {
                let incomingIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData); Self.logger.info("Successfully decoded \(incomingIDs.count) seen IDs from external iCloud KVS change.")
                let localIDs = self.seenItemIDs; let mergedIDs = localIDs.union(incomingIDs)
                if mergedIDs.count > localIDs.count {
                    self.seenItemIDs = mergedIDs; Self.logger.info("Merged external seen IDs. New total: \(mergedIDs.count).")
                    Task.detached { await self.cacheService.saveSeenIDs(mergedIDs, forKey: Self.localSeenItemsCacheKey) }
                } else {
                    Self.logger.debug("Incoming seen IDs did not add new items to the local set. No UI update needed.")
                    Task.detached { await self.cacheService.saveSeenIDs(localIDs, forKey: Self.localSeenItemsCacheKey) }
                }
            } catch { Self.logger.error("Failed to decode seen IDs from external iCloud KVS change data: \(error.localizedDescription)") }
        case NSUbiquitousKeyValueStoreAccountChange: Self.logger.warning("iCloud account changed. Reloading seen items state."); await loadSeenItemIDs()
        case NSUbiquitousKeyValueStoreQuotaViolationChange: Self.logger.error("iCloud KVS Quota Violation! Syncing might stop.")
        default: Self.logger.warning("Unhandled iCloud KVS change reason: \(changeReason)"); break
        }
    }

    deinit {
        if let observer = keyValueStoreChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            AppSettings.logger.debug("Removed iCloud KVS observer in deinit.")
        }
        saveSeenItemsTask?.cancel()
        AppSettings.logger.debug("Cancelled pending saveSeenItemsTask in deinit.")
    }
}
// --- END OF COMPLETE FILE ---
