// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF MODIFIED FILE ---

// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift

import SwiftUI
import os // <-- Import os

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingClearFeedCacheAlert = false // Benannt nach dem, was es tut

    // Mögliche Optionen für Cache-Größen (in MB)
    let cacheSizeOptions = [50, 100, 250, 500, 1000] // Beispielwerte

    // --- HINZUGEFÜGT: Logger Instanz ---
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form { // Form für konsistentes Aussehen
                Section("Video") {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                }

                // --- Cache Bereich ---
                Section("Cache (Bilder & Feeds)") { // Titel angepasst
                    // Angezeigte Größe (zeigt kombinierte Größe)
                    HStack {
                        Text("Aktuelle Größe")
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentCacheSizeMB))
                            .foregroundColor(.secondary)
                    }

                    // Einstellung für maximale Größe (betrifft nur Bilder-Cache!)
                    Picker("Maximale Größe (Bilder)", selection: $settings.maxCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }
                    .onChange(of: settings.maxCacheSizeMB) { _, _ in
                        // Logik zum Anwenden des Limits ist in AppSettings.maxCacheSizeMB.didSet
                        Self.logger.info("Max image cache size setting changed.")
                    }


                    // Button zum Leeren (löscht jetzt Feed-Daten UND Bilder)
                    Button("Feed- & Bild-Cache leeren", role: .destructive) {
                        showingClearFeedCacheAlert = true // Zeigt den Alert
                    }
                    // Optional: Separater Button zum Löschen *aller* Daten-Caches
                     Button("Alle Daten-Caches löschen", role: .destructive) {
                          // Hier könnte ein anderer Alert/Aktion hin,
                          // um settings.clearAllAppCache() aufzurufen
                          // Fürs Erste lassen wir es beim Feed/Bild-Cache
                          Self.logger.warning("Clear ALL Data Cache button tapped - Not implemented via UI Alert yet.") // Use Self.logger here
                     }.tint(.orange) // Andere Farbe zur Unterscheidung
                }
                // --- Ende Cache Bereich ---

                // Hier könnten weitere App-Einstellungen hin
            }
            .navigationTitle("Einstellungen")
            // Alert zur Bestätigung des Löschens (Feed + Bilder)
            .alert("Feed- & Bild-Cache leeren?", isPresented: $showingClearFeedCacheAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) {
                    Task {
                        await settings.clearFeedAndImageCache() // Ruft die spezifische Funktion auf
                    }
                }
            } message: {
                Text("Möchtest du wirklich alle zwischengespeicherten Feed-Daten und Bilder löschen? Favoriten bleiben erhalten.")
            }
            // Aktualisiere die Cache-Größe, wenn die Ansicht erscheint
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
