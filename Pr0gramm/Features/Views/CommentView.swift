// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation
import UIKit // Für UIFont
import os // Für Logger

/// Displays a single comment, including user info, score, relative time, and formatted content with tappable links.
/// Supports collapsing/expanding if it has children. Allows favoriting comments and voting via a context menu.
struct CommentView: View {
    let comment: ItemComment
    @Binding var previewLinkTarget: PreviewLinkTarget?
    let hasChildren: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onReply: () -> Void

    @State private var showingUserProfileFor: String? = nil

    @EnvironmentObject var authService: AuthService // Check login status & favorite/vote state
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentView")

    // --- MODIFIED: Handle optional comment.mark ---
    private var markEnum: Mark { Mark(rawValue: comment.mark ?? -1) } // Default to -1 if mark is nil
    private var userMarkColor: Color { markEnum.displayColor }
    // --- END MODIFICATION ---
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
            CommentView.logger.error("Error creating NSDataDetector: \(error.localizedDescription)")
        }
        return attributedString
    }

    private var isFavorited: Bool {
        authService.favoritedCommentIDs.contains(comment.id)
    }

    private var isTogglingFavorite: Bool {
        authService.isFavoritingComment[comment.id] ?? false
    }

    private var currentVote: Int {
        authService.votedCommentStates[comment.id] ?? 0
    }

    private var isVoting: Bool {
        authService.isVotingComment[comment.id] ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // User Info Row
            HStack(spacing: 6) {
                if hasChildren {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                } else {
                    Spacer().frame(width: 12, height: 12)
                }

                Circle().fill(userMarkColor)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 8, height: 8)
                // --- MODIFIED: Handle optional comment.name ---
                Text(comment.name ?? "User") // Default zu "User" wenn name nil ist
                    .font(UIConstants.captionFont.weight(.semibold))
                // --- END MODIFICATION ---
                Text("•").foregroundColor(.secondary)
                Text("\(score)").font(UIConstants.captionFont).foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary)
                Text(relativeTime).font(UIConstants.captionFont).foregroundColor(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if hasChildren {
                    onToggleCollapse()
                }
            }

            if !isCollapsed {
                Text(attributedCommentContent)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, hasChildren ? 20 : 20)
            }
        }
        .padding(.vertical, 6)
        .opacity(isCollapsed ? 0.7 : 1.0)
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                CommentView.logger.info("Pr0gramm link tapped, attempting to preview item ID: \(itemID)")
                self.previewLinkTarget = PreviewLinkTarget(id: itemID)
                return .handled
            } else {
                CommentView.logger.info("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
        .onChange(of: authService.favoritedCommentIDs) { _, _ in }
        .onChange(of: authService.votedCommentStates) { _, _ in }
        .contextMenu {
            // --- MODIFIED: ContextMenu Content extracted to a function to help compiler ---
            contextMenuContent
        }
        .sheet(item: $showingUserProfileFor) { username in
             UserProfileSheetView(username: username)
                 .environmentObject(authService)
                 .environmentObject(AppSettings())
        }
    }

    // --- NEW: Extracted Context Menu Content ---
    @ViewBuilder
    private var contextMenuContent: some View {
        if authService.isLoggedIn {
            Button {
                onReply()
            } label: {
                Label("Antworten", systemImage: "arrowshape.turn.up.left")
            }

            Button {
                Task {
                    CommentView.logger.debug("Context Menu: Favorite button tapped for comment \(comment.id)")
                    await authService.performCommentFavToggle(commentId: comment.id)
                }
            } label: {
                Label(isFavorited ? "Favorit entfernen" : "Favorit", systemImage: isFavorited ? "heart.fill" : "heart")
            }
            .disabled(isTogglingFavorite)

            Divider()

            Button {
                Task {
                    CommentView.logger.debug("Context Menu: Upvote button tapped for comment \(comment.id)")
                    await authService.performCommentVote(commentId: comment.id, voteType: 1)
                }
            } label: {
                Label("Upvote", systemImage: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
            }
            .disabled(isVoting)

            Button {
                Task {
                    CommentView.logger.debug("Context Menu: Downvote button tapped for comment \(comment.id)")
                    await authService.performCommentVote(commentId: comment.id, voteType: -1)
                }
            } label: {
                Label("Downvote", systemImage: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
            }
            .disabled(isVoting)

            Divider()
            // --- MODIFIED: Safely unwrap comment.name for the button action ---
            if let commenterName = comment.name, !commenterName.isEmpty {
                Button {
                    CommentView.logger.info("Context Menu: Show User Profile tapped for \(commenterName)")
                    showingUserProfileFor = commenterName
                } label: {
                    Label("User Profil anzeigen", systemImage: "person.circle")
                }
            }
            // --- END MODIFICATION ---
        }
    }
    // --- END NEW ---


    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if let itemID = Int(component) { return itemID }
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let itemID = Int(value) {
                    return itemID
                }
            }
        }
        CommentView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }
}

extension String: Identifiable {
    public var id: String { self }
}

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
                CommentView.logger.warning("Warning: Could not precisely convert SwiftUI Font to UIFont. Using body style as fallback.")
                return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}


// MARK: - Preview
#Preview("Normal with Reply & Voted") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            let auth = AuthService(appSettings: AppSettings())
            auth.isLoggedIn = true
            auth.favoritedCommentIDs = [1]
            auth.votedCommentStates = [1: 1, 4: -1]

            return List {
                 CommentView(
                     comment: ItemComment(id: 1, parent: 0, content: "Top comment http://pr0gramm.com/new/12345", created: Int(Date().timeIntervalSince1970)-100, up: 15, down: 1, confidence: 0.9, name: "S0ulreaver", mark: 2, itemId: 54321),
                     previewLinkTarget: $target,
                     hasChildren: true,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
                 .listRowInsets(EdgeInsets())

                 CommentView(
                     comment: ItemComment(id: 4, parent: 0, content: "RIP neben msn und icq.", created: Int(Date().timeIntervalSince1970)-150, up: 152, down: 3, confidence: 0.9, name: "S0ulreaver", mark: 2, itemId: 54321),
                     previewLinkTarget: $target,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
                  .listRowInsets(EdgeInsets())

                 CommentView(
                     comment: ItemComment(id: 10, parent: 0, content: "Dieser Kommentar ist weder favorisiert noch gevotet.", created: Int(Date().timeIntervalSince1970)-200, up: 10, down: 2, confidence: 0.9, name: "TestUser", mark: 1, itemId: 54321),
                     previewLinkTarget: $target,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
                  .listRowInsets(EdgeInsets())
                 // --- NEW: Preview for comment with nil name/mark ---
                 CommentView(
                     comment: ItemComment(id: 11, parent: 0, content: "Kommentar mit nil name/mark.", created: Int(Date().timeIntervalSince1970)-250, up: 5, down: 1, confidence: 0.9, name: nil, mark: nil, itemId: 54321),
                     previewLinkTarget: $target,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") }
                 )
                  .listRowInsets(EdgeInsets())
                 // --- END NEW ---
            }
            .listStyle(.plain)
            .environmentObject(auth)
        }
    }
    return PreviewWrapper()
}

#Preview("Collapsed") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
            CommentView(
                comment: ItemComment(id: 2, parent: 0, content: "Collapsed comment...", created: Int(Date().timeIntervalSince1970)-200, up: 5, down: 0, confidence: 0.9, name: "UserB", mark: 1, itemId: 54321),
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

#Preview("No Children") {
    struct PreviewWrapper: View {
        @State var target: PreviewLinkTarget? = nil
        var body: some View {
             let auth = AuthService(appSettings: AppSettings())
             auth.isLoggedIn = true

            return CommentView(
                comment: ItemComment(id: 3, parent: 1, content: "Reply without children...", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "UserC", mark: 7, itemId: 54321),
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
