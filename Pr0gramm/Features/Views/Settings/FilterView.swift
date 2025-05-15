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
    // --- NEW: Explicit control for "Hide Seen Items" toggle ---
    /// Determines if the "Hide Seen Items" toggle should be shown,
    /// assuming settings.enableExperimentalHideSeen is also true.
    let showHideSeenItemsToggle: Bool
    // --- END NEW ---

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

                        // --- MODIFIED: Conditional display of "Hide Seen Items" toggle ---
                        if settings.enableExperimentalHideSeen && showHideSeenItemsToggle {
                            Toggle("Nur Frisches anzeigen (Experimentell)", isOn: $settings.hideSeenItems)
                                .font(UIConstants.bodyFont)
                        }
                        // --- END MODIFICATION ---

                    } header: {
                        Text("Anzeige")
                    } footer: {
                        // --- MODIFIED: Footer only if "Hide Seen" is potentially shown ---
                        if settings.enableExperimentalHideSeen && showHideSeenItemsToggle {
                             Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                                .font(UIConstants.footnoteFont)
                        }
                        // --- END MODIFICATION ---
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }


                // Section for Content Filters
                if authService.isLoggedIn {
                    Section {
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                            .font(UIConstants.bodyFont)
                            .disabled(settings.feedType == .junk)
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
                        Text(settings.feedType == .junk ? "Im 'Müll'-Feed werden nur SFW und NSFP Inhalte angezeigt. Andere Filter sind hier nicht anwendbar." : "Achtung: NSFW/NSFL/NSFP unterliegt App Store Richtlinien und Verfügbarkeit auf pr0gramm.")
                            .font(UIConstants.footnoteFont)
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                } else {
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

#Preview("In Settings (Full Options)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Enable for preview
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    return FilterView(hideFeedOptions: false, showHideSeenItemsToggle: true) // Explicitly show both for settings
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("In Feed/Search (Hide Feed, Show Seen Toggle)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Enable for preview
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    return FilterView(hideFeedOptions: true, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("In Favorites (Hide Feed, Hide Seen Toggle)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Keep enabled to test if showHideSeenItemsToggle works
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    return FilterView(hideFeedOptions: true, showHideSeenItemsToggle: false) // Explicitly hide "Hide Seen"
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out (Hide Feed, Show Seen Toggle - but disabled)") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true
    return FilterView(hideFeedOptions: true, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(AuthService(appSettings: AppSettings()))
}
// --- END OF COMPLETE FILE ---
