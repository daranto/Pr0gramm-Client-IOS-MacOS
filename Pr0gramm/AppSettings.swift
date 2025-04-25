// Pr0gramm/Pr0gramm/AppSettings.swift

import Foundation
import Combine
import os
import Kingfisher

// Enum FeedType (Sollte jetzt wieder korrekt erkannt werden)
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

@MainActor
class AppSettings: ObservableObject {

    // Logger bleibt static
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")

    // MARK: - Dependencies
    private let cacheService = CacheService()

    // MARK: - UserDefaults Keys
    private static let isVideoMutedPreferenceKey = "isVideoMutedPreference_v1"
    private static let feedTypeKey = "feedTypePreference_v1"
    private static let showSFWKey = "showSFWPreference_v1"
    private static let showNSFWKey = "showNSFWPreference_v1"
    private static let showNSFLKey = "showNSFLPreference_v1"
    private static let showPOLKey = "showPOLPreference_v1"
    private static let maxCacheSizeMBKey = "maxCacheSizeMB_v1"

    // MARK: - Published Properties
    @Published var isVideoMuted: Bool {
        didSet { UserDefaults.standard.set(isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
    }
    @Published var feedType: FeedType {
        didSet { UserDefaults.standard.set(feedType.rawValue, forKey: Self.feedTypeKey) }
    }
    @Published var showSFW: Bool {
        didSet { UserDefaults.standard.set(showSFW, forKey: Self.showSFWKey) }
    }
    @Published var showNSFW: Bool {
        didSet { UserDefaults.standard.set(showNSFW, forKey: Self.showNSFWKey) }
    }
    @Published var showNSFL: Bool {
        didSet { UserDefaults.standard.set(showNSFL, forKey: Self.showNSFLKey) }
    }
    @Published var showPOL: Bool {
        didSet { UserDefaults.standard.set(showPOL, forKey: Self.showPOLKey) }
    }
    @Published var maxCacheSizeMB: Int {
        didSet {
            UserDefaults.standard.set(maxCacheSizeMB, forKey: Self.maxCacheSizeMBKey)
            updateKingfisherCacheLimit()
        }
    }
    // Wird initial auf 0 gesetzt und dann im Task aktualisiert
    @Published var currentCacheSizeMB: Double

    // MARK: - Computed Properties for API
    // --- KORRIGIERT: Getter hinzugefügt, falls Compilerfehler bestehen ---
    var apiFlags: Int {
        get {
            var flags = 0
            if showSFW { flags |= 1 }
            if showNSFW { flags |= 2 }
            if showNSFL { flags |= 4 }
            if showPOL { flags |= 8 }
            return flags == 0 ? 1 : flags
        }
    }
    var apiPromoted: Int {
        get {
            return feedType.rawValue
        }
    }
    // ---------------------------------------------------------------

    // MARK: - Initializer (UMSTRUKTURIERT)
    init() {
        // --- Phase 1: Initialize ALL stored properties FIRST ---
        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil
                             ? true
                             : UserDefaults.standard.bool(forKey: Self.isVideoMutedPreferenceKey)

        self.feedType = FeedType(rawValue: UserDefaults.standard.integer(forKey: Self.feedTypeKey))
                         ?? .promoted

        self.showSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) == nil
                       ? true
                       : UserDefaults.standard.bool(forKey: Self.showSFWKey)

        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)

        self.maxCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxCacheSizeMBKey) == nil
                              ? 100
                              : UserDefaults.standard.integer(forKey: Self.maxCacheSizeMBKey)

        // Initialisiere currentCacheSizeMB (wird gleich im Task aktualisiert)
        self.currentCacheSizeMB = 0.0

        // --- Phase 1 ENDS HERE ---

        // --- Phase 2: Now 'self' is fully available ---
        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        Self.logger.info("- Content Flags: SFW(\(self.showSFW)) NSFW(\(self.showNSFW))")
        Self.logger.info("- Content Flags: NSFL(\(self.showNSFL)) POL(\(self.showPOL))")
        Self.logger.info("- maxCacheSizeMB: \(self.maxCacheSizeMB)")

        // Setze Default-Werte in UserDefaults, falls nötig
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil {
            UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey)
        }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil {
            UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey)
        }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil {
            UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey)
        }
        if UserDefaults.standard.object(forKey: Self.maxCacheSizeMBKey) == nil {
            UserDefaults.standard.set(self.maxCacheSizeMB, forKey: Self.maxCacheSizeMBKey)
        }

        // Rufe Methoden erst in Phase 2 auf
        updateKingfisherCacheLimit()
        Task { await updateCurrentCacheSize() }
    }

    // MARK: - Cache Management Methods

    func clearAppCache() async {
        Self.logger.info("Clear App Cache requested.")
        await cacheService.clearAllCache()
        let logger = Self.logger // Lokale Kopie
        // --- KORRIGIERT: await entfernt ---
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
        }
        // ---------------------------------
        await updateCurrentCacheSize()
    }

    func updateCurrentCacheSize() async {
        let dataSizeBytes = await cacheService.getCurrentCacheTotalSize()
        let logger = Self.logger // Lokale Kopie für Closure
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

        let totalSizeBytes = Int64(dataSizeBytes) + Int64(imageSizeBytes)
        let totalSizeMB = Double(totalSizeBytes) / (1024.0 * 1024.0)

        await MainActor.run {
            self.currentCacheSizeMB = totalSizeMB
            Self.logger.info("Updated combined currentCacheSizeMB to: \(String(format: "%.2f", totalSizeMB)) MB (Data: \(dataSizeBytes) B, Images: \(imageSizeBytes) B)")
        }
    }

    private func updateKingfisherCacheLimit() {
        let limitBytes = UInt(self.maxCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher disk cache size limit to \(limitBytes) bytes (\(self.maxCacheSizeMB) MB).")
    }

    // MARK: - Cache Access Methods (Daten-Cache)
    func saveItemsToCache(_ items: [Item], for feedType: FeedType) async {
        await cacheService.saveItems(items, for: feedType)
    }

    func loadItemsFromCache(for feedType: FeedType) async -> [Item]? {
        return await cacheService.loadItems(for: feedType)
    }
}
