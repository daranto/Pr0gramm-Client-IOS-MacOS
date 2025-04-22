// CommentView.swift
import SwiftUI

struct CommentView: View {
    let comment: ItemComment // Nimmt weiterhin ItemComment entgegen (hat mark: Int)

    // Abgeleitetes Enum für die Anzeige
    private var markEnum: Mark {
        // Fallback auf .schwuchtel (was rawValue 0 hat)
        return Mark(rawValue: comment.mark) ?? .schwuchtel
    }

    // Konvertiert UserMark in eine Farbe
    private var userMarkColor: Color {
        return markEnum.displayColor // Verwendet Enum-Farbe
    }

    // Gibt den Namen für die Mark zurück
    private var userMarkName: String {
         // Spezialfall für API Mark 0
         if comment.mark == 0 {
             return "Standard"
         }
        return markEnum.displayName // Verwendet Enum-Namen
    }

    // Berechnet den Score
    private var score: Int {
        comment.up - comment.down
    }

    // Formatiert die Zeit relativ
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle() // User Mark Punkt
                    .fill(userMarkColor)
                    .frame(width: 8, height: 8)
                Text(comment.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(userMarkColor) // Name in Mark-Farbe
                Text("•").foregroundColor(.secondary)
                Text("\(score)") // Score
                    .font(.caption)
                    .foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary)
                Text(relativeTime) // Zeit
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(comment.content) // Kommentartext
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 6)
    }
}

// Preview für CommentView
#Preview {
    // Erstellt Beispielkommentar mit Int für mark
    let sampleComment = ItemComment(id: 1, parent: 0, content: "Das ist ein Beispielkommentar.", created: Int(Date().timeIntervalSince1970) - 120, up: 15, down: 2, confidence: 0.9, name: "TestUser", mark: 1) // mark: 1 = Neuschwuchtel

    CommentView(comment: sampleComment)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}

#Preview("Mark 0") {
    let sampleCommentMark0 = ItemComment(id: 2, parent: 0, content: "Kommentar von Standard-User.", created: Int(Date().timeIntervalSince1970) - 60, up: 5, down: 0, confidence: 0.95, name: "StandardUser", mark: 0) // mark: 0

    CommentView(comment: sampleCommentMark0)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}
