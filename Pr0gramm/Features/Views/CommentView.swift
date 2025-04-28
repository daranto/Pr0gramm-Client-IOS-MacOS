// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation
import UIKit // <-- Import UIKit für UIFont

/// Displays a single comment, including user info, score, relative time, and formatted content with tappable links.
struct CommentView: View {
    let comment: ItemComment
    /// Binding to trigger the preview sheet when a pr0gramm link is tapped.
    @Binding var previewLinkTarget: PreviewLinkTarget?

    /// The user's rank/mark as an enum case.
    private var markEnum: Mark { Mark(rawValue: comment.mark) }
    /// The color associated with the user's rank.
    private var userMarkColor: Color { markEnum.displayColor }
    /// The display name of the user's rank.
    private var userMarkName: String { markEnum.displayName }
    /// The calculated score (upvotes - downvotes).
    private var score: Int { comment.up - comment.down }

    /// A human-readable, relative timestamp (e.g., "5 min ago").
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated // Use short style like "min", "hr"
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// The comment content formatted with tappable links.
    private var attributedCommentContent: AttributedString {
        var attributedString = AttributedString(comment.content)

        // --- MODIFIED: Convert SwiftUI Font to UIFont ---
        let baseUIFont = UIFont.uiFont(from: UIConstants.footnoteFont) // Use helper
        attributedString.font = baseUIFont // Set base font using UIFont
        // --- END MODIFICATION ---

        do {
            // Use NSDataDetector to find URLs within the comment text
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: comment.content, options: [], range: NSRange(location: 0, length: comment.content.utf16.count))

            // Apply link styling and URL attribute to detected matches
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url // Make it tappable
                attributedString[range].foregroundColor = .accentColor // Style links
                // --- MODIFIED: Apply UIFont to links too ---
                attributedString[range].font = baseUIFont // Ensure link font matches base font
                // --- END MODIFICATION ---
            }
        } catch {
            // Log error if detector fails (should be rare)
            print("Error creating NSDataDetector: \(error)")
        }
        return attributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: User info, score, time
            HStack(spacing: 6) {
                Circle() // User mark indicator
                    .fill(userMarkColor)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5)) // Subtle border
                    .frame(width: 8, height: 8)
                Text(comment.name)
                    .font(UIConstants.captionFont.weight(.semibold)) // Use adaptive bold caption
                Text("•").foregroundColor(.secondary) // Separator
                // Display score with color coding
                Text("\(score)")
                    .font(UIConstants.captionFont) // Use adaptive caption
                    .foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary) // Separator
                Text(relativeTime)
                     .font(UIConstants.captionFont) // Use adaptive caption
                    .foregroundColor(.secondary)
                Spacer() // Push content to the left
            }
            // Comment Content: Display the attributed string
            // Font modifier removed, as it's set in attributedCommentContent
            Text(attributedCommentContent)
                .foregroundColor(.primary)
                .lineLimit(nil) // Allow multiple lines
                .fixedSize(horizontal: false, vertical: true) // Ensure vertical expansion
        }
        .padding(.vertical, 6) // Vertical padding around the comment
        // Intercept link taps using the .environment modifier
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                print("Pr0gramm link tapped, attempting to preview item ID: \(itemID)")
                self.previewLinkTarget = PreviewLinkTarget(id: itemID)
                return .handled
            } else {
                print("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }

    /// Attempts to parse an item ID from a pr0gramm.com URL.
    private func parsePr0grammLink(url: URL) -> Int? { /* ... unverändert ... */
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents; for component in pathComponents.reversed() { if let itemID = Int(component) { return itemID } }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems { for item in queryItems { if item.name == "id", let value = item.value, let itemID = Int(value) { return itemID } } }
        print("Could not parse item ID from pr0gramm link: \(url)"); return nil
    }
}

// --- NEU: Helper Extension to convert Font to UIFont ---
// (Kopiert von DetailViewContent, falls nicht global verfügbar)
fileprivate extension UIFont {
    /// Attempts to convert a SwiftUI `Font` to a `UIFont`.
    /// This is a basic implementation and might not cover all custom fonts.
    static func uiFont(from font: Font) -> UIFont {
        // Based on the Font type, determine the corresponding UIFont text style
        // This requires mapping SwiftUI Font types to UIFont.TextStyle
        // Note: This mapping might not be perfect for all cases.
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
                // Fallback for system fonts with specific sizes or custom fonts
                // This part is tricky and might require more complex logic
                // or potentially using private APIs (which is not recommended).
                // For standard system sizes, you might try a default:
                print("Warning: Could not precisely convert SwiftUI Font to UIFont. Using body style as fallback.")
                return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}
// --- ENDE NEU ---


// MARK: - Preview (unverändert)
#Preview { /* ... unveränderter Code ... */ }
// --- END OF COMPLETE FILE ---
