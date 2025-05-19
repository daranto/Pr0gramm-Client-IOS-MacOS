// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// A view, typically presented as a sheet, allowing the user to configure
/// feed type (New/Promoted) and content filters (SFW, NSFW, etc.).
/// Can optionally hide the feed-specific options and the "hide seen items" toggle.
struct FilterView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    /// The FeedType that should dictate the filter disabling behavior (e.g., for Junk feed).
    /// If nil, feed-type specific disabling is ignored (e.g., for Favorites).
    let relevantFeedTypeForFilterBehavior: FeedType?

    /// Determines if feed-specific options (Type) should be hidden.
    let hideFeedOptions: Bool
    /// Determines if the "Hide Seen Items" toggle should be shown,
    /// assuming settings.enableExperimentalHideSeen is also true.
    let showHideSeenItemsToggle: Bool


    /// Initializer allows specifying whether to hide feed options and the "hide seen" toggle.
    /// - Parameter relevantFeedTypeForFilterBehavior: The `FeedType` (if any) that influences filter availability.
    /// - Parameter hideFeedOptions: Set to `true` to hide the Feed Type picker. Defaults to `false`.
    /// - Parameter showHideSeenItemsToggle: Set to `false` to explicitly hide the "Hide Seen Items" toggle,
    ///   even if the experimental feature is enabled. Defaults to `true`.
    init(relevantFeedTypeForFilterBehavior: FeedType?, hideFeedOptions: Bool = false, showHideSeenItemsToggle: Bool = true) {
        self.relevantFeedTypeForFilterBehavior = relevantFeedTypeForFilterBehavior
        self.hideFeedOptions = hideFeedOptions
        self.showHideSeenItemsToggle = showHideSeenItemsToggle
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section for Feed Type Selection and Hide Seen toggle
                if !hideFeedOptions || (settings.enableExperimentalHideSeen && showHideSeenItemsToggle) {
                    Section {
                        if !hideFeedOptions { // Feed Type Picker
                            Picker("Feed Typ", selection: $settings.feedType) {
                                ForEach(FeedType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                        .font(UIConstants.bodyFont)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if settings.enableExperimentalHideSeen && showHideSeenItemsToggle {
                            Toggle("Nur Frisches anzeigen (Experimentell)", isOn: $settings.hideSeenItems)
                                .font(UIConstants.bodyFont)
                        }

                    } header: {
                        Text("Anzeige")
                    } footer: {
                        if settings.enableExperimentalHideSeen && showHideSeenItemsToggle {
                             Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                                .font(UIConstants.footnoteFont)
                        }
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }


                // Section for Content Filters
                Section {
                    // SFW Toggle ist immer sichtbar
                    Toggle("SFW", isOn: $settings.showSFW)
                        .font(UIConstants.bodyFont)
                        // Deaktiviert, wenn der relevante Feed-Typ Junk ist UND der User eingeloggt ist.
                        .disabled(relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn)
                        .onChange(of: settings.showSFW) { _, newValue in
                            // Wenn eingeloggt und SFW aktiviert wird, und der relevante Feed-Typ nicht Junk ist, dann NSFP mitziehen
                            if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk && newValue {
                                settings.showNSFP = true
                            }
                            // Wenn SFW deaktiviert wird und eingeloggt (und relevanter Feed-Typ nicht Junk), dann NSFP auch deaktivieren
                            else if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk && !newValue {
                                settings.showNSFP = false
                            }
                        }
                    
                    // NSFP ist sichtbar, wenn:
                    // 1. User nicht eingeloggt ist ODER
                    // 2. User eingeloggt ist UND der relevante Feed-Typ Junk ist (obwohl es hier disabled ist).
                    // Dies spiegelt wider, dass für ausgeloggte User NSFP eine explizite Option ist,
                    // und für eingeloggte User im Junk-Feed SFW+NSFP fix ist.
                    if !authService.isLoggedIn || (relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn) {
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             .font(UIConstants.bodyFont)
                             // Deaktiviert, wenn der relevante Feed-Typ Junk ist UND der User eingeloggt ist.
                             .disabled(relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn)
                    }

                    // NSFW, NSFL, POL nur für eingeloggte User (und wenn relevanter Feed-Typ nicht Junk ist)
                    if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk {
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                    } else if !authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk {
                        // Hinweis für ausgeloggte User, wenn der Kontext kein Junk-Feed ist.
                        Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                           .font(UIConstants.bodyFont)
                           .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                    // Angepasster Footer-Text basierend auf dem Kontext
                    if authService.isLoggedIn && relevantFeedTypeForFilterBehavior == .junk {
                        Text("Im 'Müll'-Feed werden nur SFW und NSFP Inhalte angezeigt. Andere Filter sind hier nicht anwendbar.")
                            .font(UIConstants.footnoteFont)
                    } else if authService.isLoggedIn { // Gilt für Feed/Promoted und Favoriten/Suche (wenn relevantFeedType nicht .junk ist)
                        Text("SFW beinhaltet bei eingeloggten Nutzern automatisch auch NSFP.")
                            .font(UIConstants.footnoteFont)
                    } else { // Ausgeloggt
                        Text("Für ausgeloggte Nutzer wird nur SFW Inhalt angezeigt. NSFP ist ein Teil von SFW. Melde dich an für mehr Optionen.")
                            .font(UIConstants.footnoteFont)
                    }
                }
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .font(UIConstants.bodyFont)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Feed Context (Logged In, Feed=Promoted)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    previewSettings.feedType = .promoted // Für diesen Preview-Fall
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Feed Context (Logged In, Feed=Junk)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    previewSettings.feedType = .junk // Wichtig für diesen Preview-Fall
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Favorites Context (Logged In)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    // Für Favoriten ist der relevantFeedType nil
    return FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Search Context (Logged In, SearchFeedType=Promoted)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    // SearchView würde seinen eigenen searchFeedType hier übergeben
    return FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: true, showHideSeenItemsToggle: false)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out (relevantFeedType = .promoted)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = false
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: false)
    return FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
