// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// A view, typically presented as a sheet, allowing the user to configure
/// feed type (New/Promoted) and content filters (SFW, NSFW, etc.).
/// Can optionally hide the feed-specific options.
struct FilterView: View {
    @EnvironmentObject var settings: AppSettings // Access global settings
    @EnvironmentObject var authService: AuthService // Check login status for filter availability
    @Environment(\.dismiss) var dismiss // Action to close the sheet

    /// Determines if feed-specific options (Type, Hide Seen) should be hidden.
    let hideFeedOptions: Bool

    /// Initializer allows specifying whether to hide feed options.
    /// - Parameter hideFeedOptions: Set to `true` to hide the Feed Type picker and Hide Seen toggle. Defaults to `false`.
    init(hideFeedOptions: Bool = false) {
        self.hideFeedOptions = hideFeedOptions
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section for Feed Type Selection and Hide Seen toggle
                // Wird jetzt nur angezeigt, wenn hideFeedOptions = false ist (z.B. in SettingsView, nicht in FeedView oder SearchView)
                if !hideFeedOptions {
                    Section {
                        Picker("Feed Typ", selection: $settings.feedType) {
                            ForEach(FeedType.allCases) { type in
                                Text(type.displayName).tag(type)
                                    .font(UIConstants.bodyFont)
                            }
                        }
                        .pickerStyle(.segmented)

                        if settings.enableExperimentalHideSeen {
                            Toggle("Nur Frisches anzeigen (Experimentell)", isOn: $settings.hideSeenItems)
                                .font(UIConstants.bodyFont)
                        }

                    } header: {
                        Text("Anzeige")
                    } footer: {
                        if settings.enableExperimentalHideSeen {
                             Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                                .font(UIConstants.footnoteFont)
                        }
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }

                // Section for Content Filters
                if authService.isLoggedIn {
                    Section {
                        // Toggle "Müll anzeigen" wurde entfernt, da es jetzt ein FeedType ist.
                        // Die folgenden Toggles werden ignoriert, wenn settings.feedType == .junk ist (Logik in AppSettings.apiFlags)
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                            .font(UIConstants.bodyFont)
                            .disabled(settings.feedType == .junk) // Deaktivieren, wenn Müll-Feed aktiv
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                            .disabled(settings.feedType == .junk)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                             .disabled(settings.feedType == .junk)
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             .font(UIConstants.bodyFont)
                             .disabled(settings.feedType == .junk)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                             .disabled(settings.feedType == .junk)
                    } header: {
                        Text("Inhaltsfilter")
                    } footer: {
                        // --- MODIFIED: Footer angepasst ---
                        Text(settings.feedType == .junk ? "Im 'Müll'-Feed werden nur SFW und NSFP Inhalte angezeigt. Andere Filter sind hier nicht anwendbar." : "Achtung: NSFW/NSFL/NSFP unterliegt App Store Richtlinien und Verfügbarkeit auf pr0gramm.")
                        // --- END MODIFICATION ---
                            .font(UIConstants.footnoteFont)
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                } else { // User not logged in
                     Section("Inhaltsfilter") {
                         Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.secondary)
                     }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }
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

#Preview("Standard (Feed) - FilterView nicht mehr direkt von hier") {
    // Diese Preview ist weniger relevant, da FilterView aus FeedView jetzt hideFeedOptions=true hat.
    // Die volle FilterView wird eher in den globalen Settings angezeigt.
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    return FilterView(hideFeedOptions: false) // Zeigt alle Optionen für die Settings-Ansicht
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Aus Feed/Search Kontext (hideFeedOptions=true)") {
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    return FilterView(hideFeedOptions: true) // So wird es aus FeedView/SearchView aufgerufen
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out (hideFeedOptions=true)") {
    FilterView(hideFeedOptions: true)
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Junk FeedType Active (hideFeedOptions=true)") {
    let previewSettings = AppSettings()
    previewSettings.feedType = .junk // Setze Junk-Feed für Preview
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    return FilterView(hideFeedOptions: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
