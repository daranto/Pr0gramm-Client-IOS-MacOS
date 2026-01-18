// Pr0gramm/Pr0gramm/Features/MediaManagement/CustomVideoPlayerRepresentable.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit

#if canImport(UIKit)
import UIKit

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

#elseif canImport(AppKit)
import AppKit

/// A `NSViewRepresentable` that wraps an `AVPlayerView`
/// to integrate the macOS video player into SwiftUI.
struct CustomVideoPlayerRepresentable: NSViewRepresentable {
    var player: AVPlayer?
    /// The handler for keyboard events.
    @ObservedObject var handler: KeyboardActionHandler
    /// Callback triggered just before entering fullscreen.
    var onWillBeginFullScreen: () -> Void
    /// Callback triggered just after exiting fullscreen.
    var onWillEndFullScreen: () -> Void
    /// The horizontal size class (not used on macOS).
    var horizontalSizeClass: UserInterfaceSizeClass?
    
    class Coordinator {
        var fullscreenObserver: NSObjectProtocol?
        var exitFullscreenObserver: NSObjectProtocol?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = true
        playerView.showsSharingServiceButton = false
        playerView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(playerView)
        
        // Constraints für playerView
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        print("CustomVideoPlayerRepresentable (macOS): makeNSView - Player set, controls: inline")
        
        // Setup fullscreen notification observers using coordinator
        context.coordinator.fullscreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak onWillBeginFullScreen] _ in
            print("CustomVideoPlayerRepresentable (macOS): Will enter fullscreen")
            onWillBeginFullScreen?()
        }
        
        context.coordinator.exitFullscreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak onWillEndFullScreen] _ in
            print("CustomVideoPlayerRepresentable (macOS): Did exit fullscreen")
            onWillEndFullScreen?()
        }
        
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let playerView = nsView.subviews.first as? AVPlayerView else { return }
        
        // Update the player instance if it changes
        if playerView.player !== player {
            print("CustomVideoPlayerRepresentable (macOS): Updating player.")
            playerView.player = player
        }
        
        // Ensure controlsStyle stays inline to show all controls
        if playerView.controlsStyle != .inline {
            print("CustomVideoPlayerRepresentable (macOS): Resetting controlsStyle to inline")
            playerView.controlsStyle = .inline
        }
        
        // Ensure videoGravity stays consistent
        if playerView.videoGravity != .resizeAspect {
            print("CustomVideoPlayerRepresentable (macOS): Resetting videoGravity to resizeAspect")
            playerView.videoGravity = .resizeAspect
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Clean up notification observers
        if let observer = coordinator.fullscreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = coordinator.exitFullscreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        print("CustomVideoPlayerRepresentable (macOS): Dismantled NSView and removed observers")
    }
}

#endif
// --- END OF COMPLETE FILE ---
