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
                }

                // Section for Cache Settings
                Section {
                    // Display current cache sizes (read-only)
                    HStack {
                        Text("Bild-Cache Größe")
                        Spacer()
                        // Format cache size nicely
                        Text(String(format: "%.1f MB", settings.currentImageDataCacheSizeMB))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Daten-Cache Größe")
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentDataCacheSizeMB))
                            .foregroundColor(.secondary)
                    }

                    // Picker to select max image cache size
                    Picker("Max. Bild-Cache Größe", selection: $settings.maxImageCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }
                    .onChange(of: settings.maxImageCacheSizeMB) { _, _ in
                        // Log when the setting changes (the actual update happens in AppSettings)
                        Self.logger.info("Max image cache size setting changed.")
                    }

                    // Button to clear all caches
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true // Trigger confirmation alert
                    }

                } header: {
                    // Use standard header for the section title
                    Text("Cache")
                } footer: {
                    // Provide explanatory text about cache limits
                    Text("Der Bild-Cache (Kingfisher) wird automatisch auf die gewählte Maximalgröße begrenzt. Der Daten-Cache (Feeds etc.) hat ein festes Limit von 50 MB und löscht die ältesten Einträge bei Überschreitung (LRU).")
                }
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
