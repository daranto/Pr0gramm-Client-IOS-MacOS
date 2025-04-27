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
}
