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
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentView")

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

    private var isFavorited: Bool {
        authService.favoritedCommentIDs.contains(comment.id)
    }

    private var isTogglingFavorite: Bool {
        authService.isFavoritingComment[comment.id] ?? false
    }

    // --- NEW: Computed properties for comment voting ---
    private var currentVote: Int {
        authService.votedCommentStates[comment.id] ?? 0 // 0 = no vote, 1 = up, -1 = down
    }

    private var isVoting: Bool {
        authService.isVotingComment[comment.id] ?? false
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

                // Action Buttons (only if logged in)
                if authService.isLoggedIn {
                    // Favorite Button
                    Button {
                        Task {
                            Self.logger.debug("Favorite button tapped for comment \(comment.id)")
                            await authService.performCommentFavToggle(commentId: comment.id)
                        }
                    } label: {
                        if isTogglingFavorite {
                            ProgressView()
                                .frame(width: 16, height: 16)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: isFavorited ? "heart.fill" : "heart")
                                .foregroundColor(isFavorited ? .pink : .secondary)
                                .font(.body)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingFavorite)
                    .padding(.leading, 5)

                    // Reply Button
                    Button(action: onReply) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 5)
                }
                // --- END Action Buttons ---
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasChildren { onToggleCollapse() } }


            if !isCollapsed {
                HStack(alignment: .top, spacing: 8) {
                    if authService.isLoggedIn {
                        VStack(spacing: 6) {
                            Button {
                                 Task {
                                      Self.logger.debug("Upvote button tapped for comment \(comment.id)")
                                      await authService.performCommentVote(commentId: comment.id, voteType: 1)
                                 }
                            } label: {
                                Image(systemName: currentVote == 1 ? "arrow.up.circle.fill" : "arrow.up.circle")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(currentVote == 1 ? Color.white : Color.secondary,
                                                     currentVote == 1 ? Color.green : Color.secondary)
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .disabled(isVoting)

                            Button {
                                 Task {
                                      Self.logger.debug("Downvote button tapped for comment \(comment.id)")
                                      await authService.performCommentVote(commentId: comment.id, voteType: -1)
                                 }
                            } label: {
                                Image(systemName: currentVote == -1 ? "arrow.down.circle.fill" : "arrow.down.circle")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(currentVote == -1 ? Color.white : Color.secondary,
                                                     currentVote == -1 ? Color.red : Color.secondary)
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .disabled(isVoting)
                        }
                    }

                    Text(attributedCommentContent)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, hasChildren ? 18 : 20)
            }
        }
        .padding(.vertical, 6)
        .opacity(isCollapsed ? 0.7 : 1.0)
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                print("Pr0gramm link tapped, attempting to preview item ID: \(itemID)")
                // self.previewLinkTarget = PreviewLinkTarget(id: itemID) // Keep sheet mechanism for comment links
                return .handled // Prevent default browser opening
            } else {
                print("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
        .onChange(of: authService.favoritedCommentIDs) { _, _ in /* Force update */ }
        // --- NEW: Add onChange observer for comment votes ---
        .onChange(of: authService.votedCommentStates) { _, _ in
             // This empty block forces the view to re-evaluate 'currentVote'
             // when the global dictionary changes.
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


// MARK: - Preview (updated to include vote states)
#Preview("Normal with Reply & Voted") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            let auth = AuthService(appSettings: AppSettings())
            auth.isLoggedIn = true
            auth.favoritedCommentIDs = [1] // Simulate favorited
            // --- NEW: Simulate voted state ---
            auth.votedCommentStates = [1: 1, 4: -1] // Comment 1 upvoted, comment 4 downvoted
            // --- END NEW ---

            return VStack(alignment: .leading) {
                 CommentView(
                     comment: ItemComment(id: 1, parent: 0, content: "Top comment http://pr0gramm.com/new/12345", created: Int(Date().timeIntervalSince1970)-100, up: 15, down: 1, confidence: 0.9, name: "UserA", mark: 2),
                     previewLinkTarget: $target,
                     hasChildren: true,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
                 Divider()
                 CommentView(
                     comment: ItemComment(id: 4, parent: 0, content: "Another comment", created: Int(Date().timeIntervalSince1970)-150, up: 2, down: 5, confidence: 0.9, name: "UserDown", mark: 1),
                     previewLinkTarget: $target,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
            }
            .padding()
            .environmentObject(auth) // Use the configured auth service
        }
    }
    return PreviewWrapper()
}

#Preview("Collapsed") { // Unchanged
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
    return PreviewWrapper()
}

#Preview("No Children") { // Unchanged
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
             let auth = AuthService(appSettings: AppSettings())
             auth.isLoggedIn = true

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
