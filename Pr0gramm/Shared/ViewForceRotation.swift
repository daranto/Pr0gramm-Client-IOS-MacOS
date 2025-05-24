// Pr0gramm/Pr0gramm/Shared/ViewForceRotation.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import UIKit // Für UIInterfaceOrientationMask

extension View {
    @ViewBuilder
    func forceRotation(orientation: UIInterfaceOrientationMask) -> some View {
        // Wir speichern die aktuelle Orientierung der App, bevor wir sie ändern.
        // Wichtig: Dies ist die *gewünschte* Orientierung der App, nicht unbedingt die des Geräts.
        let currentAppOrientationLock = AppDelegate.orientationLock
        
        self.onAppear {
            // Nur ändern, wenn die neue Orientierung anders ist als die aktuell gesperrte.
            if AppDelegate.orientationLock != orientation {
                AppDelegate.orientationLock = orientation
            }
        }
        .onDisappear {
            // Beim Verschwinden der View setzen wir die Orientierungssperre auf den Wert zurück,
            // den sie *vor dem Erscheinen dieser View* hatte.
            // Dies verhindert, dass das Verlassen einer tief verschachtelten View, die auch .forceRotation nutzt,
            // die Orientierung einer übergeordneten View überschreibt.
            // Wenn die aktuelle Sperre immer noch die von dieser View gesetzte ist, dann zurücksetzen.
            // Andernfalls hat eine andere View inzwischen die Kontrolle übernommen.
            if AppDelegate.orientationLock == orientation {
                 AppDelegate.orientationLock = currentAppOrientationLock
            }
        }
    }
}
// --- END OF COMPLETE FILE ---
