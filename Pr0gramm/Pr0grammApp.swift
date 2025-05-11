// Pr0gramm/Pr0gramm/Pr0grammApp.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVFoundation
import os

/// The main entry point for the Pr0gramm SwiftUI application.
@main
struct Pr0grammApp: App {
    /// Manages global application settings and cache interactions.
    @StateObject private var appSettings: AppSettings
    /// Handles user authentication state and API calls.
    @StateObject private var authService: AuthService
    /// Manages the currently selected tab and navigation requests.
    @StateObject private var navigationService = NavigationService()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammApp")

    init() {
        // Initialize services, ensuring AuthService has access to AppSettings
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings))

        configureAudioSession()
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
                // --- MODIFIED: Apply preferredColorScheme dynamically ---
                .preferredColorScheme(appSettings.colorSchemeSetting.swiftUIScheme)
                // --- END MODIFICATION ---
        }
    }

    /// Configures the shared AVAudioSession to:
    /// 1. Allow audio playback even when the silent switch is on (`.playback`).
    /// 2. Attempt to mix with other audio playing on the system (`.mixWithOthers`).
    /// 3. Force audio output to the device's built-in speaker (`overrideOutputAudioPort(.speaker)`).
    private func configureAudioSession() {
        Self.logger.info("Configuring AVAudioSession...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category to playback (ignores mute switch) and allow mixing
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            Self.logger.info("AVAudioSession category set to '.playback' with options '[.mixWithOthers]'.")

            // Activate the session BEFORE overriding the port
            try audioSession.setActive(true)
            Self.logger.info("AVAudioSession activated.")

            do {
                try audioSession.overrideOutputAudioPort(.speaker)
                Self.logger.info("AVAudioSession output successfully overridden to force speaker.")
            } catch let error as NSError {
                Self.logger.error("Failed to override output port to speaker: \(error.localizedDescription) (Code: \(error.code))")
            }

            Self.logger.info("AVAudioSession configuration complete.")

        } catch {
            Self.logger.error("Failed during AVAudioSession configuration (setCategory or setActive): \(error.localizedDescription)")
        }
    }
}
// --- END OF COMPLETE FILE ---
