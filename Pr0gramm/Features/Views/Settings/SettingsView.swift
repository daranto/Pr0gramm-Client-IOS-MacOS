// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingClearCacheAlert = false // Für Bestätigungsdialog

    // Mögliche Optionen für Cache-Größen (in MB)
    let cacheSizeOptions = [50, 100, 250, 500, 1000] // Beispielwerte

    var body: some View {
        NavigationStack {
            Form { // Form für konsistentes Aussehen
                Section("Video") {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                }

                // --- NEUER Cache Bereich ---
                Section("Cache") {
                    // Angezeigte Größe
                    HStack {
                        Text("Aktuelle Größe")
                        Spacer()
                        // Zeigt die Größe an, formatiert auf 1 Dezimalstelle
                        Text(String(format: "%.1f MB", settings.currentCacheSizeMB))
                            .foregroundColor(.secondary)
                    }

                    // Einstellung für maximale Größe
                    Picker("Maximale Größe", selection: $settings.maxCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }

                    // Button zum Leeren
                    Button("Cache leeren", role: .destructive) {
                        showingClearCacheAlert = true // Zeigt den Alert
                    }
                }
                // --- Ende Cache Bereich ---

                // Hier könnten weitere App-Einstellungen hin
            }
            .navigationTitle("Einstellungen")
            // Alert zur Bestätigung des Löschens
            .alert("Cache leeren?", isPresented: $showingClearCacheAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) {
                    // Asynchrone Aktion starten
                    Task {
                        await settings.clearAppCache()
                    }
                }
            } message: {
                Text("Möchtest du wirklich alle zwischengespeicherten Feed-Daten löschen?")
            }
            // Aktualisiere die Cache-Größe, wenn die Ansicht erscheint
            .onAppear {
                Task {
                    await settings.updateCurrentCacheSize()
                }
            }
        }
    }
}

#Preview { SettingsView().environmentObject(AppSettings()) }
