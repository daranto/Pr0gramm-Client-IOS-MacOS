import SwiftUI
import AVKit

/// A `UIViewControllerRepresentable` that wraps a `CustomAVPlayerViewController`
/// to integrate the standard iOS video player (`AVPlayerViewController`) into SwiftUI.
/// It passes the `AVPlayer`, keyboard actions, and fullscreen callbacks to the underlying view controller.
struct CustomVideoPlayerRepresentable: UIViewControllerRepresentable {
    var player: AVPlayer?
    /// The handler for keyboard events (passed to the view controller).
    @ObservedObject var handler: KeyboardActionHandler
    /// Callback triggered just before entering fullscreen.
    var onWillBeginFullScreen: () -> Void
    /// Callback triggered just after exiting fullscreen.
    var onWillEndFullScreen: () -> Void

    func makeUIViewController(context: Context) -> CustomAVPlayerViewController {
        let controller = CustomAVPlayerViewController()
        controller.player = player
        controller.actionHandler = handler
        // Pass callbacks to the view controller
        controller.willBeginFullScreen = onWillBeginFullScreen
        controller.willEndFullScreen = onWillEndFullScreen
        print("CustomVideoPlayerRepresentable: makeUIViewController")
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
    }
}
