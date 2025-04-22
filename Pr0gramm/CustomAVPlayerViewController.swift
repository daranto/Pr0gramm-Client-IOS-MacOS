// CustomAVPlayerViewController.swift
import AVKit
import UIKit

class CustomAVPlayerViewController: AVPlayerViewController {

    var actionHandler: KeyboardActionHandler?

    override var keyCommands: [UIKeyCommand]? {
        let standardCommands = super.keyCommands ?? []
        let nonArrowCommands = standardCommands.filter { command in
            if let input = command.input {
                return input != UIKeyCommand.inputLeftArrow &&
                       input != UIKeyCommand.inputRightArrow &&
                       input != UIKeyCommand.inputUpArrow &&
                       input != UIKeyCommand.inputDownArrow
            }
            return true
        }
        return nonArrowCommands
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false

        for press in presses {
            guard let key = press.key else { continue }

            print("CustomAVPlayerViewController: Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags)")

            // --- Entfernt: Die Prüfung auf leere Modifier ---
            // if key.modifierFlags.isEmpty {

                // Switch direkt ausführen
                switch key.keyCode {
                case .keyboardLeftArrow:
                    print("CustomAVPlayerViewController: Left arrow detected, calling previous action.")
                    actionHandler?.selectPreviousAction?()
                    didHandleEvent = true

                case .keyboardRightArrow:
                    print("CustomAVPlayerViewController: Right arrow detected, calling next action.")
                    actionHandler?.selectNextAction?()
                    didHandleEvent = true

                default:
                    break // Andere Tasten ignorieren
                }
            // } // Ende des entfernten if-Blocks

            // Wenn wir eine Pfeiltaste behandelt haben, brauchen wir nicht weiter im Set zu suchen
            if didHandleEvent { break }
        }

        // Rufe super.pressesBegan NUR auf, wenn WIR das Event NICHT behandelt haben.
        if !didHandleEvent {
            print("CustomAVPlayerViewController: Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             print("CustomAVPlayerViewController: Arrow key handled by us, NOT calling super.pressesBegan.")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("CustomAVPlayerViewController: viewDidDisappear, pausing player.")
        self.player?.pause()
    }

    deinit {
         print("CustomAVPlayerViewController deinit")
    }
}
