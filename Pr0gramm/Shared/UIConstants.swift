// Pr0gramm/Pr0gramm/Shared/UIConstants.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation // Für ProcessInfo

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
// --- END OF COMPLETE FILE ---
