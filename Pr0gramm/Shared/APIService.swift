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
    let up: Int
    let down: Int
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

struct UserSyncResponse: Codable {
    let likeNonce: String?
}

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

struct InboxMessage: Codable, Identifiable {
    let id: Int
    let type: String
    let itemId: Int?
    let thumb: String?
    let flags: Int?
    let name: String?
    let mark: Int?
    let senderId: Int
    let score: Int
    let created: Int
    let message: String?
    let read: Int
    let blocked: Int

    var itemThumbnailUrl: URL? {
        guard let thumb = thumb, !thumb.isEmpty else { return nil }
        return URL(string: "https://thumb.pr0gramm.com/")?.appendingPathComponent(thumb)
    }
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

    func fetchItems(
        flags: Int,
        promoted: Int? = nil,
        user: String? = nil,
        tags: String? = nil, // This will now include the score tag if needed
        olderThanId: Int? = nil,
        collectionNameForUser: String? = nil,
        isOwnCollection: Bool = false
        // minScore parameter removed
    ) async throws -> [Item] {
        let endpoint = "/items/get"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = [URLQueryItem(name: "flags", value: String(flags))]
        var logDescription = "flags=\(flags)"

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

        if let tags = tags, !tags.isEmpty { // Check if tags string is not empty
            queryItems.append(URLQueryItem(name: "tags", value: tags))
            logDescription += ", tags='\(tags)'"
        }
        if let promoted = promoted, collectionNameForUser == nil {
            queryItems.append(URLQueryItem(name: "promoted", value: String(promoted)))
            logDescription += ", promoted=\(promoted)"
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
            Self.logger.info("API fetch completed for [\(logDescription)]: \(apiResponse.items.count) items received. atEnd: \(apiResponse.atEnd ?? false)")
            return apiResponse.items
        } catch {
            Self.logger.error("Error during \(endpoint) (\(logDescription)): \(error.localizedDescription)")
            throw error
        }
    }

    func fetchItem(id: Int, flags: Int) async throws -> Item? {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/get"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let queryItems = [ URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "flags", value: String(flags)) ]; urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { throw URLError(.badURL) }; Self.logger.debug("Fetching single item with ID \(id) and flags \(flags)"); let request = URLRequest(url: url)
        do { let (data, response) = try await URLSession.shared.data(for: request); let apiResponse: ApiResponse = try handleApiResponse(data: data, response: response, endpoint: "/items/get (single item)"); let foundItem = apiResponse.items.first; if foundItem == nil && !apiResponse.items.isEmpty { Self.logger.warning("API returned items for ID \(id), but none matched the requested ID.") } else if apiResponse.items.count > 1 { Self.logger.warning("API returned \(apiResponse.items.count) items when fetching single ID \(id).") }; return foundItem }
        catch { Self.logger.error("Error during /items/get (single item) for ID \(id): \(error.localizedDescription)"); throw error }
    }

    func fetchFavorites(username: String, collectionKeyword: String, flags: Int, olderThanId: Int? = nil) async throws -> [Item] {
        Self.logger.debug("Fetching favorites for user \(username), collectionKeyword '\(collectionKeyword)', flags \(flags), olderThan: \(olderThanId ?? -1)")
        return try await fetchItems(
            flags: flags,
            user: username,
            olderThanId: olderThanId,
            collectionNameForUser: collectionKeyword,
            isOwnCollection: true
        )
    }

    @available(*, deprecated, message: "Use fetchItems(tags:flags:promoted:olderThanId:) instead")
    func searchItems(tags: String, flags: Int) async throws -> [Item] {
        return try await fetchItems(flags: flags, user: nil, tags: tags)
    }

    func fetchItemInfo(itemId: Int) async throws -> ItemsInfoResponse {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("items/info"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        urlComponents.queryItems = [ URLQueryItem(name: "itemId", value: String(itemId)) ]; guard let url = urlComponents.url else { throw URLError(.badURL) }; let request = URLRequest(url: url)
        do { let (data, response) = try await URLSession.shared.data(for: request); return try handleApiResponse(data: data, response: response, endpoint: "/items/info") }
        catch { Self.logger.error("Error during /items/info for \(itemId): \(error.localizedDescription)"); throw error }
     }

    func login(credentials: LoginRequest) async throws -> LoginResponse {
        let endpoint = "/user/login"; let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); var components = URLComponents()
        components.queryItems = [ URLQueryItem(name: "name", value: credentials.username), URLQueryItem(name: "password", value: credentials.password) ]
        if let captcha = credentials.captcha, let token = credentials.token, !captcha.isEmpty, !token.isEmpty { Self.logger.info("Adding captcha and token to login request."); components.queryItems?.append(URLQueryItem(name: "captcha", value: captcha)); components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        else { Self.logger.info("No valid captcha/token provided for login request.") }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8); Self.logger.info("Attempting login for user: \(credentials.username)")
        do { let (data, response) = try await URLSession.shared.data(for: request); let loginResponse: LoginResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint); if loginResponse.success { Self.logger.info("Login successful (API success:true) for user: \(credentials.username)") } else { Self.logger.warning("Login failed (API success:false) for user \(credentials.username): \(loginResponse.error ?? "Unknown API error")") }; if loginResponse.ban?.banned == true { Self.logger.warning("Login failed: User \(credentials.username) is banned.") }; return loginResponse }
        catch { Self.logger.error("Error during \(endpoint): \(error.localizedDescription)"); throw error }
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
            Self.logger.info("User sync successful. Nonce: \(syncResponse.likeNonce ?? "nil")")
            return syncResponse
        }
        catch {
            Self.logger.error("Failed to sync user (offset \(offset)): \(error.localizedDescription)")
            throw error
        }
    }

    // --- MODIFIED: addToCollection now accepts collectionId ---
    func addToCollection(itemId: Int, collectionId: Int, nonce: String) async throws {
        let endpoint = "/collections/add"
        Self.logger.info("Attempting to add item \(itemId) to collection \(collectionId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "itemId", value: String(itemId)),
            URLQueryItem(name: "collectionId", value: String(collectionId)), // Add collectionId
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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
    // --- END MODIFICATION ---

    func removeFromCollection(itemId: Int, collectionId: Int, nonce: String) async throws {
        let endpoint = "/collections/remove"; Self.logger.info("Attempting to remove item \(itemId) from collection \(collectionId)."); let url = baseURL.appendingPathComponent(endpoint); var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); var components = URLComponents(); components.queryItems = [ URLQueryItem(name: "itemId", value: String(itemId)), URLQueryItem(name: "collectionId", value: String(collectionId)), URLQueryItem(name: "_nonce", value: nonce) ]; request.httpBody = components.query?.data(using: .utf8)
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
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "id", value: String(itemId)),
            URLQueryItem(name: "vote", value: String(vote)),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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

    func voteComment(commentId: Int, vote: Int, nonce: String) async throws {
        let endpoint = "/comments/vote"
        Self.logger.info("Attempting to vote \(vote) on comment \(commentId).")
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "id", value: String(commentId)),
            URLQueryItem(name: "vote", value: String(vote)),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "itemId", value: String(itemId)),
            URLQueryItem(name: "parentId", value: String(parentId)),
            URLQueryItem(name: "comment", value: comment),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "id", value: String(commentId)),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "id", value: String(commentId)),
            URLQueryItem(name: "_nonce", value: nonce)
        ]
        request.httpBody = components.query?.data(using: .utf8)
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

    func fetchInboxMessages(older: Int? = nil) async throws -> InboxResponse {
        let endpoint = "/inbox/all"
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        if let olderTimestamp = older {
            urlComponents.queryItems = [URLQueryItem(name: "older", value: String(olderTimestamp))]
            Self.logger.info("Fetching inbox messages older than timestamp: \(olderTimestamp)")
        } else {
            Self.logger.info("Fetching initial inbox messages.")
        }

        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url)
        logRequestDetails(request, for: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let apiResponse: InboxResponse = try handleApiResponse(data: data, response: response, endpoint: endpoint + (older == nil ? " (initial)" : " (older: \(older!))"))
            Self.logger.info("Successfully fetched \(apiResponse.messages.count) inbox messages. AtEnd: \(apiResponse.atEnd)")
            return apiResponse
        } catch {
            Self.logger.error("Error fetching inbox messages: \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 Self.logger.warning("Fetching inbox messages failed: User authentication required.")
            }
            throw error
        }
    }

    private func handleApiResponse<T: Decodable>(data: Data, response: URLResponse, endpoint: String) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else { Self.logger.error("API Error (\(endpoint)): Response is not HTTPURLResponse."); throw URLError(.cannotParseResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else { let responseBody = String(data: data, encoding: .utf8) ?? "No body"; Self.logger.error("API Error (\(endpoint)): Invalid HTTP status code: \(httpResponse.statusCode). Body: \(responseBody)"); if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Authentication failed for \(endpoint)"]) }; throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode) for \(endpoint). Body: \(responseBody)"]) }
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
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) { let maskedBody = bodyString.replacingOccurrences(of: #"password=[^&]+"#, with: "password=****", options: .regularExpression); Self.logger.debug("\(maskedBody)") }
        else { Self.logger.debug("(No Body or Could not decode body)") }
        Self.logger.debug("--- End Request Details ---")
    }
}
// --- END OF COMPLETE FILE ---
