// Pr0gramm/Pr0gramm/Shared/APIService.swift
// --- START OF MODIFIED FILE ---

// APIService.swift

import Foundation
import os

// MARK: - API Data Structures (Top Level)

// --- Structs für /items/info Response ---
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

// --- Struct für /items/get Response ---
// --- HINZUGEFÜGT: atStart ---
struct ApiResponse: Codable {
    let items: [Item]; let atEnd: Bool?; let atStart: Bool? // Item.mark bleibt Int
}

// --- Structs für /user/login Response ---
struct LoginResponse: Codable {
    let success: Bool; let error: String?; let ban: BanInfo?
}
struct BanInfo: Codable {
    let banned: Bool; let reason: String; let till: Int?; let userId: Int?
}

// --- Struct für /user/captcha Response ---
struct CaptchaResponse: Codable {
    let token: String
    let captcha: String // Base64 encoded image string
}

// --- Struct für die /profile/info Antwort ---
struct ProfileInfoResponse: Codable {
    let user: ApiProfileUser
    let commentCount: Int?; let uploadCount: Int?; let tagCount: Int?
    // Füge hier weitere Top-Level Felder hinzu, falls benötigt
}

// Struktur für das 'user'-Objekt innerhalb von ProfileInfoResponse
struct ApiProfileUser: Codable, Hashable {
    let id: Int; let name: String; let registered: Int; let score: Int
    let mark: Int // <-- Bleibt Int von der API
    let up: Int?; let down: Int?; let banned: Int?; let bannedUntil: Int?
}

// UserInfo-Struktur - Zielformat für AuthService & Views
struct UserInfo: Codable, Hashable {
    let id: Int; let name: String; let registered: Int; let score: Int
    let mark: Int // <-- Bleibt Int
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

    // --- NEUE FUNKTION: fetchFavorites ---
    func fetchFavorites(username: String, flags: Int, olderThanId: Int? = nil) async throws -> [Item] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        var queryItems = [
            URLQueryItem(name: "flags", value: String(flags)),
            URLQueryItem(name: "user", value: username), // Username des eingeloggten Benutzers
            URLQueryItem(name: "collection", value: "favoriten"), // Spezifische Kollektion
            URLQueryItem(name: "self", value: "true") // Wichtig für Benutzerdaten
        ]
        if let olderId = olderThanId { queryItems.append(URLQueryItem(name: "older", value: String(olderId))) }
        urlComponents.queryItems = queryItems; guard let url = urlComponents.url else { throw URLError(.badURL) }

        Self.logger.debug("Fetching favorites for user \(username) with flags \(flags), olderThan: \(olderThanId ?? -1)")
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // Wichtig: Die Antwortstruktur ist dieselbe wie bei fetchItems
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (favorites)")
            Self.logger.info("Successfully fetched \(apiResponse.items.count) favorite items for user \(username). atEnd: \(apiResponse.atEnd ?? false)")
            return apiResponse.items
        } catch {
            Self.logger.error("Error during /items/get (favorites) for user \(username): \(error.localizedDescription)")
            // Prüfe auf 401/403 - deutet auf ausgeloggten Zustand hin
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                Self.logger.warning("Fetching favorites failed: User authentication required (likely not logged in or session expired).")
            }
            throw error
        }
    }
    // --- ENDE NEUE FUNKTION ---

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
        let endpoint = "/user/captcha"; let url = baseURL.appendingPathComponent(endpoint); let request = URLRequest(url: url); Self.logger.info("Fetching new captcha...")
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
}
// --- END OF MODIFIED FILE ---
