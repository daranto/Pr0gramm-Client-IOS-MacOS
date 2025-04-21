// Item.swift
import Foundation

struct ApiResponse: Codable {
    let items: [Item]
    // KEIN 'older' oder 'nextCursor' hier, da nicht dokumentiert für /items/get Response
    let atEnd: Bool? // Beibehalten, falls nützlich
    // let error: String?
}

// Item struct bleibt wie zuletzt (mit created und flags)
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

    // --- Computed Properties (NUR EINMAL HIER DEFINIERT) ---
    var isVideo: Bool {
        image.lowercased().hasSuffix(".mp4") || image.lowercased().hasSuffix(".webm")
    }

    var thumbnailUrl: URL? {
        return URL(string: "https://thumb.pr0gramm.com/\(thumb)")
    }

    var imageUrl: URL? {
        if isVideo {
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
