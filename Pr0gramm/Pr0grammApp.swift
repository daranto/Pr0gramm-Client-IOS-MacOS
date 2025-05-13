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

    // --- NEW: Environment variable for scenePhase ---
    @Environment(\.scenePhase) var scenePhase
    // --- END NEW ---

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammApp")

    init() {
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
                .task { // Wird einmal beim Start der WindowGroup ausgeführt
                    await authService.checkInitialLoginStatus()
                    // --- NEW: Filter-Reset beim ersten Start (nach Login-Check) ---
                    applyFilterResetIfNeeded()
                    // --- END NEW ---
                }
                .preferredColorScheme(appSettings.colorSchemeSetting.swiftUIScheme)
                // --- NEW: Beobachte scenePhase für Filter-Reset ---
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active && oldPhase == .inactive { // Von inaktiv zu aktiv (z.B. Rückkehr aus Hintergrund)
                        Pr0grammApp.logger.info("App became active from inactive state.")
                        applyFilterResetIfNeeded()
                    } else if newPhase == .active && oldPhase == .background { // Von Hintergrund zu aktiv
                        Pr0grammApp.logger.info("App became active from background state.")
                        applyFilterResetIfNeeded()
                    }
                }
                // --- END NEW ---
        }
    }
    
    // --- NEW: Methode zum Zurücksetzen der Filter ---
    private func applyFilterResetIfNeeded() {
        if appSettings.resetFiltersOnAppOpen {
            Pr0grammApp.logger.info("Applying filter reset to SFW as per settings.")
            appSettings.showSFW = true
            appSettings.showNSFW = false
            appSettings.showNSFL = false
            appSettings.showNSFP = false
            appSettings.showPOL = false
            // Der FeedType (Neu/Beliebt/Müll) wird hier nicht geändert, nur die Inhaltsfilter.
        } else {
            Pr0grammApp.logger.info("Filter reset on app open is disabled.")
        }
    }
    // --- END NEW ---

    private func configureAudioSession() {
        Self.logger.info("Configuring AVAudioSession...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            Self.logger.info("AVAudioSession category set to '.playback' with options '[.mixWithOthers]'.")

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
