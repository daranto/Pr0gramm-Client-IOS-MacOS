// Pr0gramm/Pr0gramm/Shared/CommentsSection.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents a single comment ready for display in a flat list (LazyVStack),
/// including its indentation level.
struct FlatCommentDisplayItem: Identifiable {
    let id: Int // Use original comment ID
    let comment: ItemComment
    let level: Int // Indentation level (0 for top-level)
}

/// A view that displays a list of comments for an item, handling loading and error states.
/// Uses a LazyVStack with a flattened comment list for performance with many comments.
struct CommentsSection: View {
    let flatComments: [FlatCommentDisplayItem]
    let status: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?

    // Initializer expecting the pre-flattened list
    init(
        flatComments: [FlatCommentDisplayItem],
        status: InfoLoadingStatus,
        previewLinkTarget: Binding<PreviewLinkTarget?>
    ) {
        self.flatComments = flatComments
        self.status = status
        self._previewLinkTarget = previewLinkTarget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Use spacing 0 for precise control with Divider
            Divider().padding(.bottom, 5) // Divider above comments
            commentContent // The main content area (LazyVStack or status views)
        }
        // Padding applied outside the VStack if needed, e.g., in DetailViewContent
        // .padding(.horizontal)
    }

    @ViewBuilder
    private var commentContent: some View {
        switch status {
        case .idle, .loading:
            ProgressView("Lade Kommentare...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding() // Add padding around the loading indicator
        case .error(let message):
            VStack { // Wrap error in VStack for better centering/padding
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title)
                Text("Fehler beim Laden der Kommentare")
                    .foregroundColor(.red)
                    .padding(.top, 2)
                Text(message).font(.caption).foregroundColor(.secondary).padding(.horizontal)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            .onAppear { print("CommentsSection Error Detail: \(message)") }
        case .loaded:
            if flatComments.isEmpty {
                Text("Keine Kommentare vorhanden.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Use LazyVStack for efficient rendering of potentially long lists
                LazyVStack(alignment: .leading, spacing: 0) { // spacing: 0, dividers handle spacing
                    ForEach(flatComments) { flatItem in
                        // VStack to group CommentView and Divider
                        VStack(alignment: .leading, spacing: 0) {
                             CommentView(
                                 comment: flatItem.comment,
                                 previewLinkTarget: $previewLinkTarget
                             )
                             // Apply indentation based on level
                             .padding(.leading, CGFloat(flatItem.level * 15))
                             // Add padding around the CommentView content itself
                             .padding(.horizontal) // Horizontal padding for text content
                             .padding(.vertical, 6)   // Vertical padding around text

                             Divider() // Visual separator between comments
                         }
                         .id(flatItem.id) // Stable ID for LazyVStack performance
                    }
                }
                // No extra padding needed around LazyVStack itself if parent handles it
            }
        }
    }
}

// RecursiveCommentView is removed.

// MARK: - Previews (Using a local flattening helper for preview data)

// Local helper function for preview data generation ONLY
@MainActor
private func createPreviewFlatCommentsHelper(maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    // Sample data remains the same...
    let reply_reply_reply = DisplayComment(id: 5, comment: ItemComment(id: 5, parent: 4, content: "Ebene 3", created: Int(Date().timeIntervalSince1970) - 20, up: 1, down: 0, confidence: 0.6, name: "UserE", mark: 1), children: [])
    let reply_reply = DisplayComment(id: 4, comment: ItemComment(id: 4, parent: 2, content: "Antwort auf die Antwort.", created: Int(Date().timeIntervalSince1970) - 50, up: 1, down: 0, confidence: 0.7, name: "UserC", mark: 2), children: [reply_reply_reply])
    let reply1_1 = DisplayComment(id: 2, comment: ItemComment(id: 2, parent: 1, content: "Antwort auf den ersten.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7), children: [reply_reply])
    let top1 = DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1), children: [reply1_1])
    let top2 = DisplayComment(id: 3, comment: ItemComment(id: 3, parent: 0, content: "Zweiter Top-Level Kommentar. https://pr0gramm.com/new/55555", created: Int(Date().timeIntervalSince1970) - 60, up: 10, down: 3, confidence: 0.9, name: "UserD", mark: 3), children: [])
    let displayComments = [top1, top2]

    var flatList: [FlatCommentDisplayItem] = []
    func traverse(nodes: [DisplayComment], currentLevel: Int) {
        guard currentLevel <= maxDepth else { return }
        for node in nodes {
            flatList.append(FlatCommentDisplayItem(id: node.id, comment: node.comment, level: currentLevel))
            if currentLevel < maxDepth { traverse(nodes: node.children, currentLevel: currentLevel + 1) }
        }
    }
    traverse(nodes: displayComments, currentLevel: 0)
    return flatList
}


private struct CommentsSectionPreviewWrapper<Content: View>: View {
    @State private var previewTarget: PreviewLinkTarget? = nil
    let content: (Binding<PreviewLinkTarget?>) -> Content

    init(@ViewBuilder content: @escaping (Binding<PreviewLinkTarget?>) -> Content) {
        self.content = content
    }

    var body: some View {
        content($previewTarget)
            .environmentObject(AppSettings())
    }
}


#Preview("Loaded Flat List (Depth 5)") {
    CommentsSectionPreviewWrapper { $target in
        ScrollView {
            CommentsSection(
                flatComments: createPreviewFlatCommentsHelper(maxDepth: 5), // Use helper
                status: .loaded,
                previewLinkTarget: $target
            )
        }
    }
}

#Preview("Loaded Flat List (Depth 1)") {
    CommentsSectionPreviewWrapper { $target in
        ScrollView {
            CommentsSection(
                flatComments: createPreviewFlatCommentsHelper(maxDepth: 1), // Use helper
                status: .loaded,
                previewLinkTarget: $target
            )
        }
    }
}


#Preview("Loading") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], status: .loading, previewLinkTarget: $target)
    }
}

#Preview("Error") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], status: .error("Netzwerkfehler."), previewLinkTarget: $target)
    }
}

#Preview("Empty") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], status: .loaded, previewLinkTarget: $target)
    }
}

// Flattening function is no longer part of CommentsSection.swift itself.

// --- END OF COMPLETE FILE ---
