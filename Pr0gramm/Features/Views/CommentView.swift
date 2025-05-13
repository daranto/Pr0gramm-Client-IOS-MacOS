// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation
import UIKit // Für UIFont
import os // Für Logger

struct CommentView: View {
    let comment: ItemComment
    let uploaderName: String
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var userProfileSheetTarget: UserProfileSheetTarget?
    let hasChildren: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onReply: () -> Void
    let targetCommentID: Int?
    let onHighlightCompleted: (Int) -> Void

    @EnvironmentObject var authService: AuthService
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentView")

    @State private var isHighlighted: Bool = false

    private var markEnum: Mark { Mark(rawValue: comment.mark ?? -1) }
    private var userMarkColor: Color { markEnum.displayColor }
    private var score: Int { comment.up - comment.down }
    private var isOriginalPoster: Bool { comment.name?.lowercased() == uploaderName.lowercased() }

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
                Text(comment.name ?? "User")
                    .font(UIConstants.captionFont.weight(.semibold))
                if isOriginalPoster {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
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
        .background(isHighlighted ? Color.accentColor.opacity(0.3) : Color.clear)
        // --- MODIFIED: Animationsdauer für den Hintergrund ---
        .animation(.easeInOut(duration: 0.35), value: isHighlighted) // Dauer leicht erhöht
        // --- END MODIFICATION ---
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
        .contextMenu { contextMenuContent }
        .onChange(of: targetCommentID, initial: true) { oldTargetID, newTargetID in
            CommentView.logger.trace("Comment \(comment.id): onChange(targetCommentID) fired. Old: \(oldTargetID ?? -99), New: \(newTargetID ?? -99), isHighlighted: \(isHighlighted)")
            if newTargetID == comment.id {
                CommentView.logger.debug("Comment \(comment.id): targetCommentID (\(newTargetID ?? -1)) matches. Triggering highlight.")
                triggerHighlight()
            }
        }
    }

    private func triggerHighlight() {
        Task { @MainActor in
            guard !isHighlighted else {
                CommentView.logger.trace("Highlight for comment \(comment.id) skipped, already highlighted or in process.")
                return
            }
            
            // --- MODIFIED: Explizite Animation für das Setzen von isHighlighted ---
            withAnimation(.easeInOut(duration: 0.35)) { // Dauer passend zur .animation oben
                isHighlighted = true
            }
            // --- END MODIFICATION ---
            CommentView.logger.info("Highlight triggered for comment ID: \(comment.id)")
            
            Task {
                // --- MODIFIED: Dauer der Hervorhebung ---
                try? await Task.sleep(for: .milliseconds(700)) // z.B. 0.7 Sekunden sichtbar
                // --- END MODIFICATION ---
                await MainActor.run {
                    // --- MODIFIED: Explizite Animation für das Zurücksetzen ---
                    withAnimation(.easeInOut(duration: 0.4)) { // Dauer leicht erhöht für sanfteres Ausblenden
                        isHighlighted = false
                    }
                    // --- END MODIFICATION ---
                    CommentView.logger.info("Highlight removed for comment ID: \(comment.id)")
                    onHighlightCompleted(comment.id)
                }
            }
        }
    }

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
            if let commenterName = comment.name, !commenterName.isEmpty {
                Button {
                    CommentView.logger.info("Context Menu: Show User Profile tapped for \(commenterName)")
                    self.userProfileSheetTarget = UserProfileSheetTarget(username: commenterName)
                } label: {
                    Label("User Profil anzeigen", systemImage: "person.circle")
                }
            }
        }
    }

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


// MARK: - Preview
#Preview("Normal with Reply & Voted") {
    struct PreviewWrapperNormal: View {
        @State var previewLinkTarget_Normal: PreviewLinkTarget? = nil
        @State var userProfileSheetTarget_Normal: UserProfileSheetTarget? = nil
        var body: some View {
            let auth = AuthService(appSettings: AppSettings())
            auth.isLoggedIn = true
            auth.favoritedCommentIDs = [1]
            auth.votedCommentStates = [1: 1, 4: -1]
            let uploader = "S0ulreaver"

            return List {
                 CommentView(
                     comment: ItemComment(id: 1, parent: 0, content: "Top comment http://pr0gramm.com/new/12345", created: Int(Date().timeIntervalSince1970)-100, up: 15, down: 1, confidence: 0.9, name: "S0ulreaver", mark: 2, itemId: 54321),
                     uploaderName: uploader,
                     previewLinkTarget: $previewLinkTarget_Normal,
                     userProfileSheetTarget: $userProfileSheetTarget_Normal,
                     hasChildren: true,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") },
                     targetCommentID: 1,
                     onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
                 )
                 .listRowInsets(EdgeInsets())

                 CommentView(
                     comment: ItemComment(id: 4, parent: 0, content: "RIP neben msn und icq.", created: Int(Date().timeIntervalSince1970)-150, up: 152, down: 3, confidence: 0.9, name: "S0ulreaver", mark: 2, itemId: 54321),
                     uploaderName: uploader,
                     previewLinkTarget: $previewLinkTarget_Normal,
                     userProfileSheetTarget: $userProfileSheetTarget_Normal,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") },
                     targetCommentID: nil,
                     onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
                 )
                  .listRowInsets(EdgeInsets())

                 CommentView(
                     comment: ItemComment(id: 10, parent: 0, content: "Dieser Kommentar ist weder favorisiert noch gevotet.", created: Int(Date().timeIntervalSince1970)-200, up: 10, down: 2, confidence: 0.9, name: "TestUser", mark: 1, itemId: 54321),
                     uploaderName: uploader,
                     previewLinkTarget: $previewLinkTarget_Normal,
                     userProfileSheetTarget: $userProfileSheetTarget_Normal,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") },
                     targetCommentID: nil,
                     onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
                 )
                  .listRowInsets(EdgeInsets())
                 CommentView(
                     comment: ItemComment(id: 11, parent: 0, content: "Kommentar mit nil name/mark.", created: Int(Date().timeIntervalSince1970)-250, up: 5, down: 1, confidence: 0.9, name: nil, mark: nil, itemId: 54321),
                     uploaderName: uploader,
                     previewLinkTarget: $previewLinkTarget_Normal,
                     userProfileSheetTarget: $userProfileSheetTarget_Normal,
                     hasChildren: false,
                     isCollapsed: false,
                     onToggleCollapse: { print("Toggle tapped") },
                     onReply: { print("Reply Tapped") },
                     targetCommentID: nil,
                     onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
                 )
                  .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .environmentObject(auth)
             .sheet(item: $userProfileSheetTarget_Normal) { targetUsername in
                 Text("Preview: User Profile Sheet for \(targetUsername.username)")
             }
        }
    }
    return PreviewWrapperNormal()
}

#Preview("Collapsed") {
    struct PreviewWrapperCollapsed: View {
        @State var previewLinkTarget_Collapsed: PreviewLinkTarget? = nil
        @State var userProfileSheetTarget_Collapsed: UserProfileSheetTarget? = nil
        var body: some View {
            CommentView(
                comment: ItemComment(id: 2, parent: 0, content: "Collapsed comment...", created: Int(Date().timeIntervalSince1970)-200, up: 5, down: 0, confidence: 0.9, name: "UserB", mark: 1, itemId: 54321),
                uploaderName: "SomeOtherUser",
                previewLinkTarget: $previewLinkTarget_Collapsed,
                userProfileSheetTarget: $userProfileSheetTarget_Collapsed,
                hasChildren: true,
                isCollapsed: true,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") },
                targetCommentID: nil,
                onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
            )
            .padding()
            .environmentObject(AuthService(appSettings: AppSettings()))
        }
    }
    return PreviewWrapperCollapsed()
}

#Preview("No Children") {
    struct PreviewWrapperNoChildren: View {
        @State var previewLinkTarget_NoChildren: PreviewLinkTarget? = nil
        @State var userProfileSheetTarget_NoChildren: UserProfileSheetTarget? = nil
        var body: some View {
             let auth = AuthService(appSettings: AppSettings())
             auth.isLoggedIn = true

            return CommentView(
                comment: ItemComment(id: 3, parent: 1, content: "Reply without children...", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "UserC", mark: 7, itemId: 54321),
                uploaderName: "SomeOtherUser",
                previewLinkTarget: $previewLinkTarget_NoChildren,
                userProfileSheetTarget: $userProfileSheetTarget_NoChildren,
                hasChildren: false,
                isCollapsed: false,
                onToggleCollapse: { print("Toggle tapped") },
                onReply: { print("Reply Tapped") },
                targetCommentID: nil,
                onHighlightCompleted: { id in print("Preview: Highlight completed for \(id)") }
            )
            .padding()
            .environmentObject(auth)
        }
    }
    return PreviewWrapperNoChildren()
}
// --- END OF COMPLETE FILE ---
