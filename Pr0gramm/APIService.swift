// APIService.swift

import Foundation

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
