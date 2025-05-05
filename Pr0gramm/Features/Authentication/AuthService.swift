// Pr0gramm/Pr0gramm/Features/Authentication/AuthService.swift
// --- START OF COMPLETE FILE ---

import Foundation
import Combine
import os
import UIKit

@MainActor
class AuthService: ObservableObject {

    // MARK: - Dependencies
    private let apiService = APIService()
    private let keychainService = KeychainService()
    private let appSettings: AppSettings

    // MARK: - Keychain & UserDefaults Keys
    private let sessionCookieKey = "pr0grammSessionCookie_v1"
    private let sessionUsernameKey = "pr0grammUsername_v1"
    private let sessionCookieName = "me"
    private let userVotesKey = "pr0grammUserVotes_v1"
    // --- NEW: Key for favorited comments ---
    private let favoritedCommentsKey = "pr0grammFavoritedComments_v1"
    // --- END NEW ---

    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserInfo? = nil
    @Published var userNonce: String? = nil
    @Published var favoritesCollectionId: Int? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loginError: String? = nil
    @Published private(set) var needsCaptcha: Bool = false
    @Published private(set) var captchaToken: String? = nil
    @Published private(set) var captchaImage: UIImage? = nil

    @Published var favoritedItemIDs: Set<Int> = []
    @Published var votedItemStates: [Int: Int] = [:] // ItemID -> Vote (-1, 0, 1)
    @Published private(set) var isVoting: [Int: Bool] = [:] // Track voting progress per item

    // --- NEW: State for Comment Favorites ---
    @Published var favoritedCommentIDs: Set<Int> = []
    @Published private(set) var isFavoritingComment: [Int: Bool] = [:] // Track fav progress per comment
    // --- END NEW ---

    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        loadVotedStates() // Load persisted votes on init
        loadFavoritedCommentIDs() // Load persisted comment favs on init
        AuthService.logger.info("AuthService initialized. Loaded \(self.votedItemStates.count) vote states and \(self.favoritedCommentIDs.count) favorited comment IDs.")
    }

    // MARK: - Public Methods (Login, Logout, Check Status etc.)

    func fetchInitialCaptcha() async { // Unverändert
        AuthService.logger.info("fetchInitialCaptcha called by LoginView.")
        await MainActor.run { self.needsCaptcha = true }
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async { // Unverändert
        guard !isLoading else { AuthService.logger.warning("Login attempt skipped: Already loading."); return }
        AuthService.logger.info("Attempting login for user: \(username)")
        await MainActor.run {
            // Reset state before login attempt
            isLoading = true; loginError = nil; self.userNonce = nil; self.favoritesCollectionId = nil; self.favoritedItemIDs = []; self.votedItemStates = [:]; self.isVoting = [:]
            // --- NEW: Reset comment favs on login ---
            self.favoritedCommentIDs = []; self.isFavoritingComment = [:]
            // --- END NEW ---
            AuthService.logger.debug("Resetting user-specific states for login.")
        }

        let credentials = APIService.LoginRequest(
            username: username, password: password, captcha: captchaAnswer, token: self.captchaToken
        )

        if self.needsCaptcha && (captchaAnswer?.isEmpty ?? true || self.captchaToken?.isEmpty ?? true) {
            await MainActor.run { self.loginError = "Bitte Captcha eingeben."; isLoading = false; }
            AuthService.logger.warning("Login attempt failed: Captcha required but data missing."); return
        }

        AuthService.logger.debug("[LOGIN START] Cookies BEFORE /user/login API call:")
        await logAllCookiesForPr0gramm()

        do {
            let loginResponse = try await apiService.login(credentials: credentials)
            AuthService.logger.debug("[LOGIN SUCCESS] Cookies AFTER /user/login API call (BEFORE nonce extraction):")
            await logAllCookiesForPr0gramm()
            let extractedNonce = await extractNonceFromCookieStorage()
            await MainActor.run { self.userNonce = extractedNonce }

            if self.userNonce == nil { AuthService.logger.error("CRITICAL: Failed to obtain nonce from Cookie parsing after successful login!") }
            else { AuthService.logger.info("Nonce successfully extracted and potentially shortened from cookie after login.") }

            if loginResponse.success {
                AuthService.logger.info("Login successful via API for user: \(username)")
                let profileLoaded = await loadProfileInfo(username: username, setLoadingState: false)
                var collectionLoaded = false
                var favoritesLoaded = false // Track favorite loading
                if profileLoaded {
                    collectionLoaded = await fetchUserCollections()
                    if collectionLoaded {
                        favoritesLoaded = await loadInitialFavorites() // Load favorite IDs
                        loadVotedStates() // Load votes
                        loadFavoritedCommentIDs() // Load comment favs
                        AuthService.logger.info("Loaded \(self.votedItemStates.count) persisted vote states and \(self.favoritedCommentIDs.count) comment fav IDs after successful login.")
                    }
                }

                if profileLoaded && collectionLoaded && favoritesLoaded && self.userNonce != nil {
                    AuthService.logger.debug("[LOGIN SUCCESS] Cookies BEFORE saving to Keychain:")
                    await logAllCookiesForPr0gramm()
                    let cookieSaved = await findAndSaveSessionCookie()
                    let usernameSaved = keychainService.saveUsername(username, forKey: sessionUsernameKey)

                    await MainActor.run {
                        if cookieSaved && usernameSaved { AuthService.logger.info("Session cookie and username saved to keychain.") }
                        else { AuthService.logger.warning("Failed to save session cookie (\(cookieSaved)) or username (\(usernameSaved)) to keychain.") }
                        self.isLoggedIn = true
                        self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
                        AuthService.logger.info("User \(self.currentUser!.name) is now logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0). Initial Favs loaded: \(self.favoritedItemIDs.count). Initial Votes loaded: \(self.votedItemStates.count). Initial Comment Favs: \(self.favoritedCommentIDs.count)")
                    }
                } else {
                    await MainActor.run {
                        self.isLoggedIn = false
                        if !profileLoaded { self.loginError = "Login erfolgreich, aber Profildaten konnten nicht geladen werden." }
                        else if !collectionLoaded { self.loginError = "Login erfolgreich, aber Favoriten-Ordner konnte nicht ermittelt werden." }
                        else if !favoritesLoaded { self.loginError = "Login erfolgreich, aber Favoriten konnten nicht initial geladen werden." }
                        else { self.loginError = "Login erfolgreich, aber Session-Daten (Nonce) konnten nicht gelesen werden." }
                        AuthService.logger.error("Login sequence failed after API success. Profile: \(profileLoaded), Collections: \(collectionLoaded), Favorites: \(favoritesLoaded), Nonce: \(self.userNonce != nil)")
                    }
                    await performLogoutCleanup()
                }
            } else {
                 if loginResponse.ban?.banned == true {
                     let banReason = loginResponse.ban?.reason ?? "Unbekannter Grund"; let banEnd = loginResponse.ban?.till.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "Unbekannt"
                     await MainActor.run { self.loginError = "Login fehlgeschlagen: Benutzer ist gebannt. Grund: \(banReason) (Bis: \(banEnd))" }
                     AuthService.logger.warning("Login failed: User \(username) is banned.");
                     await performLogoutCleanup()
                 } else {
                     await MainActor.run { self.loginError = loginResponse.error ?? "Falsche Anmeldedaten oder Captcha." }
                     AuthService.logger.warning("Login failed (API Error): \(self.loginError!) - User: \(username)")
                     if self.needsCaptcha { AuthService.logger.info("Fetching new captcha after failed login attempt."); await _fetchCaptcha() }
                     else { await performLogoutCleanup() }
                 }
            }
        } catch let error as URLError where error.code == .badServerResponse && error.localizedDescription.contains("status 400") {
             AuthService.logger.warning("Login failed with 400 Bad Request. Assuming incorrect credentials or captcha.")
             await MainActor.run { self.loginError = "Falsche Anmeldedaten oder Captcha."; self.needsCaptcha = true }
             await _fetchCaptcha()
        } catch {
             AuthService.logger.error("Login failed for \(username) with error: \(error.localizedDescription)")
             await MainActor.run { self.loginError = "Fehler beim Login: \(error.localizedDescription)" }
            await performLogoutCleanup()
        }
         await MainActor.run { isLoading = false }
         AuthService.logger.debug("Login attempt finished for \(username). isLoading: \(self.isLoading)")
    }

    func logout() async { // Unverändert
         var shouldProceed = false
         await MainActor.run {
             if self.isLoggedIn && !isLoading {
                 AuthService.logger.info("Attempting logout for user: \(self.currentUser?.name ?? "Unknown")")
                 isLoading = true
                 shouldProceed = true
             } else {
                 AuthService.logger.warning("Logout skipped: Not logged in or already loading.")
                 shouldProceed = false
             }
         }
         guard shouldProceed else { return }

        do { try await apiService.logout(); AuthService.logger.info("Logout successful via API.") }
        catch { AuthService.logger.error("API logout failed: \(error.localizedDescription). Proceeding with local cleanup.") }
        await performLogoutCleanup()
         await MainActor.run { isLoading = false }
         AuthService.logger.info("Logout process finished.")
    }

    func checkInitialLoginStatus() async { // Unverändert
        AuthService.logger.info("Checking initial login status...")
        await MainActor.run {
            // Reset states, but keep loaded votes/comment favs for now
            isLoading = true; self.userNonce = nil; self.favoritesCollectionId = nil; self.favoritedItemIDs = []
        }

        var sessionValidAndProfileLoaded = false
        var collectionLoaded = false
        var nonceAvailable = false
        var favoritesLoaded = false

        AuthService.logger.debug("[SESSION RESTORE START] Cookies BEFORE restoring from Keychain:")
        await logAllCookiesForPr0gramm()

        if await loadAndRestoreSessionCookie(), let username = keychainService.loadUsername(forKey: sessionUsernameKey) {
             AuthService.logger.info("Session cookie and username ('\(username)') restored from keychain.")
             AuthService.logger.debug("[SESSION RESTORE] Cookies AFTER restoring from Keychain (BEFORE nonce extraction):")
             await logAllCookiesForPr0gramm()
             let extractedNonce = await extractNonceFromCookieStorage()
             await MainActor.run { self.userNonce = extractedNonce }
             nonceAvailable = (self.userNonce != nil)

             sessionValidAndProfileLoaded = await loadProfileInfo(username: username, setLoadingState: false)
             if sessionValidAndProfileLoaded {
                 collectionLoaded = await fetchUserCollections()
                 if collectionLoaded {
                      favoritesLoaded = await loadInitialFavorites()
                      // Votes & Comment Favs already loaded in init
                 }
             }

             if !sessionValidAndProfileLoaded || !collectionLoaded || !favoritesLoaded || !nonceAvailable {
                 AuthService.logger.warning("Cookie/Username loaded, but subsequent fetch/sync failed. Profile: \(sessionValidAndProfileLoaded), Collections: \(collectionLoaded), Favorites: \(favoritesLoaded), Nonce: \(nonceAvailable). Session might be invalid.")
                 await performLogoutCleanup() // Cleanup includes clearing votes & comment favs
                 sessionValidAndProfileLoaded = false
                 collectionLoaded = false
                 nonceAvailable = false
                 favoritesLoaded = false
             }
        } else {
             AuthService.logger.info("No session cookie or username found in keychain.")
             await MainActor.run { self.currentUser = nil }
             sessionValidAndProfileLoaded = false; collectionLoaded = false; nonceAvailable = false; favoritesLoaded = false
             await performLogoutCleanup() // Cleanup includes clearing votes & comment favs
        }

         let finalIsLoggedIn = sessionValidAndProfileLoaded && collectionLoaded && favoritesLoaded && nonceAvailable
         await MainActor.run {
             self.isLoggedIn = finalIsLoggedIn
             if self.isLoggedIn {
                  AuthService.logger.info("Initial check: User \(self.currentUser!.name) is logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0). Initial Favs loaded: \(self.favoritedItemIDs.count). Initial Votes loaded: \(self.votedItemStates.count). Initial Comment Favs: \(self.favoritedCommentIDs.count)")
             } else {
                 AuthService.logger.info("Initial check: User is not logged in (or session/profile/collection/favorites load/nonce extraction failed).")
             }
             isLoading = false
         }
    }

    // MARK: - Voting Method (Unverändert)
    func performVote(itemId: Int, voteType: Int) async {
        guard isLoggedIn, let nonce = userNonce else {
            AuthService.logger.warning("Voting skipped: User not logged in or nonce missing.")
            return
        }
        guard !(isVoting[itemId] ?? false) else {
             AuthService.logger.debug("Voting skipped for item \(itemId): Already processing a vote.")
             return
        }

        let currentVote = votedItemStates[itemId] ?? 0
        let targetVote: Int

        if voteType == 1 { targetVote = (currentVote == 1) ? 0 : 1 }
        else if voteType == -1 { targetVote = (currentVote == -1) ? 0 : -1 }
        else { AuthService.logger.error("Invalid voteType \(voteType) passed to performVote."); return }

        let previousVoteState = votedItemStates[itemId]
        AuthService.logger.debug("Setting isVoting=true for \(itemId)")
        isVoting[itemId] = true
        votedItemStates[itemId] = targetVote
        AuthService.logger.debug("Optimistic UI: Set vote state for \(itemId) to \(targetVote).")

        defer { Task { @MainActor in AuthService.logger.debug("Setting isVoting=false for \(itemId) in defer block"); self.isVoting[itemId] = false } }

        do {
            try await apiService.vote(itemId: itemId, vote: targetVote, nonce: nonce)
            AuthService.logger.info("Successfully voted \(targetVote) for item \(itemId).")
            saveVotedStates()
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Voting failed for item \(itemId): Authentication required. Session might be invalid.")
            votedItemStates[itemId] = previousVoteState
            saveVotedStates()
            await logout()
        } catch {
            AuthService.logger.error("Voting failed for item \(itemId): \(error.localizedDescription)")
            votedItemStates[itemId] = previousVoteState
            saveVotedStates()
        }
    }

    // --- NEW: Method for comment favoriting ---
    func performCommentFavToggle(commentId: Int) async {
        guard isLoggedIn, let nonce = userNonce else {
            AuthService.logger.warning("Comment favoriting skipped: User not logged in or nonce missing.")
            return
        }
        guard !(isFavoritingComment[commentId] ?? false) else {
            AuthService.logger.debug("Comment favoriting skipped for comment \(commentId): Already processing.")
            return
        }

        let isCurrentlyFavorited = favoritedCommentIDs.contains(commentId)
        let targetState = !isCurrentlyFavorited

        AuthService.logger.debug("Setting isFavoritingComment=true for comment \(commentId)")
        isFavoritingComment[commentId] = true

        // Optimistic UI update
        if targetState {
            favoritedCommentIDs.insert(commentId)
            AuthService.logger.debug("Optimistic UI: Added comment \(commentId) to favorites.")
        } else {
            favoritedCommentIDs.remove(commentId)
            AuthService.logger.debug("Optimistic UI: Removed comment \(commentId) from favorites.")
        }
        saveFavoritedCommentIDs() // Save optimistic state immediately

        defer {
            Task { @MainActor in
                AuthService.logger.debug("Setting isFavoritingComment=false for comment \(commentId) in defer block")
                self.isFavoritingComment[commentId] = false
            }
        }

        do {
            if targetState {
                try await apiService.favComment(commentId: commentId, nonce: nonce)
                AuthService.logger.info("Successfully favorited comment \(commentId) via API.")
            } else {
                try await apiService.unfavComment(commentId: commentId, nonce: nonce)
                AuthService.logger.info("Successfully unfavorited comment \(commentId) via API.")
            }
            // API call successful, optimistic state is now confirmed.
            // No need to save again unless API returned an unexpected state.
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Comment favoriting failed for comment \(commentId): Authentication required. Session might be invalid.")
            // Rollback optimistic UI
            if targetState { favoritedCommentIDs.remove(commentId) }
            else { favoritedCommentIDs.insert(commentId) }
            saveFavoritedCommentIDs() // Save rolled-back state
            await logout()
        } catch {
            AuthService.logger.error("Comment favoriting failed for comment \(commentId): \(error.localizedDescription)")
            // Rollback optimistic UI
            if targetState { favoritedCommentIDs.remove(commentId) }
            else { favoritedCommentIDs.insert(commentId) }
            saveFavoritedCommentIDs() // Save rolled-back state
        }
    }
    // --- END NEW ---

    // MARK: - Private Helper Methods (Persistence, Cleanup, etc.)

    private func loadVotedStates() { // Unverändert
        if let savedVotes = UserDefaults.standard.dictionary(forKey: userVotesKey) as? [String: Int] {
            let loadedStates = Dictionary(uniqueKeysWithValues: savedVotes.compactMap { (key: String, value: Int) -> (Int, Int)? in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
            self.votedItemStates = loadedStates
            AuthService.logger.debug("Loaded \(loadedStates.count) vote states from UserDefaults.")
        } else {
            AuthService.logger.debug("No vote states found in UserDefaults or failed to load.")
            self.votedItemStates = [:]
        }
    }

    private func saveVotedStates() { // Unverändert
        let stringKeyedVotes = Dictionary(uniqueKeysWithValues: votedItemStates.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyedVotes, forKey: userVotesKey)
        AuthService.logger.trace("Saved \(stringKeyedVotes.count) vote states to UserDefaults.")
    }

    // --- NEW: Persistence for favorited comment IDs ---
    private func loadFavoritedCommentIDs() {
        if let savedIDs = UserDefaults.standard.array(forKey: favoritedCommentsKey) as? [Int] {
            self.favoritedCommentIDs = Set(savedIDs)
            AuthService.logger.debug("Loaded \(self.favoritedCommentIDs.count) favorited comment IDs from UserDefaults.")
        } else {
            AuthService.logger.debug("No favorited comment IDs found in UserDefaults or failed to load.")
            self.favoritedCommentIDs = []
        }
    }

    private func saveFavoritedCommentIDs() {
        let idsToSave = Array(self.favoritedCommentIDs)
        UserDefaults.standard.set(idsToSave, forKey: favoritedCommentsKey)
        AuthService.logger.trace("Saved \(idsToSave.count) favorited comment IDs to UserDefaults.")
    }
    // --- END NEW ---


    @discardableResult
    private func loadInitialFavorites() async -> Bool { // Unverändert
        AuthService.logger.info("Loading initial set of favorite item IDs...")
        guard let username = self.currentUser?.name else {
             AuthService.logger.warning("Cannot load initial favorites: currentUser is nil.")
             return false
        }
        await MainActor.run { self.favoritedItemIDs = [] } // Reset before loading

        var allFavorites: [Item] = []
        var olderThanId: Int? = nil
        var fetchError: Error? = nil
        let maxPages = 10
        var pagesFetched = 0

        do {
            while pagesFetched < maxPages {
                 AuthService.logger.debug("Fetching favorites page \(pagesFetched + 1) for initial load (older: \(olderThanId ?? -1))...")
                 let fetchedItems = try await apiService.fetchFavorites(username: username, flags: 1, olderThanId: olderThanId)
                 if fetchedItems.isEmpty {
                      AuthService.logger.debug("Reached end of favorites feed during initial load.")
                      break
                 }
                 allFavorites.append(contentsOf: fetchedItems)
                 olderThanId = fetchedItems.last?.id
                 pagesFetched += 1
            }
        } catch {
            AuthService.logger.error("Error fetching favorites during initial load: \(error.localizedDescription)")
            fetchError = error
        }

        let finalIDs = Set(allFavorites.map { $0.id })
        await MainActor.run { self.favoritedItemIDs = finalIDs }
        AuthService.logger.info("Finished loading initial favorites. Loaded \(finalIDs.count) IDs across \(pagesFetched) pages. Error encountered: \(fetchError != nil)")
        return fetchError == nil || !finalIDs.isEmpty
    }

    @discardableResult
    private func loadProfileInfo(username: String, setLoadingState: Bool = true) async -> Bool { // Unverändert
        AuthService.logger.debug("Attempting to load profile info for \(username)...")
        if setLoadingState { await MainActor.run { isLoading = true } }
        await MainActor.run { loginError = nil; self.currentUser = nil }

        do {
            let profileInfoResponse = try await apiService.getProfileInfo(username: username, flags: 31)
            let newUserInfo = UserInfo(
                id: profileInfoResponse.user.id, name: profileInfoResponse.user.name,
                registered: profileInfoResponse.user.registered, score: profileInfoResponse.user.score,
                mark: profileInfoResponse.user.mark, badges: profileInfoResponse.badges
            )
            await MainActor.run { self.currentUser = newUserInfo }
            AuthService.logger.info("Successfully created UserInfo for: \(newUserInfo.name) with \(newUserInfo.badges?.count ?? 0) badges.")
            if setLoadingState { await MainActor.run { isLoading = false } }
            return true
        } catch {
            AuthService.logger.warning("Failed to load or create profile info for \(username): \(error.localizedDescription).")
            await MainActor.run { self.currentUser = nil; if setLoadingState { isLoading = false } }
            return false
        }
    }

    @discardableResult
    private func fetchUserCollections() async -> Bool { // Unverändert
        AuthService.logger.info("Fetching user collections to find favorites ID...")
        await MainActor.run { self.favoritesCollectionId = nil }

        do {
            let response = try await apiService.getUserCollections()
            var foundId: Int? = nil
            if let favCollection = response.collections.first(where: { $0.isDefault == 1 }) {
                foundId = favCollection.id
                AuthService.logger.info("Found default favorites collection: ID \(favCollection.id), Name '\(favCollection.name)'")
            }
            else if let favCollectionByKeyword = response.collections.first(where: { $0.keyword == "favoriten"}) {
                foundId = favCollectionByKeyword.id
                AuthService.logger.warning("Found favorites collection by keyword 'favoriten' (not marked as default): ID \(favCollectionByKeyword.id), Name '\(favCollectionByKeyword.name)'")
            }
            else { AuthService.logger.error("Could not find default favorites collection (isDefault=1 or keyword='favoriten') in user collections response.") }

            if let id = foundId { await MainActor.run { self.favoritesCollectionId = id }; return true }
            else { return false }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Failed to fetch user collections: Authentication required. Session might be invalid.")
            return false
        } catch {
            AuthService.logger.error("Failed to fetch user collections: \(error.localizedDescription)")
            return false
        }
    }

    private func _fetchCaptcha() async { // Unverändert
        AuthService.logger.info("Fetching new captcha data...")
        await MainActor.run { self.captchaImage = nil; self.captchaToken = nil; self.loginError = nil }
        do {
            let captchaResponse = try await apiService.fetchCaptcha();
            let token = captchaResponse.token; var base64String = captchaResponse.captcha
            if let commaRange = base64String.range(of: ",") { base64String = String(base64String[commaRange.upperBound...]); AuthService.logger.debug("Removed base64 prefix.") }
            else { AuthService.logger.debug("No base64 prefix found.") }

            var decodedImage: UIImage? = nil; var decodeError: String? = nil
            if let imageData = Data(base64Encoded: base64String) {
                decodedImage = UIImage(data: imageData)
                 if decodedImage == nil { decodeError = "Captcha konnte nicht angezeigt werden."; AuthService.logger.error("Failed to create UIImage from decoded captcha data.") }
                 else { AuthService.logger.info("Successfully decoded captcha image.") }
            } else { decodeError = "Captcha konnte nicht dekodiert werden."; AuthService.logger.error("Failed to decode base64 captcha string.") }

            await MainActor.run { self.captchaToken = token; self.captchaImage = decodedImage; self.loginError = decodeError }
        } catch {
             AuthService.logger.error("Failed to fetch captcha: \(error.localizedDescription)")
             await MainActor.run { self.loginError = "Captcha konnte nicht geladen werden." }
        }
    }

    private func performLogoutCleanup() async { // Updated to clear comment favs
        AuthService.logger.debug("Performing local logout cleanup.")
        await MainActor.run {
            self.isLoggedIn = false; self.currentUser = nil; self.userNonce = nil;
            self.favoritesCollectionId = nil; self.needsCaptcha = false; self.captchaToken = nil;
            self.captchaImage = nil; self.favoritedItemIDs = [];
            self.votedItemStates = [:]; self.isVoting = [:]
            // --- NEW: Clear comment favs ---
            self.favoritedCommentIDs = []; self.isFavoritingComment = [:]
            // --- END NEW ---
            self.appSettings.showSFW = true; self.appSettings.showNSFW = false; self.appSettings.showNSFL = false;
            self.appSettings.showNSFP = false; self.appSettings.showPOL = false
        }
        await clearCookies()
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)
        UserDefaults.standard.removeObject(forKey: userVotesKey)
        // --- NEW: Remove persisted comment favs ---
        UserDefaults.standard.removeObject(forKey: favoritedCommentsKey)
        // --- END NEW ---
        AuthService.logger.info("Reset content filters to SFW-only and cleared persisted votes and comment favorites.")
    }

    private func clearCookies() async { // Unverändert
        AuthService.logger.debug("Clearing cookies for pr0gramm.com domain.")
        guard let url = URL(string: "https://pr0gramm.com") else { return }
        await MainActor.run {
            guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
            AuthService.logger.debug("Found \(cookies.count) cookies for domain to potentially clear.")
            for cookie in cookies {
                 AuthService.logger.debug("Deleting cookie: Name='\(cookie.name)', Value='\(cookie.value.prefix(50))...', Domain='\(cookie.domain)', Path='\(cookie.path)'")
                 HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        AuthService.logger.info("Finished clearing cookies.")
    }

    @discardableResult
    private func findAndSaveSessionCookie() async -> Bool { // Unverändert
         AuthService.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
         guard let url = URL(string: "https://pr0gramm.com") else { return false }
         guard let sessionCookie = await MainActor.run(body: { HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName }) }) else { AuthService.logger.warning("Could not retrieve cookies or session cookie '\(self.sessionCookieName)' not found."); return false }
        let cookieValue = sessionCookie.value; let parts = cookieValue.split(separator: ":")
        if parts.count != 2 { AuthService.logger.warning("Session cookie '\(self.sessionCookieName)' found but value '\(cookieValue.prefix(50))...' does NOT have expected 'id:nonce' format! Saving it anyway.") } else { AuthService.logger.info("Found session cookie '\(self.sessionCookieName)' with expected format. Value: '\(cookieValue.prefix(50))...'.") }
        guard let properties = sessionCookie.properties else { AuthService.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
         AuthService.logger.info("Saving cookie properties to keychain...")
         return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    private func loadAndRestoreSessionCookie() async -> Bool { // Unverändert
        AuthService.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { AuthService.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { AuthService.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
         await MainActor.run { HTTPCookieStorage.shared.setCookie(restoredCookie) }
         AuthService.logger.info("Successfully restored session cookie '\(restoredCookie.name)' with value '\(restoredCookie.value.prefix(50))...' into HTTPCookieStorage.")
        return true
    }

    private func extractNonceFromCookieStorage() async -> String? { // Unverändert
        AuthService.logger.debug("Attempting to extract nonce from cookie storage (trying JSON format first, then shorten)...")
         guard let url = URL(string: "https://pr0gramm.com") else { return nil }
         guard let sessionCookie = await MainActor.run(body: { HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName }) }) else { AuthService.logger.warning("Could not find session cookie named '\(self.sessionCookieName)' in storage."); return nil }
        let cookieValue = sessionCookie.value; AuthService.logger.debug("[EXTRACT NONCE] Found session cookie '\(self.sessionCookieName)' with value: \(cookieValue)")
        AuthService.logger.debug("[EXTRACT NONCE] Attempting URL-decoded JSON parsing...")
        if let decodedValue = cookieValue.removingPercentEncoding, let jsonData = decodedValue.data(using: .utf8) {
            do {
                if let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any], let longNonceFromJson = jsonDict["id"] as? String {
                    AuthService.logger.debug("[EXTRACT NONCE] Found 'id' field in JSON: \(longNonceFromJson)"); let expectedNonceLength = 16
                    if longNonceFromJson.count >= expectedNonceLength { let shortNonce = String(longNonceFromJson.prefix(expectedNonceLength)); AuthService.logger.info("[EXTRACT NONCE] Successfully extracted and shortened nonce from JSON 'id' field: '\(shortNonce)'"); return shortNonce }
                    else { AuthService.logger.warning("[EXTRACT NONCE] Nonce from JSON 'id' field is shorter than expected length (\(expectedNonceLength)): '\(longNonceFromJson)'"); return nil }
                } else { AuthService.logger.warning("[EXTRACT NONCE] Failed to parse URL-decoded cookie value as JSON Dictionary or find 'id' key."); return nil }
            } catch { AuthService.logger.warning("[EXTRACT NONCE] Error parsing URL-decoded cookie value as JSON: \(error.localizedDescription)"); return nil }
        } else { AuthService.logger.warning("[EXTRACT NONCE] Failed to URL-decode cookie value or convert to Data."); return nil }
    }

    private func logAllCookiesForPr0gramm() async { // Unverändert
        guard let url = URL(string: "https://pr0gramm.com") else { return }
         AuthService.logger.debug("--- Current Cookies for \(url.host ?? "pr0gramm.com") ---")
         let cookies = await MainActor.run { HTTPCookieStorage.shared.cookies(for: url) }
        if let cookies = cookies, !cookies.isEmpty { for cookie in cookies { AuthService.logger.debug("- Name: \(cookie.name), Value: \(cookie.value.prefix(60))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path), Secure: \(cookie.isSecure), HTTPOnly: \(cookie.isHTTPOnly)") } }
        else { AuthService.logger.debug("(No cookies found for domain)") }
         AuthService.logger.debug("--- End Cookie List ---")
    }
}
// --- END OF COMPLETE FILE ---
