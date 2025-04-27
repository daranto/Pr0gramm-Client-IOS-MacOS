import SwiftUI

/// The main entry point for the Pr0gramm SwiftUI application.
@main
struct Pr0grammApp: App {
    /// Manages global application settings and cache interactions.
    @StateObject private var appSettings: AppSettings
    /// Handles user authentication state and API calls.
    @StateObject private var authService: AuthService
    /// Manages the currently selected tab and navigation requests.
    @StateObject private var navigationService = NavigationService()

    init() {
        // Initialize services, ensuring AuthService has access to AppSettings
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings))
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appSettings)
                .environmentObject(authService)
                .environmentObject(navigationService)
                .task {
                    // Check if the user is already logged in when the app starts
                    await authService.checkInitialLoginStatus()
                }
        }
    }
}
