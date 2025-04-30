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
/// Uses a LazyVStack with a flattened comment list and limits the initial number shown for performance.
struct CommentsSection: View {
    let flatComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int // Total number of comments available
    let status: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?

    @State private var showAllComments = false
    private let initialCommentLimit = 50 // Show initially e.g., 50 comments

    init(
        flatComments: [FlatCommentDisplayItem],
        totalCommentCount: Int,
        status: InfoLoadingStatus,
        previewLinkTarget: Binding<PreviewLinkTarget?>
    ) {
        self.flatComments = flatComments
        self.totalCommentCount = totalCommentCount
        self.status = status
        self._previewLinkTarget = previewLinkTarget
    }

    // Determine which comments to actually display based on state
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
            if flatComments.isEmpty {
                Text("Keine Kommentare vorhanden.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(commentsToDisplay) { flatItem in
                        VStack(alignment: .leading, spacing: 0) {
                            CommentView(comment: flatItem.comment, previewLinkTarget: $previewLinkTarget)
                                .padding(.leading, CGFloat(flatItem.level * 15))
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                            Divider()
                         }
                         .id(flatItem.id)
                    }
                }
                .padding(.vertical, 5)

                if !showAllComments && totalCommentCount > initialCommentLimit {
                    Button { withAnimation { showAllComments = true } } label: {
                        Text("Alle \(totalCommentCount) Kommentare anzeigen").font(.footnote.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered).padding(.horizontal).padding(.top, 10)
                    Divider().padding(.top, 5)
                }
            }
        }
    }
}

// MARK: - Previews

@MainActor
private func createPreviewFlatCommentsHelper(maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    // Sample data...
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
    for i in 6...100 {
         flatList.append(FlatCommentDisplayItem(id: i, comment: ItemComment(id: i, parent: 0, content: "Simulierter Kommentar \(i)", created: Int(Date().timeIntervalSince1970) - i*10, up: i % 5, down: i % 3, confidence: 0.8, name: "SimUser", mark: 1), level: 0))
    }
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


#Preview("Loaded Limited") {
    CommentsSectionPreviewWrapper { $target in
        ScrollView {
             let comments = createPreviewFlatCommentsHelper()
            CommentsSection(
                flatComments: comments,
                totalCommentCount: comments.count, // Pass total count
                status: .loaded,
                previewLinkTarget: $target
            )
        }
    }
}

#Preview("Loading") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], totalCommentCount: 0, status: .loading, previewLinkTarget: $target)
    }
}

#Preview("Error") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], totalCommentCount: 0, status: .error("Netzwerkfehler."), previewLinkTarget: $target)
    }
}

#Preview("Empty") {
    CommentsSectionPreviewWrapper { $target in
        CommentsSection(flatComments: [], totalCommentCount: 0, status: .loaded, previewLinkTarget: $target)
    }
}

// --- END OF COMPLETE FILE ---
