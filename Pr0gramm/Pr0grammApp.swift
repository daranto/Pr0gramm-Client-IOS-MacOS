// Pr0gramm/Pr0gramm/Pr0grammApp.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVFoundation
import os

/// The main entry point for the Pr0gramm SwiftUI application.
@main
struct Pr0grammApp: App {
    @StateObject private var appSettings: AppSettings
    @StateObject private var authService: AuthService
    @StateObject private var navigationService = NavigationService()
    @StateObject private var scenePhaseObserver: ScenePhaseObserver

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammApp")

    init() {
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: AuthService(appSettings: settings))
        _scenePhaseObserver = StateObject(wrappedValue: ScenePhaseObserver(appSettings: settings))

        configureAudioSession()
        Pr0grammApp.logger.info("Pr0grammApp init")
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appSettings)
                .environmentObject(authService)
                .environmentObject(navigationService)
                .environmentObject(scenePhaseObserver)
        }
    }
    
    // applyInitialFilterResetIfNeeded() wird nicht mehr direkt in Pr0grammApp benötigt,
    // da AppRootView und ScenePhaseObserver dies jetzt über appSettings.applyFilterResetOnAppOpenIfNeeded() handhaben.
    // Man könnte es für absolute Klarheit entfernen, aber es schadet auch nicht, es vorerst zu belassen (es wird nur nicht mehr aufgerufen).

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

// --- AppRootView ---
struct AppRootView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var scenePhaseObserver: ScenePhaseObserver

    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        MainView()
            .accentColor(appSettings.accentColorChoice.swiftUIColor)
            .preferredColorScheme(appSettings.colorSchemeSetting.swiftUIScheme)
            .task {
                await authService.checkInitialLoginStatus()
                // Der initiale Filter-Reset wird jetzt durch .onChange(of: scenePhase, initial: true)
                // und den ScenePhaseObserver beim ersten Aktivwerden der Szene gehandhabt.
                // Ein expliziter Aufruf hier ist nicht mehr zwingend, da initial:true das abdeckt.
                // appSettings.applyFilterResetOnAppOpenIfNeeded() // Kann entfernt oder für Debugging belassen werden
            }
            .onChange(of: scenePhase, initial: true) { oldPhase, newPhase in
                // oldPhase ist nil beim ersten Aufruf wegen initial: true
                scenePhaseObserver.handleScenePhaseChange(newPhase: newPhase, oldPhase: oldPhase)
            }
    }
}
// --- END OF COMPLETE FILE ---
