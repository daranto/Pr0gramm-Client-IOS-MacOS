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

                // --- NEW: Info Section with License & Dependencies Link ---
                Section {
                    NavigationLink(destination: LicenseAndDependenciesView()) {
                        Text("Lizenzen & Abhängigkeiten")
                            .font(UIConstants.bodyFont)
                    }
                } header: {
                    Text("Info")
                }
                // --- END NEW SECTION ---
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
// --- NEW: Placeholder for LicenseAndDependenciesView ---
struct LicenseAndDependenciesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                MIT License

                Copyright (c) 2025 Pr0gramm App Team

                Permission is hereby granted, free of charge, to any person obtaining a copy
                of this software and associated documentation files (the "Software"), to deal
                in the Software without restriction, including without limitation the rights
                to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                copies of the Software, and to permit persons to whom the Software is
                furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in
                all copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
                THE SOFTWARE.
                """)
                .font(.footnote)
                .textSelection(.enabled)

                Divider()

                Text("Verwendete Swift Packages")
                    .font(.title2).bold()
                VStack(alignment: .leading, spacing: 8) {
                    Link("Kingfisher", destination: URL(string: "https://github.com/onevcat/Kingfisher")!)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Lizenzen")
    }
}
// --- END NEW LicenseAndDependenciesView ---
// --- END OF COMPLETE FILE ---
