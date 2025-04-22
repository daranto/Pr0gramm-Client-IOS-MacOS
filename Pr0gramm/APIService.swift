// APIService.swift

import Foundation

// MARK: - Structs für /items/info Response
struct ItemsInfoResponse: Codable {
    let tags: [ItemTag]
    // let comments: [ItemComment] // Kommentare könnten später hinzugefügt werden
}

struct ItemTag: Codable, Identifiable, Hashable {
    let id: Int // Eindeutige ID des Tags selbst
    let confidence: Double // Wie sicher die Zuordnung ist (0 bis 1)
    let tag: String // Der eigentliche Tag-Text
}

// Optional: Struct für Kommentare, falls benötigt
/*
struct ItemComment: Codable, Identifiable, Hashable {
    let id: Int
    let parent: Int?
    let content: String
    let created: Int
    let up: Int
    let down: Int
    let confidence: Double
    let name: String
    let mark: Int
}
*/


class APIService {

    // Nimmt NUR olderThanId für Paging und gibt nur [Item] zurück
    func fetchItems(flags: Int, promoted: Int, olderThanId: Int? = nil) async throws -> [Item] {
        guard var urlComponents = URLComponents(string: "https://pr0gramm.com/api/items/get") else {
            throw URLError(.badURL)
        }

        var queryItems = [
            URLQueryItem(name: "flags", value: String(flags)),
            URLQueryItem(name: "promoted", value: String(promoted))
        ]

        if let olderId = olderThanId {
            queryItems.append(URLQueryItem(name: "older", value: String(olderId)))
            print("Requesting items older than ID: \(olderId)")
        } else {
            print("Requesting initial items (no paging).")
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        print("Fetching URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Error: Invalid HTTP response or status code (\( (response as? HTTPURLResponse)?.statusCode ?? -1 ))")
            if let responseString = String(data: data, encoding: .utf8) { print("Server Response (Error): \(responseString)") }
            throw URLError(.badServerResponse)
        }

        do {
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(ApiResponse.self, from: data) // Erwartet ApiResponse ohne 'older'
            print("Successfully decoded \(apiResponse.items.count) items. At End (API): \(apiResponse.atEnd ?? false)")
            return apiResponse.items // Gibt nur die Items zurück
        } catch {
            print("Error decoding JSON: \(error)")
            if let decodingError = error as? DecodingError { print("Decoding Error Details: \(decodingError)") }
            throw error
        }
    }
}

// MARK: - Item Info Fetching
extension APIService { // Erweitere die bestehende Klasse

    func fetchItemInfo(itemId: Int) async throws -> ItemsInfoResponse {
        guard var urlComponents = URLComponents(string: "https://pr0gramm.com/api/items/info") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "itemId", value: String(itemId))
        ]

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        print("Fetching Item Info URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Error: Invalid HTTP response or status code for item info (\( (response as? HTTPURLResponse)?.statusCode ?? -1 ))")
            if let responseString = String(data: data, encoding: .utf8) { print("Server Response (Error): \(responseString)") }
            throw URLError(.badServerResponse)
        }

        do {
            let decoder = JSONDecoder()
            let infoResponse = try decoder.decode(ItemsInfoResponse.self, from: data)
            print("Successfully decoded \(infoResponse.tags.count) tags for item \(itemId).")
            return infoResponse
        } catch {
            print("Error decoding item info JSON for item \(itemId): \(error)")
            if let decodingError = error as? DecodingError { print("Decoding Error Details: \(decodingError)") }
            throw error
        }
    }
}
