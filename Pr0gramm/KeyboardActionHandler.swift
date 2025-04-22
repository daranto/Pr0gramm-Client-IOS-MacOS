// KeyboardActionHandler.swift
import Foundation
import Combine // Wird für ObservableObject benötigt

// Einfaches Objekt, um die Aktionen zu halten, die bei Tastendruck ausgeführt werden sollen
class KeyboardActionHandler: ObservableObject {
    // Optional closures, die von der View gesetzt werden
    var selectNextAction: (() -> Void)?
    var selectPreviousAction: (() -> Void)?

    // Wir brauchen keine @Published Properties, da sich die Aktionen nicht ändern,
    // nachdem sie einmal gesetzt wurden.
}
