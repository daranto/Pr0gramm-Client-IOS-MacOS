// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation
import UIKit // Für UIFont
import os // Für Logger

/// Displays a single comment, including user info, score, relative time, and formatted content with tappable links.
/// Supports collapsing/expanding if it has children. Allows favoriting comments.
struct CommentView: View {
    let comment: ItemComment
    @Binding var previewLinkTarget: PreviewLinkTarget?
    let hasChildren: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onReply: () -> Void

    @EnvironmentObject var authService: AuthService // Check login status & favorite state
    // --- NEW: Logger ---
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentView")
    // --- END NEW ---

    private var markEnum: Mark { Mark(rawValue: comment.mark) }
    private var userMarkColor: Color { markEnum.displayColor }
    private var userMarkName: String { markEnum.displayName }
    private var score: Int { comment.up - comment.down }

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

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

    // --- NEW: Computed property for favorite status ---
    private var isFavorited: Bool {
        authService.favoritedCommentIDs.contains(comment.id)
    }
    // --- END NEW ---

    // --- NEW: Computed property for favoriting in progress ---
    private var isTogglingFavorite: Bool {
        authService.isFavoritingComment[comment.id] ?? false
    }
    // --- END NEW ---

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

                // --- MODIFIED: Add Favorite Button ---
                if authService.isLoggedIn {
                    // Favorite Button
                    Button {
                        Task {
                            Self.logger.debug("Favorite button tapped for comment \(comment.id)")
                            await authService.performCommentFavToggle(commentId: comment.id)
                        }
                    } label: {
                        // --- NEW: Show progress or heart ---
                        if isTogglingFavorite {
                            ProgressView()
                                .frame(width: 16, height: 16) // Match icon size roughly
                                .scaleEffect(0.7) // Make spinner smaller
                        } else {
                            Image(systemName: isFavorited ? "heart.fill" : "heart")
                                .foregroundColor(isFavorited ? .pink : .secondary)
                                .font(.caption) // Consistent size
                        }
                        // --- END NEW ---
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingFavorite) // Disable while processing
                    .padding(.leading, 5)

                    // Reply Button
                    Button(action: onReply) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 5)
                }
                // --- END MODIFICATION ---
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
                // --- MODIFIED: Use NavigationLink value for preview ---
                // For comment previews, we still use the sheet mechanism if needed,
                // but the main navigation now uses NavigationLink value.
                // This part remains for potential future use or direct previews from CommentView.
                // self.previewLinkTarget = PreviewLinkTarget(id: itemID)
                // --- END MODIFICATION ---
                // Handle navigation outside or let the system handle if not specifically previewing
                // Returning .handled here prevents default browser opening for pr0 links
                // We actually WANT the default browser if the link is not handled by our sheet.
                // Let's rethink this - OpenURLAction might not be the best place if we use NavLink value.
                // For now, let's keep it simple: allow system to handle links if not previewing.
                return .systemAction // Or handle specifically if needed elsewhere
            } else {
                print("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
        // --- NEW: Add onChange observer for comment favs ---
        .onChange(of: authService.favoritedCommentIDs) { _, _ in
            // This empty block forces the view to re-evaluate 'isFavorited'
            // when the global set changes.
        }
        // --- END NEW ---
    }

    private func parsePr0grammLink(url: URL) -> Int? { // Unverändert
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents; for component in pathComponents.reversed() { if let itemID = Int(component) { return itemID } }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems { for item in queryItems { if item.name == "id", let value = item.value, let itemID = Int(value) { return itemID } } }
        print("Could not parse item ID from pr0gramm link: \(url)"); return nil
    }
}

// Helper Extension (unverändert)
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


// MARK: - Preview (unverändert, aber profitiert vom Fix in ItemComment init)
#Preview("Normal with Reply") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            let auth = AuthService(appSettings: AppSettings())
            auth.isLoggedIn = true
            auth.favoritedCommentIDs = [1] // Simulate favorited

            return CommentView(
                comment: ItemComment(id: 1, parent: 0, content: "Top comment http://pr0gramm.com/new/12345", created: Int(Date().timeIntervalSince1970)-100, up: 15, down: 1, confidence: 0.9, name: "UserA", mark: 2),
                previewLinkTarget: $target,
                hasChildren: true,
                isCollapsed: false,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") }
            )
            .padding()
            .environmentObject(auth) // Use the configured auth service
        }
    }
    return PreviewWrapper()
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
            .environmentObject(AuthService(appSettings: AppSettings())) // Basic logged out state for this one
        }
    }
    return PreviewWrapper()
}

#Preview("No Children") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
             let auth = AuthService(appSettings: AppSettings())
             auth.isLoggedIn = true // Logged in for reply/fav button

            return CommentView(
                comment: ItemComment(id: 3, parent: 1, content: "Reply without children", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "UserC", mark: 7),
                previewLinkTarget: $target,
                hasChildren: false,
                isCollapsed: false,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") }
            )
            .padding()
            .environmentObject(auth)
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
