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
    let up: Int; let down: Int; let confidence: Double; let name: String; let mark: Int
}

// --- Struct für /items/get Response ---
struct ApiResponse: Codable {
    let items: [Item]; let atEnd: Bool? // Item muss global definiert sein
}

// --- Structs für /user/login Response ---
struct LoginResponse: Codable {
    let success: Bool; let error: String?; let ban: BanInfo?
}
struct BanInfo: Codable {
    let banned: Bool; let reason: String; let till: Int?; let userId: Int?
}

// --- NEU: Struct für das "account"-Objekt in /user/info ---
struct AccountInfo: Codable, Hashable {
    let likesArePublic: Bool?
    let deviceMail: Bool?
    let email: String? // Eventuell nur für eingeloggten User sichtbar?
    // let invites: Int? // Fehlte im Log, ggf. hinzufügen
    // let isInvited: Bool? // Fehlte im Log, ggf. hinzufügen
    let mark: Int // Hauptinfo, die wir nutzen können
    let markDefault: Int?
    let paidUntil: Int?
    let hasBetaAccess: Bool?
    // Füge hier weitere Felder hinzu, falls im JSON vorhanden und benötigt
}

// --- Angepasste UserInfoResponse für /user/info ---
struct UserInfoResponse: Codable {
    let account: AccountInfo // <-- Geändert von 'user' zu 'account'
    let invited: [UserInfo]? // Annahme: Könnte UserInfo enthalten (wenn Name/ID benötigt wird)
    let invitesDetached: Int?
    let invitesRemaining: Int?
    let payments: Int? // Oder spezifischere Struktur
    // let subscriptions: [SubscriptionInfo]? // Benötigt eigene Struct
    // let curatorCollections: [CollectionInfo]? // Benötigt eigene Struct
    let canChangeName: Bool?
    // let authorizedApps: [AppInfo]? // Benötigt eigene Struct
    // let promotedApps: [AppInfo]? // Benötigt eigene Struct
    // let digests: DigestSettings? // Benötigt eigene Struct
    let enableEmailNotifications: Bool?
    // let backgrounds: BackgroundSettings? // Benötigt eigene Struct
    // let inviteEligible: InviteEligibility? // Benötigt eigene Struct
    // let inviteEligibilityData: InviteEligibilityData? // Benötigt eigene Struct
    let ts: Int?
    let cache: String?
    let rt: Int?
    let qc: Int?
}

// Die ursprüngliche UserInfo-Struktur - bleibt vorerst erhalten,
// falls sie von 'invited' oder anderen Endpunkten verwendet wird.
// Ihre Felder (id, name, score) sind NICHT im 'account'-Objekt enthalten.
struct UserInfo: Codable, Hashable {
    let id: Int
    let name: String
    let registered: Int
    let score: Int
    let mark: Int // Doppelt mit AccountInfo.mark
    let admin: Bool
}

// --- Struct für /user/captcha Response ---
struct CaptchaResponse: Codable {
    let token: String
    let captcha: String // Base64 encoded image string
}


// MARK: - APIService Class Definition

class APIService {

    // LoginRequest bleibt intern
    struct LoginRequest {
        let username: String; let password: String; let captcha: String?; let token: String?
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "APIService")
    private let baseURL = URL(string: "https://pr0gramm.com/api")!
    private let decoder = JSONDecoder()

    // MARK: - API Methods (fetchItems, fetchItemInfo, login, logout, getUserInfo, fetchCaptcha)

    func fetchItems(flags: Int, promoted: Int, olderThanId: Int? = nil) async throws -> [Item] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        var queryItems = [ URLQueryItem(name: "flags", value: String(flags)), URLQueryItem(name: "promoted", value: String(promoted)) ]
        if let olderId = olderThanId { queryItems.append(URLQueryItem(name: "older", value: String(olderId))) }
        urlComponents.queryItems = queryItems; guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get")
            return apiResponse.items
        } catch { Self.logger.error("Error during /items/get: \(error.localizedDescription)"); throw error }
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
            // handleApiResponse prüft auf 2xx Status und decodiert LoginResponse
            // Es wirft einen Fehler bei != 2xx (z.B. 400 Bad Request), den AuthService fangen muss.
            let loginResponse: LoginResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            // Logging für Erfolg/Fehler innerhalb von LoginResponse
            if loginResponse.success { Self.logger.info("Login successful (API success:true) for user: \(credentials.username)") }
            else { Self.logger.warning("Login failed (API success:false) for user \(credentials.username): \(loginResponse.error ?? "Unknown API error")") }
            if loginResponse.ban?.banned == true { Self.logger.warning("Login failed: User \(credentials.username) is banned.") }
            return loginResponse
        } catch {
            // Fehler vom handleApiResponse (z.B. Netzwerk, != 2xx, Decoding)
            // wird an AuthService weitergegeben. AuthService behandelt den 400er speziell.
            Self.logger.error("Error during \(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func logout() async throws {
        let endpoint = "/user/logout"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"; Self.logger.info("Attempting logout.")
        do { let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (200..<300).contains(httpResponse.statusCode) { Self.logger.info("Logout request successful (HTTP \(httpResponse.statusCode)).") }
            else { Self.logger.warning("Logout request returned non-OK status: \(httpResponse.statusCode)"); throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Logout failed."]) }
        } catch { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)"); throw error }
    }

    // Gibt jetzt die angepasste UserInfoResponse zurück
    func getUserInfo() async throws -> UserInfoResponse {
        let endpoint = "/user/info"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "GET"; Self.logger.info("Fetching user info.")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let userInfoResponse: UserInfoResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            // Logging mit Mark statt Name, da Name nicht in AccountInfo ist
            Self.logger.info("Successfully fetched user info (Mark: \(userInfoResponse.account.mark))")
            return userInfoResponse
        } catch {
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired { Self.logger.warning("Fetching user info failed: User likely not logged in.") }
            else if error is DecodingError { Self.logger.error("Failed to decode /user/info response: \(error.localizedDescription)") } // Spezieller Log für Decoding
            else { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)") }
            throw error
        }
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

    // MARK: - Helper Methods (handleApiResponse unverändert)

    private func handleApiResponse<T: Decodable>(data: Data, response: URLResponse, endpoint: String) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.cannotParseResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode). Body: \(responseBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"]) }
            // Wirft Fehler bei != 2xx generell. AuthService fängt den 400er von /user/login.
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint). Body: \(responseBody)"])
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("API Error (\(endpoint)): Failed to decode JSON: \(error)")
             if let jsonString = String(data: data, encoding: .utf8) { Self.logger.error("Problematic JSON string (\(endpoint)): \(jsonString)") }
            throw error
        }
    }
}
