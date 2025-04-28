// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// View for displaying and modifying application settings, including cache management.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    /// State to control the presentation of the cache clearing confirmation alert.
    @State private var showingClearAllCacheAlert = false

    /// Predefined options for the maximum image cache size picker.
    let cacheSizeOptions = [50, 100, 250, 500, 1000] // In MB
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form {
                // Section for Video Settings
                Section("Video") {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                        // --- MODIFIED: Use adaptive font ---
                        .font(UIConstants.bodyFont)
                        // --- END MODIFICATION ---
                }

                // Section for Comment Settings
                Section("Kommentare") {
                    Picker("Sortierung", selection: $settings.commentSortOrder) {
                        ForEach(CommentSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                                // Apply font inside ForEach if needed, though Picker might handle it
                                .font(UIConstants.bodyFont) // Apply here too
                        }
                    }
                     // --- MODIFIED: Use adaptive font ---
                    .font(UIConstants.bodyFont) // Apply to Picker label
                     // --- END MODIFICATION ---
                }

                // Section for Cache Settings
                Section {
                    // Display current cache sizes (read-only)
                    HStack {
                        Text("Bild-Cache Größe")
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentImageDataCacheSizeMB))
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Daten-Cache Größe")
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentDataCacheSizeMB))
                             // --- MODIFIED: Use adaptive font ---
                            .font(UIConstants.bodyFont)
                             // --- END MODIFICATION ---
                            .foregroundColor(.secondary)
                    }

                    // Picker to select max image cache size
                    Picker("Max. Bild-Cache Größe", selection: $settings.maxImageCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                                .font(UIConstants.bodyFont) // Apply font to picker options
                        }
                    }
                     // --- MODIFIED: Use adaptive font ---
                    .font(UIConstants.bodyFont) // Apply to Picker label
                     // --- END MODIFICATION ---
                    .onChange(of: settings.maxImageCacheSizeMB) { _, _ in
                        Self.logger.info("Max image cache size setting changed.")
                    }

                    // Button to clear all caches
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true // Trigger confirmation alert
                    }
                     // --- MODIFIED: Use adaptive font ---
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .center) // Center button text
                     // --- END MODIFICATION ---

                } header: {
                    // Use standard header for the section title
                    Text("Cache")
                        // Optional: Adjust header font if needed
                        // .font(UIConstants.headlineFont)
                } footer: {
                    // Provide explanatory text about cache limits
                    Text("Der Bild-Cache (Kingfisher) wird automatisch auf die gewählte Maximalgröße begrenzt. Der Daten-Cache (Feeds etc.) hat ein festes Limit von 50 MB und löscht die ältesten Einträge bei Überschreitung (LRU).")
                         // --- MODIFIED: Use adaptive font ---
                        .font(UIConstants.footnoteFont) // Use footnote font for footer
                         // --- END MODIFICATION ---
                }
                 // Optional: Make header slightly more prominent on Mac
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

            }
            .navigationTitle("Einstellungen")
            .alert("Gesamten App-Cache leeren?", isPresented: $showingClearAllCacheAlert) {
                // Confirmation alert buttons
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) {
                    // Perform cache clearing asynchronously
                    Task {
                        await settings.clearAllAppCache()
                    }
                }
            } message: {
                // Confirmation alert message
                Text("Möchtest du wirklich alle zwischengespeicherten Daten (Feeds, Favoriten, Bilder etc.) löschen? Dies kann nicht rückgängig gemacht werden.")
                    // Optional: Apply font to alert message if needed
                    // .font(UIConstants.bodyFont)
            }
            .onAppear {
                // Update displayed cache sizes when the view appears
                Task {
                    await settings.updateCacheSizes()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // Provide AppSettings for the preview environment
    SettingsView().environmentObject(AppSettings())
}
// --- END OF COMPLETE FILE ---
