// Pr0gramm/Pr0gramm/Shared/AppOrientationManager.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import UIKit
import os

@MainActor
class AppOrientationManager: ObservableObject {
    @Published var isLockedToPortrait: Bool = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppOrientationManager")

    func lockOrientationToPortrait() {
        if !isLockedToPortrait {
            isLockedToPortrait = true
            Self.logger.info("Locking orientation to Portrait.")
            // Diese Methode versucht, die UIWindowScene zu finden und die Orientierung zu setzen.
            // Es ist wichtig, dass dies nach dem die Szene vollständig initialisiert wurde, geschieht.
            // In SwiftUI wird dies am besten über den SceneDelegate gesteuert.
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                Self.logger.error("Error requesting portrait geometry update: \(error.localizedDescription)")
            }
            // Für ältere iOS Versionen oder als Fallback
            #if !targetEnvironment(macCatalyst)
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            #endif
        } else {
            Self.logger.debug("Orientation already locked to Portrait.")
        }
    }

    func unlockOrientation() {
        if isLockedToPortrait {
            isLockedToPortrait = false
            Self.logger.info("Unlocking orientation.")
            // Erlaube wieder alle Orientierungen, die in der Info.plist definiert sind
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { error in
                 Self.logger.error("Error requesting all orientations geometry update: \(error.localizedDescription)")
            }
             #if !targetEnvironment(macCatalyst)
             // Es gibt keinen direkten "unlock"-Befehl. Man erlaubt einfach wieder alle.
             // Das System wird dann zur aktuell präferierten Orientierung wechseln oder die vom Nutzer gewählte.
             UIViewController.attemptRotationToDeviceOrientation()
             #endif
        } else {
            Self.logger.debug("Orientation was not locked.")
        }
    }
}
// --- END OF COMPLETE FILE ---
