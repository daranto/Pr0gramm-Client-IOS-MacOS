// KeyCommandView.swift
import SwiftUI
import UIKit

struct KeyCommandView: UIViewControllerRepresentable {
    @ObservedObject var handler: KeyboardActionHandler

    func makeUIViewController(context: Context) -> KeyCommandViewController {
        let controller = KeyCommandViewController()
        controller.actionHandler = handler // Handler übergeben
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandViewController, context: Context) {
        // Handler aktuell halten
        uiViewController.actionHandler = handler
    }
}
