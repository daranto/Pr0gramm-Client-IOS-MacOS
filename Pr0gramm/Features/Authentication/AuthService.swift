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

    private let sessionCookieKey = "pr0grammSessionCookie_v1"
    private let sessionUsernameKey = "pr0grammUsername_v1"
    private let sessionCookieName = "me"

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

    // --- MODIFIED: Make logger nonisolated ---
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")
    // --- END MODIFICATION ---

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        // Accessing nonisolated logger is safe
        AuthService.logger.info("AuthService initialized.")
    }

    // MARK: - Public Methods

    func fetchInitialCaptcha() async {
        // Accessing nonisolated logger is safe
        AuthService.logger.info("fetchInitialCaptcha called by LoginView.")
        await MainActor.run { // Ensure UI updates happen on main actor
             self.needsCaptcha = true
        }
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        // Accessing nonisolated logger is safe
        guard !isLoading else { AuthService.logger.warning("Login attempt skipped: Already loading."); return }
        AuthService.logger.info("Attempting login for user: \(username)")
        // Ensure UI updates happen on main actor
        await MainActor.run {
            isLoading = true; loginError = nil; self.userNonce = nil; self.favoritesCollectionId = nil // Reset
        }

        let credentials = APIService.LoginRequest(
            username: username, password: password, captcha: captchaAnswer, token: self.captchaToken
        )

        // Accessing needsCaptcha/captchaToken is safe from MainActor
        if self.needsCaptcha && (captchaAnswer?.isEmpty ?? true || self.captchaToken?.isEmpty ?? true) {
            await MainActor.run { // Ensure UI updates happen on main actor
                 self.loginError = "Bitte Captcha eingeben."; isLoading = false;
            }
             // Accessing nonisolated logger is safe
             AuthService.logger.warning("Login attempt failed: Captcha required but data missing."); return
        }

         // Accessing nonisolated logger is safe
        AuthService.logger.debug("[LOGIN START] Cookies BEFORE /user/login API call:")
        await logAllCookiesForPr0gramm() // Use await

        do {
            let loginResponse = try await apiService.login(credentials: credentials)

             // Accessing nonisolated logger is safe
            AuthService.logger.debug("[LOGIN SUCCESS] Cookies AFTER /user/login API call (BEFORE nonce extraction):")
            await logAllCookiesForPr0gramm() // Use await

            // Nonce aus Cookie lesen (JSON-Parsing + Kürzen) - now async
            let extractedNonce = await extractNonceFromCookieStorage() // Use await
            await MainActor.run { self.userNonce = extractedNonce } // Update on MainActor

            if self.userNonce == nil {
                  // Accessing nonisolated logger is safe
                 AuthService.logger.error("CRITICAL: Failed to obtain nonce from Cookie parsing after successful login!")
            } else {
                  // Accessing nonisolated logger is safe
                 AuthService.logger.info("Nonce successfully extracted and potentially shortened from cookie after login.")
            }

            if loginResponse.success {
                 // Accessing nonisolated logger is safe
                AuthService.logger.info("Login successful via API for user: \(username)")

                // Load profile (including badges)
                let profileLoaded = await loadProfileInfo(username: username, setLoadingState: false) // Updated function
                var collectionLoaded = false
                if profileLoaded {
                    collectionLoaded = await fetchUserCollections()
                }

                // Nonce-Verfügbarkeit ist kritisch für Login-Erfolg!
                if profileLoaded && collectionLoaded && self.userNonce != nil {
                     // Accessing nonisolated logger is safe
                    AuthService.logger.debug("[LOGIN SUCCESS] Cookies BEFORE saving to Keychain:")
                    await logAllCookiesForPr0gramm() // Use await
                    let cookieSaved = await findAndSaveSessionCookie() // Use await
                    let usernameSaved = keychainService.saveUsername(username, forKey: sessionUsernameKey)

                    await MainActor.run { // Ensure UI updates happen on main actor
                         if cookieSaved && usernameSaved { AuthService.logger.info("Session cookie and username saved to keychain.") }
                         else { AuthService.logger.warning("Failed to save session cookie (\(cookieSaved)) or username (\(usernameSaved)) to keychain.") }

                         self.isLoggedIn = true
                         self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
                         AuthService.logger.info("User \(self.currentUser!.name) is now logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0)")
                    }

                } else { // Profil, Collection ODER Nonce fehlgeschlagen
                    await MainActor.run { // Ensure UI updates happen on main actor
                         self.isLoggedIn = false
                         if !profileLoaded {
                            self.loginError = "Login erfolgreich, aber Profildaten konnten nicht geladen werden."
                            AuthService.logger.error("loadProfileInfo failed after successful API login.")
                         } else if !collectionLoaded {
                            self.loginError = "Login erfolgreich, aber Favoriten-Ordner konnte nicht ermittelt werden."
                             AuthService.logger.error("fetchUserCollections failed after successful login and profile load.")
                         } else { // userNonce == nil
                            self.loginError = "Login erfolgreich, aber Session-Daten (Nonce) konnten nicht gelesen werden."
                             AuthService.logger.error("Login sequence failed after API success. Profile: \(profileLoaded), Collections: \(collectionLoaded), Nonce: \(self.userNonce != nil)")
                         }
                    }
                    await performLogoutCleanup()
                }
            } else { // Login API success: false
                 if loginResponse.ban?.banned == true {
                     let banReason = loginResponse.ban?.reason ?? "Unbekannter Grund"; let banEnd = loginResponse.ban?.till.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "Unbekannt"
                     await MainActor.run { // Ensure UI updates happen on main actor
                          self.loginError = "Login fehlgeschlagen: Benutzer ist gebannt. Grund: \(banReason) (Bis: \(banEnd))"
                     }
                     AuthService.logger.warning("Login failed: User \(username) is banned.");
                     await performLogoutCleanup()
                 } else {
                     await MainActor.run { // Ensure UI updates happen on main actor
                        self.loginError = loginResponse.error ?? "Falsche Anmeldedaten oder Captcha."
                         AuthService.logger.warning("Login failed (API Error): \(self.loginError!) - User: \(username)")
                     }
                     if self.needsCaptcha { AuthService.logger.info("Fetching new captcha after failed login attempt."); await _fetchCaptcha() }
                     else { await performLogoutCleanup() }
                 }
            }
        } catch let error as URLError where error.code == .badServerResponse && error.localizedDescription.contains("status 400") {
             AuthService.logger.warning("Login failed with 400 Bad Request. Assuming incorrect credentials or captcha.")
             await MainActor.run { // Ensure UI updates happen on main actor
                  self.loginError = "Falsche Anmeldedaten oder Captcha."
                  self.needsCaptcha = true
             }
             await _fetchCaptcha()
        } catch {
             AuthService.logger.error("Login failed for \(username) with error: \(error.localizedDescription)")
             await MainActor.run { // Ensure UI updates happen on main actor
                  self.loginError = "Fehler beim Login: \(error.localizedDescription)"
             }
            await performLogoutCleanup()
        }
         await MainActor.run { isLoading = false } // Ensure UI updates happen on main actor
         AuthService.logger.debug("Login attempt finished for \(username). isLoading: \(self.isLoading)")
    }

    func logout() async {
         var shouldProceed = false
         await MainActor.run { // Access properties and update isLoading on MainActor
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
         await MainActor.run { isLoading = false } // Update on MainActor
         AuthService.logger.info("Logout process finished.")
    }

    func checkInitialLoginStatus() async {
        AuthService.logger.info("Checking initial login status...")
        await MainActor.run { // Ensure UI updates happen on main actor
             isLoading = true; self.userNonce = nil; self.favoritesCollectionId = nil // Reset
        }

        var sessionValidAndProfileLoaded = false
        var collectionLoaded = false
        var nonceAvailable = false // Explizit prüfen

        AuthService.logger.debug("[SESSION RESTORE START] Cookies BEFORE restoring from Keychain:")
        await logAllCookiesForPr0gramm() // Use await

        // --- MODIFIED: Call async loadAndRestoreSessionCookie ---
        if await loadAndRestoreSessionCookie(), let username = keychainService.loadUsername(forKey: sessionUsernameKey) {
        // --- END MODIFICATION ---
             AuthService.logger.info("Session cookie and username ('\(username)') restored from keychain.")

             AuthService.logger.debug("[SESSION RESTORE] Cookies AFTER restoring from Keychain (BEFORE nonce extraction):")
             await logAllCookiesForPr0gramm() // Use await

             // Nonce aus Cookie (JSON + Kürzen) versuchen zu extrahieren - now async
             let extractedNonce = await extractNonceFromCookieStorage() // Use await
             await MainActor.run { self.userNonce = extractedNonce } // Update on MainActor
             nonceAvailable = (self.userNonce != nil) // Prüfen ob erfolgreich

             // Load profile (including badges)
             sessionValidAndProfileLoaded = await loadProfileInfo(username: username, setLoadingState: false) // Updated function
             if sessionValidAndProfileLoaded {
                 collectionLoaded = await fetchUserCollections()
             }

             if !sessionValidAndProfileLoaded || !collectionLoaded || !nonceAvailable { // Alle 3 müssen klappen
                 AuthService.logger.warning("Cookie/Username loaded, but subsequent fetch/sync failed. Profile: \(sessionValidAndProfileLoaded), Collections: \(collectionLoaded), Nonce: \(nonceAvailable). Session might be invalid.")
                 await performLogoutCleanup()
                 sessionValidAndProfileLoaded = false
                 collectionLoaded = false
                 nonceAvailable = false
             }
        } else {
             AuthService.logger.info("No session cookie or username found in keychain.")
             await MainActor.run { self.currentUser = nil } // Update on MainActor
             sessionValidAndProfileLoaded = false; collectionLoaded = false; nonceAvailable = false
             await performLogoutCleanup()
        }

         // Update isLoggedIn based on the final results
         let finalIsLoggedIn = sessionValidAndProfileLoaded && collectionLoaded && nonceAvailable
         await MainActor.run {
             self.isLoggedIn = finalIsLoggedIn
             if self.isLoggedIn {
                  AuthService.logger.info("Initial check: User \(self.currentUser!.name) is logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0)")
             } else {
                 AuthService.logger.info("Initial check: User is not logged in (or session/profile/collection load/nonce extraction failed).")
             }
             isLoading = false
         }
    }

    // MARK: - Private Helper Methods

    @discardableResult
    private func loadProfileInfo(username: String, setLoadingState: Bool = true) async -> Bool {
        AuthService.logger.debug("Attempting to load profile info for \(username)...")
        if setLoadingState { await MainActor.run { isLoading = true } }
        await MainActor.run { loginError = nil; self.currentUser = nil } // Reset vor dem Laden

        do {
            // Use flags=31 to try and get badges
            let profileInfoResponse = try await apiService.getProfileInfo(username: username, flags: 31)

            // Create UserInfo on the current actor (MainActor because this func is MainActor isolated)
            let newUserInfo = UserInfo(
                id: profileInfoResponse.user.id,
                name: profileInfoResponse.user.name,
                registered: profileInfoResponse.user.registered,
                score: profileInfoResponse.user.score,
                mark: profileInfoResponse.user.mark,
                badges: profileInfoResponse.badges
            )
            // Update state on MainActor
            await MainActor.run {
                 self.currentUser = newUserInfo
                 AuthService.logger.info("Successfully created UserInfo for: \(self.currentUser!.name) with \(self.currentUser?.badges?.count ?? 0) badges.")
                 if setLoadingState { isLoading = false }
            }
             return true // Erfolg

        } catch {
            AuthService.logger.warning("Failed to load or create profile info for \(username): \(error.localizedDescription).")
            await MainActor.run { // Ensure updates happen on main actor
                 self.currentUser = nil
                 if setLoadingState { isLoading = false }
            }
             return false // Fehler
        }
    }


    @discardableResult
    private func fetchUserCollections() async -> Bool {
        AuthService.logger.info("Fetching user collections to find favorites ID...")
        await MainActor.run { self.favoritesCollectionId = nil } // Reset on MainActor

        do {
            let response = try await apiService.getUserCollections()
            var foundId: Int? = nil
            if let favCollection = response.collections.first(where: { $0.isDefault == 1 }) {
                foundId = favCollection.id
                AuthService.logger.info("Found default favorites collection: ID \(favCollection.id), Name '\(favCollection.name)'")
            } else if let favCollectionByKeyword = response.collections.first(where: { $0.keyword == "favoriten"}) {
                 foundId = favCollectionByKeyword.id
                 AuthService.logger.warning("Found favorites collection by keyword 'favoriten' (not marked as default): ID \(favCollectionByKeyword.id), Name '\(favCollectionByKeyword.name)'")
            } else {
                AuthService.logger.error("Could not find default favorites collection (isDefault=1 or keyword='favoriten') in user collections response.")
            }

            if let id = foundId {
                await MainActor.run { self.favoritesCollectionId = id } // Update on MainActor
                return true
            } else {
                return false
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            AuthService.logger.error("Failed to fetch user collections: Authentication required. Session might be invalid.")
            return false
        } catch {
            AuthService.logger.error("Failed to fetch user collections: \(error.localizedDescription)")
            return false
        }
    }

    private func _fetchCaptcha() async {
        AuthService.logger.info("Fetching new captcha data...")
        await MainActor.run { // Ensure UI updates happen on main actor
             self.captchaImage = nil; self.captchaToken = nil; self.loginError = nil
        }
        do {
            let captchaResponse = try await apiService.fetchCaptcha();
            let token = captchaResponse.token // Capture token

            var base64String = captchaResponse.captcha
            if let commaRange = base64String.range(of: ",") { base64String = String(base64String[commaRange.upperBound...]); AuthService.logger.debug("Removed base64 prefix.") }
            else { AuthService.logger.debug("No base64 prefix found.") }

            var decodedImage: UIImage? = nil
            var decodeError: String? = nil
            if let imageData = Data(base64Encoded: base64String) {
                decodedImage = UIImage(data: imageData)
                 if decodedImage != nil { AuthService.logger.info("Successfully decoded captcha image.") }
                 else { decodeError = "Captcha konnte nicht angezeigt werden."; AuthService.logger.error("Failed to create UIImage from decoded captcha data.") }
            } else { decodeError = "Captcha konnte nicht dekodiert werden."; AuthService.logger.error("Failed to decode base64 captcha string.") }

            await MainActor.run { // Ensure UI updates happen on main actor
                 self.captchaToken = token
                 self.captchaImage = decodedImage
                 self.loginError = decodeError // Set error only if decode failed
            }
        } catch {
             AuthService.logger.error("Failed to fetch captcha: \(error.localizedDescription)")
             await MainActor.run { // Ensure UI updates happen on main actor
                  self.loginError = "Captcha konnte nicht geladen werden."
             }
        }
    }

    private func performLogoutCleanup() async {
        AuthService.logger.debug("Performing local logout cleanup.")
        await MainActor.run { // Ensure UI updates happen on main actor
             self.isLoggedIn = false;
             self.currentUser = nil; // Wichtig: UserInfo (inkl. Badges) wird gelöscht
             self.userNonce = nil;
             self.favoritesCollectionId = nil;
             self.needsCaptcha = false;
             self.captchaToken = nil;
             self.captchaImage = nil;
             // Accessing appSettings properties is safe as performLogoutCleanup is MainActor isolated
             self.appSettings.showSFW = true
             self.appSettings.showNSFW = false
             self.appSettings.showNSFL = false
             self.appSettings.showNSFP = false
             self.appSettings.showPOL = false
        }
        await clearCookies() // Use await
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)
        AuthService.logger.info("Reset content filters to SFW-only.")
    }

    // --- Keep async, runs parts on MainActor ---
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

    // --- Keep async, runs parts on MainActor ---
    @discardableResult
    private func findAndSaveSessionCookie() async -> Bool {
         AuthService.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
         guard let url = URL(string: "https://pr0gramm.com") else { return false }

         guard let sessionCookie = await MainActor.run(body: {
              HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName })
         }) else {
             AuthService.logger.warning("Could not retrieve cookies or session cookie '\(self.sessionCookieName)' not found.")
             return false
         }

        let cookieValue = sessionCookie.value
        let parts = cookieValue.split(separator: ":")
        if parts.count != 2 {
             AuthService.logger.warning("Session cookie '\(self.sessionCookieName)' found but value '\(cookieValue.prefix(50))...' does NOT have expected 'id:nonce' format! Saving it anyway to overwrite potential old format in keychain.")
        } else {
              AuthService.logger.info("Found session cookie '\(self.sessionCookieName)' with expected format. Value: '\(cookieValue.prefix(50))...'.")
        }

        guard let properties = sessionCookie.properties else { AuthService.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
         AuthService.logger.info("Saving cookie properties to keychain...")
         return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    // --- MODIFIED: Make async ---
    private func loadAndRestoreSessionCookie() async -> Bool {
        AuthService.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { AuthService.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { AuthService.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }

         // --- MODIFIED: Set cookie on MainActor asynchronously ---
         await MainActor.run {
              HTTPCookieStorage.shared.setCookie(restoredCookie)
         }
         // --- END MODIFICATION ---
         AuthService.logger.info("Successfully restored session cookie '\(restoredCookie.name)' with value '\(restoredCookie.value.prefix(50))...' into HTTPCookieStorage.")
        return true
    }


    // --- Keep async, runs parts on MainActor  ---
    private func extractNonceFromCookieStorage() async -> String? {
        AuthService.logger.debug("Attempting to extract nonce from cookie storage (trying JSON format first, then shorten)...")
         guard let url = URL(string: "https://pr0gramm.com") else { return nil }

         guard let sessionCookie = await MainActor.run(body: {
             HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == self.sessionCookieName })
         }) else {
             AuthService.logger.warning("Could not find session cookie named '\(self.sessionCookieName)' in storage to extract nonce.")
             return nil
         }

        let cookieValue = sessionCookie.value
         AuthService.logger.debug("[EXTRACT NONCE] Found session cookie '\(self.sessionCookieName)' with value: \(cookieValue)")

        AuthService.logger.debug("[EXTRACT NONCE] Attempting URL-decoded JSON parsing...")
        if let decodedValue = cookieValue.removingPercentEncoding,
           let jsonData = decodedValue.data(using: .utf8) {
            do {
                if let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                   let longNonceFromJson = jsonDict["id"] as? String {
                     AuthService.logger.debug("[EXTRACT NONCE] Found 'id' field in JSON: \(longNonceFromJson)")

                    let expectedNonceLength = 16
                    if longNonceFromJson.count >= expectedNonceLength {
                        let shortNonce = String(longNonceFromJson.prefix(expectedNonceLength))
                         AuthService.logger.info("[EXTRACT NONCE] Successfully extracted and shortened nonce from JSON 'id' field: '\(shortNonce)'")
                        return shortNonce
                    } else {
                          AuthService.logger.warning("[EXTRACT NONCE] Nonce from JSON 'id' field is shorter than expected length (\(expectedNonceLength)): '\(longNonceFromJson)'")
                         return nil
                    }

                } else {
                     AuthService.logger.warning("[EXTRACT NONCE] Failed to parse URL-decoded cookie value as JSON Dictionary or find 'id' key.")
                    return nil
                }
            } catch {
                 AuthService.logger.warning("[EXTRACT NONCE] Error parsing URL-decoded cookie value as JSON: \(error.localizedDescription)")
                return nil
            }
        } else {
             AuthService.logger.warning("[EXTRACT NONCE] Failed to URL-decode cookie value or convert to Data.")
            return nil
        }
    }

    // --- Keep async, runs parts on MainActor ---
    private func logAllCookiesForPr0gramm() async {
        guard let url = URL(string: "https://pr0gramm.com") else { return }
         AuthService.logger.debug("--- Current Cookies for \(url.host ?? "pr0gramm.com") ---")

         let cookies = await MainActor.run { HTTPCookieStorage.shared.cookies(for: url) }

        if let cookies = cookies, !cookies.isEmpty {
            for cookie in cookies {
                  AuthService.logger.debug("- Name: \(cookie.name), Value: \(cookie.value.prefix(60))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path), Secure: \(cookie.isSecure), HTTPOnly: \(cookie.isHTTPOnly)")
            }
        } else {
             AuthService.logger.debug("(No cookies found for domain)")
        }
         AuthService.logger.debug("--- End Cookie List ---")
    }
}
// --- END OF COMPLETE FILE ---
