// CommentView.swift
import SwiftUI

struct CommentView: View {
    let comment: ItemComment

    // Konvertiert UserMark in eine Farbe
    private var userMarkColor: Color {
        // Diese Werte basieren auf den üblichen pr0gramm-Farben
        switch comment.mark {
        case 1: return .orange      // Schwuchtel
        case 2: return .green       // Neuschwuchtel
        case 3: return .blue        // Altschwuchtel
        case 4: return .purple      // Admin
        case 5: return .pink        // Gebannt
        case 6: return .gray        // Pr0mium
        case 7: return .yellow      // Mittelaltschwuchtel
        case 8: return .white       // Uraltschwuchtel
        case 9: return Color(red: 0.6, green: 0.8, blue: 1.0) // Legendenschwuchtel (hellblau)
        case 10: return Color(red: 1.0, green: 0.8, blue: 0.4) // Wichtel (orange-gelb)
        case 11: return Color(red: 0.4, green: 0.9, blue: 0.4) // Community Helfer (hellgrün)
        case 12: return Color(red: 1.0, green: 0.6, blue: 0.6) // Moderator (hellrot)
        default: return .gray       // Standard/Unbekannt
        }
    }

    // Berechnet den Score
    private var score: Int {
        comment.up - comment.down
    }

    // Formatiert die Zeit relativ
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated // z.B. "5 min ago"
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // User Mark als kleiner Punkt
                Circle()
                    .fill(userMarkColor)
                    .frame(width: 8, height: 8)
                Text(comment.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(userMarkColor) // Name in Mark-Farbe
                Text("•") // Trenner
                    .foregroundColor(.secondary)
                Text("\(score)") // Score
                    .font(.caption)
                    .foregroundColor(score >= 0 ? .green : .red)
                Text("•") // Trenner
                    .foregroundColor(.secondary)
                Text(relativeTime) // Zeit
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer() // Schiebt alles nach links
            }
            // Kommentartext (Markdown wird hier noch nicht gerendert!)
            Text(comment.content)
                .font(.footnote)
                .foregroundColor(.primary)
                // TODO: Markdown-Rendering hinzufügen (z.B. mit AttributedString oder einer Bibliothek)
        }
        .padding(.vertical, 6) // Vertikaler Abstand zwischen Kommentaren
    }
}

// Preview für CommentView
#Preview {
    let sampleComment = ItemComment(id: 1, parent: 0, content: "Das ist ein Beispielkommentar.\nEr kann auch **Markdown** enthalten (theoretisch).", created: Int(Date().timeIntervalSince1970) - 120, up: 15, down: 2, confidence: 0.9, name: "TestUser", mark: 6) // Pr0mium
    return CommentView(comment: sampleComment)
        .padding()
        .background(Color.black) // Hintergrund für Kontrast
}
