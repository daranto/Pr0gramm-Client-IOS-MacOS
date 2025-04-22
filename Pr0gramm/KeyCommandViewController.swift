// KeyCommandViewController.swift
import UIKit

class KeyCommandViewController: UIViewController {

    var actionHandler: KeyboardActionHandler?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("KeyCommandViewController: viewDidAppear - Attempting to become first responder...")
        // Wichtig: Aktiv zum First Responder machen
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        let can = true
        // print("KeyCommandViewController: canBecomeFirstResponder called - Returning \(can)")
        return can
    }

    // keyCommands wird nicht mehr benötigt, wir verwenden pressesBegan
    // override var keyCommands: [UIKeyCommand]? { ... }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }

            print("KeyCommandViewController: Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags)")

            // Pfeiltasten ohne Modifier (oder Modifier ignorieren falls nötig)
             // if key.modifierFlags.isEmpty { // Bei Bedarf auskommentieren
                switch key.keyCode {
                case .keyboardLeftArrow:
                    print("KeyCommandViewController: Left arrow detected via pressesBegan.")
                    actionHandler?.selectPreviousAction?()
                    didHandleEvent = true
                case .keyboardRightArrow:
                    print("KeyCommandViewController: Right arrow detected via pressesBegan.")
                    actionHandler?.selectNextAction?()
                    didHandleEvent = true
                default:
                    break // Andere Tasten ignorieren
                }
             // }

            if didHandleEvent { break }
        }

        // Nur super aufrufen, wenn WIR das Event NICHT behandelt haben.
        if !didHandleEvent {
            print("KeyCommandViewController: Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             print("KeyCommandViewController: Arrow key handled by us, NOT calling super.pressesBegan.")
             // Event wird hier gestoppt.
        }
    }
}
