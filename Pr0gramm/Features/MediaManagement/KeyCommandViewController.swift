// Pr0gramm/Pr0gramm/Features/MediaManagement/KeyCommandViewController.swift
// --- START OF COMPLETE FILE ---

import UIKit
import os // Import os

/// A simple `UIViewController` designed to become the first responder
/// and capture keyboard events (specifically arrow keys) using the `pressesBegan` method.
/// It then forwards these events to a `KeyboardActionHandler`.
class KeyCommandViewController: UIViewController {

    // --- NEW: Add logger ---
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "KeyCommandVC")
    // --- END NEW ---

    var actionHandler: KeyboardActionHandler?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Self.logger.debug("viewDidAppear - Attempting to become first responder...") // Use logger
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        // Self.logger.trace("canBecomeFirstResponder called - Returning true") // Use logger (optional trace)
        return true
    }

    /// Intercepts key presses to handle left and right arrow keys.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }

            // --- MODIFIED: Use .rawValue for modifierFlags ---
            Self.logger.debug("Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags.rawValue)") // Use logger and rawValue
            // --- END MODIFICATION ---

            switch key.keyCode {
            case .keyboardLeftArrow:
                Self.logger.debug("Left arrow detected via pressesBegan.") // Use logger
                actionHandler?.selectPreviousAction?()
                didHandleEvent = true
            case .keyboardRightArrow:
                Self.logger.debug("Right arrow detected via pressesBegan.") // Use logger
                actionHandler?.selectNextAction?()
                didHandleEvent = true
             // Handle Up/Down arrows
            case .keyboardUpArrow:
                Self.logger.debug("Up arrow detected, calling seek forward action.") // Use logger
                actionHandler?.seekForwardAction?() // Trigger seek forward
                didHandleEvent = true
            case .keyboardDownArrow:
                Self.logger.debug("Down arrow detected, calling seek backward action.") // Use logger
                actionHandler?.seekBackwardAction?() // Trigger seek backward
                didHandleEvent = true
            default:
                break // Ignore other keys
            }

            if didHandleEvent { break }
        }

        if !didHandleEvent {
            Self.logger.debug("Event not handled by us, calling super.pressesBegan.") // Use logger
            super.pressesBegan(presses, with: event)
        } else {
             Self.logger.debug("Arrow key handled by us, NOT calling super.pressesBegan.") // Use logger
        }
    }
}
// --- END OF COMPLETE FILE ---
