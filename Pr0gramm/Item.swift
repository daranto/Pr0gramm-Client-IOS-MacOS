import Foundation

struct ApiResponse: Codable {
    let items: [Item]
}

struct Item: Codable, Identifiable, Hashable {
    let id: Int
    let image: String // Enthält den Dateinamen, z.B. "12345.jpg" oder "67890.mp4"
    let thumb: String
    let width: Int
    let height: Int
    let up: Int
    let down: Int
    // --- NEU: Eigenschaft zur Videoerkennung ---
    var isVideo: Bool {
        // Prüft, ob der 'image'-String (der Dateiname) mit .mp4 oder .webm endet.
        // .lowercased() stellt sicher, dass es auch bei .MP4 funktioniert.
        // Füge ggf. weitere Videoendungen hinzu, falls pr0gramm diese verwendet.
        image.lowercased().hasSuffix(".mp4") || image.lowercased().hasSuffix(".webm")
    }
    // --- Ende NEU ---

    var thumbnailUrl: URL? {
        return URL(string: "https://thumb.pr0gramm.com/\(thumb)")
    }

    // Die imageUrl muss ggf. auch angepasst werden, falls Videos von einer anderen Domain kommen
    // Beispiel: Könnte sein, dass Videos auf "vid.pr0gramm.com" liegen
    // Das musst du durch Analyse der API-Antworten herausfinden.
    // Nehmen wir erstmal an, die Basis-URL ist für beides gleich:
    var imageUrl: URL? {
        // Prüfe, ob die API die volle URL oder nur den Pfad liefert.
        // Die Doku sagt "Image uri", was auf einen Pfad hindeutet.
        // Beispiel-URLs aus der Doku deuten auf img.pr0gramm.com und vid.pr0gramm.com hin.
        if isVideo {
            // Wahrscheinlich die Video-Domain verwenden
            return URL(string: "https://vid.pr0gramm.com/\(image)")
        } else {
            // Standard-Bild-Domain
            return URL(string: "https://img.pr0gramm.com/\(image)")
        }
    }
}
