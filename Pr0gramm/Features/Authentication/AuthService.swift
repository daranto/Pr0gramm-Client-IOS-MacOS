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
    private let userVotesKey = "pr0grammUserVotes_v1" // Key for UserDefaults

    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserInfo? = nil // Includes badges
    @Published var userNonce: String? = nil // Wird jetzt aus JSON Cookie ID extrahiert & gekürzt
    @Published var favoritesCollectionId: Int? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loginError: String? = nil
    @Published private(set) var needsCaptcha: Bool = false
    @Published private(set) var captchaToken: String? = nil
    @Published private(set) var captchaImage: UIImage? = nil

    @Published var favoritedItemIDs: Set<Int> = []
    // --- NEW: State for Item Votes ---
    @Published var votedItemStates: [Int: Int] = [:] // ItemID -> Vote (-1, 0, 1)
    @Published private(set) var isVoting: [Int: Bool] = [:] // Track voting progress per item
    // --- END NEW ---


    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        loadVotedStates() // Load persisted votes on init
        AuthService.logger.info("AuthService initialized. Loaded \(self.votedItemStates.count) vote states.")
    }

    // MARK: - Public Methods (Login, Logout, Check Status etc. - Mostly Unchanged)

    func fetchInitialCaptcha() async {
        AuthService.logger.info("fetchInitialCaptcha called by LoginView.")
        await MainActor.run { self.needsCaptcha = true }
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        guard !isLoading else { AuthService.logger.warning("Login attempt skipped: Already loading."); return }
        AuthService.logger.info("Attempting login for user: \(username)")
        await MainActor.run {
            // Reset state before login attempt
            isLoading = true; loginError = nil; self.userNonce = nil; self.favoritesCollectionId = nil; self.favoritedItemIDs = []; self.votedItemStates = [:]; self.isVoting = [:]
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
                    if collectionLoaded { // Load favorites only if profile and collection are ok
                        favoritesLoaded = await loadInitialFavorites() // Load favorite IDs
                        // --- Load votes AFTER successful login & profile/collection load ---
                        loadVotedStates()
                        AuthService.logger.info("Loaded \(self.votedItemStates.count) persisted vote states after successful login.")
                        // --- End Load Votes ---
                    }
                }

                // Check all conditions including nonce AND favorites
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
                        AuthService.logger.info("User \(self.currentUser!.name) is now logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0). Initial Favs loaded: \(self.favoritedItemIDs.count). Initial Votes loaded: \(self.votedItemStates.count)")
                    }
                } else { // Profile, Collection, Favorites ODER Nonce fehlgeschlagen
                    await MainActor.run {
                        self.isLoggedIn = false
                        if !profileLoaded { self.loginError = "Login erfolgreich, aber Profildaten konnten nicht geladen werden." }
                        else if !collectionLoaded { self.loginError = "Login erfolgreich, aber Favoriten-Ordner konnte nicht ermittelt werden." }
                        else if !favoritesLoaded { self.loginError = "Login erfolgreich, aber Favoriten konnten nicht initial geladen werden." }
                        else { self.loginError = "Login erfolgreich, aber Session-Daten (Nonce) konnten nicht gelesen werden." } // userNonce == nil
                        AuthService.logger.error("Login sequence failed after API success. Profile: \(profileLoaded), Collections: \(collectionLoaded), Favorites: \(favoritesLoaded), Nonce: \(self.userNonce != nil)")
                    }
                    await performLogoutCleanup()
                }
            } else { // Login API success: false
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
            // Reset states, but keep loaded votes for now
            isLoading = true; self.userNonce = nil; self.favoritesCollectionId = nil; self.favoritedItemIDs = []
        }

        var sessionValidAndProfileLoaded = false
        var collectionLoaded = false
        var nonceAvailable = false
        var favoritesLoaded = false // Track favorite loading

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
                 if collectionLoaded { // Only load favs if profile and collection are ok
                      favoritesLoaded = await loadInitialFavorites() // Load favorite IDs
                      // Votes already loaded in init, no need to reload here unless logic changes
                 }
             }

             // Check all conditions
             if !sessionValidAndProfileLoaded || !collectionLoaded || !favoritesLoaded || !nonceAvailable {
                 AuthService.logger.warning("Cookie/Username loaded, but subsequent fetch/sync failed. Profile: \(sessionValidAndProfileLoaded), Collections: \(collectionLoaded), Favorites: \(favoritesLoaded), Nonce: \(nonceAvailable). Session might be invalid.")
                 await performLogoutCleanup() // Cleanup includes clearing votes
                 sessionValidAndProfileLoaded = false
                 collectionLoaded = false
                 nonceAvailable = false
                 favoritesLoaded = false
             }
        } else {
             AuthService.logger.info("No session cookie or username found in keychain.")
             await MainActor.run { self.currentUser = nil }
             sessionValidAndProfileLoaded = false; collectionLoaded = false; nonceAvailable = false; favoritesLoaded = false
             await performLogoutCleanup() // Cleanup includes clearing votes
        }

         let finalIsLoggedIn = sessionValidAndProfileLoaded && collectionLoaded && favoritesLoaded && nonceAvailable
         await MainActor.run {
             self.isLoggedIn = finalIsLoggedIn
             if self.isLoggedIn {
                  AuthService.logger.info("Initial check: User \(self.currentUser!.name) is logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0). Initial Favs loaded: \(self.favoritedItemIDs.count). Initial Votes loaded: \(self.votedItemStates.count)")
             } else {
                 AuthService.logger.info("Initial check: User is not logged in (or session/profile/collection/favorites load/nonce extraction failed).")
             }
             isLoading = false
         }
    }

    // MARK: - Voting Method (Moved from PagedDetailView)
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

        if voteType == 1 { // Upvote tapped
            targetVote = (currentVote == 1) ? 0 : 1
        } else if voteType == -1 { // Downvote tapped
            targetVote = (currentVote == -1) ? 0 : -1
        } else {
            AuthService.logger.error("Invalid voteType \(voteType) passed to performVote.")
            return
        }

        // Optimistic UI Update
        let previousVoteState = votedItemStates[itemId] // Store previous state for rollback
        AuthService.logger.debug("Setting isVoting=true for \(itemId)")
        isVoting[itemId] = true // Use property directly
        votedItemStates[itemId] = targetVote // Update published property
        AuthService.logger.debug("Optimistic UI: Set vote state for \(itemId) to \(targetVote).")

        // Ensure isVoting is reset even if API call fails early
        defer {
             Task { @MainActor in
                  AuthService.logger.debug("Setting isVoting=false for \(itemId) in defer block")
                  self.isVoting[itemId] = false
             }
        }

        do {
            try await apiService.vote(itemId: itemId, vote: targetVote, nonce: nonce)
            AuthService.logger.info("Successfully voted \(targetVote) for item \(itemId).")
            // API call successful, optimistic state remains, save it
            saveVotedStates()
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Voting failed for item \(itemId): Authentication required. Session might be invalid.")
            votedItemStates[itemId] = previousVoteState // Rollback optimistic UI
            saveVotedStates() // Save the rolled-back state
            // Trigger logout
            await logout() // Use existing logout method
        } catch {
            AuthService.logger.error("Voting failed for item \(itemId): \(error.localizedDescription)")
            votedItemStates[itemId] = previousVoteState // Rollback optimistic UI
            saveVotedStates() // Save the rolled-back state
            // Optionally show error message to user (could be done via another @Published var)
        }
        // isVoting is reset by defer block
    }


    // MARK: - Private Helper Methods (Persistence, Cleanup, etc.)

    private func loadVotedStates() {
        if let savedVotes = UserDefaults.standard.dictionary(forKey: userVotesKey) as? [String: Int] {
            // Convert keys back to Int
                        let loadedStates = Dictionary(uniqueKeysWithValues: savedVotes.compactMap { (key: String, value: Int) -> (Int, Int)? in // <-- Explicit types for key/value
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
        // Convert keys to String for UserDefaults compatibility
        let stringKeyedVotes = Dictionary(uniqueKeysWithValues: votedItemStates.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyedVotes, forKey: userVotesKey)
        AuthService.logger.trace("Saved \(stringKeyedVotes.count) vote states to UserDefaults.")
    }

    @discardableResult
    private func loadInitialFavorites() async -> Bool { // Unchanged
        AuthService.logger.info("Loading initial set of favorite item IDs...")
        guard let username = self.currentUser?.name else {
             AuthService.logger.warning("Cannot load initial favorites: currentUser is nil.")
             return false
        }
        await MainActor.run { self.favoritedItemIDs = [] } // Reset before loading

        var allFavorites: [Item] = []
        var olderThanId: Int? = nil
        var fetchError: Error? = nil
        let maxPages = 10 // Limit requests to prevent potential infinite loops or excessive loading
        var pagesFetched = 0

        do {
            while pagesFetched < maxPages {
                 AuthService.logger.debug("Fetching favorites page \(pagesFetched + 1) for initial load (older: \(olderThanId ?? -1))...")
                 // Using minimal flags (1) for efficiency, assuming we only need IDs
                 let fetchedItems = try await apiService.fetchFavorites(username: username, flags: 1, olderThanId: olderThanId)
                 if fetchedItems.isEmpty {
                      AuthService.logger.debug("Reached end of favorites feed during initial load.")
                      break // Exit loop if no more items
                 }
                 allFavorites.append(contentsOf: fetchedItems)
                 olderThanId = fetchedItems.last?.id // Use Item ID for next page
                 pagesFetched += 1
            }
        } catch {
            AuthService.logger.error("Error fetching favorites during initial load: \(error.localizedDescription)")
            fetchError = error
        }

        let finalIDs = Set(allFavorites.map { $0.id })
        await MainActor.run { self.favoritedItemIDs = finalIDs } // Update published set
        AuthService.logger.info("Finished loading initial favorites. Loaded \(finalIDs.count) IDs across \(pagesFetched) pages. Error encountered: \(fetchError != nil)")
        return fetchError == nil || !finalIDs.isEmpty
    }

    @discardableResult
    private func loadProfileInfo(username: String, setLoadingState: Bool = true) async -> Bool { // Unchanged
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
    private func fetchUserCollections() async -> Bool { // Unchanged
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

    private func _fetchCaptcha() async { // Unchanged
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

    private func performLogoutCleanup() async { // Updated to clear votes
        AuthService.logger.debug("Performing local logout cleanup.")
        await MainActor.run {
            self.isLoggedIn = false; self.currentUser = nil; self.userNonce = nil;
            self.favoritesCollectionId = nil; self.needsCaptcha = false; self.captchaToken = nil;
            self.captchaImage = nil; self.favoritedItemIDs = [];
            self.votedItemStates = [:]; self.isVoting = [:] // <-- Clear votes
            self.appSettings.showSFW = true; self.appSettings.showNSFW = false; self.appSettings.showNSFL = false;
            self.appSettings.showNSFP = false; self.appSettings.showPOL = false
        }
        await clearCookies()
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)
        UserDefaults.standard.removeObject(forKey: userVotesKey) // <-- Remove persisted votes
        AuthService.logger.info("Reset content filters to SFW-only and cleared persisted votes.")
    }

    private func clearCookies() async { // Unchanged
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
    private func findAndSaveSessionCookie() async -> Bool { // Unchanged
         AuthService.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
         guard let url = URL(string: "https://pr0gramm.com") else { return false }
         guard let sessionCookie = await MainActor.run(body: { HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName }) }) else { AuthService.logger.warning("Could not retrieve cookies or session cookie '\(self.sessionCookieName)' not found."); return false }
        let cookieValue = sessionCookie.value; let parts = cookieValue.split(separator: ":")
        if parts.count != 2 { AuthService.logger.warning("Session cookie '\(self.sessionCookieName)' found but value '\(cookieValue.prefix(50))...' does NOT have expected 'id:nonce' format! Saving it anyway.") } else { AuthService.logger.info("Found session cookie '\(self.sessionCookieName)' with expected format. Value: '\(cookieValue.prefix(50))...'.") }
        guard let properties = sessionCookie.properties else { AuthService.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
         AuthService.logger.info("Saving cookie properties to keychain...")
         return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    private func loadAndRestoreSessionCookie() async -> Bool { // Unchanged
        AuthService.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { AuthService.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { AuthService.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
         await MainActor.run { HTTPCookieStorage.shared.setCookie(restoredCookie) }
         AuthService.logger.info("Successfully restored session cookie '\(restoredCookie.name)' with value '\(restoredCookie.value.prefix(50))...' into HTTPCookieStorage.")
        return true
    }

    private func extractNonceFromCookieStorage() async -> String? { // Unchanged
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

    private func logAllCookiesForPr0gramm() async { // Unchanged
        guard let url = URL(string: "https://pr0gramm.com") else { return }
         AuthService.logger.debug("--- Current Cookies for \(url.host ?? "pr0gramm.com") ---")
         let cookies = await MainActor.run { HTTPCookieStorage.shared.cookies(for: url) }
        if let cookies = cookies, !cookies.isEmpty { for cookie in cookies { AuthService.logger.debug("- Name: \(cookie.name), Value: \(cookie.value.prefix(60))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path), Secure: \(cookie.isSecure), HTTPOnly: \(cookie.isHTTPOnly)") } }
        else { AuthService.logger.debug("(No cookies found for domain)") }
         AuthService.logger.debug("--- End Cookie List ---")
    }
}
// --- END OF COMPLETE FILE ---
