// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// View for displaying and modifying application settings, including cache management.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingClearAllCacheAlert = false
    @State private var showingClearSeenItemsAlert = false

    let cacheSizeOptions = [50, 100, 250, 500, 1000] // In MB
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form {
                // Section for Video & Audio Settings
                Section {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                        .font(UIConstants.bodyFont)

                    // Subtitle Settings Picker
                    Picker("Untertitel anzeigen", selection: $settings.subtitleActivationMode) {
                        ForEach(SubtitleActivationMode.allCases) { mode in
                             Text(mode.displayName).tag(mode)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)

                } header: {
                     Text("Video & Ton")
                } footer: {
                     Text("Die Option 'Automatisch' zeigt Untertitel nur an, wenn das Video im Player stummgeschaltet ist. 'Immer an' versucht, Untertitel immer anzuzeigen, falls verfügbar.")
                        .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)


                // Section for Comment Settings
                Section("Kommentare") {
                    Picker("Sortierung", selection: $settings.commentSortOrder) {
                        ForEach(CommentSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                // Section for Experimental Features
                Section {
                    Toggle("Feature: 'Nur Frisches anzeigen' aktivieren", isOn: $settings.enableExperimentalHideSeen)
                        .font(UIConstants.bodyFont)
                } header: {
                     Text("Experimentelle Features")
                } footer: {
                     Text("Aktiviere diese Option, um die experimentelle Funktion 'Nur Frisches anzeigen' im Filter-Menü verfügbar zu machen. Diese Funktion blendet bereits gesehene Posts im Feed aus, kann aber bei der Paginierung (Nachladen älterer Posts) noch zu unerwartetem Verhalten führen.")
                        .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                // Section for Clearing Seen Items
                Section {
                    Button("Gesehene Posts zurücksetzen", role: .destructive) {
                        showingClearSeenItemsAlert = true
                    }
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                     Text("Anzeige-Verlauf")
                } footer: {
                     Text("Entfernt die Markierungen für bereits angesehene Posts. Die Bilder selbst bleiben im Cache erhalten. Die Option, gesehene Posts auszublenden, muss ggf. unter 'Experimentelle Features' aktiviert werden.")
                        .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)


                // Section for Cache Settings
                Section {
                    HStack {
                        Text("Bild-Cache Größe")
                            .font(UIConstants.bodyFont)
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentImageDataCacheSizeMB))
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Daten-Cache Größe")
                            .font(UIConstants.bodyFont)
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentDataCacheSizeMB))
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.secondary)
                    }
                    Picker("Max. Bild-Cache Größe", selection: $settings.maxImageCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                    .onChange(of: settings.maxImageCacheSizeMB) { _, _ in
                        Self.logger.info("Max image cache size setting changed.")
                    }
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true
                    }
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("Cache")
                } footer: {
                    Text("Der Bild-Cache (Kingfisher) wird automatisch auf die gewählte Maximalgröße begrenzt. Der Daten-Cache (Feeds etc.) hat ein festes Limit von 50 MB und löscht die ältesten Einträge bei Überschreitung (LRU). 'Gesamten App-Cache leeren' löscht Bilder, Daten und auch die Gesehen-Markierungen.")
                        .font(UIConstants.footnoteFont)
                }
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                // Section for Info & Project
                Section {
                    NavigationLink(destination: LicenseAndDependenciesView()) {
                        Text("Lizenzen & Abhängigkeiten")
                            .font(UIConstants.bodyFont)
                    }
                    if let url = URL(string: "https://github.com/daranto/Pr0gramm-Client-IOS-MacOS") {
                        Link(destination: url) {
                            Label("Projekt auf GitHub", systemImage: "link")
                                .font(UIConstants.bodyFont)
                        }
                        .tint(.accentColor)
                    }
                } header: {
                    Text("Info & Projekt")
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
            } // End Form
            .navigationTitle("Einstellungen")
            .alert("Gesehene Posts zurücksetzen?", isPresented: $showingClearSeenItemsAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Zurücksetzen", role: .destructive) { Task { await settings.clearSeenItemsCache() } }
            } message: {
                Text("Dadurch werden alle Markierungen für gesehene Bilder und Videos entfernt. Die Posts erscheinen wieder als 'neu'.")
            }
            .alert("Gesamten App-Cache leeren?", isPresented: $showingClearAllCacheAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) { Task { await settings.clearAllAppCache() } }
            } message: {
                Text("Möchtest du wirklich alle zwischengespeicherten Daten (Feeds, Favoriten, Bilder, Gesehen-Markierungen etc.) löschen? Dies kann nicht rückgängig gemacht werden.")
            }
            .onAppear { Task { await settings.updateCacheSizes() } }
        } // End NavigationStack
    } // End body
} // End struct SettingsView


// MARK: - Preview

#Preview {
    SettingsView().environmentObject(AppSettings())
}

// LicenseAndDependenciesView
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
                        .font(UIConstants.bodyFont)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Lizenzen")
         #if os(iOS)
         .navigationBarTitleDisplayMode(.inline)
         #endif
    }
}
// --- END OF COMPLETE FILE ---
