// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation
import UIKit // Für UIFont

/// Displays a single comment, including user info, score, relative time, and formatted content with tappable links.
/// Supports collapsing/expanding if it has children.
struct CommentView: View {
    let comment: ItemComment
    /// Binding to trigger the preview sheet when a pr0gramm link is tapped.
    @Binding var previewLinkTarget: PreviewLinkTarget?
    /// Indicates if this comment has replies.
    let hasChildren: Bool
    /// Indicates if this comment is currently collapsed.
    let isCollapsed: Bool
    /// Action to perform when the collapse toggle is tapped.
    let onToggleCollapse: () -> Void
    /// Action to perform when reply button is tapped
    let onReply: () -> Void

    @EnvironmentObject var authService: AuthService // Check login status

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
        let baseUIFont = UIFont.uiFont(from: UIConstants.footnoteFont)
        attributedString.font = baseUIFont

        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: comment.content, options: [], range: NSRange(location: 0, length: comment.content.utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url
                attributedString[range].foregroundColor = .accentColor
                attributedString[range].font = baseUIFont
            }
        } catch {
            print("Error creating NSDataDetector: \(error)")
        }
        return attributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Collapse/Expand Chevron
                if hasChildren {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                } else {
                    Spacer().frame(width: 12, height: 12)
                }

                // User Info Row
                Circle().fill(userMarkColor).overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5)).frame(width: 8, height: 8)
                Text(comment.name).font(UIConstants.captionFont.weight(.semibold))
                Text("•").foregroundColor(.secondary)
                Text("\(score)").font(UIConstants.captionFont).foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary)
                Text(relativeTime).font(UIConstants.captionFont).foregroundColor(.secondary)
                Spacer() // Push info to left

                // Reply Button
                if authService.isLoggedIn {
                    Button(action: onReply) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasChildren { onToggleCollapse() } }


            if !isCollapsed {
                Text(attributedCommentContent)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, hasChildren ? 18 : 20)
            }
        }
        .padding(.vertical, 6)
        .opacity(isCollapsed ? 0.7 : 1.0)
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

    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents; for component in pathComponents.reversed() { if let itemID = Int(component) { return itemID } }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems { for item in queryItems { if item.name == "id", let value = item.value, let itemID = Int(value) { return itemID } } }
        print("Could not parse item ID from pr0gramm link: \(url)"); return nil
    }
}

// Helper Extension
fileprivate extension UIFont {
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
                print("Warning: Could not precisely convert SwiftUI Font to UIFont. Using body style as fallback.")
                return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}


// MARK: - Preview
#Preview("Normal with Reply") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            CommentView(
                comment: ItemComment(id: 1, parent: 0, content: "Top comment http://pr0gramm.com/new/12345", created: Int(Date().timeIntervalSince1970)-100, up: 15, down: 1, confidence: 0.9, name: "UserA", mark: 2),
                previewLinkTarget: $target,
                hasChildren: true,
                isCollapsed: false,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") }
            )
            .padding()
            .environmentObject(AuthService(appSettings: AppSettings()))
        }
    }
    let auth = AuthService(appSettings: AppSettings())
    auth.isLoggedIn = true
    return PreviewWrapper().environmentObject(auth)
}

#Preview("Collapsed") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            CommentView(
                comment: ItemComment(id: 2, parent: 0, content: "Collapsed comment", created: Int(Date().timeIntervalSince1970)-200, up: 5, down: 0, confidence: 0.9, name: "UserB", mark: 1),
                previewLinkTarget: $target,
                hasChildren: true,
                isCollapsed: true,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") }
            )
            .padding()
            .environmentObject(AuthService(appSettings: AppSettings()))
        }
    }
    let auth = AuthService(appSettings: AppSettings())
    auth.isLoggedIn = true
    return PreviewWrapper().environmentObject(auth)
}

#Preview("No Children") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            CommentView(
                comment: ItemComment(id: 3, parent: 1, content: "Reply without children", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "UserC", mark: 7),
                previewLinkTarget: $target,
                hasChildren: false,
                isCollapsed: false,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") }
            )
            .padding()
            .environmentObject(AuthService(appSettings: AppSettings()))
        }
    }
    let auth = AuthService(appSettings: AppSettings())
    auth.isLoggedIn = true
    return PreviewWrapper().environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
