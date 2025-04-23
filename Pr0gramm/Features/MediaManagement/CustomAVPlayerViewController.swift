// CustomAVPlayerViewController.swift
import AVKit
import UIKit
import os

// Konform zum Delegate-Protokoll machen
class CustomAVPlayerViewController: AVPlayerViewController, AVPlayerViewControllerDelegate {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CustomAVPlayerVC")
    var actionHandler: KeyboardActionHandler?

    // Callbacks für Fullscreen State
    var willBeginFullScreen: (() -> Void)?
    var willEndFullScreen: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self // Delegate setzen
        Self.logger.debug("viewDidLoad: Delegate set.")
    }

    override var keyCommands: [UIKeyCommand]? {
        // ... (keyCommands bleibt gleich) ...
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
       // ... (pressesBegan bleibt gleich) ...
       var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }
            Self.logger.debug("Key Pressed - HIDUsage: \(key.keyCode.rawValue), Modifiers: \(key.modifierFlags.rawValue)")
            switch key.keyCode {
            case .keyboardLeftArrow:
                Self.logger.debug("Left arrow detected, calling previous action.")
                actionHandler?.selectPreviousAction?()
                didHandleEvent = true
            case .keyboardRightArrow:
                Self.logger.debug("Right arrow detected, calling next action.")
                actionHandler?.selectNextAction?()
                didHandleEvent = true
            default:
                break
            }
            if didHandleEvent { break }
        }
        if !didHandleEvent {
            Self.logger.debug("Event not handled by us, calling super.pressesBegan.")
            super.pressesBegan(presses, with: event)
        } else {
             Self.logger.debug("Arrow key handled by us, NOT calling super.pressesBegan.")
        }
    }

    // viewWillDisappear/viewWillAppear haben keine spezielle Logik
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.logger.debug("viewWillDisappear called.")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Self.logger.debug("viewWillAppear called.")
    }

    // MARK: - AVPlayerViewControllerDelegate Methods

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        Self.logger.debug("Delegate: willBeginFullScreenPresentation - Calling Callback")
        willBeginFullScreen?()
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        Self.logger.debug("Delegate: willEndFullScreenPresentation - Calling Callback after animation")

        // --- KORRIGIERT: Explizite Syntax ---
        coordinator.animate(
            alongsideTransition: nil, // Keine Animationen parallel nötig
            completion: { (context: UIViewControllerTransitionCoordinatorContext) in // Parameter explizit benannt (kann auch _ sein)
                self.willEndFullScreen?() // Callback im Completion-Block
            }
        )
        // --- Ende Korrektur ---
    }

    deinit {
         Self.logger.debug("deinit")
    }
}
