// CommentsSection.swift
import SwiftUI

// --- InfoLoadingStatus hier definiert ---
enum InfoLoadingStatus: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

struct CommentsSection: View {
    let comments: [ItemComment]
    let status: InfoLoadingStatus // Verwendet jetzt das lokale Enum

    var body: some View {
        VStack(alignment: .leading) {
            // Titel wurde entfernt, kann bei Bedarf wieder hinzugefügt werden
            Divider()
            switch status {
            case .idle, .loading:
                ProgressView("Lade Kommentare...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            case .error(let message):
                Text("Fehler: \(message)")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            case .loaded:
                if comments.isEmpty {
                    Text("Keine Kommentare vorhanden.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Wir verwenden LazyVStack, da die CommentsSection selbst
                    // wahrscheinlich schon in einer ScrollView ist.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            // Annahme: CommentView existiert und wurde korrekt implementiert
                            CommentView(comment: comment)
                                .padding(.bottom, 4) // Etwas Platz unter jedem Kommentar
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(.horizontal) // Padding für den gesamten Bereich
        // Optional: Fester Hintergrund für die Sektion
        // .background(Color(.systemGroupedBackground))
    }
}

// --- Korrigierte Previews ---
#Preview("Loaded") {
    let comments = [
        ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1),
        ItemComment(id: 2, parent: 1, content: "Antwort auf den ersten.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7),
        ItemComment(id: 3, parent: 0, content: "Zweiter Top-Level Kommentar.", created: Int(Date().timeIntervalSince1970) - 60, up: 10, down: 3, confidence: 0.9, name: "UserC", mark: 3)
    ]
    ScrollView { // In ScrollView für die Vorschau
        CommentsSection(comments: comments, status: .loaded)
    }
    .environmentObject(AppSettings()) // Beispiel für Environment Object
}

#Preview("Loading") {
    ScrollView {
         CommentsSection(comments: [], status: .loading)
    }
     .environmentObject(AppSettings())
}

#Preview("Error") {
    ScrollView {
         CommentsSection(comments: [], status: .error("Netzwerkfehler ist aufgetreten."))
    }
     .environmentObject(AppSettings())
}

#Preview("Empty") {
    ScrollView {
         CommentsSection(comments: [], status: .loaded)
    }
     .environmentObject(AppSettings())
}
