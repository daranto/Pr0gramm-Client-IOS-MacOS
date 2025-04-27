import UIKit

/// A simple `UIViewController` designed to become the first responder
/// and capture keyboard events (specifically arrow keys) using the `pressesBegan` method.
/// It then forwards these events to a `KeyboardActionHandler`.
class KeyCommandViewController: UIViewController {

    var actionHandler: KeyboardActionHandler?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("KeyCommandViewController: viewDidAppear - Attempting to become first responder...")
        // Crucial: Explicitly request to become the first responder to receive key events.
        becomeFirstResponder()
    }

    /// Must return `true` to allow this view controller to become the first responder.
    override var canBecomeFirstResponder: Bool {
        // print("KeyCommandViewController: canBecomeFirstResponder called - Returning true")
        return true
    }

    /// Intercepts key presses to handle left and right arrow keys.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }

            print("KeyCommandViewController: Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags)")

            // Check for specific arrow key codes
            // Note: Modifier flags could be checked here if needed (e.g., key.modifierFlags.isEmpty)
            switch key.keyCode {
            case .keyboardLeftArrow:
                print("KeyCommandViewController: Left arrow detected via pressesBegan.")
                actionHandler?.selectPreviousAction?() // Trigger the assigned action
                didHandleEvent = true
            case .keyboardRightArrow:
                print("KeyCommandViewController: Right arrow detected via pressesBegan.")
                actionHandler?.selectNextAction?() // Trigger the assigned action
                didHandleEvent = true
            default:
                break // Ignore other keys
            }

            if didHandleEvent { break } // Stop processing if handled
        }

        // Only call the superclass implementation if *we did not* handle the event.
        // This prevents the event from propagating further up the responder chain if we consumed it.
        if !didHandleEvent {
            print("KeyCommandViewController: Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             print("KeyCommandViewController: Arrow key handled by us, NOT calling super.pressesBegan.")
             // Event processing stops here.
        }
    }
}
