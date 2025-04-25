// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine
import os
import Kingfisher

// Enum FeedType (unverändert)
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

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")

    // MARK: - Dependencies
    private let cacheService = CacheService()

    // MARK: - UserDefaults Keys (Angepasst)
    private static let isVideoMutedPreferenceKey = "isVideoMutedPreference_v1"
    private static let feedTypeKey = "feedTypePreference_v1"
    private static let showSFWKey = "showSFWPreference_v1"
    private static let showNSFWKey = "showNSFWPreference_v1"
    private static let showNSFLKey = "showNSFLPreference_v1"
    // --- UM BENANNT ---
    private static let showNSFPKey = "showNSFPPreference_v1" // Alt: showPOLKey (Flag 8)
    // --- NEU ---
    private static let showPOLKey = "showPOLPreference_v1"   // Neu: Politik (Flag 16)
    private static let maxCacheSizeMBKey = "maxCacheSizeMB_v1"

    // MARK: - Published Properties (Angepasst)
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
    // --- UM BENANNT & NEU ---
    @Published var showNSFP: Bool { // Alt: showPOL (Flag 8)
        didSet { UserDefaults.standard.set(showNSFP, forKey: Self.showNSFPKey) }
    }
    @Published var showPOL: Bool { // Neu: Politik (Flag 16)
        didSet { UserDefaults.standard.set(showPOL, forKey: Self.showPOLKey) }
    }
    // -----------------------
    @Published var maxCacheSizeMB: Int {
        didSet {
            UserDefaults.standard.set(maxCacheSizeMB, forKey: Self.maxCacheSizeMBKey)
            updateKingfisherCacheLimit()
        }
    }
    @Published var currentCacheSizeMB: Double

    // MARK: - Computed Properties for API (Angepasst)
    var apiFlags: Int {
        get {
            var flags = 0
            if showSFW { flags |= 1 }    // 1
            if showNSFW { flags |= 2 }   // 2
            if showNSFL { flags |= 4 }   // 4
            if showNSFP { flags |= 8 }   // 8  (ehemals POL)
            if showPOL { flags |= 16 }  // 16 (neu für Politik)

            // API erwartet 1 (SFW), wenn nichts ausgewählt ist
            return flags == 0 ? 1 : flags
        }
    }
    var apiPromoted: Int {
        get {
            return feedType.rawValue
        }
    }

    // --- Angepasst: Prüft jetzt auch showPOL ---
    var hasActiveContentFilter: Bool {
        return showSFW || showNSFW || showNSFL || showNSFP || showPOL
    }
    // -------------------------------------------

    // MARK: - Initializer (Angepasst)
    init() {
        // Lade vorhandene Werte oder setze Standards
        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil
                             ? true : UserDefaults.standard.bool(forKey: Self.isVideoMutedPreferenceKey)
        self.feedType = FeedType(rawValue: UserDefaults.standard.integer(forKey: Self.feedTypeKey)) ?? .promoted
        self.showSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) == nil
                        ? true : UserDefaults.standard.bool(forKey: Self.showSFWKey)
        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        // --- Angepasst: Lade/Setze für NSFP und POL ---
        self.showNSFP = UserDefaults.standard.bool(forKey: Self.showNSFPKey) // Lade NSFP (alt POL)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)   // Lade neuen POL
        // -------------------------------------------
        self.maxCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxCacheSizeMBKey) == nil
                              ? 100 : UserDefaults.standard.integer(forKey: Self.maxCacheSizeMBKey)
        self.currentCacheSizeMB = 0.0

        // Log Initialwerte (Angepasst)
        Self.logger.info("AppSettings initialized:")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        Self.logger.info("- Content Flags: SFW(\(self.showSFW)) NSFW(\(self.showNSFW)) NSFL(\(self.showNSFL)) NSFP(\(self.showNSFP)) POL(\(self.showPOL)) -> API Flags: \(self.apiFlags)") // Log angepasst
        Self.logger.info("- maxCacheSizeMB: \(self.maxCacheSizeMB)")

        // Speichere Standardwerte, falls nötig
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil {
            UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey)
        }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil {
            UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey)
        }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil {
            UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey)
        }
        // NSFP und POL brauchen keinen Standardwert hier, da bool(forKey:) false zurückgibt, wenn nichts da ist.
        if UserDefaults.standard.object(forKey: Self.maxCacheSizeMBKey) == nil {
            UserDefaults.standard.set(self.maxCacheSizeMB, forKey: Self.maxCacheSizeMBKey)
        }

        updateKingfisherCacheLimit()
        Task { await updateCurrentCombinedCacheSize() }
    }

    // MARK: - Cache Management Methods
    /// Löscht den Feed-Daten-Cache UND den Kingfisher Image-Cache.
    func clearFeedAndImageCache() async {
        Self.logger.info("Clearing Feed Data Cache and Kingfisher Image Cache requested.")
        // Lösche spezifisch den Feed-Daten-Cache
        await cacheService.clearFeedCache()
        let logger = Self.logger // Lokale Kopie
        // Lösche Kingfisher Cache
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
        }
        await updateCurrentCombinedCacheSize()
    }

    /// Löscht ALLE Daten-Caches (Feed + Favoriten etc.) UND den Kingfisher Image-Cache.
    func clearAllAppCache() async {
        Self.logger.warning("Clearing ALL Data Cache and Kingfisher Image Cache requested.")
        // Lösche alle Daten-Caches
        await cacheService.clearAllDataCache()
        let logger = Self.logger // Lokale Kopie
        // Lösche Kingfisher Cache
        KingfisherManager.shared.cache.clearDiskCache {
            logger.info("Kingfisher disk cache clearing finished.")
        }
        await updateCurrentCombinedCacheSize()
    }

    /// Aktualisiert die Anzeige der *kombinierten* Cache-Größe (Daten + Bilder).
    func updateCurrentCombinedCacheSize() async {
        // Hole Größe des Daten-Caches
        let dataSizeBytes = await cacheService.getCurrentDataCacheTotalSize()
        let logger = Self.logger // Lokale Kopie für Closure

        // Hole Größe des Kingfisher Caches
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

        // Kombiniere und konvertiere zu MB
        let totalSizeBytes = Int64(dataSizeBytes) + Int64(imageSizeBytes)
        let totalSizeMB = Double(totalSizeBytes) / (1024.0 * 1024.0)

        // Aktualisiere Published Property auf dem Main Actor
        await MainActor.run {
            self.currentCacheSizeMB = totalSizeMB
            Self.logger.info("Updated combined currentCacheSizeMB to: \(String(format: "%.2f", totalSizeMB)) MB (Data: \(dataSizeBytes) B, Images: \(imageSizeBytes) B)")
        }
    }

    /// Aktualisiert das Größenlimit für den Kingfisher Cache.
    private func updateKingfisherCacheLimit() {
        let limitBytes = UInt(self.maxCacheSizeMB) * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = limitBytes
        Self.logger.info("Set Kingfisher disk cache size limit to \(limitBytes) bytes (\(self.maxCacheSizeMB) MB).")
    }

    // MARK: - Cache Access Methods (Daten-Cache mit Key)
    /// Speichert Items im Daten-Cache unter einem spezifischen Schlüssel.
    func saveItemsToCache(_ items: [Item], forKey cacheKey: String) async {
        guard !cacheKey.isEmpty else {
             Self.logger.warning("Attempted to save items with an empty cache key. Aborting.")
             return
        }
        await cacheService.saveItems(items, forKey: cacheKey)
    }

    /// Lädt Items aus dem Daten-Cache anhand eines spezifischen Schlüssels.
    func loadItemsFromCache(forKey cacheKey: String) async -> [Item]? {
         guard !cacheKey.isEmpty else {
             Self.logger.warning("Attempted to load items with an empty cache key. Returning nil.")
             return nil
         }
        return await cacheService.loadItems(forKey: cacheKey)
    }
}
// --- END OF COMPLETE FILE ---
