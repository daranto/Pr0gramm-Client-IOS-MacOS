// Pr0gramm/Pr0gramm/Shared/CommentsSection.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

// FlatCommentDisplayItem Struktur muss in ihrer eigenen Datei existieren (FlatCommentDisplayItem.swift)

/// A view that displays a list of comments for an item, handling loading and error states.
/// Uses a LazyVStack with a flattened comment list and limits the initial number shown for performance.
struct CommentsSection: View {
    let flatComments: [FlatCommentDisplayItem] // Now receives the *filtered* list
    let totalCommentCount: Int
    let status: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?
    // Receive state/action for collapsing
    let isCommentCollapsed: (Int) -> Bool
    let toggleCollapseAction: (Int) -> Void

    @State private var showAllComments = false // This logic might need review if pagination and collapsing interact weirdly
    private let initialCommentLimit = 50 // Show initially e.g., 50 comments

    // commentsToDisplay calculation remains similar, but operates on the pre-filtered list
    private var commentsToDisplay: [FlatCommentDisplayItem] {
        if showAllComments {
            return flatComments
        } else {
            // Apply pagination limit *after* filtering for visibility
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
        // --- MODIFIED: Use explicit enum type ---
        case InfoLoadingStatus.idle, InfoLoadingStatus.loading:
             ProgressView("Lade Kommentare...")
                 .frame(maxWidth: .infinity, alignment: .center).padding()
        case InfoLoadingStatus.error(let message):
             VStack {
                 Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title)
                 Text("Fehler beim Laden der Kommentare").foregroundColor(.red).padding(.top, 2)
                 Text(message).font(.caption).foregroundColor(.secondary).padding(.horizontal)
             }
             .frame(maxWidth: .infinity, alignment: .center).padding()
             .onAppear { print("CommentsSection Error Detail: \(message)") }
        case InfoLoadingStatus.loaded:
        // --- END MODIFICATION ---
             if flatComments.isEmpty && totalCommentCount > 0 { // Check totalCommentCount too
                  Text("Alle Kommentare sind eingeklappt oder entsprechen nicht den Filtern.")
                       .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
             } else if totalCommentCount == 0 { // Explicitly check if there were no comments *at all*
                  Text("Keine Kommentare vorhanden.")
                       .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
             } else {
                 LazyVStack(alignment: .leading, spacing: 0) {
                     ForEach(commentsToDisplay) { flatItem in // Iterate over filtered+paginated list
                         VStack(alignment: .leading, spacing: 0) {
                             CommentView(
                                 comment: flatItem.comment,
                                 previewLinkTarget: $previewLinkTarget,
                                 hasChildren: flatItem.hasChildren, // Pass hasChildren
                                 isCollapsed: isCommentCollapsed(flatItem.id), // Pass check result
                                 onToggleCollapse: { toggleCollapseAction(flatItem.id) } // Pass action specific to this ID
                             )
                             .padding(.leading, CGFloat(flatItem.level * 15))
                             .padding(.horizontal)
                             .padding(.bottom, 4)
                             // Only show divider if the comment itself isn't collapsed (or if it has no children)
                             if !isCommentCollapsed(flatItem.id) {
                                  Divider()
                             }
                          }
                          .id(flatItem.id)
                     }
                 }
                 .padding(.vertical, 5)

                 // "Show All" button logic might need adjustment if many comments are collapsed
                 if !showAllComments && flatComments.count > initialCommentLimit { // Compare visible count to limit
                     Button { withAnimation { showAllComments = true } } label: {
                         // Consider showing total *visible* count vs total *raw* count?
                         Text("Alle \(flatComments.count) sichtbaren Kommentare anzeigen (von \(totalCommentCount))").font(.footnote.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                     }
                     .buttonStyle(.bordered).padding(.horizontal).padding(.top, 10)
                     Divider().padding(.top, 5)
                 }
             }
        }
    }
}

// Previews (unverändert, aber brauchen FlatCommentDisplayItem)

// Helper function needed for preview context
@MainActor
private func createPreviewFlatCommentsHelper(maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    // Sample data using ItemComment directly
    let comment1 = ItemComment(id: 1, parent: 0, content: "Top 1", created: 1, up: 10, down: 0, confidence: 1, name: "UserA", mark: 1)
    let comment2 = ItemComment(id: 2, parent: 1, content: "Reply 1.1", created: 2, up: 5, down: 0, confidence: 1, name: "UserB", mark: 2)
    let comment3 = ItemComment(id: 3, parent: 1, content: "Reply 1.2", created: 3, up: 2, down: 0, confidence: 1, name: "UserC", mark: 1)
    let comment4 = ItemComment(id: 4, parent: 2, content: "Reply 1.1.1", created: 4, up: 1, down: 0, confidence: 1, name: "UserD", mark: 0)
    let comment5 = ItemComment(id: 5, parent: 0, content: "Top 2", created: 5, up: 8, down: 1, confidence: 1, name: "UserE", mark: 3)

    // Manually create the flat structure for preview
    return [
        FlatCommentDisplayItem(id: 1, comment: comment1, level: 0, hasChildren: true),
        FlatCommentDisplayItem(id: 2, comment: comment2, level: 1, hasChildren: true),
        FlatCommentDisplayItem(id: 4, comment: comment4, level: 2, hasChildren: false),
        FlatCommentDisplayItem(id: 3, comment: comment3, level: 1, hasChildren: false),
        FlatCommentDisplayItem(id: 5, comment: comment5, level: 0, hasChildren: false)
    ]
}


// Preview Wrapper
private struct CommentsSectionPreviewWrapper<Content: View>: View {
    @State private var previewTarget: PreviewLinkTarget? = nil
    // Add state for collapsed comments for preview
    @State private var collapsedIDs: Set<Int> = []

    let content: (Binding<PreviewLinkTarget?>, @escaping (Int) -> Bool, @escaping (Int) -> Void) -> Content

    init(@ViewBuilder content: @escaping (Binding<PreviewLinkTarget?>, @escaping (Int) -> Bool, @escaping (Int) -> Void) -> Content) {
        self.content = content
    }

    private func isCollapsed(_ id: Int) -> Bool {
        collapsedIDs.contains(id)
    }

    private func toggleCollapse(_ id: Int) {
        if collapsedIDs.contains(id) {
            collapsedIDs.remove(id)
        } else {
            collapsedIDs.insert(id)
        }
    }

    var body: some View {
        content($previewTarget, isCollapsed, toggleCollapse)
            .environmentObject(AppSettings()) // Add AppSettings for CommentView fonts
    }
}


#Preview("Loaded Limited") {
    CommentsSectionPreviewWrapper { $target, isCollapsed, toggleCollapse in
        ScrollView {
             let comments = createPreviewFlatCommentsHelper()
            CommentsSection(
                flatComments: comments,
                totalCommentCount: comments.count,
                status: .loaded,
                previewLinkTarget: $target,
                isCommentCollapsed: isCollapsed, // Pass function
                toggleCollapseAction: toggleCollapse // Pass action
            )
        }
    }
}

#Preview("Loading") {
    CommentsSectionPreviewWrapper { $target, isCollapsed, toggleCollapse in
        CommentsSection(
            flatComments: [], totalCommentCount: 0, status: .loading,
            previewLinkTarget: $target, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse
        )
    }
}

#Preview("Error") {
    CommentsSectionPreviewWrapper { $target, isCollapsed, toggleCollapse in
        CommentsSection(
            flatComments: [], totalCommentCount: 0, status: .error("Netzwerkfehler."),
            previewLinkTarget: $target, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse
        )
    }
}

#Preview("Empty") {
    CommentsSectionPreviewWrapper { $target, isCollapsed, toggleCollapse in
        CommentsSection(
            flatComments: [], totalCommentCount: 0, status: .loaded,
            previewLinkTarget: $target, isCommentCollapsed: isCollapsed, toggleCollapseAction: toggleCollapse
        )
    }
}

// --- END OF COMPLETE FILE ---
