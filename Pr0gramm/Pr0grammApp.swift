// Pr0grammApp.swift

import SwiftUI

@main
struct Pr0grammApp: App {
    // Erzeugt eine Instanz unserer Einstellungen und stellt sicher,
    // dass sie über den gesamten Lebenszyklus der App erhalten bleibt (@StateObject).
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainView()
                // Macht die appSettings-Instanz für ContentView und alle
                // darunterliegenden Views als EnvironmentObject verfügbar.
                .environmentObject(appSettings)
        }
    }
}
