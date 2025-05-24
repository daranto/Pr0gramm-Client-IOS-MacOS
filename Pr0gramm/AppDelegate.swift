// Pr0gramm/Pr0gramm/AppDelegate.swift
// --- START OF COMPLETE FILE ---

import UIKit
import os

class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegateOrientation")

    static var orientationLock = UIInterfaceOrientationMask.portrait {
        didSet {
            Self.logger.info("Orientation lock changed to: \(String(describing: orientationLock.description)) (old: \(String(describing: oldValue.description)))")
            if orientationLock != oldValue { // Nur handeln, wenn sich der Wert wirklich ändert
                if #available(iOS 16.0, *) {
                    Self.logger.debug("iOS 16+: Requesting geometry update.")
                    UIApplication.shared.connectedScenes.forEach { scene in
                        if let windowScene = scene as? UIWindowScene {
                            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock)) { error in
                                Self.logger.error("Error requesting geometry update: \(error.localizedDescription)")
                            }
                        }
                        // Nach dem Request kann man versuchen, die Rotation zu erzwingen, falls nötig
                        UIViewController.attemptRotationToDeviceOrientation()
                    }
                } else {
                    Self.logger.debug("iOS <16: Setting orientation via UIDevice.")
                    // Fallback für ältere iOS-Versionen
                    if orientationLock.contains(.landscapeLeft) || orientationLock.contains(.landscapeRight) {
                         // Bevorzuge eine spezifische Landscape-Orientierung, wenn mehrere erlaubt sind
                        let newOrientation = orientationLock.contains(.landscapeRight) ? UIInterfaceOrientation.landscapeRight : UIInterfaceOrientation.landscapeLeft
                        UIDevice.current.setValue(newOrientation.rawValue, forKey: "orientation")
                        Self.logger.info("Set device orientation to: \(newOrientation.rawValue)")
                    } else if orientationLock.contains(.portrait) || orientationLock.contains(.allButUpsideDown) || orientationLock == .all {
                        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                        Self.logger.info("Set device orientation to: portrait")
                    }
                    // Manchmal ist ein erneuter Versuch nötig, die Rotation anzuwenden
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            } else {
                 Self.logger.debug("Orientation lock did not actually change. Skipping update.")
            }
        }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Self.logger.info("AppDelegate: didFinishLaunchingWithOptions")
        // Initialisiere den Lock, falls nötig, obwohl der Default schon .portrait ist.
        // AppDelegate.orientationLock = .portrait
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.logger.info("AppDelegate: supportedInterfaceOrientationsFor window called, returning: \(String(describing: AppDelegate.orientationLock.description))")
        return AppDelegate.orientationLock
    }
}

// Helper für die Beschreibung der Maske (optional, für bessere Logs)
extension UIInterfaceOrientationMask {
    var description: String {
        var descriptions = [String]()
        if self.contains(.portrait) { descriptions.append("portrait") }
        if self.contains(.portraitUpsideDown) { descriptions.append("portraitUpsideDown") }
        if self.contains(.landscapeLeft) { descriptions.append("landscapeLeft") }
        if self.contains(.landscapeRight) { descriptions.append("landscapeRight") }
        if self == .all { return "all" }
        if self == .allButUpsideDown { return "allButUpsideDown" }
        if self == .landscape { return "landscape (left & right)"}
        return descriptions.isEmpty ? "none" : descriptions.joined(separator: ", ")
    }
}
// --- END OF COMPLETE FILE ---
