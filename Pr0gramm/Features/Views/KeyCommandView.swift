import SwiftUI
import UIKit

/// A `UIViewControllerRepresentable` that embeds `KeyCommandViewController` into a SwiftUI view hierarchy.
/// This allows capturing specific keyboard events (like arrow keys) in SwiftUI by making the underlying
/// view controller the first responder.
struct KeyCommandView: UIViewControllerRepresentable {
    /// The handler that receives keyboard actions.
    @ObservedObject var handler: KeyboardActionHandler

    func makeUIViewController(context: Context) -> KeyCommandViewController {
        let controller = KeyCommandViewController()
        controller.actionHandler = handler // Pass the handler during creation
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandViewController, context: Context) {
        // Keep the action handler updated if the SwiftUI view's state changes
        uiViewController.actionHandler = handler
    }
}
