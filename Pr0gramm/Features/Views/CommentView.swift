// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation // Import Foundation für NSDataDetector und AttributedString

struct CommentView: View {
    let comment: ItemComment

    private var markEnum: Mark {
        return Mark(rawValue: comment.mark)
    }

    private var userMarkColor: Color {
        return markEnum.displayColor
    }

    private var userMarkName: String {
         if comment.mark == 0 {
             return "Standard"
         }
        return markEnum.displayName
    }

    private var score: Int {
        comment.up - comment.down
    }

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // --- NEU: Computed Property für AttributedString mit Links ---
    private var attributedCommentContent: AttributedString {
        var attributedString = AttributedString(comment.content)

        // Versuche, URLs zu erkennen
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: comment.content, options: [], range: NSRange(location: 0, length: comment.content.utf16.count))

            for match in matches {
                guard let range = Range(match.range, in: attributedString) else { continue }
                // Extrahiere die URL aus dem Treffer
                guard let url = match.url else { continue }

                // Weise Attribute zu
                attributedString[range].link = url
                attributedString[range].foregroundColor = .accentColor // Mache Links klickbar (Standard-Akzentfarbe)
                // Optional: Unterstreichung hinzufügen
                // attributedString[range].underlineStyle = .single
            }
        } catch {
            // Fehler bei der Erstellung des DataDetectors, unwahrscheinlich
            print("Error creating NSDataDetector: \(error)")
            // Gib den ursprünglichen (nicht-verlinkten) String zurück
            return AttributedString(comment.content)
        }

        return attributedString
    }
    // --- Ende NEU ---

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(userMarkColor)
                    .overlay(
                        Circle().stroke(Color.black, lineWidth: 0.5)
                    )
                    .frame(width: 8, height: 8)

                Text(comment.name)
                    .font(.caption.weight(.semibold))

                Text("•").foregroundColor(.secondary)
                Text("\(score)")
                    .font(.caption)
                    .foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary)
                Text(relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            // --- GEÄNDERT: Verwendet jetzt den AttributedString ---
            Text(attributedCommentContent)
                .font(.footnote) // Schriftart für den gesamten Text
                .foregroundColor(.primary) // Standardtextfarbe
            // --- Ende Änderung ---
        }
        .padding(.vertical, 6)
        // Wichtig: Damit die Links auch tatsächlich geöffnet werden können
        .environment(\.openURL, OpenURLAction { url in
            // Standardverhalten: Öffne im externen Browser
            // Optional: Hier könnte man noch loggen oder prüfen
            print("Opening URL: \(url)")
            return .systemAction // Übergibt an das System zum Öffnen
        })
    }
}

// Preview für CommentView (unverändert, aber zeigt jetzt potenziell Links)
#Preview {
    let sampleComment = ItemComment(id: 1, parent: 0, content: "Das ist ein Beispielkommentar mit einem Link: https://pr0gramm.com und noch mehr Text.", created: Int(Date().timeIntervalSince1970) - 120, up: 15, down: 2, confidence: 0.9, name: "TestUser", mark: 1)

    CommentView(comment: sampleComment)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}

#Preview("Mark 0") {
    let sampleCommentMark0 = ItemComment(id: 2, parent: 0, content: "Kommentar von Standard-User. www.google.de", created: Int(Date().timeIntervalSince1970) - 60, up: 5, down: 0, confidence: 0.95, name: "StandardUser", mark: 0)

    CommentView(comment: sampleCommentMark0)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}

#Preview("Unknown Mark") {
    let sampleCommentUnknown = ItemComment(id: 3, parent: 0, content: "Kommentar ohne Link.", created: Int(Date().timeIntervalSince1970) - 30, up: 1, down: 1, confidence: 0.5, name: "MysteryUser", mark: 99)

    CommentView(comment: sampleCommentUnknown)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}
// --- END OF COMPLETE FILE ---
