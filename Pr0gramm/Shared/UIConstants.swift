// Pr0gramm/Pr0gramm/Shared/UIConstants.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation // Für ProcessInfo
import UIKit // Für UIFont

/// Defines adaptive UI constants, especially font sizes, for different platforms.
struct UIConstants {

    /// Checks if the app is running as an iOS app on macOS.
    static let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
    
    static let isCurrentDeviceiPhone: Bool = {
        #if targetEnvironment(macCatalyst)
        return false // Mac (Designed for iPad) ist nicht iPhone
        #else
        return UIDevice.current.userInterfaceIdiom == .phone
        #endif
    }()

    // Neuer Helper, um iPad und Mac zu erkennen
    static let isPadOrMac: Bool = {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad || isRunningOnMac
        #endif
    }()

    // --- Adaptive Font Sizes ---
    static var largeTitleFont: Font { isRunningOnMac ? .largeTitle : .largeTitle }
    static var titleFont: Font { isRunningOnMac ? .title : .title3 }
    static var headlineFont: Font { isRunningOnMac ? .title2 : .headline }
    static var bodyFont: Font { isRunningOnMac ? .title3 : .callout }
    static var subheadlineFont: Font { isRunningOnMac ? .headline : .subheadline }
    static var captionFont: Font { isRunningOnMac ? .body : .caption }
    static var caption2Font: Font { isRunningOnMac ? .callout : .caption2 }
    static var footnoteFont: Font { isRunningOnMac ? .headline : .footnote }


    static var gridItemMinWidth: CGFloat { isRunningOnMac ? 250 : 100 }

}

extension UIFont {
    static func uiFont(from font: Font) -> UIFont {
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
                return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}
// --- END OF COMPLETE FILE ---
