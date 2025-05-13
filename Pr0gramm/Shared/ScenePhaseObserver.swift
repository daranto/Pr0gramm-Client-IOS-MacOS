// ScenePhaseObserver.swift
// (z.B. in Pr0gramm/Pr0gramm/Shared/ScenePhaseObserver.swift)
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

@MainActor
class ScenePhaseObserver: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ScenePhaseObserver")
    private weak var appSettings: AppSettings?

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        ScenePhaseObserver.logger.info("ScenePhaseObserver initialized.")
    }

    func handleScenePhaseChange(newPhase: ScenePhase, oldPhase: ScenePhase?) {
        guard let settings = appSettings else {
            ScenePhaseObserver.logger.warning("AppSettings not available in handleScenePhaseChange.")
            return
        }

        if newPhase == .active {
            // Nur beim Übergang von inaktiv/background zu aktiv
            if oldPhase == .inactive || oldPhase == .background {
                ScenePhaseObserver.logger.info("App became active from \(String(describing: oldPhase)) state via ScenePhaseObserver.")
                settings.applyFilterResetOnAppOpenIfNeeded() // Rufe die Methode in AppSettings auf
            } else if oldPhase == nil {
                 // Dieser Fall ist für initial: true im .onChange des AppRootView
                 // und wird auch für den Kaltstart verwendet.
                 ScenePhaseObserver.logger.info("App became active (initial call or first active) via ScenePhaseObserver.")
                 settings.applyFilterResetOnAppOpenIfNeeded()
            }
        }
    }
}
// --- END OF COMPLETE FILE ---
