// Pr0gramm/Pr0gramm/Shared/CommentsSection.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

struct CommentsSection: View {
    let flatComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int
    let status: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?
    // --- NEW: Binding for user profile sheet target ---
    @Binding var userProfileSheetTarget: UserProfileSheetTarget?
    // --- END NEW ---
    let isCommentCollapsed: (Int) -> Bool
    let toggleCollapseAction: (Int) -> Void
    let showCommentInputAction: (Int) -> Void // parentId

    @State private var showAllComments = false
    private let initialCommentLimit = 50

    private var commentsToDisplay: [FlatCommentDisplayItem] {
        if showAllComments {
            return flatComments
        } else {
            return Array(flatComments.prefix(initialCommentLimit))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.bottom, 5)
            commentContent
        }
    }

    @ViewBuilder
    private var commentContent: some View {
        switch status {
        case .idle, .loading:
             ProgressView("Lade Kommentare...")
                 .frame(maxWidth: .infinity, alignment: .center).padding()
        case .error(let message):
             VStack {
                 Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title)
                 Text("Fehler beim Laden der Kommentare").foregroundColor(.red).padding(.top, 2)
                 Text(message).font(.caption).foregroundColor(.secondary).padding(.horizontal)
             }
             .frame(maxWidth: .infinity, alignment: .center).padding()
             .onAppear { print("CommentsSection Error Detail: \(message)") }
        case .loaded:
             if flatComments.isEmpty && totalCommentCount > 0 {
                  Text("Alle Kommentare sind eingeklappt oder entsprechen nicht den Filtern.")
                       .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
             } else if totalCommentCount == 0 {
                  Text("Keine Kommentare vorhanden.")
                       .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
             } else {
                 LazyVStack(alignment: .leading, spacing: 0) {
                     ForEach(commentsToDisplay) { flatItem in
                         VStack(alignment: .leading, spacing: 0) {
                             CommentView(
                                 comment: flatItem.comment,
                                 previewLinkTarget: $previewLinkTarget,
                                 userProfileSheetTarget: $userProfileSheetTarget, // Pass binding
                                 hasChildren: flatItem.hasChildren,
                                 isCollapsed: isCommentCollapsed(flatItem.id),
                                 onToggleCollapse: { toggleCollapseAction(flatItem.id) },
                                 onReply: { showCommentInputAction(flatItem.id) }
                             )
                             .padding(.leading, CGFloat(flatItem.level * 15))
                             .padding(.horizontal)
                             .padding(.bottom, 4)
                             if !isCommentCollapsed(flatItem.id) {
                                  Divider()
                             }
                          }
                          .id(flatItem.id)
                     }
                 }
                 .padding(.vertical, 5)

                 if !showAllComments && flatComments.count > initialCommentLimit {
                     Button { withAnimation { showAllComments = true } } label: {
                         Text("Alle \(flatComments.count) sichtbaren Kommentare anzeigen (von \(totalCommentCount))").font(.footnote.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                     }
                     .buttonStyle(.bordered).padding(.horizontal).padding(.top, 10)
                     Divider().padding(.top, 5)
                 }
             }
        }
    }
}

// Previews
@MainActor private func createPreviewFlatCommentsHelper(maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    let comment1 = ItemComment(id: 1, parent: 0, content: "Top 1", created: 1, up: 10, down: 0, confidence: 1, name: "UserA", mark: 1)
    let comment2 = ItemComment(id: 2, parent: 1, content: "Reply 1.1", created: 2, up: 5, down: 0, confidence: 1, name: "UserB", mark: 2)
    let comment3 = ItemComment(id: 3, parent: 1, content: "Reply 1.2", created: 3, up: 2, down: 0, confidence: 1, name: "UserC", mark: 1)
    let comment4 = ItemComment(id: 4, parent: 2, content: "Reply 1.1.1", created: 4, up: 1, down: 0, confidence: 1, name: "UserD", mark: 0)
    let comment5 = ItemComment(id: 5, parent: 0, content: "Top 2", created: 5, up: 8, down: 1, confidence: 1, name: "UserE", mark: 3)
    return [
        FlatCommentDisplayItem(id: 1, comment: comment1, level: 0, hasChildren: true),
        FlatCommentDisplayItem(id: 2, comment: comment2, level: 1, hasChildren: true),
        FlatCommentDisplayItem(id: 4, comment: comment4, level: 2, hasChildren: false),
        FlatCommentDisplayItem(id: 3, comment: comment3, level: 1, hasChildren: false),
        FlatCommentDisplayItem(id: 5, comment: comment5, level: 0, hasChildren: false)
    ]
}

private struct CommentsSectionPreviewWrapper<Content: View>: View {
    @State private var previewTarget: PreviewLinkTarget? = nil
    // --- NEW: Add userProfileSheetTarget for preview ---
    @State private var userProfileTarget: UserProfileSheetTarget? = nil
    // --- END NEW ---
    @State private var collapsedIDs: Set<Int> = []

    let content: (Binding<PreviewLinkTarget?>, Binding<UserProfileSheetTarget?>, @escaping (Int) -> Bool, @escaping (Int) -> Void, @escaping (Int) -> Void) -> Content

    init(@ViewBuilder content: @escaping (Binding<PreviewLinkTarget?>, Binding<UserProfileSheetTarget?>, @escaping (Int) -> Bool, @escaping (Int) -> Void, @escaping (Int) -> Void) -> Content) {
        self.content = content
    }
    private func isCollapsed(_ id: Int) -> Bool { collapsedIDs.contains(id) }
    private func toggleCollapse(_ id: Int) { if collapsedIDs.contains(id) { collapsedIDs.remove(id) } else { collapsedIDs.insert(id) } }
    private func showCommentInput(_ parentId: Int) { print("Preview: Show Comment Input for parentId: \(parentId)") }

    var body: some View {
        content($previewTarget, $userProfileTarget, isCollapsed, toggleCollapse, showCommentInput)
            .environmentObject(AppSettings())
            .environmentObject(AuthService(appSettings: AppSettings()))
    }
}


#Preview("Loaded Limited") {
    CommentsSectionPreviewWrapper { $linkTarget, $userTarget, isCollapsed, toggleCollapse, showCommentInput in
        ScrollView {
             let comments = createPreviewFlatCommentsHelper()
            CommentsSection(
                flatComments: comments,
                totalCommentCount: comments.count,
                status: .loaded,
                previewLinkTarget: $linkTarget,
                userProfileSheetTarget: $userTarget, // Pass binding
                isCommentCollapsed: isCollapsed,
                toggleCollapseAction: toggleCollapse,
                showCommentInputAction: showCommentInput
            )
        }
    }
}

#Preview("Loading") { CommentsSectionPreviewWrapper { $linkTarget, $userTarget, isCollapsed, toggleCollapse, showCommentInput in CommentsSection(flatComments: [], totalCommentCount: 0, status: .loading, previewLinkTarget: $linkTarget, userProfileSheetTarget: $userTarget, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse, showCommentInputAction: showCommentInput) } }
#Preview("Error") { CommentsSectionPreviewWrapper { $linkTarget, $userTarget, isCollapsed, toggleCollapse, showCommentInput in CommentsSection(flatComments: [], totalCommentCount: 0, status: .error("Netzwerkfehler."), previewLinkTarget: $linkTarget, userProfileSheetTarget: $userTarget, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse, showCommentInputAction: showCommentInput) } }
#Preview("Empty") { CommentsSectionPreviewWrapper { $linkTarget, $userTarget, isCollapsed, toggleCollapse, showCommentInput in CommentsSection(flatComments: [], totalCommentCount: 0, status: .loaded, previewLinkTarget: $linkTarget, userProfileSheetTarget: $userTarget, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse, showCommentInputAction: showCommentInput) } }

// --- END OF COMPLETE FILE ---
