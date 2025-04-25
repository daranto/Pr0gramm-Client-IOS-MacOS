// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingClearAllCacheAlert = false

    let cacheSizeOptions = [50, 100, 250, 500, 1000]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form {
                // --- Unverändert ---
                Section("Video") {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                }

                // --- Cache Bereich (Korrigierte Section-Initialisierung) ---
                // Explizit header und footer verwenden
                Section {
                    // Der Inhalt der Section bleibt gleich
                    HStack {
                        Text("Bild-Cache Größe")
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentImageDataCacheSizeMB))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Daten-Cache Größe")
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentDataCacheSizeMB))
                            .foregroundColor(.secondary)
                    }
                    Picker("Max. Bild-Cache Größe", selection: $settings.maxImageCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }
                    .onChange(of: settings.maxImageCacheSizeMB) { _, _ in
                        Self.logger.info("Max image cache size setting changed.")
                    }
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true
                    }
                } header: {
                    // Den Titel hier als Header definieren
                    Text("Cache")
                } footer: {
                    // Der Footer bleibt gleich
                    Text("Der Bild-Cache wird automatisch auf die gewählte Maximalgröße begrenzt. Der Daten-Cache (Feeds etc.) hat ein festes Limit von 50 MB und löscht die ältesten Einträge bei Überschreitung.")
                }
                // --- Ende Cache Bereich ---
            }
            .navigationTitle("Einstellungen")
            .alert("Gesamten App-Cache leeren?", isPresented: $showingClearAllCacheAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) {
                    Task {
                        await settings.clearAllAppCache()
                    }
                }
            } message: {
                Text("Möchtest du wirklich alle zwischengespeicherten Daten (Feeds, Favoriten, Bilder etc.) löschen? Dies kann nicht rückgängig gemacht werden.")
            }
            .onAppear {
                Task {
                    await settings.updateCacheSizes()
                }
            }
        }
    }
}

#Preview { SettingsView().environmentObject(AppSettings()) }
// --- END OF COMPLETE FILE ---
