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
    private let favoritedCommentsKey = "pr0grammFavoritedComments_v1"
    private let userCommentVotesKey = "pr0grammUserCommentVotes_v1"

    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserInfo? = nil
    @Published var userNonce: String? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loginError: String? = nil
    @Published private(set) var needsCaptcha: Bool = false
    @Published private(set) var captchaToken: String? = nil
    @Published private(set) var captchaImage: UIImage? = nil

    @Published var favoritedItemIDs: Set<Int> = []
    @Published var votedItemStates: [Int: Int] = [:]
    @Published private(set) var isVoting: [Int: Bool] = [:]

    @Published var favoritedCommentIDs: Set<Int> = []
    @Published private(set) var isFavoritingComment: [Int: Bool] = [:]

    @Published var votedCommentStates: [Int: Int] = [:]
    @Published private(set) var isVotingComment: [Int: Bool] = [:]
    
    @Published var unreadMessageCount: Int = 0
    @Published private(set) var userCollections: [ApiCollection] = []

    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        loadVotedStates()
        loadFavoritedCommentIDs()
        loadVotedCommentStates()
        AuthService.logger.info("AuthService initialized. Loaded \(self.votedItemStates.count) item vote states, \(self.votedCommentStates.count) comment vote states, and \(self.favoritedCommentIDs.count) favorited comment IDs.")
    }

    #if DEBUG
    func setUserCollectionsForPreview(_ collections: [ApiCollection]) {
        self.userCollections = collections
    }
    #endif


    func fetchInitialCaptcha() async {
        AuthService.logger.info("fetchInitialCaptcha called by LoginView.")
        await MainActor.run { self.needsCaptcha = true }
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        guard !isLoading else { AuthService.logger.warning("Login attempt skipped: Already loading."); return }
        AuthService.logger.info("Attempting login for user: \(username)")
        await MainActor.run {
            isLoading = true; loginError = nil; self.userNonce = nil; self.favoritedItemIDs = []; self.votedItemStates = [:]; self.isVoting = [:]
            self.favoritedCommentIDs = []; self.isFavoritingComment = [:]
            self.votedCommentStates = [:]; self.isVotingComment = [:]
            self.unreadMessageCount = 0
            self.userCollections = []
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
                let profileAndCollectionsLoaded = await loadProfileInfoAndCollections(username: username, setLoadingState: false)
                var favoritesLoaded = false
                var countLoaded = false

                if profileAndCollectionsLoaded {
                    if let defaultCollection = self.userCollections.first(where: { $0.isActuallyDefault }) {
                        self.appSettings.selectedCollectionIdForFavorites = defaultCollection.id
                        AuthService.logger.info("Default collection ID \(defaultCollection.id) ('\(defaultCollection.name)') set in AppSettings.")
                    } else if let firstCollection = self.userCollections.first {
                        self.appSettings.selectedCollectionIdForFavorites = firstCollection.id
                        AuthService.logger.warning("No default collection found. Using first available collection ID \(firstCollection.id) ('\(firstCollection.name)') for AppSettings.")
                    } else {
                        self.appSettings.selectedCollectionIdForFavorites = nil
                        AuthService.logger.warning("No collections found for user. selectedCollectionIdForFavorites set to nil.")
                    }
                    // --- MODIFIED: Set isLoggedIn earlier ---
                    await MainActor.run { self.isLoggedIn = true } // Set preliminary loggedIn status
                    // --- END MODIFICATION ---

                    if self.appSettings.selectedCollectionIdForFavorites != nil {
                        favoritesLoaded = await loadInitialFavorites()
                    } else {
                        favoritesLoaded = true
                        AuthService.logger.info("Skipping initial favorites load as no collection ID is selected.")
                    }
                    loadVotedStates()
                    loadFavoritedCommentIDs()
                    loadVotedCommentStates()
                    countLoaded = await updateUnreadCount() // Now isLoggedIn should be true here
                    AuthService.logger.info("Loaded states after successful login. Votes: \(self.votedItemStates.count), Comment Favs: \(self.favoritedCommentIDs.count), Comment Votes: \(self.votedCommentStates.count), Unread: \(self.unreadMessageCount), Collections: \(self.userCollections.count)")
                }

                // Final check if all steps were successful
                let finalLoginSuccess = profileAndCollectionsLoaded && favoritesLoaded && countLoaded && self.userNonce != nil
                await MainActor.run { self.isLoggedIn = finalLoginSuccess } // Set final isLoggedIn status

                if finalLoginSuccess {
                    AuthService.logger.debug("[LOGIN SUCCESS] Cookies BEFORE saving to Keychain:")
                    await logAllCookiesForPr0gramm()
                    let cookieSaved = await findAndSaveSessionCookie()
                    let usernameSaved = keychainService.saveUsername(username, forKey: sessionUsernameKey)

                    await MainActor.run {
                        if cookieSaved && usernameSaved { AuthService.logger.info("Session cookie and username saved to keychain.") }
                        else { AuthService.logger.warning("Failed to save session cookie (\(cookieSaved)) or username (\(usernameSaved)) to keychain.") }
                        // self.isLoggedIn = true // Already set above
                        self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
                        AuthService.logger.info("User \(self.currentUser!.name) is now logged in. Nonce: \(self.userNonce != nil), SelectedFavColID: \(self.appSettings.selectedCollectionIdForFavorites ?? -1), Badges: \(self.currentUser?.badges?.count ?? 0), ItemFavs: \(self.favoritedItemIDs.count), Votes: \(self.votedItemStates.count), CommentFavs: \(self.favoritedCommentIDs.count), CommentVotes: \(self.votedCommentStates.count), Unread: \(self.unreadMessageCount), Collections: \(self.userCollections.count)")
                    }
                } else {
                    await MainActor.run {
                        // self.isLoggedIn = false; // Already set to false by finalLoginSuccess
                        if !profileAndCollectionsLoaded { self.loginError = "Login erfolgreich, aber Profildaten/Sammlungen konnten nicht geladen werden." }
                        else if !favoritesLoaded { self.loginError = "Login erfolgreich, aber Favoriten konnten nicht initial geladen werden." }
                        else if !countLoaded { self.loginError = "Login erfolgreich, aber Nachrichtenzähler konnte nicht geladen werden." }
                        else { self.loginError = "Login erfolgreich, aber Session-Daten (Nonce) konnten nicht gelesen werden." }
                        AuthService.logger.error("Login sequence failed. Profile/Collections: \(profileAndCollectionsLoaded), Favorites: \(favoritesLoaded), Count: \(countLoaded), Nonce: \(self.userNonce != nil)")
                    }
                    await performLogoutCleanup() // This will also set isLoggedIn to false
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

    func logout() async {
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

    func checkInitialLoginStatus() async {
        AuthService.logger.info("Checking initial login status...")
        await MainActor.run {
            isLoading = true; self.userNonce = nil; self.favoritedItemIDs = []
            self.isLoggedIn = false // Start with logged out state
        }

        var profileAndCollectionsLoaded = false
        var nonceAvailable = false
        var favoritesLoaded = false
        var countLoaded = false
        var finalIsLoggedIn = false // Variable to determine the final login state

        AuthService.logger.debug("[SESSION RESTORE START] Cookies BEFORE restoring from Keychain:")
        await logAllCookiesForPr0gramm()

        if await loadAndRestoreSessionCookie(), let username = keychainService.loadUsername(forKey: sessionUsernameKey) {
             AuthService.logger.info("Session cookie and username ('\(username)') restored from keychain.")
             AuthService.logger.debug("[SESSION RESTORE] Cookies AFTER restoring from Keychain (BEFORE nonce extraction):")
             await logAllCookiesForPr0gramm()
             let extractedNonce = await extractNonceFromCookieStorage()
             await MainActor.run { self.userNonce = extractedNonce }
             nonceAvailable = (self.userNonce != nil)

             profileAndCollectionsLoaded = await loadProfileInfoAndCollections(username: username, setLoadingState: false)
             if profileAndCollectionsLoaded && nonceAvailable { // Only proceed if profile and nonce are good
                // --- MODIFIED: Set isLoggedIn to true before loading dependent data ---
                await MainActor.run { self.isLoggedIn = true }
                // --- END MODIFICATION ---

                 if self.appSettings.selectedCollectionIdForFavorites == nil {
                     if let defaultCollection = self.userCollections.first(where: { $0.isActuallyDefault }) {
                         self.appSettings.selectedCollectionIdForFavorites = defaultCollection.id
                         AuthService.logger.info("Default collection ID \(defaultCollection.id) ('\(defaultCollection.name)') set in AppSettings during initial check.")
                     } else if let firstCollection = self.userCollections.first {
                         self.appSettings.selectedCollectionIdForFavorites = firstCollection.id
                         AuthService.logger.warning("No default collection found. Using first available collection ID \(firstCollection.id) ('\(firstCollection.name)') for AppSettings during initial check.")
                     } else {
                         AuthService.logger.warning("No collections found for user during initial check. selectedCollectionIdForFavorites remains nil.")
                     }
                 } else {
                      AuthService.logger.info("Using previously selected collection ID \(self.appSettings.selectedCollectionIdForFavorites!) from AppSettings during initial check.")
                 }

                 if self.appSettings.selectedCollectionIdForFavorites != nil {
                     favoritesLoaded = await loadInitialFavorites()
                 } else {
                     favoritesLoaded = true
                     AuthService.logger.info("Skipping initial favorites load as no collection ID is selected during initial check.")
                 }
                 countLoaded = await updateUnreadCount() // Now isLoggedIn should be true here
                 
                 finalIsLoggedIn = profileAndCollectionsLoaded && favoritesLoaded && nonceAvailable && countLoaded
             }
        }
        
        if !finalIsLoggedIn { // If any step failed or no initial session
            AuthService.logger.info("Initial login check determined user is NOT logged in or session data incomplete.")
            await performLogoutCleanup() // Ensure clean state if not fully logged in
        }

         await MainActor.run {
             self.isLoggedIn = finalIsLoggedIn // Set the final determined state
             if self.isLoggedIn {
                  AuthService.logger.info("Initial check: User \(self.currentUser!.name) is logged in. Nonce: \(self.userNonce != nil), SelectedFavColID: \(self.appSettings.selectedCollectionIdForFavorites ?? -1), Badges: \(self.currentUser?.badges?.count ?? 0), ItemFavs: \(self.favoritedItemIDs.count), Votes: \(self.votedItemStates.count), CommentFavs: \(self.favoritedCommentIDs.count), CommentVotes: \(self.votedCommentStates.count), Unread: \(self.unreadMessageCount), Collections: \(self.userCollections.count)")
             } else {
                 AuthService.logger.info("Initial check: User is not logged in (final determination).")
             }
             isLoading = false
         }
    }

    // ... (Rest of AuthService, including performVote, performCommentFavToggle, etc., unchanged from previous correct version) ...

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

        if targetState {
            favoritedCommentIDs.insert(commentId)
            AuthService.logger.debug("Optimistic UI: Added comment \(commentId) to favorites.")
        } else {
            favoritedCommentIDs.remove(commentId)
            AuthService.logger.debug("Optimistic UI: Removed comment \(commentId) from favorites.")
        }
        saveFavoritedCommentIDs()

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
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Comment favoriting failed for comment \(commentId): Authentication required. Session might be invalid.")
            if targetState { favoritedCommentIDs.remove(commentId) } else { favoritedCommentIDs.insert(commentId) }
            saveFavoritedCommentIDs()
            await logout()
        } catch {
            AuthService.logger.error("Comment favoriting failed for comment \(commentId): \(error.localizedDescription)")
            if targetState { favoritedCommentIDs.remove(commentId) } else { favoritedCommentIDs.insert(commentId) }
            saveFavoritedCommentIDs()
        }
    }

    func performCommentVote(commentId: Int, voteType: Int) async {
        guard isLoggedIn, let nonce = userNonce else {
            AuthService.logger.warning("Comment voting skipped: User not logged in or nonce missing.")
            return
        }
        guard !(isVotingComment[commentId] ?? false) else {
            AuthService.logger.debug("Comment voting skipped for comment \(commentId): Already processing a vote.")
            return
        }

        let currentVote = votedCommentStates[commentId] ?? 0
        let targetVote: Int

        if voteType == 1 { targetVote = (currentVote == 1) ? 0 : 1 }
        else if voteType == -1 { targetVote = (currentVote == -1) ? 0 : -1 }
        else { AuthService.logger.error("Invalid voteType \(voteType) passed to performCommentVote."); return }

        let previousVoteState = votedCommentStates[commentId]

        AuthService.logger.debug("Setting isVotingComment=true for comment \(commentId)")
        isVotingComment[commentId] = true
        votedCommentStates[commentId] = targetVote
        AuthService.logger.debug("Optimistic UI: Set comment vote state for \(commentId) to \(targetVote).")

        defer {
            Task { @MainActor in
                AuthService.logger.debug("Setting isVotingComment=false for comment \(commentId) in defer block")
                self.isVotingComment[commentId] = false
            }
        }

        do {
            try await apiService.voteComment(commentId: commentId, vote: targetVote, nonce: nonce)
            AuthService.logger.info("Successfully voted \(targetVote) for comment \(commentId).")
            saveVotedCommentStates()
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Comment voting failed for comment \(commentId): Authentication required. Session might be invalid.")
            votedCommentStates[commentId] = previousVoteState
            saveVotedCommentStates()
            await logout()
        } catch {
            AuthService.logger.error("Comment voting failed for comment \(commentId): \(error.localizedDescription)")
            votedCommentStates[commentId] = previousVoteState
            saveVotedCommentStates()
        }
    }


    @discardableResult
    func updateUnreadCount() async -> Bool {
        guard isLoggedIn else {
            AuthService.logger.debug("Skipping unread count update: User not logged in.")
            if unreadMessageCount != 0 {
                await MainActor.run { self.unreadMessageCount = 0 }
            }
            return true
        }
        AuthService.logger.debug("Updating unread message count...")
        do {
            let response = try await apiService.fetchInboxMessages(older: nil)
            guard !Task.isCancelled else { return false }
            let newCount = response.queue?.total ?? 0
            await MainActor.run {
                if self.unreadMessageCount != newCount {
                     self.unreadMessageCount = newCount
                     AuthService.logger.info("Unread message count updated to: \(newCount)")
                } else {
                     AuthService.logger.debug("Unread message count remains: \(newCount)")
                }
            }
            return true
        } catch {
            AuthService.logger.error("Failed to update unread message count: \(error.localizedDescription)")
            return false
        }
    }

    private func loadVotedStates() {
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

    private func saveVotedStates() {
        let stringKeyedVotes = Dictionary(uniqueKeysWithValues: votedItemStates.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyedVotes, forKey: userVotesKey)
        AuthService.logger.trace("Saved \(stringKeyedVotes.count) vote states to UserDefaults.")
    }

    private func loadVotedCommentStates() {
        if let savedVotes = UserDefaults.standard.dictionary(forKey: userCommentVotesKey) as? [String: Int] {
            let loadedStates = Dictionary(uniqueKeysWithValues: savedVotes.compactMap { (key: String, value: Int) -> (Int, Int)? in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
            self.votedCommentStates = loadedStates
            AuthService.logger.debug("Loaded \(loadedStates.count) comment vote states from UserDefaults.")
        } else {
            AuthService.logger.debug("No comment vote states found in UserDefaults or failed to load.")
            self.votedCommentStates = [:]
        }
    }

    private func saveVotedCommentStates() {
        let stringKeyedVotes = Dictionary(uniqueKeysWithValues: votedCommentStates.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyedVotes, forKey: userCommentVotesKey)
        AuthService.logger.trace("Saved \(stringKeyedVotes.count) comment vote states to UserDefaults.")
    }


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

    @discardableResult
    private func loadInitialFavorites() async -> Bool {
        AuthService.logger.info("Loading initial set of favorite item IDs...")
        guard let username = self.currentUser?.name,
              let selectedCollectionID = self.appSettings.selectedCollectionIdForFavorites,
              let selectedCollection = self.userCollections.first(where: { $0.id == selectedCollectionID }),
              let collectionKeyword = selectedCollection.keyword else {
            AuthService.logger.warning("Cannot load initial favorites: currentUser, selectedCollectionIdForFavorites, or collection keyword is nil.")
            return false
        }
        await MainActor.run { self.favoritedItemIDs = [] }

        var allFavorites: [Item] = []
        var olderThanId: Int? = nil
        var fetchError: Error? = nil
        let maxPages = 10
        var pagesFetched = 0

        do {
            while pagesFetched < maxPages {
                AuthService.logger.debug("Fetching favorites page \(pagesFetched + 1) for collection '\(collectionKeyword)' (older: \(olderThanId ?? -1))...")
                let fetchedItems = try await apiService.fetchFavorites(
                    username: username,
                    collectionKeyword: collectionKeyword,
                    flags: 1,
                    olderThanId: olderThanId
                )
                if fetchedItems.isEmpty {
                    AuthService.logger.debug("Reached end of favorites feed (collection '\(collectionKeyword)') during initial load.")
                    break
                }
                allFavorites.append(contentsOf: fetchedItems)
                olderThanId = fetchedItems.last?.id
                pagesFetched += 1
            }
        } catch {
            AuthService.logger.error("Error fetching favorites (collection '\(collectionKeyword)') during initial load: \(error.localizedDescription)")
            fetchError = error
        }

        let finalIDs = Set(allFavorites.map { $0.id })
        await MainActor.run { self.favoritedItemIDs = finalIDs }
        AuthService.logger.info("Finished loading initial favorites for collection '\(collectionKeyword)'. Loaded \(finalIDs.count) IDs across \(pagesFetched) pages. Error encountered: \(fetchError != nil)")
        return fetchError == nil || !finalIDs.isEmpty
    }

    @discardableResult
    private func loadProfileInfoAndCollections(username: String, setLoadingState: Bool = true) async -> Bool {
        AuthService.logger.debug("Attempting to load profile info and collections for \(username)...")
        if setLoadingState { await MainActor.run { isLoading = true } }
        await MainActor.run { loginError = nil; self.currentUser = nil; self.userCollections = [] }

        do {
            let profileInfoResponse = try await apiService.getProfileInfo(username: username, flags: 31)
            
            let newUserInfo = UserInfo(
                id: profileInfoResponse.user.id, name: profileInfoResponse.user.name,
                registered: profileInfoResponse.user.registered, score: profileInfoResponse.user.score,
                mark: profileInfoResponse.user.mark, badges: profileInfoResponse.badges,
                collections: nil
            )
            
            await MainActor.run {
                self.currentUser = newUserInfo
                self.userCollections = profileInfoResponse.collections ?? []
                self.currentUser?.collections = self.userCollections
            }
            AuthService.logger.info("Successfully created UserInfo for: \(newUserInfo.name) with \(newUserInfo.badges?.count ?? 0) badges and \(self.userCollections.count) collections.")
            if setLoadingState { await MainActor.run { isLoading = false } }
            return true
        } catch {
            AuthService.logger.warning("Failed to load or create profile info/collections for \(username): \(error.localizedDescription).")
            await MainActor.run { self.currentUser = nil; self.userCollections = []; if setLoadingState { isLoading = false } }
            return false
        }
    }
    
    @discardableResult
    private func fetchUserCollections() async -> Bool {
        AuthService.logger.info("Fetching user collections (via dedicated call if needed)...")
        guard let username = currentUser?.name else {
             AuthService.logger.warning("Cannot fetch user collections: currentUser is nil.")
             return false
        }
        if !self.userCollections.isEmpty {
            AuthService.logger.info("User collections already loaded (\(self.userCollections.count) found). Skipping redundant fetchUserCollections call.")
            return true
        }
        
        AuthService.logger.warning("User collections were not loaded via profile/info. Attempting old /collections/get.")
        await MainActor.run { self.userCollections = [] }

        do {
            let response = try await apiService.getUserCollections()
            await MainActor.run { self.userCollections = response.collections }
            AuthService.logger.info("Fetched \(response.collections.count) collections using OLD /collections/get API for \(username).")
            
            if self.currentUser != nil {
                self.currentUser?.collections = response.collections
            }
            return true
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Failed to fetch user collections (old API): Authentication required. Session might be invalid.")
            return false
        } catch {
            AuthService.logger.error("Failed to fetch user collections (old API): \(error.localizedDescription)")
            return false
        }
    }


    private func _fetchCaptcha() async {
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

    private func performLogoutCleanup() async {
        AuthService.logger.debug("Performing local logout cleanup.")
        let usernameToClearCache = self.currentUser?.name
        let collectionIdToClearCache = self.appSettings.selectedCollectionIdForFavorites

        await MainActor.run {
            self.isLoggedIn = false; self.currentUser = nil; self.userNonce = nil;
            self.needsCaptcha = false; self.captchaToken = nil;
            self.captchaImage = nil; self.favoritedItemIDs = [];
            self.votedItemStates = [:]; self.isVoting = [:]
            self.favoritedCommentIDs = []; self.isFavoritingComment = [:]
            self.votedCommentStates = [:]; self.isVotingComment = [:]
            self.unreadMessageCount = 0
            self.userCollections = []
            self.appSettings.selectedCollectionIdForFavorites = nil
            self.appSettings.showSFW = true; self.appSettings.showNSFW = false; self.appSettings.showNSFL = false;
            self.appSettings.showNSFP = false; self.appSettings.showPOL = false
        }
        await clearCookies()
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)
        UserDefaults.standard.removeObject(forKey: userVotesKey)
        UserDefaults.standard.removeObject(forKey: favoritedCommentsKey)
        UserDefaults.standard.removeObject(forKey: userCommentVotesKey)
        
        await self.appSettings.clearFavoritesCache(username: usernameToClearCache, collectionId: collectionIdToClearCache)
        AuthService.logger.info("Reset content filters to SFW-only and cleared persisted item votes, comment favorites, and comment votes. Cleared collections data and favorites cache.")
    }

    private func clearCookies() async {
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
    private func findAndSaveSessionCookie() async -> Bool {
         AuthService.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
         guard let url = URL(string: "https://pr0gramm.com") else { return false }
         guard let sessionCookie = await MainActor.run(body: { HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName }) }) else { AuthService.logger.warning("Could not retrieve cookies or session cookie '\(self.sessionCookieName)' not found."); return false }
        let cookieValue = sessionCookie.value; let parts = cookieValue.split(separator: ":")
        if parts.count != 2 { AuthService.logger.warning("Session cookie '\(self.sessionCookieName)' found but value '\(cookieValue.prefix(50))...' does NOT have expected 'id:nonce' format! Saving it anyway.") } else { AuthService.logger.info("Found session cookie '\(self.sessionCookieName)' with expected format. Value: '\(cookieValue.prefix(50))...'.") }
        guard let properties = sessionCookie.properties else { AuthService.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
         AuthService.logger.info("Saving cookie properties to keychain...")
         return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    private func loadAndRestoreSessionCookie() async -> Bool {
        AuthService.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { AuthService.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { AuthService.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
         await MainActor.run { HTTPCookieStorage.shared.setCookie(restoredCookie) }
         AuthService.logger.info("Successfully restored session cookie '\(restoredCookie.name)' with value '\(restoredCookie.value.prefix(50))...' into HTTPCookieStorage.")
        return true
    }

    private func extractNonceFromCookieStorage() async -> String? {
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

    private func logAllCookiesForPr0gramm() async {
        guard let url = URL(string: "https://pr0gramm.com") else { return }
         AuthService.logger.debug("--- Current Cookies for \(url.host ?? "pr0gramm.com") ---")
         let cookies = await MainActor.run { HTTPCookieStorage.shared.cookies(for: url) }
        if let cookies = cookies, !cookies.isEmpty { for cookie in cookies { AuthService.logger.debug("- Name: \(cookie.name), Value: \(cookie.value.prefix(60))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path), Secure: \(cookie.isSecure), HTTPOnly: \(cookie.isHTTPOnly)") } }
        else { AuthService.logger.debug("(No cookies found for domain)") }
         AuthService.logger.debug("--- End Cookie List ---")
    }
}
// --- END OF COMPLETE FILE ---
