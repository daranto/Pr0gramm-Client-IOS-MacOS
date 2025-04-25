// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

struct FilterView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Feed Typ", selection: $settings.feedType) {
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Anzeige")
                }

                if authService.isLoggedIn {
                    Section {
                        Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                    } header: { Text("Inhaltsfilter") }
                      footer: { Text("Achtung: Die Anzeige von NSFW/NSFL/NSFP Inhalten unterliegt den App Store Richtlinien.") }
                }
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// --- Previews KORRIGIERT ---
#Preview("Logged Out") {
    // Struktur: View {}.environmentObject(...)
    FilterView()
        .environmentObject(AppSettings()) // Erstelle Settings direkt hier
        .environmentObject(AuthService(appSettings: AppSettings())) // Erstelle Auth direkt hier
}

#Preview("Logged In") {
    // Struktur: View {}.environmentObject(...)
    FilterView()
        .environmentObject(AppSettings()) // Erstelle Settings direkt hier
        .environmentObject({ // Erstelle und konfiguriere Auth Service im Closure
            let settings = AppSettings() // Braucht eigene Instanz für Auth Init
            let auth = AuthService(appSettings: settings)
            auth.isLoggedIn = true
            auth.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1)
            return auth // Gib den konfigurierten Service zurück
        }()) // Führe das Closure aus, um den Auth Service zu erstellen
}
// --- END OF COMPLETE FILE ---
