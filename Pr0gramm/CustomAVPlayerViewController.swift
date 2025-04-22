// CustomAVPlayerViewController.swift
import AVKit
import UIKit

class CustomAVPlayerViewController: AVPlayerViewController {

    // --- Benötigt: Referenz zum Action Handler ---
    var actionHandler: KeyboardActionHandler?

    // keyCommands override bleibt (entfernt Standard-Aktionen)
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

    // --- pressesBegan behandelt Pfeiltasten direkt über Handler ---
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false // Prüfen, ob WIR das Event behandelt haben

        for press in presses {
            guard let key = press.key else { continue }

            print("CustomAVPlayerViewController: Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags)") // Debugging

            // Prüfe auf Pfeiltasten ohne Modifier (oder ignoriere Modifier, falls nötig)
             // if key.modifierFlags.isEmpty { // Diese Prüfung bei Bedarf wieder entfernen
                switch key.keyCode {
                case .keyboardLeftArrow:
                    print("CustomAVPlayerViewController: Left arrow detected, calling previous action.")
                    // --- Aktion direkt im Handler aufrufen ---
                    actionHandler?.selectPreviousAction?()
                    didHandleEvent = true // Wir haben es behandelt

                case .keyboardRightArrow:
                    print("CustomAVPlayerViewController: Right arrow detected, calling next action.")
                    // --- Aktion direkt im Handler aufrufen ---
                    actionHandler?.selectNextAction?()
                    didHandleEvent = true // Wir haben es behandelt

                default:
                    // Andere Tasten werden ignoriert (von unserer Logik)
                    break
                }
            // } // Ende if modifierFlags.isEmpty

            // Wenn wir eine Pfeiltaste behandelt haben, brauchen wir nicht weiter im Set zu suchen
             if didHandleEvent { break }
        }

        // Rufe super.pressesBegan NUR auf, wenn WIR das Event NICHT behandelt haben.
        if !didHandleEvent {
            print("CustomAVPlayerViewController: Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             print("CustomAVPlayerViewController: Arrow key handled by us, NOT calling super.pressesBegan.")
             // Event wird hier gestoppt.
        }
    }
     // --- Ende pressesBegan override ---

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("CustomAVPlayerViewController: viewDidDisappear, pausing player.")
        self.player?.pause()
    }

    deinit {
         print("CustomAVPlayerViewController deinit")
    }
}
