// ScenePhaseObserver.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

@MainActor
class ScenePhaseObserver: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ScenePhaseObserver")
    private weak var appSettings: AppSettings?
    private weak var authService: AuthService?

    init(appSettings: AppSettings, authService: AuthService) {
        self.appSettings = appSettings
        self.authService = authService
        ScenePhaseObserver.logger.info("ScenePhaseObserver initialized.")
    }

    func handleScenePhaseChange(newPhase: ScenePhase, oldPhase: ScenePhase?) {
        guard let settings = appSettings, let auth = authService else {
            ScenePhaseObserver.logger.warning("AppSettings or AuthService not available in handleScenePhaseChange.")
            return
        }

        if newPhase == .active {
            if oldPhase == .inactive || oldPhase == .background {
                ScenePhaseObserver.logger.info("App became active from \(String(describing: oldPhase)) state via ScenePhaseObserver.")
                // --- MODIFIED: applyStartupFiltersIfNeeded statt applyFilterResetOnAppOpenIfNeeded ---
                settings.applyStartupFiltersIfNeeded()
                // --- END MODIFICATION ---
                Task { await auth.fetchUnreadCounts() }
            } else if oldPhase == nil {
                 ScenePhaseObserver.logger.info("App became active (initial call or first active) via ScenePhaseObserver.")
                 // --- MODIFIED: applyStartupFiltersIfNeeded statt applyFilterResetOnAppOpenIfNeeded ---
                 settings.applyStartupFiltersIfNeeded()
                 // --- END MODIFICATION ---
                 Task { await auth.fetchUnreadCounts() }
            }
        }
    }
}
// --- END OF COMPLETE FILE ---
