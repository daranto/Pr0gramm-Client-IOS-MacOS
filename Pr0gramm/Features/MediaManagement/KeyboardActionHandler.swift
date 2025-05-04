// Pr0gramm/Pr0gramm/Features/MediaManagement/KeyboardActionHandler.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine // Required for ObservableObject

/// A simple `ObservableObject` used to bridge keyboard actions (like arrow key presses)
/// captured by UIKit components (`KeyCommandViewController` or `CustomAVPlayerViewController`)
/// to SwiftUI views or view models. SwiftUI views can set the action closures.
class KeyboardActionHandler: ObservableObject {
    /// Closure to be executed when the "next" action (e.g., right arrow) is detected.
    var selectNextAction: (() -> Void)?
    /// Closure to be executed when the "previous" action (e.g., left arrow) is detected.
    var selectPreviousAction: (() -> Void)?
    // --- NEW: Actions for seeking ---
    /// Closure to be executed when the "seek forward" action (e.g., up arrow) is detected.
    var seekForwardAction: (() -> Void)?
    /// Closure to be executed when the "seek backward" action (e.g., down arrow) is detected.
    var seekBackwardAction: (() -> Void)?
    // --- END NEW ---
}
// --- END OF COMPLETE FILE ---
