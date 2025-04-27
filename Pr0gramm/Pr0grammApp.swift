// Pr0gramm/Pr0gramm/Pr0grammApp.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVFoundation // <-- Add this import for AVAudioSession
import os         // <-- Add this import for Logger

/// The main entry point for the Pr0gramm SwiftUI application.
@main
struct Pr0grammApp: App {
    /// Manages global application settings and cache interactions.
    @StateObject private var appSettings: AppSettings
    /// Handles user authentication state and API calls.
    @StateObject private var authService: AuthService
    /// Manages the currently selected tab and navigation requests.
    @StateObject private var navigationService = NavigationService()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammApp") // <-- Add logger

    init() {
        // Initialize services, ensuring AuthService has access to AppSettings
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings))

        // --- Add AVAudioSession Configuration ---
        configureAudioSession()
        // ---------------------------------------
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

    // --- Add this private function ---
    /// Configures the shared AVAudioSession to allow audio playback even when the silent switch is on.
    private func configureAudioSession() {
        Self.logger.info("Configuring AVAudioSession...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set the category to .playback. This category allows audio playback
            // to ignore the device's silent switch (ringer mute).
            // It also allows mixing with audio from other apps by default.
            try audioSession.setCategory(.playback, mode: .default) // .default mode is usually sufficient

            // Optionally, activate the audio session here. While AVPlayer often handles
            // activation implicitly, activating it explicitly can sometimes prevent
            // minor delays or issues, especially if other audio features were planned.
            try audioSession.setActive(true)

            Self.logger.info("AVAudioSession configured successfully with category '.playback' and activated.")

        } catch {
            Self.logger.error("Failed to configure or activate AVAudioSession: \(error.localizedDescription)")
        }
    }
    // ------------------------------
}
// --- END OF COMPLETE FILE ---
