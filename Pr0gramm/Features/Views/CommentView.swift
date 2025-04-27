import SwiftUI
import Foundation

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
        do {
            // Use NSDataDetector to find URLs within the comment text
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: comment.content, options: [], range: NSRange(location: 0, length: comment.content.utf16.count))

            // Apply link styling and URL attribute to detected matches
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url // Make it tappable
                attributedString[range].foregroundColor = .accentColor // Style links
                // Add other attributes like underline if desired:
                // attributedString[range].underlineStyle = .single
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
                Text(comment.name).font(.caption.weight(.semibold))
                Text("•").foregroundColor(.secondary) // Separator
                // Display score with color coding
                Text("\(score)")
                    .font(.caption)
                    .foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary) // Separator
                Text(relativeTime).font(.caption).foregroundColor(.secondary)
                Spacer() // Push content to the left
            }
            // Comment Content: Display the attributed string
            Text(attributedCommentContent)
                .font(.footnote) // Standard comment text size
                .foregroundColor(.primary)
                .lineLimit(nil) // Allow multiple lines
                .fixedSize(horizontal: false, vertical: true) // Ensure vertical expansion
        }
        .padding(.vertical, 6) // Vertical padding around the comment
        // Intercept link taps using the .environment modifier
        .environment(\.openURL, OpenURLAction { url in
            // Check if the tapped URL is a pr0gramm link
            if let itemID = parsePr0grammLink(url: url) {
                print("Pr0gramm link tapped, attempting to preview item ID: \(itemID)")
                // Set the state variable to trigger the preview sheet
                self.previewLinkTarget = PreviewLinkTarget(id: itemID)
                return .handled // Indicate we handled the URL action
            } else {
                // For non-pr0gramm links, use the default system behavior (open in browser)
                print("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }

    /// Attempts to parse an item ID from a pr0gramm.com URL.
    /// Handles various URL structures (e.g., /new/123, /top/123?id=456).
    /// - Parameter url: The URL to parse.
    /// - Returns: The extracted item ID as an `Int`, or `nil` if parsing fails.
    private func parsePr0grammLink(url: URL) -> Int? {
        // Check if the host matches pr0gramm.com
        guard let host = url.host?.lowercased(),
              (host == "pr0gramm.com" || host == "www.pr0gramm.com") else {
            return nil // Not a pr0gramm link
        }

        // Try extracting ID from the last path component
        let pathComponents = url.pathComponents
        // Iterate backwards through path components (/top/, /5516804)
        for component in pathComponents.reversed() {
            if let itemID = Int(component) {
                return itemID // Found a numeric ID in the path
            }
        }

        // If not in path, check query parameters (e.g., ?id=...)
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let itemID = Int(value) {
                    return itemID // Found an 'id' query parameter
                }
            }
        }

        // If no ID found in path or query
        print("Could not parse item ID from pr0gramm link: \(url)")
        return nil
    }
}

// MARK: - Preview

#Preview {
    // Use @State for the binding in previews
    @State var previewTarget: PreviewLinkTarget? = nil
    let sampleComment = ItemComment(id: 1, parent: 0, content: "Das ist ein Beispielkommentar mit einem Link: https://pr0gramm.com/top/6595750 und noch mehr Text sowie google.de", created: Int(Date().timeIntervalSince1970) - 120, up: 15, down: 2, confidence: 0.9, name: "TestUser", mark: 1)

    return CommentView(comment: sampleComment, previewLinkTarget: $previewTarget)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}
