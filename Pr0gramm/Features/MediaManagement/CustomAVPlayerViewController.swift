import AVKit
import UIKit
import os

/// A custom subclass of `AVPlayerViewController` that handles keyboard input
/// (specifically arrow keys) and provides callbacks for fullscreen transitions via its delegate.
class CustomAVPlayerViewController: AVPlayerViewController, AVPlayerViewControllerDelegate {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CustomAVPlayerVC")
    /// The object responsible for handling keyboard actions (e.g., navigating to next/previous item).
    var actionHandler: KeyboardActionHandler?

    // Callbacks triggered by the delegate methods.
    var willBeginFullScreen: (() -> Void)?
    var willEndFullScreen: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self // Set self as the delegate to receive fullscreen callbacks
        Self.logger.debug("viewDidLoad: Delegate set.")
    }

    /// Overrides the default key commands to remove the standard arrow key behaviors
    /// provided by `AVPlayerViewController` (like seeking), allowing us to handle them ourselves.
    override var keyCommands: [UIKeyCommand]? {
        let standardCommands = super.keyCommands ?? []
        // Filter out the standard arrow key commands
        let nonArrowCommands = standardCommands.filter { command in
            if let input = command.input {
                return input != UIKeyCommand.inputLeftArrow &&
                       input != UIKeyCommand.inputRightArrow &&
                       input != UIKeyCommand.inputUpArrow &&
                       input != UIKeyCommand.inputDownArrow
            }
            return true // Keep commands without specific input defined
        }
        return nonArrowCommands
    }

    /// Intercepts key presses to handle left and right arrow keys for custom navigation actions.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
       var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }
            Self.logger.debug("Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags.rawValue)")

            // Handle left/right arrow keys specifically
            switch key.keyCode {
            case .keyboardLeftArrow:
                Self.logger.debug("Left arrow detected, calling previous action.")
                actionHandler?.selectPreviousAction?() // Trigger custom action
                didHandleEvent = true
            case .keyboardRightArrow:
                Self.logger.debug("Right arrow detected, calling next action.")
                actionHandler?.selectNextAction?() // Trigger custom action
                didHandleEvent = true
            default:
                break // Ignore other keys
            }
            if didHandleEvent { break } // Stop processing if handled
        }

        // If we didn't handle the event (i.e., it wasn't an arrow key we care about),
        // pass it up to the superclass to handle standard player controls (like spacebar).
        if !didHandleEvent {
            Self.logger.debug("Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             // If we handled it, prevent the superclass from also processing it.
             Self.logger.debug("Arrow key handled by us, NOT calling super.pressesBegan.")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.logger.debug("viewWillDisappear called.")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Self.logger.debug("viewWillAppear called.")
    }

    // MARK: - AVPlayerViewControllerDelegate Methods

    /// Delegate method called *before* the player begins transitioning to fullscreen.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        Self.logger.debug("Delegate: willBeginFullScreenPresentation - Calling Callback")
        willBeginFullScreen?() // Trigger the provided callback
    }

    /// Delegate method called *before* the player begins transitioning *out* of fullscreen.
    /// The callback (`willEndFullScreen`) is triggered *after* the transition animation completes.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        Self.logger.debug("Delegate: willEndFullScreenPresentation - Calling Callback after animation")

        // Use the coordinator's completion block to ensure the callback runs
        // only after the fullscreen exit animation finishes.
        coordinator.animate(
            alongsideTransition: nil, // No parallel animations needed
            completion: { (context: UIViewControllerTransitionCoordinatorContext) in
                self.willEndFullScreen?() // Trigger the callback in the completion handler
            }
        )
    }

    deinit {
         Self.logger.debug("deinit")
    }
}
