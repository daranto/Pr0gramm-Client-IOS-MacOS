// AppSettings.swift

import Foundation
import Combine

// Enum für den Feed-Typ
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

class AppSettings: ObservableObject {

    // MARK: - UserDefaults Keys
    private static let isVideoMutedPreferenceKey = "isVideoMutedPreference_v1"
    private static let feedTypeKey = "feedTypePreference_v1"
    private static let showSFWKey = "showSFWPreference_v1"
    private static let showNSFWKey = "showNSFWPreference_v1"
    private static let showNSFLKey = "showNSFLPreference_v1"
    private static let showPOLKey = "showPOLPreference_v1"

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

    // MARK: - Computed Properties for API
    var apiFlags: Int {
        var flags = 0
        if showSFW { flags |= 1 }
        if showNSFW { flags |= 2 }
        if showNSFL { flags |= 4 }
        if showPOL { flags |= 8 }
        return flags == 0 ? 1 : flags
    }

    var apiPromoted: Int {
        return feedType.rawValue
    }

    // MARK: - Initializer
    init() {
        // --- Phase 1: Initialize ALL stored properties ---
        // Direkt Zuweisen des Werts aus UserDefaults ODER des Standardwerts.
        // Dies MUSS für jede @Published-Variable geschehen, bevor 'self' weiter verwendet wird.

        self.isVideoMuted = UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil
                             ? true // Default value if key doesn't exist
                             : UserDefaults.standard.bool(forKey: Self.isVideoMutedPreferenceKey)

        self.feedType = FeedType(rawValue: UserDefaults.standard.integer(forKey: Self.feedTypeKey))
                         ?? .promoted // Default value if key doesn't exist or rawValue is invalid

        self.showSFW = UserDefaults.standard.object(forKey: Self.showSFWKey) == nil
                       ? true // Default value
                       : UserDefaults.standard.bool(forKey: Self.showSFWKey)

        // Für Bool-Werte gibt .bool(forKey:) standardmäßig 'false' zurück, wenn der Schlüssel fehlt,
        // was hier unser gewünschter Standardwert ist.
        self.showNSFW = UserDefaults.standard.bool(forKey: Self.showNSFWKey)
        self.showNSFL = UserDefaults.standard.bool(forKey: Self.showNSFLKey)
        self.showPOL = UserDefaults.standard.bool(forKey: Self.showPOLKey)

        // --- Phase 2: Initialization complete ---
        // Jetzt sind alle gespeicherten Eigenschaften initialisiert, und 'self' kann sicher verwendet werden.

        print("AppSettings initialized:")
        print("- isVideoMuted: \(self.isVideoMuted)")
        print("- feedType: \(self.feedType)")
        print("- showSFW: \(self.showSFW)")
        print("- showNSFW: \(self.showNSFW)")
        print("- showNSFL: \(self.showNSFL)")
        print("- showPOL: \(self.showPOL)")

        // Optional: Speichere die Standardwerte explizit, falls sie gerade zum ersten Mal gesetzt wurden.
        // (Die didSet-Observer tun dies nur bei *Änderungen* nach der Initialisierung).
        if UserDefaults.standard.object(forKey: Self.isVideoMutedPreferenceKey) == nil {
            UserDefaults.standard.set(self.isVideoMuted, forKey: Self.isVideoMutedPreferenceKey)
        }
        if UserDefaults.standard.object(forKey: Self.feedTypeKey) == nil {
            UserDefaults.standard.set(self.feedType.rawValue, forKey: Self.feedTypeKey)
        }
        if UserDefaults.standard.object(forKey: Self.showSFWKey) == nil {
            UserDefaults.standard.set(self.showSFW, forKey: Self.showSFWKey)
        }
        // Für die anderen Flags ist dies nicht unbedingt nötig, da ihr Standardwert 'false' ist
        // und .bool(forKey:) auch 'false' zurückgibt, wenn der Schlüssel fehlt.
    }
}
