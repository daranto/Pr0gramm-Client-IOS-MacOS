// Pr0gramm/Pr0gramm/Features/MediaManagement/CustomVideoPlayerRepresentable.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit

/// A `UIViewControllerRepresentable` that wraps a `CustomAVPlayerViewController`
/// to integrate the standard iOS video player (`AVPlayerViewController`) into SwiftUI.
/// It passes the `AVPlayer`, keyboard actions, fullscreen callbacks, and video gravity settings
/// to the underlying view controller.
struct CustomVideoPlayerRepresentable: UIViewControllerRepresentable {
    var player: AVPlayer?
    /// The handler for keyboard events (passed to the view controller).
    @ObservedObject var handler: KeyboardActionHandler
    /// Callback triggered just before entering fullscreen.
    var onWillBeginFullScreen: () -> Void
    /// Callback triggered just after exiting fullscreen.
    var onWillEndFullScreen: () -> Void
    /// The horizontal size class to determine video gravity. (Wird jetzt ignoriert)
    var horizontalSizeClass: UserInterfaceSizeClass?

    func makeUIViewController(context: Context) -> CustomAVPlayerViewController {
        let controller = CustomAVPlayerViewController()
        controller.player = player
        controller.actionHandler = handler
        controller.willBeginFullScreen = onWillBeginFullScreen
        controller.willEndFullScreen = onWillEndFullScreen
        
        // --- MODIFIED: Testweise feste videoGravity ---
        controller.videoGravity = AVLayerVideoGravity.resizeAspect
        print("CustomVideoPlayerRepresentable: makeUIViewController (FIXED Gravity: \(controller.videoGravity.rawValue))")
        // --- END MODIFICATION ---
        return controller
    }

    func updateUIViewController(_ uiViewController: CustomAVPlayerViewController, context: Context) {
        // Update the player instance if it changes
        if uiViewController.player !== player {
             print("CustomVideoPlayerRepresentable: Updating player.")
            uiViewController.player = player
        }
        // Update the handler if it changes
        if uiViewController.actionHandler !== handler {
             print("CustomVideoPlayerRepresentable: Updating handler.")
             uiViewController.actionHandler = handler
        }
        // Keep callbacks up-to-date
        uiViewController.willBeginFullScreen = onWillBeginFullScreen
        uiViewController.willEndFullScreen = onWillEndFullScreen

        // --- MODIFIED: Testweise feste videoGravity, kein Update basierend auf horizontalSizeClass ---
        let targetGravity: AVLayerVideoGravity = AVLayerVideoGravity.resizeAspect
        if uiViewController.videoGravity != targetGravity {
            // Dieser Block sollte jetzt seltener oder gar nicht mehr aufgerufen werden,
            // es sei denn, die Gravity wurde extern geändert.
            print("CustomVideoPlayerRepresentable: Updating videoGravity to \(targetGravity.rawValue) (sollte fest sein)")
            uiViewController.videoGravity = targetGravity
        }
        // --- END MODIFICATION ---
    }
}
// --- END OF COMPLETE FILE ---
