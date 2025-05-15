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

    /// Determines if feed-specific options (Type) should be hidden.
    let hideFeedOptions: Bool
    /// Determines if the "Hide Seen Items" toggle should be shown,
    /// assuming settings.enableExperimentalHideSeen is also true.
    let showHideSeenItemsToggle: Bool

    /// Initializer allows specifying whether to hide feed options and the "hide seen" toggle.
    /// - Parameter hideFeedOptions: Set to `true` to hide the Feed Type picker. Defaults to `false`.
    /// - Parameter showHideSeenItemsToggle: Set to `false` to explicitly hide the "Hide Seen Items" toggle,
    ///   even if the experimental feature is enabled. Defaults to `true`.
    init(hideFeedOptions: Bool = false, showHideSeenItemsToggle: Bool = true) {
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
                        .disabled(settings.feedType == .junk && authService.isLoggedIn) // Deaktiviert für Junk, wenn eingeloggt
                        .onChange(of: settings.showSFW) { _, newValue in
                            // Wenn eingeloggt und SFW aktiviert wird, und nicht Junk-Feed, dann NSFP mitziehen
                            if authService.isLoggedIn && settings.feedType != .junk && newValue {
                                settings.showNSFP = true
                            }
                            // Wenn SFW deaktiviert wird und eingeloggt (nicht Junk), dann NSFP auch deaktivieren
                            else if authService.isLoggedIn && settings.feedType != .junk && !newValue {
                                settings.showNSFP = false
                            }
                        }
                    
                    if !authService.isLoggedIn || settings.feedType == .junk {
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             .font(UIConstants.bodyFont)
                             .disabled(settings.feedType == .junk && authService.isLoggedIn) // Für Junk-Feed ist NSFP fix
                    }

                    // NSFW, NSFL, POL nur für eingeloggte User (und nicht Junk-Feed)
                    if authService.isLoggedIn && settings.feedType != .junk {
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                    } else if !authService.isLoggedIn && settings.feedType != .junk {
                        // Hinweis für ausgeloggte User
                        Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                           .font(UIConstants.bodyFont)
                           .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                    if authService.isLoggedIn && settings.feedType == .junk {
                        Text("Im 'Müll'-Feed werden nur SFW und NSFP Inhalte angezeigt. Andere Filter sind hier nicht anwendbar.")
                            .font(UIConstants.footnoteFont)
                    } else if authService.isLoggedIn {
                        Text("SFW beinhaltet bei eingeloggten Nutzern automatisch auch NSFP. Für den 'Müll'-Feed gelten feste Filter.")
                            .font(UIConstants.footnoteFont)
                    } else {
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

#Preview("In Settings (Full Options - Logged In)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Enable for preview
    let previewAuthService = AuthService(appSettings: previewSettings) // AuthService mit den previewSettings initialisieren
    previewAuthService.isLoggedIn = true
    // --- MODIFIED: Methode auf previewSettings aufrufen ---
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true) // Wichtig für Preview
    // --- END MODIFICATION ---
    return FilterView(hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("In Settings (Full Options - Logged Out)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = false
    // --- MODIFIED: Methode auf previewSettings aufrufen ---
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: false) // Wichtig für Preview
    // --- END MODIFICATION ---
    return FilterView(hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("In Feed/Search (Hide Feed, Show Seen Toggle - Logged In)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Enable for preview
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    // --- MODIFIED: Methode auf previewSettings aufrufen ---
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    // --- END MODIFICATION ---
    return FilterView(hideFeedOptions: true, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("In Favorites (Hide Feed, Hide Seen Toggle - Logged In)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Keep enabled to test if showHideSeenItemsToggle works
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    // --- MODIFIED: Methode auf previewSettings aufrufen ---
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    // --- END MODIFICATION ---
    return FilterView(hideFeedOptions: true, showHideSeenItemsToggle: false) // Explicitly hide "Hide Seen"
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
