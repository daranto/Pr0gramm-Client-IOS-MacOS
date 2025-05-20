// Pr0gramm/Pr0gramm/Shared/APIService.swift
// --- START OF COMPLETE FILE ---

import Foundation
import os
import UIKit // For UIImage in CaptchaResponse

// MARK: - API Data Structures (Top Level)

/// Response structure for the `/items/info` endpoint.
struct ItemsInfoResponse: Codable {
    let tags: [ItemTag]
    let comments: [ItemComment]
}
/// Represents a tag associated with an item.
struct ItemTag: Codable, Identifiable, Hashable {
    let id: Int
    let confidence: Double
    let tag: String
}
/// Represents a comment associated with an item.
struct ItemComment: Codable, Identifiable, Hashable {
    let id: Int
    let parent: Int?
    let content: String
    let created: Int
    var up: Int
    var down: Int
    let confidence: Double?
    let name: String?
    let mark: Int?
    let itemId: Int?
    let thumb: String?

    init(id: Int, parent: Int?, content: String, created: Int, up: Int, down: Int, confidence: Double?, name: String?, mark: Int?, itemId: Int? = nil, thumb: String? = nil) {
        self.id = id
        self.parent = parent
        self.content = content
        self.created = created
        self.up = up
        self.down = down
        self.confidence = confidence
        self.name = name
        self.mark = mark
        self.itemId = itemId
        self.thumb = thumb
    }

    var itemThumbnailUrl: URL? {
        guard let thumb = thumb, !thumb.isEmpty else { return nil }
        return URL(string: "https://thumb.pr0gramm.com/")?.appendingPathComponent(thumb)
    }
}
/// Generic response structure for endpoints returning a list of items (e.g., `/items/get`).
struct ApiResponse: Codable {
    let items: [Item]
    let atEnd: Bool?
    let atStart: Bool?
    let hasOlder: Bool?
    let hasNewer: Bool?
    let error: String?
}
/// Response structure for the `/user/login` endpoint.
struct LoginResponse: Codable {
    let success: Bool
    let error: String?
    let ban: BanInfo?
    let nonce: NonceInfo?
}
/// Details about a user ban.
struct BanInfo: Codable {
    let banned: Bool
    let reason: String
    let till: Int?
    let userId: Int?
}
/// Nonce structure from API response (currently unused).
struct NonceInfo: Codable {
    let nonce: String
}
/// Response structure for the `/user/captcha` endpoint.
struct CaptchaResponse: Codable {
    let token: String
    let captcha: String
}

struct ApiBadge: Codable, Identifiable, Hashable {
    var id: String { image }
    let image: String
    let description: String?
    let created: Int?
    let link: String?
    let category: String?

    var fullImageUrl: URL? {
        return URL(string: "https://pr0gramm.com/media/badges/")?.appendingPathComponent(image)
    }
}

struct ProfileInfoResponse: Codable {
    let user: ApiProfileUser
    let badges: [ApiBadge]?
    let commentCount: Int?
    let uploadCount: Int?
    let tagCount: Int?
    let collections: [ApiCollection]?
}

struct ApiProfileUser: Codable, Hashable {
    let id: Int
    let name: String
    let registered: Int?
    let score: Int?
    let mark: Int
    let up: Int?
    let down: Int?
    let banned: Int?
    let bannedUntil: Int?
}

struct UserInfo: Codable, Hashable {
    let id: Int
    let name: String
    let registered: Int
    let score: Int
    let mark: Int
    let badges: [ApiBadge]?
    var collections: [ApiCollection]?
}
struct CollectionsResponse: Codable {
    let collections: [ApiCollection]
}
struct ApiCollection: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let keyword: String?
    let isPublic: Int
    let isDefault: Int
    let itemCount: Int
    var isActuallyPublic: Bool { isPublic == 1 }
    var isActuallyDefault: Bool { isDefault == 1 }
}

// --- Corrected UserSyncResponse for inbox counts ---
struct InboxCounts: Codable {
    let comments: Int?
    let mentions: Int?
    let messages: Int?
    let notifications: Int?
    let follows: Int?
    let digests: Int? // Assuming this might also be part of the inbox payload
}

struct UserSettingsSync: Codable { // Assuming UserSettings is also part of the sync
    let themeId: Int?
    let showAds: Bool?
    let favUpvote: Bool?
    // Add other settings fields as per actual API response if needed
}

struct UserSyncResponse: Codable {
    let inbox: InboxCounts?
    let log: String?
    let logLength: Int?
    let score: Int?
    let settings: UserSettingsSync? // Assuming settings comes with sync
    let ts: Int?
    let cache: String? // API spec says "Cache-Buster-String"
    let rt: Int?
    let qc: Int?
    let likeNonce: String? // Kept this as it was the original field
}
// --- End Corrected ---


struct PostCommentResultComment: Codable, Identifiable, Hashable {
    let id: Int
    let parent: Int?
    let content: String
    let created: Int
    let up: Int
    let down: Int
    let confidence: Double
    let name: String?
    let mark: Int?
}

struct CommentsPostSuccessResponse: Codable {
    let success: Bool
    let commentId: Int
    let comments: [PostCommentResultComment]
}

struct CommentsPostErrorResponse: Codable {
    let success: Bool
    let error: String
}

struct ProfileCommentLikesResponse: Codable {
    let comments: [ItemComment]
    let hasOlder: Bool
    let hasNewer: Bool
}

struct ProfileCommentsResponse: Codable {
    let comments: [ItemComment]
    let user: ApiProfileUser?
    let hasOlder: Bool
    let hasNewer: Bool
}

struct InboxResponse: Codable {
    let messages: [InboxMessage]
    let atEnd: Bool
    let queue: InboxQueueInfo?
}

struct InboxQueueInfo: Codable {
    let comments: Int?
    let mentions: Int?
    let follows: Int?
    let messages: Int?
    let notifications: Int?
    let total: Int?
}

struct InboxMessage: Codable, Identifiable, Equatable {
    let id: Int
    let type: String?
    let itemId: Int?
    let thumb: String?
    let flags: Int?
    let name: String?
    let mark: Int?
    let senderId: Int?
    let score: Int?
    let created: Int
    let message: String?
    let read: Int
    let blocked: Int?
    let sent: Int?

    var itemThumbnailUrl: URL? {
        guard let thumb = thumb, !thumb.isEmpty else { return nil }
        return URL(string: "https://thumb.pr0gramm.com/")?.appendingPathComponent(thumb)
    }
    
    static func == (lhs: InboxMessage, rhs: InboxMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.type == rhs.type &&
               lhs.itemId == rhs.itemId &&
               lhs.thumb == rhs.thumb &&
               lhs.flags == rhs.flags &&
               lhs.name == rhs.name &&
               lhs.mark == rhs.mark &&
               lhs.senderId == rhs.senderId &&
               lhs.score == rhs.score &&
               lhs.created == rhs.created &&
               lhs.message == rhs.message &&
               lhs.read == rhs.read &&
               lhs.blocked == rhs.blocked &&
               lhs.sent == rhs.sent
    }
}

struct PrivateMessage: Codable, Identifiable, Equatable {
    let id: Int
    let created: Int
    let mark: Int
    let message: String?
    let name: String
    let read: Int
    let sent: Int

    static func == (lhs: PrivateMessage, rhs: PrivateMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.created == rhs.created &&
               lhs.mark == rhs.mark &&
               lhs.message == rhs.message &&
               lhs.name == rhs.name &&
               lhs.read == rhs.read &&
               lhs.sent == rhs.sent
    }
}

struct InboxConversationsResponse: Codable {
    let conversations: [InboxConversation]
    let atEnd: Bool
    let ts: Int?
}

struct InboxConversation: Codable, Identifiable {
    var id: String { name }
    let name: String
    let mark: Int
    let lastMessage: Int
    let unreadCount: Int
    let blocked: Int
    let canReceiveMessages: Int
}

struct InboxMessagesWithUserResponse: Codable {
    let with: InboxConversationUser
    let messages: [PrivateMessage]
    let atEnd: Bool
    let ts: Int?
}

struct InboxConversationUser: Codable {
    let name: String
    let mark: Int
    let blocked: Bool
    let canReceiveMessages: Bool
}

struct PostPrivateMessageAPIResponse: Codable {
    let messages: [PrivateMessage]
    let atEnd: Bool?
    let success: Bool
    let ts: Int?
}


extension Array where Element == URLQueryItem {
    func removingDuplicatesByName() -> [URLQueryItem] {
        var addedDict = [String: Bool]()
        return filter {
            addedDict.updateValue(true, forKey: $0.name) == nil
        }
    }
}


class APIService {
    struct LoginRequest { let username: String; let password: String; let captcha: String?; let token: String? }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "APIService")
    private let baseURL = URL(string: "https://pr0gramm.com/api")!
    private let decoder = JSONDecoder()

    private func formURLEncode(parameters: [String: String]) -> Data? {
        let unreservedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))

        let parameterArray = parameters.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: unreservedChars) ?? key
            var encodedValue = ""
            for char in value {
                if char == " " {
                    encodedValue += "+"
                } else if char.unicodeScalars.allSatisfy(unreservedChars.contains) {
                    encodedValue.append(char)
                } else {
                    encodedValue += String(char).addingPercentEncoding(withAllowedCharacters: unreservedChars) ?? String(char)
                }
            }
            return "\(encodedKey)=\(encodedValue)"
        }
        
        let encodedParametersString = parameterArray.joined(separator: "&")
        Self.logger.trace("Manually form-URL-encoded body: \(encodedParametersString)")
        return encodedParametersString.data(using: .utf8)
    }

    func fetchItems(
        flags: Int,
        promoted: Int? = nil,
        user: String? = nil,
        tags: String? = nil,
        olderThanId: Int? = nil,
        collectionNameForUser: String? = nil,
        isOwnCollection: Bool = false,
        showJunkParameter: Bool = false
    ) async throws -> ApiResponse {
        let endpoint = "/items/get"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = [URLQueryItem(name: "flags", value: String(flags))]
        var logDescription = "flags=\(flags)"

        if showJunkParameter {
            queryItems.append(URLQueryItem(name: "show_junk", value: "1"))
            logDescription += ", show_junk=1"
        }

        if let name = collectionNameForUser {
            queryItems.append(URLQueryItem(name: "collection", value: name))
            logDescription += ", collectionName=\(name)"
            if isOwnCollection {
                guard let ownerUsername = user else {
                    Self.logger.error("Error: isOwnCollection is true, but no user (owner) provided for collection '\(name)'.")
                    throw NSError(domain: "APIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Benutzer für eigene Sammlung nicht angegeben."])
                }
                queryItems.append(URLQueryItem(name: "user", value: ownerUsername))
                queryItems.append(URLQueryItem(name: "self", value: "true"))
                logDescription += ", collectionOwner=\(ownerUsername), self=true"
            }
        } else if let regularUser = user {
            queryItems.append(URLQueryItem(name: "user", value: regularUser))
            logDescription += ", user=\(regularUser) (for uploads/feed)"
        }

        if let tags = tags, !tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: tags))
            logDescription += ", tags='\(tags)'"
        }
        if let promotedValue = promoted, collectionNameForUser == nil, !showJunkParameter {
            queryItems.append(URLQueryItem(name: "promoted", value: String(promotedValue)))
            logDescription += ", promoted=\(promotedValue)"
        }
        if let olderId = olderThanId {
            queryItems.append(URLQueryItem(name: "older", value: String(olderId)))
            logDescription += ", older=\(olderId)"
        }
        
        urlComponents.queryItems = queryItems.removingDuplicatesByName()
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        Self.logger.info("Fetching items from \(endpoint) with params: [\(logDescription)] URL: \(url.absoluteString)")
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "\(endpoint) (\(logDescription))")
            if let apiError = apiResponse.error {
                Self.logger.error("API returned error for [\(logDescription)]: \(apiError)")
                if apiError == "nothingFound" {
                    return ApiResponse(items: [], atEnd: true, atStart: nil, hasOlder: false, hasNewer: nil, error: apiError)
                } else if apiError == "tooShort" {
                     throw NSError(domain: "APIService.fetchItems", code: 2, userInfo: [NSLocalizedDescriptionKey: "Suchbegriff zu kurz (mind. 2 Zeichen)."])
                }
            }
            Self.logger.info("API fetch completed for [\(logDescription)]: \(apiResponse.items.count) items received. atEnd: \(apiResponse.atEnd ?? false)")
            return apiResponse
        } catch {
            Self.logger.error("Error during \(endpoint) (\(logDescription)): \(error.localizedDescription)")
            throw error
        }
    }

    func fetchItem(id: Int, flags: Int) async throws -> Item? {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        let queryItemsList = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "flags", value: String(flags))
        ]
        Self.logger.debug("Fetching single item with ID \(id) and flags \(flags). (No 'show_junk' parameter for single item fetch by default)")

        urlComponents.queryItems = queryItemsList
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (single item ID: \(id), flags: \(flags))")

            let foundItem = apiResponse.items.first { $0.id == id }

            if apiResponse.items.count > 1 && foundItem == nil {
                Self.logger.warning("API returned \(apiResponse.items.count) items for ID \(id), but none matched the requested ID. This might indicate the item does not conform to flags \(flags).")
            } else if apiResponse.items.count > 1 {
                 Self.logger.info("API returned \(apiResponse.items.count) items when fetching single ID \(id). Correct item with ID \(id) was found and selected.")
            } else if foundItem == nil && !apiResponse.items.isEmpty {
                 Self.logger.warning("API returned a single item for ID \(id), but its ID did not match the requested ID.")
            }
            return foundItem
        } catch {
            Self.logger.error("Error during /items/get (single item) for ID \(id): \(error.localizedDescription)")
            throw error
        }
    }


    func fetchFavorites(username: String, collectionKeyword: String, flags: Int, olderThanId: Int? = nil) async throws -> ApiResponse {
        Self.logger.debug("Fetching favorites for user \(username), collectionKeyword '\(collectionKeyword)', flags \(flags), olderThan: \(olderThanId ?? -1)")
        return try await fetchItems(
            flags: flags,
            user: username,
            olderThanId: olderThanId,
            collectionNameForUser: collectionKeyword,
            isOwnCollection: true,
            showJunkParameter: false
        )
    }

    @available(*, deprecated, message: "Use fetchItems(tags:flags:promoted:olderThanId:showJunkParameter:) instead")
    func searchItems(tags: String, flags: Int) async throws -> ApiResponse {
        return try await fetchItems(flags: flags, user: nil, tags: tags, showJunkParameter: false)
    }

    func fetchItemInfo(itemId: Int) async throws -> ItemsInfoResponse {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/info"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "itemId", value: String(itemId)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }; let request = URLRequest(url: url)
        do { let (data, response) = try await URLSession.shared.data(for: request); return try handleApiResponse(data: data, response: response, endpoint: "/items/info") }
        catch { Self.logger.error("Error during /items/info for \(itemId): \(error.localizedDescription)"); throw error }
     }

    func login(credentials: LoginRequest) async throws -> LoginResponse {
        let endpoint = "/user/login"
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var parameters: [String: String] = [
            "name": credentials.username,
            "password": credentials.password
        ]

        if let captcha = credentials.captcha, let token = credentials.token, !captcha.isEmpty, !token.isEmpty {
            Self.logger.info("Adding captcha and token to login request parameters.")
            parameters["captcha"] = captcha
            parameters["token"] = token
        } else {
            Self.logger.info("No valid captcha/token provided for login request.")
        }
        
        request.httpBody = formURLEncode(parameters: parameters)

        Self.logger.info("Attempting login for user: \(credentials.username)")
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let loginResponse: LoginResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            if loginResponse.success {
                Self.logger.info("Login successful (API success:true) for user: \(credentials.username)")
            } else {
                Self.logger.warning("Login failed (API success:false) for user \(credentials.username): \(loginResponse.error ?? "Unknown API error")")
            }
            if loginResponse.ban?.banned == true {
                Self.logger.warning("Login failed: User \(credentials.username) is banned.")
            }
            return loginResponse
        } catch {
            Self.logger.error("Error during \(endpoint): \(error.localizedDescription)")
            throw error
        }
    }


    func logout() async throws {
        let endpoint = "/user/logout"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"; Self.logger.info("Attempting logout.")
        do { let (_, response) = try await URLSession.shared.data(for: request); guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }; if (200..<300).contains(httpResponse.statusCode) { Self.logger.info("Logout request successful (HTTP \(httpResponse.statusCode)).") } else { Self.logger.warning("Logout request returned non-OK status: \(httpResponse.statusCode)"); throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Logout failed."]) } }
        catch { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)"); throw error }
    }

    func fetchCaptcha() async throws -> CaptchaResponse {
        let endpoint = "/user/captcha"; let url = baseURL.appendingPathComponent(endpoint); let request = URLRequest(url: url); Self.logger.info("Fetching new captcha...")
        do { let (data, response) = try await URLSession.shared.data(for: request); let captchaResponse: CaptchaResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint); Self.logger.info("Successfully fetched captcha with token: \(captchaResponse.token)"); return captchaResponse }
        catch { Self.logger.error("Error fetching or decoding captcha: \(error.localizedDescription)"); throw error }
    }

    func getProfileInfo(username: String, flags: Int = 31) async throws -> ProfileInfoResponse {
        let endpoint = "/profile/info"; guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "name", value: username), URLQueryItem(name: "flags", value: String(flags)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        Self.logger.info("Fetching profile info for user: \(username) with flags \(flags)")
        do { let (data, response) = try await URLSession.shared.data(for: request); let profileInfoResponse: ProfileInfoResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint); Self.logger.info("Successfully fetched profile info for: \(profileInfoResponse.user.name) (Badges: \(profileInfoResponse.badges?.count ?? 0), Collections: \(profileInfoResponse.collections?.count ?? 0))"); return profileInfoResponse }
        catch { if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired { Self.logger.warning("Fetching profile info failed for \(username): Session likely invalid.") } else if error is DecodingError { Self.logger.error("Failed to decode /profile/info response for \(username): \(error.localizedDescription)") } else { Self.logger.error("Error during \(endpoint) for \(username): \(error.localizedDescription)") }; throw error }
    }

    func getUserCollections() async throws -> CollectionsResponse {
        let endpoint = "/collections/get"; Self.logger.info("Fetching user collections (old API)..."); let url = baseURL.appendingPathComponent(endpoint); let request = URLRequest(url: url);
        do { let (data, response) = try await URLSession.shared.data(for: request); return try handleApiResponse(data: data, response: response, endpoint: endpoint) }
        catch { Self.logger.error("Failed to fetch user collections (old API): \(error.localizedDescription)"); throw error }
    }

    func syncUser(offset: Int = 0) async throws -> UserSyncResponse {
        let endpoint = "/user/sync"; Self.logger.info("Performing user sync with offset \(offset)..."); guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "offset", value: String(offset)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }; let request = URLRequest(url: url);
        logRequestDetails(request, for: endpoint)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let syncResponse: UserSyncResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint + " (offset: \(offset))")
            Self.logger.info("User sync successful. Nonce: \(syncResponse.likeNonce ?? "nil"). Inbox counts: \(String(describing: syncResponse.inbox))") // Log inbox counts
            return syncResponse
        }
        catch {
            Self.logger.error("Failed to sync user (offset \(offset)): \(error.localizedDescription)")
            throw error
        }
    }

    func addToCollection(itemId: Int, collectionId: Int, nonce: String) async throws {
        let endpoint = "/collections/add"
        Self.logger.info("Attempting to add item \(itemId) to collection \(collectionId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "itemId": String(itemId), "collectionId": String(collectionId), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (item: \(itemId), collection: \(collectionId))")
            Self.logger.info("Successfully sent add to collection \(collectionId) request for item \(itemId).")
        } catch {
            Self.logger.error("Failed to add item \(itemId) to collection \(collectionId): \(error.localizedDescription)")
            throw error
        }
    }

    func removeFromCollection(itemId: Int, collectionId: Int, nonce: String) async throws {
        let endpoint = "/collections/remove"; Self.logger.info("Attempting to remove item \(itemId) from collection \(collectionId)."); let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "itemId": String(itemId), "collectionId": String(collectionId), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do { let (_, response) = try await URLSession.shared.data(for: request); try handleApiResponseVoid(response: response, endpoint: endpoint + " (item: \(itemId), collection: \(collectionId))"); Self.logger.info("Successfully sent remove from collection request for item \(itemId).") }
        catch { Self.logger.error("Failed to remove item \(itemId) from collection \(collectionId): \(error.localizedDescription)"); throw error }
    }

    func vote(itemId: Int, vote: Int, nonce: String) async throws {
        let endpoint = "/items/vote"
        Self.logger.info("Attempting to vote \(vote) on item \(itemId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "id": String(itemId), "vote": String(vote), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (item: \(itemId), vote: \(vote))")
            Self.logger.info("Successfully sent vote (\(vote)) for item \(itemId).")
        } catch {
            Self.logger.error("Failed to vote (\(vote)) for item \(itemId): \(error.localizedDescription)")
            throw error
        }
    }

    func voteTag(tagId: Int, vote: Int, nonce: String) async throws {
        let endpoint = "/tags/vote"
        Self.logger.info("Attempting to vote \(vote) on tag \(tagId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "id": String(tagId), "vote": String(vote), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (tag: \(tagId), vote: \(vote))")
            Self.logger.info("Successfully sent vote (\(vote)) for tag \(tagId).")
        } catch {
            Self.logger.error("Failed to vote (\(vote)) for tag \(tagId): \(error.localizedDescription)")
            throw error
        }
    }

    func addTags(itemId: Int, tags: String, nonce: String) async throws {
        let endpoint = "/tags/add"
        Self.logger.info("Attempting to add tags '\(tags)' to item \(itemId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [
            "itemId": String(itemId),
            "tags": tags,
            "_nonce": nonce
        ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Keine gültige HTTP-Antwort vom Server."])
            }

            if (200..<300).contains(httpResponse.statusCode) {
                Self.logger.info("Successfully added tags '\(tags)' to item \(itemId).")
                return
            } else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unbekannter Fehlerbody"
                Self.logger.error("Failed to add tags. Status: \(httpResponse.statusCode). Body: \(errorBody)")
                if let errorResponse = try? decoder.decode(CommentsPostErrorResponse.self, from: data) {
                    throw NSError(domain: "APIService.addTags", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
                }
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Hinzufügen der Tags (Status: \(httpResponse.statusCode)). Body: \(errorBody)"])
            }
        } catch {
            Self.logger.error("Failed to add tags '\(tags)' to item \(itemId): \(error.localizedDescription)")
            throw error
        }
    }

    func voteComment(commentId: Int, vote: Int, nonce: String) async throws {
        let endpoint = "/comments/vote"
        Self.logger.info("Attempting to vote \(vote) on comment \(commentId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "id": String(commentId), "vote": String(vote), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (comment: \(commentId), vote: \(vote))")
            Self.logger.info("Successfully sent vote (\(vote)) for comment \(commentId).")
        } catch {
            Self.logger.error("Failed to vote (\(vote)) for comment \(commentId): \(error.localizedDescription)")
            throw error
        }
    }

    func postComment(itemId: Int, parentId: Int, comment: String, nonce: String) async throws -> [PostCommentResultComment] {
        let endpoint = "/comments/post"
        Self.logger.info("Attempting to post comment to item \(itemId) (parent: \(parentId)).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters: [String: String] = [
            "itemId": String(itemId),
            "parentId": String(parentId),
            "comment": comment,
            "_nonce": nonce
        ]
        request.httpBody = formURLEncode(parameters: parameters)

        logRequestDetails(request, for: endpoint)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -999
                 Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(statusCode).")
                 if let errorResponse = try? decoder.decode(CommentsPostErrorResponse.self, from: data) {
                     throw NSError(domain: "APIService.postComment", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
                 } else if statusCode == 401 || statusCode == 403 {
                     throw URLError(.userAuthenticationRequired)
                 } else {
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(statusCode)"])
                 }
            }
            do {
                let successResponse = try decoder.decode(CommentsPostSuccessResponse.self, from: data)
                Self.logger.info("Successfully posted comment \(successResponse.commentId) to item \(itemId). Received \(successResponse.comments.count) updated comments.")
                return successResponse.comments
            } catch {
                 Self.logger.warning("Failed to decode CommentPostSuccessResponse, trying error response. Error: \(error)")
                 do {
                     let errorResponse = try decoder.decode(CommentsPostErrorResponse.self, from: data)
                     Self.logger.error("Comment post failed with API error: \(errorResponse.error)")
                     throw NSError(domain: "APIService.postComment", code: 1, userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
                 } catch let decodingError {
                     Self.logger.error("Failed to decode BOTH success and error responses for comment post: \(decodingError)")
                     throw decodingError
                 }
            }
        } catch {
            Self.logger.error("Failed to post comment to item \(itemId) (parent: \(parentId)): \(error.localizedDescription)")
            throw error
        }
    }

    func fetchFavoritedComments(username: String, flags: Int, before: Int? = nil) async throws -> ProfileCommentLikesResponse {
        let endpoint = "/profile/commentLikes"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        var queryItems = [
            URLQueryItem(name: "name", value: username),
            URLQueryItem(name: "flags", value: String(flags))
        ]

        if let beforeTimestamp = before {
            queryItems.append(URLQueryItem(name: "before", value: String(beforeTimestamp)))
            Self.logger.info("Fetching favorited comments for '\(username)' (flags: \(flags)) before timestamp: \(beforeTimestamp)")
        } else {
             let distantFutureTimestamp = Int(Date.distantFuture.timeIntervalSince1970)
             queryItems.append(URLQueryItem(name: "before", value: String(distantFutureTimestamp)))
             Self.logger.info("Fetching initial favorited comments for '\(username)' (flags: \(flags))")
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ProfileCommentLikesResponse = try handleApiResponse(data: data, response: response, endpoint: "\(endpoint) (user: \(username))")
            Self.logger.info("Successfully fetched \(apiResponse.comments.count) favorited comments for user \(username). HasOlder: \(apiResponse.hasOlder)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching favorited comments for user \(username): \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 Self.logger.warning("Fetching favorited comments failed: User authentication required.")
            }
            throw error
        }
    }

    func fetchProfileComments(username: String, flags: Int, before: Int? = nil) async throws -> ProfileCommentsResponse {
        let endpoint = "/profile/comments"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        var queryItems = [
            URLQueryItem(name: "name", value: username),
            URLQueryItem(name: "flags", value: String(flags))
        ]

        if let beforeTimestamp = before {
            queryItems.append(URLQueryItem(name: "before", value: String(beforeTimestamp)))
            Self.logger.info("Fetching profile comments for '\(username)' (flags: \(flags)) before timestamp: \(beforeTimestamp)")
        } else {
             let distantFutureTimestamp = Int(Date.distantFuture.timeIntervalSince1970)
             queryItems.append(URLQueryItem(name: "before", value: String(distantFutureTimestamp)))
             Self.logger.info("Fetching initial profile comments for '\(username)' (flags: \(flags))")
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: ProfileCommentsResponse = try handleApiResponse(data: data, response: response, endpoint: "\(endpoint) (user: \(username))")
            Self.logger.info("Successfully fetched \(apiResponse.comments.count) profile comments for user \(username). HasOlder: \(apiResponse.hasOlder)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching profile comments for user \(username): \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 Self.logger.warning("Fetching profile comments failed: User authentication required.")
            }
            throw error
        }
    }

    func favComment(commentId: Int, nonce: String) async throws {
        let endpoint = "/comments/fav"
        Self.logger.info("Attempting to favorite comment \(commentId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "id": String(commentId), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (commentId: \(commentId))")
            Self.logger.info("Successfully favorited comment \(commentId).")
        } catch {
            Self.logger.error("Failed to favorite comment \(commentId): \(error.localizedDescription)")
            throw error
        }
    }

    func unfavComment(commentId: Int, nonce: String) async throws {
        let endpoint = "/comments/unfav"
        Self.logger.info("Attempting to unfavorite comment \(commentId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [ "id": String(commentId), "_nonce": nonce ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try handleApiResponseVoid(response: response, endpoint: endpoint + " (commentId: \(commentId))")
            Self.logger.info("Successfully unfavorited comment \(commentId).")
        } catch {
            Self.logger.error("Failed to unfavorite comment \(commentId): \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchInboxMessagesAll(older: Int? = nil) async throws -> InboxResponse {
        let endpoint = "/inbox/all"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        if let olderTimestamp = older {
            urlComponents.queryItems = [URLQueryItem(name: "older", value: String(olderTimestamp))]
            Self.logger.info("Fetching general inbox messages ('/inbox/all') older than timestamp: \(olderTimestamp)")
        } else {
            Self.logger.info("Fetching initial general inbox messages ('/inbox/all').")
        }

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint + (older == nil ? " (initial)" : " (older: \(older!))"))
            Self.logger.info("Successfully fetched \(apiResponse.messages.count) general inbox messages from /inbox/all. AtEnd: \(apiResponse.atEnd)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching general inbox messages from /inbox/all: \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 Self.logger.warning("Fetching general inbox messages from /inbox/all failed: User authentication required.")
            }
            throw error
        }
    }

    func fetchInboxCommentsApi(older: Int? = nil) async throws -> InboxResponse {
        let endpoint = "/inbox/comments"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if let olderTimestamp = older {
            urlComponents.queryItems = [URLQueryItem(name: "older", value: String(olderTimestamp))]
            Self.logger.info("Fetching inbox comments from '\(endpoint)' older than timestamp: \(olderTimestamp)")
        } else {
            Self.logger.info("Fetching initial inbox comments from '\(endpoint)'.")
        }
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            Self.logger.info("Successfully fetched \(apiResponse.messages.count) comments from \(endpoint). AtEnd: \(apiResponse.atEnd)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching comments from \(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func fetchInboxNotificationsApi(older: Int? = nil) async throws -> InboxResponse {
        let endpoint = "/inbox/notifications"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if let olderTimestamp = older {
            urlComponents.queryItems = [URLQueryItem(name: "older", value: String(olderTimestamp))]
            Self.logger.info("Fetching inbox notifications from '\(endpoint)' older than timestamp: \(olderTimestamp)")
        } else {
            Self.logger.info("Fetching initial inbox notifications from '\(endpoint)'.")
        }
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            Self.logger.info("Successfully fetched \(apiResponse.messages.count) notifications/follows from \(endpoint). AtEnd: \(apiResponse.atEnd)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching notifications/follows from \(endpoint): \(error.localizedDescription)")
            throw error
        }
    }


    func fetchInboxConversations() async throws -> InboxConversationsResponse {
        let endpoint = "/inbox/conversations"
        Self.logger.info("Fetching inbox conversations from \(endpoint)...")
        let url = baseURL.appendingPathComponent(endpoint)
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxConversationsResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            Self.logger.info("Successfully fetched \(apiResponse.conversations.count) inbox conversations.")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching inbox conversations: \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                Self.logger.warning("Fetching inbox conversations failed: User authentication required.")
            }
            throw error
        }
    }

    func fetchInboxMessagesWithUser(username: String, older: Int? = nil) async throws -> InboxMessagesWithUserResponse {
        let endpoint = "/inbox/messages"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = [URLQueryItem(name: "with", value: username)]
        if let olderTimestamp = older {
            queryItems.append(URLQueryItem(name: "older", value: String(olderTimestamp)))
            Self.logger.info("Fetching messages with user '\(username)' older than timestamp: \(olderTimestamp)")
        } else {
            Self.logger.info("Fetching initial messages with user '\(username)'.")
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint + "?with=\(username)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxMessagesWithUserResponse = try handleApiResponse(data: data, response: response, endpoint: "\(endpoint)?with=\(username)")
            Self.logger.info("Successfully fetched \(apiResponse.messages.count) messages with user '\(username)'. AtEnd: \(apiResponse.atEnd)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching messages with user '\(username)': \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                Self.logger.warning("Fetching messages with user '\(username)' failed: User authentication required.")
            }
            throw error
        }
    }
    
    func postPrivateMessage(to recipientName: String, messageText: String, nonce: String) async throws -> PostPrivateMessageAPIResponse {
        let endpoint = "/inbox/post"
        Self.logger.info("Attempting to post private message to '\(recipientName)'.")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters: [String: String] = [
            "recipientName": recipientName,
            "comment": messageText,
            "_nonce": nonce
        ]
        request.httpBody = formURLEncode(parameters: parameters)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let jsonString = String(data: data, encoding: .utf8) {
                Self.logger.info("Raw JSON response from /inbox/post: \(jsonString)")
            }
            let apiResponse: PostPrivateMessageAPIResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint)
            
            if apiResponse.success {
                Self.logger.info("Successfully posted private message to '\(recipientName)'. API returned \(apiResponse.messages.count) messages.")
            } else {
                Self.logger.warning("Failed to post private message to '\(recipientName)': API success was false.")
                throw NSError(domain: "APIService.postPrivateMessage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Senden (API success:false)."])
            }
            return apiResponse
        } catch {
            Self.logger.error("Error posting private message to '\(recipientName)': \(error.localizedDescription)")
            throw error
        }
    }


    private func handleApiResponse<T: Decodable>(data: Data, response: URLResponse, endpoint: String) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else { Self.logger.error("API Error (\(endpoint)): Response is not HTTPURLResponse."); throw URLError(.cannotParseResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode). Body: \(responseBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"]) }
            if let apiErrorResponse = try? decoder.decode(ApiResponse.self, from: data), let apiError = apiErrorResponse.error {
                 if apiError == "tooShort" {
                     throw NSError(domain: "APIService.\(endpoint.replacingOccurrences(of: "/", with: "."))", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Suchbegriff zu kurz (mind. 2 Zeichen)."])
                 } else if apiError == "nothingFound" {
                     Self.logger.warning("API returned error '\(apiError)' for endpoint \(endpoint). This might need specific handling in the caller.")
                 }
                 throw NSError(domain: "APIService.\(endpoint.replacingOccurrences(of: "/", with: "."))", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError])
            }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint). Body: \(responseBody)"])
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { Self.logger.error("API Error (\(endpoint)): Failed to decode JSON: \(error)"); if let decodingError = error as? DecodingError { Self.logger.error("Decoding Error Details (\(endpoint)): \(String(describing: decodingError))") }; if let jsonString = String(data: data, encoding: .utf8) { Self.logger.error("Problematic JSON string (\(endpoint)): \(jsonString)") }; throw error }
    }

    private func handleApiResponseVoid(response: URLResponse, endpoint: String) throws {
         guard let httpResponse = response as? HTTPURLResponse else { Self.logger.error("API Error (\(endpoint)): Response is not HTTPURLResponse."); throw URLError(.cannotParseResponse) }
         guard (200..<300).contains(httpResponse.statusCode) else { Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode)."); if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"]) }; throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint)."]) }
    }

    private func logRequestDetails(_ request: URLRequest, for endpoint: String) {
        Self.logger.debug("--- Request Details for \(endpoint) ---")
        if let url = request.url { Self.logger.debug("URL: \(url.absoluteString)") } else { Self.logger.debug("URL: MISSING") }
        Self.logger.debug("Method: \(request.httpMethod ?? "MISSING")"); Self.logger.debug("Headers:")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty { headers.forEach { key, value in let displayValue = (key.lowercased() == "cookie") ? "\(value.prefix(10))... (masked)" : value; Self.logger.debug("- \(key): \(displayValue)") } }
        else { Self.logger.debug("- (No Headers)") }
        Self.logger.debug("Body:")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            var displayBody = bodyString
            if endpoint == "/user/login" {
                 displayBody = bodyString.replacingOccurrences(of: #"password=([^&]+)"#, with: "password=****", options: .regularExpression)
            }
            Self.logger.debug("\(displayBody)")
        } else {
            Self.logger.debug("(No Body or Could not decode body)")
        }
        Self.logger.debug("--- End Request Details ---")
    }
}
// --- END OF COMPLETE FILE ---
