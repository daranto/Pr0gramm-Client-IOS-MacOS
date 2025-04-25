// Pr0gramm/Pr0gramm/Shared/CommentsSection.swift
// --- START OF COMPLETE FILE ---

// CommentsSection.swift
import SwiftUI

struct CommentsSection: View {
    let comments: [ItemComment]
    let status: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget? // <-- GEÄNDERT: Typ ist jetzt Wrapper

    var body: some View {
        VStack(alignment: .leading) {
            Divider()
            switch status {
            case .idle, .loading:
                ProgressView("Lade Kommentare...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            case .error(let message):
                Text("Fehler beim Laden der Kommentare")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .onAppear {
                         print("CommentsSection Error Detail: \(message)")
                    }
            case .loaded:
                if comments.isEmpty {
                    Text("Keine Kommentare vorhanden.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            CommentView(
                                comment: comment,
                                previewLinkTarget: $previewLinkTarget // <-- Binding weitergeben (Typ ist jetzt Wrapper)
                            )
                                .padding(.bottom, 4)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// --- Korrigierte Previews (State Typ geändert) ---
#Preview("Loaded") {
    let comments = [
        ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1),
        ItemComment(id: 2, parent: 1, content: "Antwort auf den ersten.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7),
        ItemComment(id: 3, parent: 0, content: "Zweiter Top-Level Kommentar. https://pr0gramm.com/new/55555", created: Int(Date().timeIntervalSince1970) - 60, up: 10, down: 3, confidence: 0.9, name: "UserC", mark: 3)
    ]
    // GEÄNDERT: State Typ für Preview
    @State var previewTarget: PreviewLinkTarget? = nil
    return ScrollView {
        CommentsSection(comments: comments, status: .loaded, previewLinkTarget: $previewTarget)
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
