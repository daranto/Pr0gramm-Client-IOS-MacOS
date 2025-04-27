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
    /// The horizontal size class to determine video gravity.
    var horizontalSizeClass: UserInterfaceSizeClass?

    func makeUIViewController(context: Context) -> CustomAVPlayerViewController {
        let controller = CustomAVPlayerViewController()
        controller.player = player
        controller.actionHandler = handler
        controller.willBeginFullScreen = onWillBeginFullScreen
        controller.willEndFullScreen = onWillEndFullScreen
        // Set initial video gravity based on size class, using explicit type
        controller.videoGravity = (horizontalSizeClass == .compact) ? AVLayerVideoGravity.resizeAspectFill : AVLayerVideoGravity.resizeAspect // <-- Explicit Type
        print("CustomVideoPlayerRepresentable: makeUIViewController (Gravity: \(controller.videoGravity.rawValue))")
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

        // Update video gravity if size class changes, using explicit type
        let targetGravity: AVLayerVideoGravity = (horizontalSizeClass == .compact) ? AVLayerVideoGravity.resizeAspectFill : AVLayerVideoGravity.resizeAspect // <-- Explicit Type
        if uiViewController.videoGravity != targetGravity {
            print("CustomVideoPlayerRepresentable: Updating videoGravity to \(targetGravity.rawValue)")
            uiViewController.videoGravity = targetGravity
        }
    }
}
// --- END OF COMPLETE FILE ---
