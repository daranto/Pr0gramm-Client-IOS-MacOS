// FilterView.swift

import SwiftUI

struct FilterView: View {
    // Zugriff auf die globalen Einstellungen, um sie zu lesen und zu ändern.
    @EnvironmentObject var settings: AppSettings
    // Environment-Variable, um das Sheet programmatisch zu schließen.
    @Environment(\.dismiss) var dismiss

    var body: some View {
        // NavigationStack gibt uns eine Titelzeile und Platz für einen Done-Button.
        NavigationStack {
            // Form gruppiert die Einstellungen optisch.
            Form {
                // --- Section 1: Feed-Typ (Neu/Beliebt) ---
                Section {
                    // Picker zur Auswahl zwischen .new und .promoted.
                    // $settings.feedType bindet den Picker-Wert direkt an die Einstellung.
                    Picker("Feed Typ", selection: $settings.feedType) {
                        // Iteriert durch alle Fälle des FeedType Enums.
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    // Segmented Picker Style ist oft passend für wenige Optionen.
                    .pickerStyle(.segmented)
                } header: {
                    Text("Anzeige") // Überschrift für die Section
                }

                // --- Section 2: Content Flags ---
                Section {
                    // Toggles für die einzelnen Flags.
                    // $settings.showSFW etc. bindet den Toggle-Status direkt.
                    Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                    Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                    Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                    Toggle("POL (Politik/Religion)", isOn: $settings.showPOL) // Beispielname
                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                     // Wichtiger Hinweis für den Benutzer
                     Text("Achtung: Die Anzeige von NSFW/NSFL Inhalten unterliegt den App Store Richtlinien.")
                }
            } // Ende Form
            .navigationTitle("Filter") // Titel der Filter-Ansicht
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline) // Kleiner Titel auf iOS
            #endif
            // --- Toolbar mit Done-Button ---
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { // Oben rechts
                    Button("Fertig") {
                        dismiss() // Schließt das Sheet
                    }
                }
            }
        } // Ende NavigationStack
    }
}

#Preview {
    FilterView()
        .environmentObject(AppSettings()) // Preview braucht Einstellungen
}
