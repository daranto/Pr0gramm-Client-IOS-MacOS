// Pr0gramm/Pr0gramm/Shared/APIService.swift
// --- START OF COMPLETE FILE ---

// APIService.swift

import Foundation
import os
import UIKit // Import UIKit für UIImage

// MARK: - API Data Structures (Top Level)
struct ItemsInfoResponse: Codable {
    let tags: [ItemTag]
    let comments: [ItemComment]
}
struct ItemTag: Codable, Identifiable, Hashable {
    let id: Int; let confidence: Double; let tag: String
}
struct ItemComment: Codable, Identifiable, Hashable {
    let id: Int; let parent: Int?; let content: String; let created: Int
    let up: Int; let down: Int; let confidence: Double; let name: String; let mark: Int // Bleibt Int
}
struct ApiResponse: Codable {
    let items: [Item]; let atEnd: Bool?; let atStart: Bool? // Item.mark bleibt Int
}
struct LoginResponse: Codable {
    let success: Bool; let error: String?; let ban: BanInfo?; let nonce: NonceInfo? // Nonce hier *könnte* veraltet sein
}
struct BanInfo: Codable {
    let banned: Bool; let reason: String; let till: Int?; let userId: Int?
}
struct NonceInfo: Codable {
    let nonce: String
} // Bleibt, falls API es doch mal liefert
struct CaptchaResponse: Codable {
    let token: String
    let captcha: String // Base64 encoded image string
}
struct ProfileInfoResponse: Codable {
    let user: ApiProfileUser
    let commentCount: Int?; let uploadCount: Int?; let tagCount: Int?
}
struct ApiProfileUser: Codable, Hashable {
    let id: Int; let name: String; let registered: Int; let score: Int
    let mark: Int // <-- Bleibt Int von der API
    let up: Int?; let down: Int?; let banned: Int?; let bannedUntil: Int?
}
struct UserInfo: Codable, Hashable {
    let id: Int; let name: String; let registered: Int; let score: Int
    let mark: Int // <-- Bleibt Int
}
struct CollectionsResponse: Codable {
    let collections: [ApiCollection]
}
struct ApiCollection: Codable, Identifiable {
    let id: Int
    let name: String
    let keyword: String?
    let isPublic: Int
    let isDefault: Int
    let itemCount: Int
}
struct UserSyncResponse: Codable {
    let likeNonce: String? // Name laut Referenz-Repo
}


// MARK: - APIService Class Definition
class APIService {
    struct LoginRequest { let username: String; let password: String; let captcha: String?; let token: String? }
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "APIService")
    private let baseURL = URL(string: "https://pr0gramm.com/api")!
    private let decoder = JSONDecoder()

    // MARK: - API Methods
    func fetchItems(flags: Int, promoted: Int, olderThanId: Int? = nil) async throws -> [Item] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        var queryItems = [ URLQueryItem(name: "flags", value: String(flags)), URLQueryItem(name: "promoted", value: String(promoted)) ]
        if let olderId = olderThanId { queryItems.append(URLQueryItem(name: "older", value: String(olderId))) }
        urlComponents.queryItems = queryItems; guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (feed)")
            return apiResponse.items
        } catch { Self.logger.error("Error during /items/get (feed): \(error.localizedDescription)"); throw error }
    }

    func fetchItem(id: Int, flags: Int) async throws -> Item? {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "flags", value: String(flags))
        ]
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        Self.logger.debug("Fetching single item with ID \(id) and flags \(flags)")
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (single item)")
            let foundItem = apiResponse.items.first
            if foundItem == nil && !apiResponse.items.isEmpty { Self.logger.warning("API returned items for ID \(id), but none matched the requested ID.") }
            else if apiResponse.items.count > 1 { Self.logger.warning("API returned \(apiResponse.items.count) items when fetching single ID \(id).") }
            return foundItem
        } catch { Self.logger.error("Error during /items/get (single item) for ID \(id): \(error.localizedDescription)"); throw error }
    }

    func fetchFavorites(username: String, flags: Int, olderThanId: Int? = nil) async throws -> [Item] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        var queryItems = [
            URLQueryItem(name: "flags", value: String(flags)),
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "collection", value: "favoriten"),
            URLQueryItem(name: "self", value: "true")
        ]
        if let olderId = olderThanId { queryItems.append(URLQueryItem(name: "older", value: String(olderId))) }
        urlComponents.queryItems = queryItems; guard let url = urlComponents.url else { throw URLError(.badURL) }
        Self.logger.debug("Fetching favorites for user \(username) with flags \(flags), olderThan: \(olderThanId ?? -1)")
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (favorites)")
            Self.logger.info("Successfully fetched \(apiResponse.items.count) favorite items for user \(username). atEnd: \(apiResponse.atEnd ?? false)")
            let favoritedItems = apiResponse.items.map { item -> Item in
                var mutableItem = item
                mutableItem.favorited = true
                return mutableItem
            }
            return favoritedItems
        } catch { Self.logger.error("Error during /items/get (favorites) for user \(username): \(error.localizedDescription)"); if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired { Self.logger.warning("Fetching favorites failed: User authentication required.") }; throw error }
    }

    func searchItems(tags: String, flags: Int) async throws -> [Item] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let queryItems = [
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "flags", value: String(flags)),
            URLQueryItem(name: "promoted", value: "0") // Search all
        ]
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        Self.logger.info("Searching items with tags '\(tags)' and flags \(flags)")
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (search)")
            Self.logger.info("Search returned \(apiResponse.items.count) items for tags '\(tags)'. atEnd: \(apiResponse.atEnd ?? false)")
            return apiResponse.items
        } catch { Self.logger.error("Error during /items/get (search) for tags '\(tags)': \(error.localizedDescription)"); throw error }
    }

    func fetchItemInfo(itemId: Int) async throws -> ItemsInfoResponse {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/info"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "itemId", value: String(itemId)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try handleApiResponse(data: data, response: response, endpoint: "/items/info")
        } catch { Self.logger.error("Error during /items/info for \(itemId): \(error.localizedDescription)"); throw error }
     }

    func login(credentials: LoginRequest) async throws -> LoginResponse {
        let endpoint = "/user/login"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); var components = URLComponents()
        components.queryItems = [ URLQueryItem(name: "name", value: credentials.username), URLQueryItem(name: "password", value: credentials.password) ]
        if let captcha = credentials.captcha, let token = credentials.token, !captcha.isEmpty, !token.isEmpty {
            Self.logger.info("Adding captcha and token to login request.")
            components.queryItems?.append(URLQueryItem(name: "captcha", value: captcha)); components.queryItems?.append(URLQueryItem(name: "token", value: token))
        } else { Self.logger.info("No valid captcha/token provided for login request.") }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8); Self.logger.info("Attempting login for user: \(credentials.username)")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let loginResponse: LoginResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            if loginResponse.success { Self.logger.info("Login successful (API success:true) for user: \(credentials.username)") }
            else { Self.logger.warning("Login failed (API success:false) for user \(credentials.username): \(loginResponse.error ?? "Unknown API error")") }
            if loginResponse.ban?.banned == true { Self.logger.warning("Login failed: User \(credentials.username) is banned.") }
            return loginResponse
        } catch { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)"); throw error }
    }

    func logout() async throws {
        let endpoint = "/user/logout"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"; Self.logger.info("Attempting logout.")
        do { let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (200..<300).contains(httpResponse.statusCode) { Self.logger.info("Logout request successful (HTTP \(httpResponse.statusCode)).") }
            else { Self.logger.warning("Logout request returned non-OK status: \(httpResponse.statusCode)"); throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Logout failed."]) }
        } catch { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)"); throw error }
    }

    func fetchCaptcha() async throws -> CaptchaResponse {
        let endpoint = "/user/captcha"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); Self.logger.info("Fetching new captcha...")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let captchaResponse: CaptchaResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            Self.logger.info("Successfully fetched captcha with token: \(captchaResponse.token)")
            return captchaResponse
        } catch { Self.logger.error("Error fetching or decoding captcha: \(error.localizedDescription)"); throw error }
    }

    func getProfileInfo(username: String, flags: Int = 9) async throws -> ProfileInfoResponse {
        let endpoint = "/profile/info"; guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "name", value: username), URLQueryItem(name: "flags", value: String(flags)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = "GET"; Self.logger.info("Fetching profile info for user: \(username)")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let profileInfoResponse: ProfileInfoResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            Self.logger.info("Successfully fetched profile info for: \(profileInfoResponse.user.name)")
            return profileInfoResponse
        } catch {
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired { Self.logger.warning("Fetching profile info failed for \(username): Session likely invalid.") }
            else if error is DecodingError { Self.logger.error("Failed to decode /profile/info response for \(username): \(error.localizedDescription)") }
            else { Self.logger.error("Error during \(endpoint) for \(username): \(error.localizedDescription)") }
            throw error
        }
    }

    func getUserCollections() async throws -> CollectionsResponse {
        let endpoint = "/collections/get"
        Self.logger.info("Fetching user collections...")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try handleApiResponse(data: data, response: response, endpoint: endpoint)
        } catch {
            Self.logger.error("Failed to fetch user collections: \(error.localizedDescription)")
            throw error
        }
    }

    func syncUser(offset: Int = 0) async throws -> UserSyncResponse {
        let endpoint = "/user/sync"
        Self.logger.info("Performing user sync with offset \(offset)...")

        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = urlComponents.url else {
             throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try handleApiResponse(data: data, response: response, endpoint: endpoint + " (offset: \(offset))")
        } catch {
            Self.logger.error("Failed to sync user (offset \(offset)): \(error.localizedDescription)")
            throw error
        }
    }

    // --- Favoriten-Endpunkte (Add OHNE, Remove MIT collectionId) ---
    func addToCollection(itemId: Int, nonce: String) async throws { // OHNE collectionId
        let endpoint = "/collections/add"
        Self.logger.info("Attempting to add item \(itemId) to default collection (Favorites).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "itemId", value: String(itemId)),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        logRequestDetails(request, for: endpoint)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (item: \(itemId))")
            Self.logger.info("Successfully sent add to collection request for item \(itemId).")
        } catch {
            Self.logger.error("Failed to add item \(itemId) to collection: \(error.localizedDescription)")
            throw error
        }
    }

    func removeFromCollection(itemId: Int, collectionId: Int, nonce: String) async throws { // MIT collectionId
        let endpoint = "/collections/remove"
        Self.logger.info("Attempting to remove item \(itemId) from collection \(collectionId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "itemId", value: String(itemId)),
            URLQueryItem(name: "collectionId", value: String(collectionId)), // Wieder hinzugefügt
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        logRequestDetails(request, for: endpoint)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (item: \(itemId), collection: \(collectionId))")
            Self.logger.info("Successfully sent remove from collection request for item \(itemId).")
        } catch {
            Self.logger.error("Failed to remove item \(itemId) from collection \(collectionId): \(error.localizedDescription)")
            throw error
        }
    }
    // --- ENDE ---


    // MARK: - Helper Methods
    private func handleApiResponse<T: Decodable>(data: Data, response: URLResponse, endpoint: String) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else { Self.logger.error("API Error (\(endpoint)): Response is not HTTPURLResponse."); throw URLError(.cannotParseResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode). Body: \(responseBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"]) }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint). Body: \(responseBody)"])
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("API Error (\(endpoint)): Failed to decode JSON: \(error)")
             if let decodingError = error as? DecodingError { Self.logger.error("Decoding Error Details (\(endpoint)): \(String(describing: decodingError))") }
             if let jsonString = String(data: data, encoding: .utf8) { Self.logger.error("Problematic JSON string (\(endpoint)): \(jsonString)") }
            throw error
        }
    }

    private func handleApiResponseVoid(response: URLResponse, endpoint: String) throws {
         guard let httpResponse = response as? HTTPURLResponse else {
             Self.logger.error("API Error (\(endpoint)): Response is not HTTPURLResponse.");
             throw URLError(.cannotParseResponse)
         }
         guard (200..<300).contains(httpResponse.statusCode) else {
             Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode).")
             if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                 throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"])
             }
             throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint)."])
         }
    }

    private func logRequestDetails(_ request: URLRequest, for endpoint: String) {
        Self.logger.debug("--- Request Details for \(endpoint) ---")
        if let url = request.url {
            Self.logger.debug("URL: \(url.absoluteString)")
        } else {
            Self.logger.debug("URL: MISSING")
        }
        Self.logger.debug("Method: \(request.httpMethod ?? "MISSING")")
        Self.logger.debug("Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            Self.logger.debug("- \(key): \(value)")
        }
        if request.allHTTPHeaderFields == nil || request.allHTTPHeaderFields?.isEmpty == true {
             Self.logger.debug("- (No Headers)")
        }

        Self.logger.debug("Body:")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            Self.logger.debug("\(bodyString)")
        } else {
            Self.logger.debug("(No Body or Could not decode body)")
        }
        Self.logger.debug("--- End Request Details ---")
    }
}
// --- END OF COMPLETE FILE ---
