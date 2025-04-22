// APIService.swift

import Foundation

// --- Structs für /items/info Response ---
struct ItemsInfoResponse: Codable {
    let tags: [ItemTag]
    let comments: [ItemComment]
}

struct ItemTag: Codable, Identifiable, Hashable {
    let id: Int
    let confidence: Double
    let tag: String
}

struct ItemComment: Codable, Identifiable, Hashable {
    let id: Int
    let parent: Int? // 0 wenn Top-Level
    let content: String
    let created: Int
    let up: Int
    let down: Int
    let confidence: Double
    let name: String
    let mark: Int
}
// --- Ende Info Structs ---

// --- Struct für /items/get Response (NUR EINMAL DEFINIERT) ---
struct ApiResponse: Codable {
    let items: [Item]
    let atEnd: Bool?
    // let error: String?
}
// --- Ende Get Struct ---

class APIService {

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
            // Deaktiviert für weniger Logs: print("Requesting items older than ID: \(olderId)")
        } else {
            // Deaktiviert für weniger Logs: print("Requesting initial items (no paging).")
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        // Deaktiviert für weniger Logs: print("Fetching URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Error: Invalid HTTP response or status code for /items/get (\( (response as? HTTPURLResponse)?.statusCode ?? -1 ))")
            if let responseString = String(data: data, encoding: .utf8) { print("Server Response (Error): \(responseString)") }
            throw URLError(.badServerResponse)
        }

        do {
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(ApiResponse.self, from: data) // Verwendet das obige Struct
            // Deaktiviert für weniger Logs: print("Successfully decoded \(apiResponse.items.count) items. At End (API): \(apiResponse.atEnd ?? false)")
            return apiResponse.items
        } catch {
            print("Error decoding /items/get JSON: \(error)")
            if let decodingError = error as? DecodingError { print("Decoding Error Details: \(decodingError)") }
            throw error
        }
    }
}

// MARK: - Item Info Fetching
extension APIService {
    func fetchItemInfo(itemId: Int) async throws -> ItemsInfoResponse {
        guard var urlComponents = URLComponents(string: "https://pr0gramm.com/api/items/info") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [ URLQueryItem(name: "itemId", value: String(itemId)) ]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        // Deaktiviert für weniger Logs: print("Fetching Item Info URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             print("Error: Invalid HTTP response or status code for item info (\( (response as? HTTPURLResponse)?.statusCode ?? -1 ))")
             if let responseString = String(data: data, encoding: .utf8) { print("Server Response (Error): \(responseString)") }
            throw URLError(.badServerResponse)
        }

        do {
            let decoder = JSONDecoder()
            let infoResponse = try decoder.decode(ItemsInfoResponse.self, from: data) // Verwendet das Struct oben
            // Deaktiviert für weniger Logs: print("Successfully decoded \(infoResponse.tags.count) tags and \(infoResponse.comments.count) comments for item \(itemId).")
            return infoResponse
        } catch {
            print("Error decoding item info JSON for item \(itemId): \(error)")
            if let decodingError = error as? DecodingError { print("Decoding Error Details: \(decodingError)") }
            throw error
        }
    }
}
