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
                                // Apply adaptive font to picker options
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .pickerStyle(.segmented) // Use segmented control for feed type
                    // Optional: Apply font to the Picker itself if needed, though segmented style might control it
                    // .font(UIConstants.bodyFont)

                    // Toggle to hide seen items
                    Toggle("Nur Frisches anzeigen", isOn: $settings.hideSeenItems)
                        // --- MODIFIED: Use adaptive font ---
                        .font(UIConstants.bodyFont)
                        // --- END MODIFICATION ---

                } header: {
                    Text("Anzeige")
                        // Optional: Adjust header font if needed
                        // .font(UIConstants.headlineFont)
                } footer: {
                    Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                         // --- MODIFIED: Use adaptive font ---
                        .font(UIConstants.footnoteFont) // Use footnote for footer
                         // --- END MODIFICATION ---
                }
                 // Optional: Make header slightly more prominent on Mac
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)


                // Section for Content Filters (only shown if logged in)
                if authService.isLoggedIn {
                    Section {
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                            // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                            // --- END MODIFICATION ---
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                            // --- END MODIFICATION ---
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                    } header: {
                        Text("Inhaltsfilter")
                         // Optional: Adjust header font if needed
                         // .font(UIConstants.headlineFont)
                    } footer: {
                        // Add warning/disclaimer about content filters
                        Text("Achtung: Die Anzeige von NSFW/NSFL/NSFP Inhalten unterliegt den App Store Richtlinien und der Verfügbarkeit auf pr0gramm.")
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.footnoteFont) // Use footnote for footer
                            // --- END MODIFICATION ---
                    }
                     // Optional: Make header slightly more prominent on Mac
                    .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                } else {
                    // Optionally show a message if logged out, or simply omit the section
                     Section("Inhaltsfilter") {
                         Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                            // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                            // --- END MODIFICATION ---
                            .foregroundColor(.secondary)
                     }
                     // Optional: Make header slightly more prominent on Mac
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline) // Use inline style for sheet navigation bar
            #endif
            .toolbar {
                // Add a "Done" button to dismiss the sheet
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        // --- MODIFIED: Use adaptive font ---
                        .font(UIConstants.bodyFont) // Apply to toolbar button
                        // --- END MODIFICATION ---
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Logged Out") {
    FilterView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Logged In") {
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: []);
    return FilterView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
