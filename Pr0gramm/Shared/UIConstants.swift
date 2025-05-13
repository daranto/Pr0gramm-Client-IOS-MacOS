// Pr0gramm/Pr0gramm/Shared/UIConstants.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation // Für ProcessInfo
import UIKit // Für UIFont

/// Defines adaptive UI constants, especially font sizes, for different platforms.
struct UIConstants {

    /// Checks if the app is running as an iOS app on macOS.
    static let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    // --- Adaptive Font Sizes ---
    // Deutlich größere Fonts für den Mac gewählt

    /// Font for primary titles or large emphasis (e.g., Benis score).
    static var largeTitleFont: Font { isRunningOnMac ? .largeTitle : .largeTitle } // Bleibt largeTitle

    /// Font for standard view titles or important labels.
    static var titleFont: Font { isRunningOnMac ? .title : .title3 } // Mac: title, iOS: title3

    /// Font for section headers or prominent labels.
    static var headlineFont: Font { isRunningOnMac ? .title2 : .headline } // Mac: title2, iOS: headline

    /// Font for standard body text or list item labels.
    static var bodyFont: Font { isRunningOnMac ? .title3 : .callout } // Mac: title3, iOS: callout

    /// Font for secondary labels or less important text.
    static var subheadlineFont: Font { isRunningOnMac ? .headline : .subheadline } // Mac: headline, iOS: subheadline

    /// Font for captions, tags, timestamps, etc.
    static var captionFont: Font { isRunningOnMac ? .body : .caption } // Mac: body, iOS: caption

    /// Font for smaller captions or tab bar labels.
    static var caption2Font: Font { isRunningOnMac ? .callout : .caption2 } // Mac: callout, iOS: caption2

    /// Font for footnotes or detailed text (e.g., comment content).
    static var footnoteFont: Font { isRunningOnMac ? .headline : .footnote } // Mac: headline, iOS: footnote

    // --- Adaptive Padding/Spacing (Beispiele) ---
    // static var defaultPadding: CGFloat { isRunningOnMac ? 16 : 12 }
    // static var defaultSpacing: CGFloat { isRunningOnMac ? 10 : 8 }

    // --- Grid Column Width ---
    static var gridItemMinWidth: CGFloat { isRunningOnMac ? 250 : 100 }

}

// --- NEW: Moved UIFont extension here and made it internal (default) ---
extension UIFont {
    static func uiFont(from font: Font) -> UIFont {
        // Logger kann hier nicht direkt verwendet werden, da UIConstants keine Member hat.
        // Aber die Logik ist einfach genug.
        switch font {
            case .largeTitle: return UIFont.preferredFont(forTextStyle: .largeTitle)
            case .title: return UIFont.preferredFont(forTextStyle: .title1)
            case .title2: return UIFont.preferredFont(forTextStyle: .title2)
            case .title3: return UIFont.preferredFont(forTextStyle: .title3)
            case .headline: return UIFont.preferredFont(forTextStyle: .headline)
            case .subheadline: return UIFont.preferredFont(forTextStyle: .subheadline)
            case .body: return UIFont.preferredFont(forTextStyle: .body)
            case .callout: return UIFont.preferredFont(forTextStyle: .callout)
            case .footnote: return UIFont.preferredFont(forTextStyle: .footnote)
            case .caption: return UIFont.preferredFont(forTextStyle: .caption1)
            case .caption2: return UIFont.preferredFont(forTextStyle: .caption2)
            default:
                // print("Warning: Could not precisely convert SwiftUI Font to UIFont. Using body style as fallback.")
                // In einer Utility-Klasse könnte man hier ggf. loggen, in einer Struct-Extension ist print() eine Option.
                return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}
// --- END NEW ---
// --- END OF COMPLETE FILE ---
