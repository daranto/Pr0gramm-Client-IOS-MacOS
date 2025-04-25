// Pr0gramm/Pr0gramm/Shared/Item.swift
// --- START OF MODIFIED FILE ---

// Item.swift
import Foundation

// Item struct erweitert um optionale repost, variants und favorited Felder
struct Item: Codable, Identifiable, Hashable {
    let id: Int
    let promoted: Int? // Kann für zukünftige Logik nützlich sein
    let userId: Int
    let down: Int
    let up: Int
    let created: Int // Unix Timestamp
    let image: String
    let thumb: String // Wird für thumbnailUrl gebraucht
    let fullsize: String?
    let preview: String?
    let width: Int
    let height: Int
    let audio: Bool
    let source: String?
    let flags: Int   // SFW, NSFW etc.
    let user: String
    let mark: Int
    let repost: Bool?
    let variants: [ItemVariant]?
    var favorited: Bool? // <-- HINZUGEFÜGT: Optional Bool für lokalen Favoritenstatus

    // --- Computed Properties (unverändert) ---
    var isVideo: Bool {
        image.lowercased().hasSuffix(".mp4") || image.lowercased().hasSuffix(".webm")
    }

    var thumbnailUrl: URL? {
        return URL(string: "https://thumb.pr0gramm.com/\(thumb)")
    }

    var imageUrl: URL? {
        if isVideo {
            // TODO: Später ggf. Logik für 'variants' hinzufügen, um beste Qualität zu wählen
            return URL(string: "https://vid.pr0gramm.com/\(image)")
        } else {
            return URL(string: "https://img.pr0gramm.com/\(image)")
        }
    }

    var creationDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(created))
    }
    // --- Ende Computed Properties ---
}

// --- NEUE STRUKTUR: ItemVariant ---
// Repräsentiert eine einzelne Video-Variante aus der API
struct ItemVariant: Codable, Hashable {
    let name: String     // z.B. "vp9s", "vp9", "source"
    let path: String     // Relativer Pfad zur Videodatei
    let mimeType: String // z.B. "video/mp4"
    let codec: String    // z.B. "vp9", "h264"
    let width: Int
    let height: Int
    let bitRate: Double? // Kann Double sein
    let fileSize: Int?   // Kann Int sein

    // Computed Property für die vollständige URL (falls benötigt)
    var variantUrl: URL? {
        return URL(string: "https://vid.pr0gramm.com\(path)")
    }
}
// --- ENDE NEUE STRUKTUR ---

// --- END OF MODIFIED FILE ---
