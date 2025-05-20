// ScenePhaseObserver.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

@MainActor
class ScenePhaseObserver: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ScenePhaseObserver")
    private weak var appSettings: AppSettings?
    // --- NEW: Add AuthService reference ---
    private weak var authService: AuthService?
    // --- END NEW ---

    // --- MODIFIED: Update initializer ---
    init(appSettings: AppSettings, authService: AuthService) {
        self.appSettings = appSettings
        self.authService = authService // Store AuthService
        ScenePhaseObserver.logger.info("ScenePhaseObserver initialized.")
    }
    // --- END MODIFICATION ---

    func handleScenePhaseChange(newPhase: ScenePhase, oldPhase: ScenePhase?) {
        // --- MODIFIED: Get both services ---
        guard let settings = appSettings, let auth = authService else {
            ScenePhaseObserver.logger.warning("AppSettings or AuthService not available in handleScenePhaseChange.")
            return
        }
        // --- END MODIFICATION ---


        if newPhase == .active {
            if oldPhase == .inactive || oldPhase == .background {
                ScenePhaseObserver.logger.info("App became active from \(String(describing: oldPhase)) state via ScenePhaseObserver.")
                settings.applyFilterResetOnAppOpenIfNeeded()
                // --- NEW: Fetch unread counts ---
                Task { await auth.fetchUnreadCounts() }
                // --- END NEW ---
            } else if oldPhase == nil {
                 ScenePhaseObserver.logger.info("App became active (initial call or first active) via ScenePhaseObserver.")
                 settings.applyFilterResetOnAppOpenIfNeeded()
                 // --- NEW: Fetch unread counts for initial active state too ---
                 Task { await auth.fetchUnreadCounts() }
                 // --- END NEW ---
            }
        }
        // --- NEW: Potentially stop timer when app goes to background (optional, AuthService handles its own timer start/stop on login/logout) ---
        // else if newPhase == .background {
        //     ScenePhaseObserver.logger.info("App went to background. (Timer is managed by AuthService)")
        // }
        // --- END NEW ---
    }
}
// --- END OF COMPLETE FILE ---
