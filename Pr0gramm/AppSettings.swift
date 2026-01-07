// Pr0gramm/Pr0gramm/AppSettings.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine // Needed for observer token
import os
import Kingfisher
import CloudKit // Needed for NSUbiquitousKeyValueStore
import SwiftUI // Needed for ColorScheme, Color
import BackgroundTasks // Für BGTaskScheduler
import UserNotifications // Für Berechtigungen und Badge

// MARK: - Excluded Tag Model

struct ExcludedTag: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    
    init(id: UUID = UUID(), name: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
    }
}

enum BackgroundFetchInterval: Int, CaseIterable, Identifiable {
    case minutes30 = 1800 // 30 * 60
    case minutes60 = 3600 // 60 * 60
    case hours2 = 7200    // 2 * 3600
    case hours4 = 14400   // 4 * 3600
    case hours6 = 21600   // 6 * 3600
    case hours12 = 43200  // 12 * 3600

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .minutes30: return "30 Minuten"
        case .minutes60: return "1 Stunde"
        case .hours2: return "2 Stunden"
        case .hours4: return "4 Stunden"
        case .hours6: return "6 Stunden"
        case .hours12: return "12 Stunden"
        }
    }

    var timeInterval: TimeInterval {
        return TimeInterval(self.rawValue)
    }
}

enum FeedType: Int, CaseIterable, Identifiable {
    case new = 0
    case promoted = 1
    case junk = 2

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .new: return "Neu"
        case .promoted: return "Beliebt"
        case .junk: return "Müll"
        }
    }
}

enum CommentSortOrder: Int, CaseIterable, Identifiable {
    case date = 0, score = 1
    var id: Int { self.rawValue }
    var displayName: String {
        switch self { case .date: return "Datum / Zeit"; case .score: return "Benis (Score)"}
    }
}

enum SubtitleActivationMode: Int, CaseIterable, Identifiable {
    case disabled = 0
    case alwaysOn = 2
    var id: Int { self.rawValue }
    var displayName: String {
        switch self {
        case .disabled: return "Deaktiviert"
        case .alwaysOn: return "Aktiviert"
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

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case orange = "Bewährtes Orange"
    case green = "Angenehmes Grün"
    case olive = "Olivgrün des Friedens"
    case blue = "Episches Blau"
    case pink = "Altes Pink"

    var id: String { self.rawValue }
    var displayName: String { self.rawValue }

    var swiftUIColor: Color {
        switch self {
        case .orange: return Color(hex: 0xee4d2e)
        case .green: return Color(hex: 0x64b944)
        case .olive: return Color(hex: 0x827717)
        case .blue: return Color(hex: 0x008FFF)
        case .pink: return Color(hex: 0xc2185b)
        }
    }
}


@MainActor
class AppSettings: ObservableObject {

    private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppSettings")
    private let cacheService = CacheService()
    private nonisolated let cloudStore = NSUbiquitousKeyValueStore.default


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
    private static let subtitleActivationModeKey = "subtitleActivationMode_v1"
    private static let selectedCollectionIdForFavoritesKey = "selectedCollectionIdForFavorites_v1"
    private static let colorSchemeSettingKey = "colorSchemeSetting_v1"
    private static let gridSizeSettingKey = "gridSizeSetting_v1"
    private static let enableStartupFiltersKey = "enableStartupFilters_v1"
    private static let startupFilterSFWKey = "startupFilterSFW_v1"
    private static let startupFilterNSFWKey = "startupFilterNSFW_v1"
    private static let startupFilterNSFLKey = "startupFilterNSFL_v1"
    private static let startupFilterPOLKey = "startupFilterPOL_v1"
    private static let accentColorChoiceKey = "accentColorChoice_v1"
    private static let localSeenItemsCacheKey = "seenItems_v1"
    private static let iCloudSeenItemsKey = "seenItemIDs_iCloud_v2"
    private static let iCloudExcludedTagsKey = "excludedTags_iCloud_v1"
    private static let enableUnlimitedStyleFeedKey = "enableUnlimitedStyleFeed_v1"
    private static let enableBackgroundFetchForNotificationsKey = "enableBackgroundFetchForNotifications_v1"
    private static let backgroundFetchIntervalKey = "backgroundFetchInterval_v1"
    private static let forcePhoneLayoutOnPadAndMacKey = "forcePhoneLayoutOnPadAndMac_v1" // Neuer Key
    private static let excludedTagsKey = "excludedTags_v1" // Neue Key für ausgeschlossene Tags
    private var keyValueStoreChangeObserver: NSObjectProtocol?

    @Published var isVideoMuted: Bool { didSet { UserDefaults.standard.set(isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) } }
    @Published var feedType: FeedType {
        didSet {
            UserDefaults.standard.set(feedType.rawValue, forKey: Self.feedTypeKey)
            Self.logger.info("Feed type changed to: \(self.feedType.displayName)")
            if isUserLoggedInForApiFlags && feedType != .junk {
                self.showNSFP = self.showSFW
            }
        }
    }
    @Published var showSFW: Bool {
        didSet {
            UserDefaults.standard.set(showSFW, forKey: Self.showSFWKey)
            if isUserLoggedInForApiFlags && feedType != .junk {
                self.showNSFP = showSFW
                AppSettings.logger.debug("showSFW changed to \(self.showSFW). Automatically set showNSFP to \(self.showNSFP) (logged in, not junk).")
            }
        }
    }
    @Published var showNSFW: Bool { didSet { UserDefaults.standard.set(showNSFW, forKey: Self.showNSFWKey) } }
    @Published var showNSFL: Bool { didSet { UserDefaults.standard.set(showNSFL, forKey: Self.showNSFLKey) } }
    @Published var showNSFP: Bool {
        didSet {
            UserDefaults.standard.set(showNSFP, forKey: Self.showNSFPKey)
            AppSettings.logger.debug("showNSFP (internal state) changed to \(self.showNSFP).")
        }
    }
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
            if oldValue != gridSize {
                UserDefaults.standard.set(gridSize.rawValue, forKey: Self.gridSizeSettingKey)
                Self.logger.info("Grid size setting changed to: \(self.gridSize.displayName) (rawValue: \(self.gridSize.rawValue))")
            }
        }
    }
    
    @Published var enableStartupFilters: Bool {
        didSet {
            UserDefaults.standard.set(enableStartupFilters, forKey: Self.enableStartupFiltersKey)
            Self.logger.info("Enable startup filters setting changed to: \(self.enableStartupFilters)")
            if enableStartupFilters {
                if UserDefaults.standard.object(forKey: Self.startupFilterSFWKey) == nil { self.startupFilterSFW = true }
                if UserDefaults.standard.object(forKey: Self.startupFilterNSFWKey) == nil { self.startupFilterNSFW = false }
                if UserDefaults.standard.object(forKey: Self.startupFilterNSFLKey) == nil { self.startupFilterNSFL = false }
                if UserDefaults.standard.object(forKey: Self.startupFilterPOLKey) == nil { self.startupFilterPOL = false }
            }
        }
    }
    @Published var startupFilterSFW: Bool {
        didSet {
            UserDefaults.standard.set(startupFilterSFW, forKey: Self.startupFilterSFWKey)
        }
    }
    @Published var startupFilterNSFW: Bool { didSet { UserDefaults.standard.set(startupFilterNSFW, forKey: Self.startupFilterNSFWKey) } }
    @Published var startupFilterNSFL: Bool { didSet { UserDefaults.standard.set(startupFilterNSFL, forKey: Self.startupFilterNSFLKey) } }
    @Published var startupFilterPOL: Bool { didSet { UserDefaults.standard.set(startupFilterPOL, forKey: Self.startupFilterPOLKey) } }

    @Published var accentColorChoice: AccentColorChoice {
        didSet {
            if oldValue != accentColorChoice {
                UserDefaults.standard.set(accentColorChoice.rawValue, forKey: Self.accentColorChoiceKey)
                Self.logger.info("Accent color choice changed to: \(self.accentColorChoice.displayName)")
            }
        }
    }
    
    @Published var enableUnlimitedStyleFeed: Bool {
        didSet {
            if oldValue != enableUnlimitedStyleFeed {
                UserDefaults.standard.set(enableUnlimitedStyleFeed, forKey: Self.enableUnlimitedStyleFeedKey)
                Self.logger.info("Experimental 'Enable Unlimited Style Feed' setting changed to: \(self.enableUnlimitedStyleFeed)")
            }
        }
    }

    @Published var enableBackgroundFetchForNotifications: Bool {
        didSet {
            UserDefaults.standard.set(enableBackgroundFetchForNotifications, forKey: Self.enableBackgroundFetchForNotificationsKey)
            Self.logger.info("Enable Background Fetch for Notifications setting changed to: \(self.enableBackgroundFetchForNotifications)")
            if enableBackgroundFetchForNotifications {
                BackgroundNotificationManager.shared.requestNotificationPermission()
                BackgroundNotificationManager.shared.scheduleAppRefresh()
            } else {
                BackgroundNotificationManager.shared.cancelAllBackgroundTasks()
                Task {
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    Self.logger.info("Background fetch disabled. Cancelled tasks, reset badge and cleared delivered notifications.")
                }
            }
        }
    }
    
    @Published var backgroundFetchInterval: BackgroundFetchInterval {
        didSet {
            UserDefaults.standard.set(backgroundFetchInterval.rawValue, forKey: Self.backgroundFetchIntervalKey)
            Self.logger.info("Background Fetch Interval setting changed to: \(self.backgroundFetchInterval.displayName)")
            if enableBackgroundFetchForNotifications {
                BackgroundNotificationManager.shared.scheduleAppRefresh()
            }
        }
    }

    // Neue Einstellung für das Layout
    @Published var forcePhoneLayoutOnPadAndMac: Bool {
        didSet {
            if oldValue != forcePhoneLayoutOnPadAndMac {
                UserDefaults.standard.set(forcePhoneLayoutOnPadAndMac, forKey: Self.forcePhoneLayoutOnPadAndMacKey)
                Self.logger.info("Force phone layout on iPad/Mac setting changed to: \(self.forcePhoneLayoutOnPadAndMac)")
            }
        }
    }
    
    // Neue Einstellung für ausgeschlossene Tags
    // Die iCloud ist die einzige "Source of Truth", UserDefaults ist nur ein lokaler Cache
    @Published var excludedTags: [ExcludedTag] {
        didSet {
            Self.logger.info("Excluded tags changed to: \(self.excludedTags.map { "\($0.name)(\($0.isEnabled ? "on" : "off"))" })")
            
            // Lokaler Cache (nur als Backup, falls iCloud nicht verfügbar ist)
            if let encoded = try? JSONEncoder().encode(excludedTags) {
                UserDefaults.standard.set(encoded, forKey: Self.excludedTagsKey)
            }
            
            // iCloud ist die primäre Datenquelle - sofort synchronisieren
            saveExcludedTagsToCloudSync()
        }
    }


    @Published var transientSessionMuteState: Bool? = nil
    @Published var currentImageDataCacheSizeMB: Double = 0.0
    @Published var currentDataCacheSizeMB: Double = 0.0
    @Published private(set) var seenItemIDs: Set<Int> = []

    private var saveSeenItemsTask: Task<Void, Never>?
    private let saveSeenItemsDebounceDelay: Duration = .seconds(1)

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


    private var _isUserLoggedInForApiFlags: Bool = false
    private let flagAccessQueue = DispatchQueue(label: "com.aetherium.Pr0gramm.flagAccessQueue")

    public func updateUserLoginStatusForApiFlags(isLoggedIn: Bool) {
        let oldLoginStatus = self._isUserLoggedInForApiFlags
        flagAccessQueue.sync {
            self._isUserLoggedInForApiFlags = isLoggedIn
        }
        AppSettings.logger.info("User login status for API flags calculation updated to: \(isLoggedIn)")
        
        if oldLoginStatus != isLoggedIn {
            if isLoggedIn && self.feedType != .junk {
                self.showNSFP = self.showSFW
            } else if !isLoggedIn {
                self.showNSFP = self.showSFW
            }
        }
    }

    private var isUserLoggedInForApiFlags: Bool {
        flagAccessQueue.sync {
            return self._isUserLoggedInForApiFlags
        }
    }

    var apiFlags: Int {
        get {
            let loggedIn = self.isUserLoggedInForApiFlags

            if !loggedIn {
                return 1
            }

            if feedType == .junk {
                // Im Junk-Feed werden alle Flags berücksichtigt
                var flags = 0
                if showSFW { flags |= 1 }
                if showNSFP { flags |= 8 }
                if showNSFW { flags |= 2 }
                if showNSFL { flags |= 4 }
                if showPOL { flags |= 16 }
                return flags == 0 ? 1 : flags
            } else {
                // In anderen Feeds wird NSFP automatisch mit SFW gekoppelt
                var flags = 0
                if showSFW {
                    flags |= 1
                    flags |= 8
                }
                if showNSFW {
                    flags |= 2
                }
                if showNSFL {
                    flags |= 4
                }
                if showPOL {
                    flags |= 16
                }
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
    
    /// Gibt einen Tag-String für die API zurück, der alle ausgeschlossenen Tags im Format "!++-tag1,+-tag2" enthält.
    /// Falls keine Tags ausgeschlossen sind oder der aktuelle Feed-Typ "Müll" ist, wird `nil` zurückgegeben.
    /// Leerzeichen in Tag-Namen werden durch "+-" ersetzt (z.B. "Wichteln 2025" wird zu "+-Wichteln+-2025").
    /// Ausgeschlossene Tags gelten nur für "Neu" und "Beliebt", nicht für "Müll".
    var apiExcludedTagsString: String? {
        // Im Müll-Feed werden keine Tags ausgeschlossen
        guard feedType != .junk else { return nil }
        
        let enabledTags = excludedTags.filter { $0.isEnabled }
        guard !enabledTags.isEmpty else { return nil }
        let tagString = enabledTags.map { tag in
            // Leerzeichen in Tag-Namen durch "+-" ersetzen
            let processedName = tag.name.replacingOccurrences(of: " ", with: "+-")
            return "+-\(processedName)"
        }.joined(separator: ",")
        return "!\(tagString)"
    }

    var hasActiveContentFilter: Bool {
        if isUserLoggedInForApiFlags {
            if feedType == .junk {
                return showSFW || showNSFP
            } else {
                return showSFW || showNSFW || showNSFL || showPOL
            }
        } else {
            return showSFW
        }
    }

    init() {
        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) as? Bool ?? true
        
        let initialRawFeedType = UserDefaults.standard.integer(forKey: Self.feedTypeKey)
        self._feedType = Published(initialValue: FeedType(rawValue: initialRawFeedType) ?? .promoted)
        
        let initialNSFPFromDefaults = UserDefaults.standard.object(forKey: Self.showNSFPKey) as? Bool
        self._showNSFP = Published(initialValue: initialNSFPFromDefaults ?? (UserDefaults.standard.object(forKey: Self.showSFWKey) as? Bool ?? true))
        
        self._showSFW = Published(initialValue: UserDefaults.standard.object(forKey: Self.showSFWKey) as? Bool ?? true)
        
        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)
        
        self.maxImageCacheSizeMB = UserDefaults.standard.object(forKey: Self.maxImageCacheSizeMBKey) as? Int ?? 100
        let initialRawCommentSortOrder = UserDefaults.standard.integer(forKey: Self.commentSortOrderKey)
        self.commentSortOrder = CommentSortOrder(rawValue: initialRawCommentSortOrder) ?? .date
        
        self.hideSeenItems = UserDefaults.standard.bool(forKey: Self.hideSeenItemsKey)

        let initialRawSubtitleActivationMode = UserDefaults.standard.integer(forKey: Self.subtitleActivationModeKey)
        self.subtitleActivationMode = SubtitleActivationMode(rawValue: initialRawSubtitleActivationMode) ?? .disabled
        self.selectedCollectionIdForFavorites = UserDefaults.standard.object(forKey: Self.selectedCollectionIdForFavoritesKey) as? Int
        let initialRawColorScheme = UserDefaults.standard.integer(forKey: Self.colorSchemeSettingKey)
        self.colorSchemeSetting = ColorSchemeSetting(rawValue: initialRawColorScheme) ?? .system
        let initialRawGridSize = UserDefaults.standard.integer(forKey: Self.gridSizeSettingKey)
        var tempGridSize = GridSizeSetting(rawValue: initialRawGridSize) ?? .small
        if tempGridSize.rawValue > 5 { tempGridSize = .large }
        self.gridSize = tempGridSize
        
        self.enableStartupFilters = UserDefaults.standard.bool(forKey: Self.enableStartupFiltersKey)
        self.startupFilterSFW = UserDefaults.standard.object(forKey: Self.startupFilterSFWKey) as? Bool ?? true
        self.startupFilterNSFW = UserDefaults.standard.bool(forKey: Self.startupFilterNSFWKey)
        self.startupFilterNSFL = UserDefaults.standard.bool(forKey: Self.startupFilterNSFLKey)
        self.startupFilterPOL = UserDefaults.standard.bool(forKey: Self.startupFilterPOLKey)

        let initialRawAccentColor = UserDefaults.standard.string(forKey: Self.accentColorChoiceKey)
        self.accentColorChoice = AccentColorChoice(rawValue: initialRawAccentColor ?? AccentColorChoice.blue.rawValue) ?? .blue
        self.enableUnlimitedStyleFeed = UserDefaults.standard.bool(forKey: Self.enableUnlimitedStyleFeedKey)
        self.enableBackgroundFetchForNotifications = UserDefaults.standard.object(forKey: Self.enableBackgroundFetchForNotificationsKey) as? Bool ?? false
        let initialRawFetchInterval = UserDefaults.standard.integer(forKey: Self.backgroundFetchIntervalKey)
        self.backgroundFetchInterval = BackgroundFetchInterval(rawValue: initialRawFetchInterval) ?? .minutes60
        self.forcePhoneLayoutOnPadAndMac = UserDefaults.standard.bool(forKey: Self.forcePhoneLayoutOnPadAndMacKey)
        
        // Load excluded tags - iCloud ist die primäre Datenquelle
        // Wir laden NICHT von UserDefaults beim Start, sondern warten auf iCloud
        self.excludedTags = []
        
        Self.logger.info("AppSettings initialized (Stage 2 Log):")
        Self.logger.info("- isVideoMuted: \(self.isVideoMuted)")
        Self.logger.info("- feedType: \(self.feedType.displayName)")
        Self.logger.info("- showSFW: \(self.showSFW), showNSFW: \(self.showNSFW), showNSFL: \(self.showNSFL), showNSFP: \(self.showNSFP), showPOL: \(self.showPOL)")
        Self.logger.info("- apiFlags computed: \(self.apiFlags), apiPromoted computed: \(String(describing: self.apiPromoted)), apiShowJunk computed: \(self.apiShowJunk)")
        Self.logger.info("- hideSeenItems (actual): \(self.hideSeenItems)")
        Self.logger.info("- subtitleActivationMode: \(self.subtitleActivationMode.displayName)")
        Self.logger.info("- selectedCollectionIdForFavorites: \(self.selectedCollectionIdForFavorites != nil ? String(self.selectedCollectionIdForFavorites!) : "nil")")
        Self.logger.info("- colorSchemeSetting: \(self.colorSchemeSetting.displayName)")
        Self.logger.info("- gridSize: \(self.gridSize.displayName)")
        Self.logger.info("- enableStartupFilters: \(self.enableStartupFilters)")
        Self.logger.info("- startupFilters (SFW:\(self.startupFilterSFW), NSFW:\(self.startupFilterNSFW), NSFL:\(self.startupFilterNSFL), POL:\(self.startupFilterPOL))")
        Self.logger.info("- accentColorChoice: \(self.accentColorChoice.displayName)")
        Self.logger.info("- enableUnlimitedStyleFeed: \(self.enableUnlimitedStyleFeed)")
        Self.logger.info("- enableBackgroundFetchForNotifications: \(self.enableBackgroundFetchForNotifications)")
        Self.logger.info("- backgroundFetchInterval: \(self.backgroundFetchInterval.displayName)")
        Self.logger.info("- forcePhoneLayoutOnPadAndMac: \(self.forcePhoneLayoutOnPadAndMac)")

        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil { UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey) }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil { UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey) }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil { UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey) }
        if UserDefaults.standard.object(forKey: Self.showNSFPKey) == nil { UserDefaults.standard.set(self.showNSFP, forKey: Self.showNSFPKey) }
        if UserDefaults.standard.object(forKey: Self.hideSeenItemsKey) == nil { UserDefaults.standard.set(self.hideSeenItems, forKey: Self.hideSeenItemsKey) }
        if UserDefaults.standard.object(forKey: Self.subtitleActivationModeKey) == nil { UserDefaults.standard.set(self.subtitleActivationMode.rawValue, forKey: Self.subtitleActivationModeKey) }
        if UserDefaults.standard.object(forKey: Self.colorSchemeSettingKey) == nil { UserDefaults.standard.set(self.colorSchemeSetting.rawValue, forKey: Self.colorSchemeSettingKey) }
        if UserDefaults.standard.object(forKey: Self.gridSizeSettingKey) == nil { UserDefaults.standard.set(self.gridSize.rawValue, forKey: Self.gridSizeSettingKey) }
        if UserDefaults.standard.object(forKey: Self.enableStartupFiltersKey) == nil { UserDefaults.standard.set(self.enableStartupFilters, forKey: Self.enableStartupFiltersKey) }
        if UserDefaults.standard.object(forKey: Self.startupFilterSFWKey) == nil { UserDefaults.standard.set(self.startupFilterSFW, forKey: Self.startupFilterSFWKey) }
        if UserDefaults.standard.object(forKey: Self.startupFilterNSFWKey) == nil { UserDefaults.standard.set(self.startupFilterNSFW, forKey: Self.startupFilterNSFWKey) }
        if UserDefaults.standard.object(forKey: Self.startupFilterNSFLKey) == nil { UserDefaults.standard.set(self.startupFilterNSFL, forKey: Self.startupFilterNSFLKey) }
        if UserDefaults.standard.object(forKey: Self.startupFilterPOLKey) == nil { UserDefaults.standard.set(self.startupFilterPOL, forKey: Self.startupFilterPOLKey) }
        if UserDefaults.standard.object(forKey: Self.accentColorChoiceKey) == nil { UserDefaults.standard.set(self.accentColorChoice.rawValue, forKey: Self.accentColorChoiceKey) }
        if UserDefaults.standard.object(forKey: Self.enableUnlimitedStyleFeedKey) == nil { UserDefaults.standard.set(self.enableUnlimitedStyleFeed, forKey: Self.enableUnlimitedStyleFeedKey) }
        if UserDefaults.standard.object(forKey: Self.enableBackgroundFetchForNotificationsKey) == nil { UserDefaults.standard.set(self.enableBackgroundFetchForNotifications, forKey: Self.enableBackgroundFetchForNotificationsKey) }
        if UserDefaults.standard.object(forKey: Self.backgroundFetchIntervalKey) == nil { UserDefaults.standard.set(self.backgroundFetchInterval.rawValue, forKey: Self.backgroundFetchIntervalKey) }
        if UserDefaults.standard.object(forKey: Self.forcePhoneLayoutOnPadAndMacKey) == nil { UserDefaults.standard.set(self.forcePhoneLayoutOnPadAndMac, forKey: Self.forcePhoneLayoutOnPadAndMacKey) }


        updateKingfisherCacheLimit()
        setupCloudKitKeyValueStoreObserver()
        Task {
            await loadSeenItemIDs()
            await loadExcludedTagsFromCloud()
            await updateCacheSizes()
        }
    }
    
    /// Cycles through the available subtitle activation modes.
    func cycleSubtitleMode() {
        switch self.subtitleActivationMode {
        case .disabled:
            self.subtitleActivationMode = .alwaysOn
        case .alwaysOn:
            self.subtitleActivationMode = .disabled
        }
    }


    public func applyStartupFiltersIfNeeded() {
        if self.enableStartupFilters {
            Self.logger.info("Applying custom startup filters as per settings.")
            self.showSFW = self.startupFilterSFW
            self.showNSFW = self.startupFilterNSFW
            self.showNSFL = self.startupFilterNSFL
            self.showPOL = self.startupFilterPOL
            
            if self.feedType == .junk {
                if !self.startupFilterSFW {
                }
            }

            Self.logger.info("Startup filters applied: SFW:\(self.showSFW), NSFW:\(self.showNSFW), NSFL:\(self.showNSFL), NSFP(actual):\(self.showNSFP), POL:\(self.showPOL)")
        } else {
            Self.logger.info("Custom startup filters are disabled.")
        }
    }


    func clearSeenItemsCache() async {
        Self.logger.warning("Clearing Seen Items Cache (Local & iCloud) requested.")
        await MainActor.run {
            self.seenItemIDs = []
        }
        Self.logger.info("Cleared in-memory seen items set.")
        
        Task.detached { [cacheService = self.cacheService, cloudStore = self.cloudStore] in
            await cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
            Self.logger.info("Cleared local seen items cache file via CacheService (background).")
            
            cloudStore.removeObject(forKey: Self.iCloudSeenItemsKey)
            let syncSuccess = cloudStore.synchronize()
            Self.logger.info("Removed seen items key from iCloud KVS. Synchronize requested: \(syncSuccess) (background).")
        }
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

    func markItemAsSeen(id: Int) {
        guard !seenItemIDs.contains(id) else {
            Self.logger.trace("Item \(id) was already marked as seen (in-memory).")
            return
        }
        
        var updatedIDs = seenItemIDs
        updatedIDs.insert(id)
        seenItemIDs = updatedIDs
        Self.logger.debug("Marked item \(id) as seen (in-memory). Total seen: \(self.seenItemIDs.count). Scheduling save.")

        scheduleSaveSeenItems()
    }

    func markItemsAsSeen(ids: Set<Int>) {
        let newIDs = ids.subtracting(seenItemIDs)
        guard !newIDs.isEmpty else {
            Self.logger.trace("No new items to mark as seen from the provided batch.")
            return
        }
        
        Self.logger.debug("Marking \(newIDs.count) new items as seen (in-memory).")
        var idsToUpdate = seenItemIDs
        idsToUpdate.formUnion(newIDs)
        seenItemIDs = idsToUpdate
        Self.logger.info("Marked \(newIDs.count) items as seen (in-memory). Total seen: \(self.seenItemIDs.count). Scheduling save.")
        
        scheduleSaveSeenItems()
    }
    
    private func scheduleSaveSeenItems() {
        saveSeenItemsTask?.cancel()
        
        let idsToSave = self.seenItemIDs
        
        saveSeenItemsTask = Task {
            do {
                try await Task.sleep(for: saveSeenItemsDebounceDelay)
                guard !Task.isCancelled else {
                    Self.logger.info("Debounced save task for seen items cancelled during sleep.")
                    return
                }
                Task.detached(priority: .utility) { [weak self] in
                    guard let self = self else { return }
                    await self.performActualSaveOfSeenIDs(ids: idsToSave)
                }
            } catch is CancellationError {
                Self.logger.info("Debounced save task (scheduling part) cancelled.")
            } catch {
                Self.logger.error("Error in debounced save task scheduling: \(error.localizedDescription)")
            }
        }
    }

    public func forceSaveSeenItems() async {
        saveSeenItemsTask?.cancel()
        Self.logger.info("Force save seen items requested. Current debounced task (if any) cancelled.")
        let currentIDsToSave = self.seenItemIDs
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            await self.performActualSaveOfSeenIDs(ids: currentIDsToSave)
        }
    }

    private func performActualSaveOfSeenIDs(ids: Set<Int>) async {
        Self.logger.debug("BG Save: Saving \(ids.count) seen item IDs to local cache...")
        await cacheService.saveSeenIDs(ids, forKey: Self.localSeenItemsCacheKey)

        Self.logger.debug("BG Save: Saving \(ids.count) seen item IDs to iCloud KVS...")
        do {
            let data = try JSONEncoder().encode(ids)
            self.cloudStore.set(data, forKey: Self.iCloudSeenItemsKey)
            let syncSuccess = self.cloudStore.synchronize()
            Self.logger.info("BG Save: Saved seen IDs to iCloud KVS. Synchronize requested: \(syncSuccess).")
        } catch {
            Self.logger.error("BG Save: Failed to encode or save seen IDs to iCloud KVS: \(error.localizedDescription)")
        }
    }


    private func loadSeenItemIDs() async {
        Self.logger.debug("Loading seen item IDs (iCloud first, then local cache)...")
        var loadedFromCloud = false
        
        if let cloudData = cloudStore.data(forKey: Self.iCloudSeenItemsKey) {
            Self.logger.debug("Found data in iCloud KVS for key \(Self.iCloudSeenItemsKey).")
            do {
                let decodedIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData)
                await MainActor.run { self.seenItemIDs = decodedIDs }
                loadedFromCloud = true
                Self.logger.info("Successfully loaded \(decodedIDs.count) seen item IDs from iCloud KVS.")
                Task.detached(priority: .background) { await self.cacheService.saveSeenIDs(decodedIDs, forKey: Self.localSeenItemsCacheKey) }
            } catch {
                Self.logger.error("Failed to decode seen item IDs from iCloud KVS data: \(error.localizedDescription). Falling back to local cache.")
            }
        } else {
            Self.logger.info("No data found in iCloud KVS for key \(Self.iCloudSeenItemsKey). Checking local cache...")
        }

        if !loadedFromCloud {
            if let localIDs = await cacheService.loadSeenIDs(forKey: Self.localSeenItemsCacheKey) {
                 await MainActor.run { self.seenItemIDs = localIDs }
                 Self.logger.info("Loaded \(localIDs.count) seen item IDs from LOCAL cache.")
                 Task.detached(priority: .background) {
                      Self.logger.info("Syncing locally loaded seen IDs UP to iCloud (using performActualSave).")
                      await self.performActualSaveOfSeenIDs(ids: localIDs)
                 }
            } else {
                Self.logger.warning("Could not load seen item IDs from iCloud or local cache. Starting with an empty set.")
                 await MainActor.run { self.seenItemIDs = [] }
            }
        }
    }

    private func setupCloudKitKeyValueStoreObserver() {
        if keyValueStoreChangeObserver != nil { NotificationCenter.default.removeObserver(keyValueStoreChangeObserver!); keyValueStoreChangeObserver = nil }
        keyValueStoreChangeObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloudStore, queue: .main) { [weak self, capturedCloudStore = self.cloudStore] notification in
            Task { @MainActor [weak self, capturedCloudStore] in
                await self?.handleCloudKitStoreChange(notification: notification, cloudStoreToUse: capturedCloudStore)
            }
        }
        let syncSuccess = cloudStore.synchronize(); Self.logger.info("Setup iCloud KVS observer. Initial synchronize requested: \(syncSuccess)")
    }

    private func handleCloudKitStoreChange(notification: Notification, cloudStoreToUse: NSUbiquitousKeyValueStore) async {
        Self.logger.info("Received iCloud KVS didChangeExternallyNotification.")
        guard let userInfo = notification.userInfo, let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { Self.logger.warning("Could not get change reason from KVS notification."); return }
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { Self.logger.debug("KVS change notification did not contain changedKeys. Ignoring."); return }
        
        let seenItemsChanged = changedKeys.contains(Self.iCloudSeenItemsKey)
        let excludedTagsChanged = changedKeys.contains(Self.iCloudExcludedTagsKey)
        
        guard seenItemsChanged || excludedTagsChanged else { 
            Self.logger.debug("KVS change notification did not contain our keys. Ignoring."); 
            return 
        }
        
        Self.logger.info("Change detected for our keys in iCloud KVS. SeenItems: \(seenItemsChanged), ExcludedTags: \(excludedTagsChanged)")

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            Self.logger.debug("Change reason: ServerChange or InitialSyncChange.")
            
            // Handle seen items changes
            if seenItemsChanged {
                guard let cloudData = cloudStoreToUse.data(forKey: Self.iCloudSeenItemsKey) else {
                    Self.logger.warning("Our key (\(Self.iCloudSeenItemsKey)) was reportedly changed, but no data found in KVS. Possibly deleted externally?")
                    await MainActor.run { self.seenItemIDs = [] }
                    await self.cacheService.clearCache(forKey: Self.localSeenItemsCacheKey)
                    Self.logger.info("Cleared local seen items state because key was missing in iCloud after external change notification.")
                    return
                }
                do {
                    let incomingIDs = try JSONDecoder().decode(Set<Int>.self, from: cloudData); Self.logger.info("Successfully decoded \(incomingIDs.count) seen IDs from external iCloud KVS change.")
                    let localIDs = self.seenItemIDs; let mergedIDs = localIDs.union(incomingIDs)
                    if mergedIDs.count > localIDs.count || mergedIDs != localIDs {
                        await MainActor.run { self.seenItemIDs = mergedIDs }
                        Self.logger.info("Merged external seen IDs. New total: \(mergedIDs.count).")
                        Task.detached(priority: .background) { await self.cacheService.saveSeenIDs(mergedIDs, forKey: Self.localSeenItemsCacheKey) }
                    } else {
                        Self.logger.debug("Incoming seen IDs did not add new items or change the local set. No UI update needed.")
                    }
                } catch { Self.logger.error("Failed to decode seen IDs from external iCloud KVS change data: \(error.localizedDescription)") }
            }
            
            // Handle excluded tags changes
            if excludedTagsChanged {
                guard let cloudData = cloudStoreToUse.data(forKey: Self.iCloudExcludedTagsKey) else {
                    Self.logger.warning("Excluded tags key was changed but no data found in iCloud. Using empty array.")
                    await MainActor.run { 
                        self.excludedTags = [] 
                    }
                    UserDefaults.standard.removeObject(forKey: Self.excludedTagsKey)
                    return
                }
                do {
                    let incomingTags = try JSONDecoder().decode([ExcludedTag].self, from: cloudData)
                    Self.logger.info("Received \(incomingTags.count) excluded tags from iCloud (external change).")
                    
                    // iCloud ist die Source of Truth - überschreibe lokale Daten komplett
                    await MainActor.run { 
                        self.excludedTags = incomingTags
                    }
                    
                    // Cache lokal aktualisieren
                    if let encoded = try? JSONEncoder().encode(incomingTags) {
                        UserDefaults.standard.set(encoded, forKey: Self.excludedTagsKey)
                    }
                } catch { 
                    Self.logger.error("Failed to decode excluded tags from iCloud: \(error.localizedDescription)") 
                }
            }
            
        case NSUbiquitousKeyValueStoreAccountChange: 
            Self.logger.warning("iCloud account changed. Reloading seen items and excluded tags state.")
            await loadSeenItemIDs()
            await loadExcludedTagsFromCloud()
        case NSUbiquitousKeyValueStoreQuotaViolationChange: 
            Self.logger.error("iCloud KVS Quota Violation! Syncing might stop.")
        default: 
            Self.logger.warning("Unhandled iCloud KVS change reason: \(changeReason)"); 
            break
        }
    }
    
    // Synchrone Version für didSet (läuft auf dem aktuellen Thread)
    private func saveExcludedTagsToCloudSync() {
        let tagsToSave = self.excludedTags
        Self.logger.debug("Sync Save: Saving \(tagsToSave.count) excluded tags to iCloud KVS...")
        do {
            let data = try JSONEncoder().encode(tagsToSave)
            self.cloudStore.set(data, forKey: Self.iCloudExcludedTagsKey)
            let syncSuccess = self.cloudStore.synchronize()
            Self.logger.info("Sync Save: Saved excluded tags to iCloud KVS. Synchronize requested: \(syncSuccess).")
        } catch {
            Self.logger.error("Sync Save: Failed to encode or save excluded tags to iCloud KVS: \(error.localizedDescription)")
        }
    }
    
    // Load excluded tags from iCloud - iCloud ist die einzige Source of Truth
    private func loadExcludedTagsFromCloud() async {
        Self.logger.debug("Loading excluded tags from iCloud (primary source)...")
        
        if let cloudData = cloudStore.data(forKey: Self.iCloudExcludedTagsKey) {
            Self.logger.debug("Found data in iCloud KVS for excluded tags.")
            do {
                let decodedTags = try JSONDecoder().decode([ExcludedTag].self, from: cloudData)
                
                await MainActor.run { 
                    self.excludedTags = decodedTags 
                }
                Self.logger.info("Successfully loaded \(decodedTags.count) excluded tags from iCloud KVS.")
                
                // Cache lokal aktualisieren
                if let encoded = try? JSONEncoder().encode(decodedTags) {
                    UserDefaults.standard.set(encoded, forKey: Self.excludedTagsKey)
                }
            } catch {
                Self.logger.error("Failed to decode excluded tags from iCloud KVS: \(error.localizedDescription)")
                // Fallback zu lokalem Cache nur bei Fehler
                await loadExcludedTagsFromLocalCache()
            }
        } else {
            Self.logger.info("No data in iCloud KVS for excluded tags.")
            // Versuche lokalen Cache zu laden und zu iCloud hochzuladen
            await loadExcludedTagsFromLocalCache()
        }
    }
    
    // Fallback: Lade von lokalem Cache (nur wenn iCloud nicht verfügbar ist)
    private func loadExcludedTagsFromLocalCache() async {
        if let data = UserDefaults.standard.data(forKey: Self.excludedTagsKey),
           let decoded = try? JSONDecoder().decode([ExcludedTag].self, from: data) {
            Self.logger.info("Loaded \(decoded.count) excluded tags from local cache (fallback).")
            await MainActor.run { 
                self.excludedTags = decoded 
            }
            // Sync zu iCloud
            Self.logger.info("Syncing local cached tags up to iCloud...")
            saveExcludedTagsToCloudSync()
        } else {
            Self.logger.info("No local cache available. Starting with empty excluded tags.")
            await MainActor.run { 
                self.excludedTags = [] 
            }
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
