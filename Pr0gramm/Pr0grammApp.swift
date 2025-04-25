// Pr0grammApp.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

@main
struct Pr0grammApp: App {
    // --- GEÄNDERT: Explizite Initialisierung im init() ---
    @StateObject private var appSettings: AppSettings
    @StateObject private var authService: AuthService

    init() {
        // Erstelle zuerst die AppSettings Instanz
        let settings = AppSettings()
        // Initialisiere die StateObjects mit den Instanzen
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings)) // Übergebe settings
    }
    // --- ENDE ÄNDERUNG ---


    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appSettings) // Bleibt gleich
                .environmentObject(authService) // Bleibt gleich
                .task { // Korrekter Ort für den Initialisierungsaufruf
                    await authService.checkInitialLoginStatus()
                }
        }
    }
}
// --- END OF COMPLETE FILE ---
