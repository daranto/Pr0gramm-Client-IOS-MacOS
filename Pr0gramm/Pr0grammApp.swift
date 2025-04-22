// Pr0grammApp.swift

import SwiftUI

@main
struct Pr0grammApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appSettings)
                .environmentObject(authService)
                .task { // Korrekter Ort für den Initialisierungsaufruf
                    await authService.checkInitialLoginStatus()
                }
        }
    }
}
