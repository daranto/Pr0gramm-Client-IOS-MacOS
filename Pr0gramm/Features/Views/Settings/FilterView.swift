// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// A view, typically presented as a sheet, allowing the user to configure
/// feed type (New/Promoted) and content filters (SFW, NSFW, etc.).
struct FilterView: View {
    @EnvironmentObject var settings: AppSettings // Access global settings
    @EnvironmentObject var authService: AuthService // Check login status for filter availability
    @Environment(\.dismiss) var dismiss // Action to close the sheet

    var body: some View {
        NavigationStack {
            Form {
                // Section for Feed Type Selection
                Section {
                    Picker("Feed Typ", selection: $settings.feedType) {
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented) // Use segmented control for feed type

                    // Toggle to hide seen items
                    Toggle("Gesehene ausblenden", isOn: $settings.hideSeenItems)

                } header: {
                    Text("Anzeige")
                } footer: {
                    Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                }


                // Section for Content Filters (only shown if logged in)
                if authService.isLoggedIn {
                    Section {
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                    } header: {
                        Text("Inhaltsfilter")
                    } footer: {
                        // Add warning/disclaimer about content filters
                        Text("Achtung: Die Anzeige von NSFW/NSFL/NSFP Inhalten unterliegt den App Store Richtlinien und der Verfügbarkeit auf pr0gramm.")
                    }
                } else {
                    // Optionally show a message if logged out, or simply omit the section
                    // Section("Inhaltsfilter") { Text("Melde dich an, um NSFW/NSFL Filter anzupassen.").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline) // Use inline style for sheet navigation bar
            #endif
            .toolbar {
                // Add a "Done" button to dismiss the sheet
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

// MARK: - Previews

#Preview("Logged Out") {
    // Simulate logged-out state
    FilterView()
        .environmentObject(AppSettings()) // Provide default settings
        .environmentObject(AuthService(appSettings: AppSettings())) // Provide logged-out auth service
}

#Preview("Logged In") {
    // --- CORRECTED PREVIEW ---
    // 1. Create settings instance first
    let previewSettings = AppSettings()
    // 2. Create AuthService instance, configuring it for logged-in state
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    // 3. Provide necessary UserInfo, including the 'badges' argument
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: []) // Added badges: []
    // 4. Return the view, applying environment objects
    return FilterView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
    // --- END CORRECTION ---
}
// --- END OF COMPLETE FILE ---
