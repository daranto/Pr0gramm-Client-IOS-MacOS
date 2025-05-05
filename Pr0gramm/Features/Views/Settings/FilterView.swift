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
                if !hideFeedOptions {
                    Section {
                        Picker("Feed Typ", selection: $settings.feedType) {
                            ForEach(FeedType.allCases) { type in
                                Text(type.displayName).tag(type)
                                    .font(UIConstants.bodyFont)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Conditionally show the "Hide Seen" toggle
                        // Only show if the experimental feature is enabled in AppSettings
                        if settings.enableExperimentalHideSeen {
                            Toggle("Nur Frisches anzeigen (Experimentell)", isOn: $settings.hideSeenItems)
                                .font(UIConstants.bodyFont)
                        }

                    } header: {
                        Text("Anzeige")
                    // --- MODIFIED: Footer now only shown if the toggle is visible ---
                    } footer: {
                        // Only show the basic explanation if the experimental toggle is actually visible
                        if settings.enableExperimentalHideSeen {
                             Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                                .font(UIConstants.footnoteFont)
                        }
                        // No footer text is shown if the experimental feature is off
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                    // --- END MODIFICATION ---
                }

                // Section for Content Filters (always shown if context allows, visibility depends on login)
                if authService.isLoggedIn {
                    Section {
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                            .font(UIConstants.bodyFont)
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             .font(UIConstants.bodyFont)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                    } header: {
                        Text("Inhaltsfilter")
                    } footer: {
                        Text("Achtung: Die Anzeige von NSFW/NSFL/NSFP Inhalten unterliegt den App Store Richtlinien und der Verfügbarkeit auf pr0gramm.")
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

// MARK: - Previews (Unchanged)

#Preview("Standard (Feed)") {
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: []);
    // Default initializer, shows all options
    return FilterView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Search Context") {
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: []);
    // Initializer with hideFeedOptions = true
    return FilterView(hideFeedOptions: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out") {
    // Default initializer, Feed options shown, Content filters hidden
    FilterView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Experimental Enabled") {
    let previewSettings = AppSettings()
    previewSettings.enableExperimentalHideSeen = true // Enable experimental feature for preview
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    return FilterView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
