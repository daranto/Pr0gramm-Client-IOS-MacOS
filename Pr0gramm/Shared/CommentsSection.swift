// Pr0gramm/Pr0gramm/Shared/CommentsSection.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// A view that displays a list of comments for an item, handling loading and error states,
/// and rendering comments hierarchically with indentation.
struct CommentsSection: View {
    let comments: [DisplayComment] // <-- ACCEPTS DisplayComment NOW
    let status: InfoLoadingStatus
    /// Binding to trigger the presentation of a linked item preview sheet.
    @Binding var previewLinkTarget: PreviewLinkTarget?

    var body: some View {
        VStack(alignment: .leading) {
            Divider().padding(.bottom, 5) // Add padding below divider
            switch status {
            case .idle, .loading:
                ProgressView("Lade Kommentare...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            case .error(let message):
                // Display error message with details logged to console
                Text("Fehler beim Laden der Kommentare")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .onAppear {
                         print("CommentsSection Error Detail: \(message)") // Log error for debugging
                    }
            case .loaded:
                if comments.isEmpty {
                    Text("Keine Kommentare vorhanden.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Render comments recursively
                    ForEach(comments) { displayComment in
                        // Start recursion for top-level comments
                        RecursiveCommentView(displayComment: displayComment, previewLinkTarget: $previewLinkTarget, level: 0)
                    }
                }
            }
        }
        .padding(.horizontal) // Add horizontal padding to the entire section
    }
}

/// A helper view that recursively displays a comment and its children with appropriate indentation.
struct RecursiveCommentView: View {
    let displayComment: DisplayComment
    @Binding var previewLinkTarget: PreviewLinkTarget?
    let level: Int // Current indentation level

    /// The amount of padding to apply based on the level.
    private var indentationPadding: CGFloat { CGFloat(level * 15) } // Adjust 15 as needed

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Display the actual comment content using the original CommentView
            CommentView(
                comment: displayComment.comment,
                previewLinkTarget: $previewLinkTarget
            )
                .padding(.leading, indentationPadding) // Apply indentation

            Divider() // Divider after each comment (including nested ones)

            // Recursively render children, increasing the level
            ForEach(displayComment.children) { childComment in
                RecursiveCommentView(
                    displayComment: childComment,
                    previewLinkTarget: $previewLinkTarget,
                    level: level + 1 // Increment level for children
                )
            }
        }
    }
}


// MARK: - Previews

#Preview("Loaded") {
    // Sample hierarchical data
    let reply1_1 = DisplayComment(id: 2, comment: ItemComment(id: 2, parent: 1, content: "Antwort auf den ersten.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7), children: [])
    let top1 = DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1), children: [reply1_1])
    let top2 = DisplayComment(id: 3, comment: ItemComment(id: 3, parent: 0, content: "Zweiter Top-Level Kommentar. https://pr0gramm.com/new/55555", created: Int(Date().timeIntervalSince1970) - 60, up: 10, down: 3, confidence: 0.9, name: "UserC", mark: 3), children: [])
    let displayComments = [top1, top2]

    @State var previewTarget: PreviewLinkTarget? = nil
    return ScrollView {
        CommentsSection(comments: displayComments, status: .loaded, previewLinkTarget: $previewTarget)
    }
    .environmentObject(AppSettings())
}

#Preview("Loading") {
    @State var previewTarget: PreviewLinkTarget? = nil
    return ScrollView {
         CommentsSection(comments: [], status: .loading, previewLinkTarget: $previewTarget)
    }
     .environmentObject(AppSettings())
}

#Preview("Error") {
    @State var previewTarget: PreviewLinkTarget? = nil
    return ScrollView {
         CommentsSection(comments: [], status: .error("Netzwerkfehler ist aufgetreten."), previewLinkTarget: $previewTarget)
    }
     .environmentObject(AppSettings())
}

#Preview("Empty") {
    @State var previewTarget: PreviewLinkTarget? = nil
    return ScrollView {
         CommentsSection(comments: [], status: .loaded, previewLinkTarget: $previewTarget)
    }
     .environmentObject(AppSettings())
}
// --- END OF COMPLETE FILE ---
