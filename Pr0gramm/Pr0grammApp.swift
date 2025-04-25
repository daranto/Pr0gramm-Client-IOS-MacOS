// Pr0gramm/Pr0gramm/Pr0grammApp.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

@main
struct Pr0grammApp: App {
    @StateObject private var appSettings: AppSettings
    @StateObject private var authService: AuthService
    @StateObject private var navigationService = NavigationService() // <-- Initialize NavigationService

    init() {
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings))
    }


    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appSettings)
                .environmentObject(authService)
                .environmentObject(navigationService) // <-- Inject NavigationService
                .task {
                    await authService.checkInitialLoginStatus()
                }
        }
    }
}
// --- END OF COMPLETE FILE ---
