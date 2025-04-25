// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF MODIFIED FILE ---

// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift

import SwiftUI
import os

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    // --- Umbenannt: State-Variable für Klarheit ---
    @State private var showingClearAllCacheAlert = false

    let cacheSizeOptions = [50, 100, 250, 500, 1000]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form {
                Section("Video") {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                }

                // --- Cache Bereich (Überarbeitet) ---
                Section("Cache") { // Einfacherer Titel
                    HStack {
                        Text("Aktuelle Größe")
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentCacheSizeMB))
                            .foregroundColor(.secondary)
                    }

                    Picker("Maximale Größe (Bilder)", selection: $settings.maxCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }
                    .onChange(of: settings.maxCacheSizeMB) { _, _ in
                        Self.logger.info("Max image cache size setting changed.")
                    }

                    // --- Nur noch EIN Button ---
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true // Löst den einzigen Alert aus
                    }
                    // --- Zweiter Button entfernt ---
                }
                // --- Ende Cache Bereich ---
            }
            .navigationTitle("Einstellungen")
            // --- Angepasster Alert ---
            .alert("Gesamten App-Cache leeren?", isPresented: $showingClearAllCacheAlert) { // Verwendet umbenannte Variable
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) {
                    Task {
                        // --- Ruft jetzt die Funktion zum Löschen *aller* Caches auf ---
                        await settings.clearAllAppCache()
                    }
                }
            } message: {
                // --- Angepasste Nachricht ---
                Text("Möchtest du wirklich alle zwischengespeicherten Daten (Feeds, Favoriten, Bilder etc.) löschen? Dies kann nicht rückgängig gemacht werden.")
            }
            .onAppear {
                Task {
                    await settings.updateCurrentCombinedCacheSize()
                }
            }
        }
    }
}

#Preview { SettingsView().environmentObject(AppSettings()) }
// --- END OF MODIFIED FILE ---
