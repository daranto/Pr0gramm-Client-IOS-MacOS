// CustomVideoPlayerRepresentable.swift
import SwiftUI
import AVKit

struct CustomVideoPlayerRepresentable: UIViewControllerRepresentable {
    var player: AVPlayer?
    @ObservedObject var handler: KeyboardActionHandler
    // Callbacks werden wieder benötigt
    var onWillBeginFullScreen: () -> Void
    var onWillEndFullScreen: () -> Void

    func makeUIViewController(context: Context) -> CustomAVPlayerViewController {
        let controller = CustomAVPlayerViewController()
        controller.player = player
        controller.actionHandler = handler
        // Callbacks an VC weitergeben
        controller.willBeginFullScreen = onWillBeginFullScreen
        controller.willEndFullScreen = onWillEndFullScreen
        print("CustomVideoPlayerRepresentable: makeUIViewController")
        return controller
    }

    func updateUIViewController(_ uiViewController: CustomAVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
             print("CustomVideoPlayerRepresentable: Updating player.")
            uiViewController.player = player
        }
        if uiViewController.actionHandler !== handler {
             print("CustomVideoPlayerRepresentable: Updating handler.")
             uiViewController.actionHandler = handler
        }
        // Callbacks aktuell halten
        uiViewController.willBeginFullScreen = onWillBeginFullScreen
        uiViewController.willEndFullScreen = onWillEndFullScreen
    }
}
