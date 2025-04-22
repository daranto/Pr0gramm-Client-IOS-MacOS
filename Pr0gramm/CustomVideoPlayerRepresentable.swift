// CustomVideoPlayerRepresentable.swift
import SwiftUI
import AVKit

struct CustomVideoPlayerRepresentable: UIViewControllerRepresentable {
    var player: AVPlayer?
    // --- NEU: Handler entgegennehmen ---
    @ObservedObject var handler: KeyboardActionHandler

    func makeUIViewController(context: Context) -> CustomAVPlayerViewController {
        let controller = CustomAVPlayerViewController()
        controller.player = player
        // --- NEU: Handler übergeben ---
        controller.actionHandler = handler
        print("CustomVideoPlayerRepresentable: makeUIViewController")
        return controller
    }

    func updateUIViewController(_ uiViewController: CustomAVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
             print("CustomVideoPlayerRepresentable: Updating player.")
            uiViewController.player = player
        }
        // --- NEU: Handler aktuell halten (wichtig!) ---
        if uiViewController.actionHandler !== handler {
             print("CustomVideoPlayerRepresentable: Updating handler.")
             uiViewController.actionHandler = handler
        }
    }
}
