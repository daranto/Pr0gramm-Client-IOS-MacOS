// APIService.swift

import Foundation

class APIService {

    // --- Angepasste Funktion ---
    func fetchItems(flags: Int, promoted: Int) async throws -> [Item] {
        // Baue die URL dynamisch zusammen
        var urlComponents = URLComponents(string: "https://pr0gramm.com/api/items/get")
        urlComponents?.queryItems = [
            URLQueryItem(name: "flags", value: String(flags)),
            URLQueryItem(name: "promoted", value: String(promoted))
            // Hier könnten später Paging-Parameter hinzukommen (older, newer)
        ]

        guard let url = urlComponents?.url else {
            print("Error: Could not create URL from components.")
            throw URLError(.badURL)
        }

        print("Fetching URL: \(url.absoluteString)") // Zum Debuggen

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Error: Invalid HTTP response or status code.")
            // Versuche, die Antwort als String auszugeben, falls es ein Fehlertext ist
            if let responseString = String(data: data, encoding: .utf8) {
                print("Server Response: \(responseString)")
            }
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(ApiResponse.self, from: data)
        return apiResponse.items
    }
    // --- Ende der Anpassung ---

    // Hier könnten später weitere API-Funktionen hinzukommen (Login, Vote, ...)
}
