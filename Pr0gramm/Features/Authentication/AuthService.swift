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

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        Self.logger.info("AuthService initialized.")
    }

    // MARK: - Public Methods

    func fetchInitialCaptcha() async {
        Self.logger.info("fetchInitialCaptcha called by LoginView.")
        self.needsCaptcha = true
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        guard !isLoading else { Self.logger.warning("Login attempt skipped: Already loading."); return }
        Self.logger.info("Attempting login for user: \(username)"); isLoading = true; loginError = nil; self.userNonce = nil; self.favoritesCollectionId = nil // Reset

        let credentials = APIService.LoginRequest(
            username: username, password: password, captcha: captchaAnswer, token: self.captchaToken
        )

        if self.needsCaptcha && (captchaAnswer?.isEmpty ?? true || self.captchaToken?.isEmpty ?? true) {
             self.loginError = "Bitte Captcha eingeben."; Self.logger.warning("Login attempt failed: Captcha required but data missing."); isLoading = false; return
        }

        Self.logger.debug("[LOGIN START] Cookies BEFORE /user/login API call:")
        logAllCookiesForPr0gramm()

        do {
            let loginResponse = try await apiService.login(credentials: credentials)

            Self.logger.debug("[LOGIN SUCCESS] Cookies AFTER /user/login API call (BEFORE nonce extraction):")
            logAllCookiesForPr0gramm()

            // Nonce aus Cookie lesen (JSON-Parsing + Kürzen)
            self.userNonce = extractNonceFromCookieStorage()
            if self.userNonce == nil {
                 Self.logger.error("CRITICAL: Failed to obtain nonce from Cookie parsing after successful login!")
            } else {
                 Self.logger.info("Nonce successfully extracted and potentially shortened from cookie after login.")
            }

            if loginResponse.success {
                Self.logger.info("Login successful via API for user: \(username)")

                // Load profile (including badges)
                let profileLoaded = await loadProfileInfo(username: username, setLoadingState: false) // Updated function
                var collectionLoaded = false
                if profileLoaded {
                    collectionLoaded = await fetchUserCollections()
                }

                // Nonce-Verfügbarkeit ist kritisch für Login-Erfolg!
                if profileLoaded && collectionLoaded && self.userNonce != nil {
                    Self.logger.debug("[LOGIN SUCCESS] Cookies BEFORE saving to Keychain:")
                    logAllCookiesForPr0gramm()
                    let cookieSaved = findAndSaveSessionCookie()
                    let usernameSaved = keychainService.saveUsername(username, forKey: sessionUsernameKey)
                    if cookieSaved && usernameSaved { Self.logger.info("Session cookie and username saved to keychain.") }
                    else { Self.logger.warning("Failed to save session cookie (\(cookieSaved)) or username (\(usernameSaved)) to keychain.") }

                    self.isLoggedIn = true
                    self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
                    Self.logger.info("User \(self.currentUser!.name) is now logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0)")

                } else { // Profil, Collection ODER Nonce fehlgeschlagen
                    self.isLoggedIn = false
                    if !profileLoaded {
                        self.loginError = "Login erfolgreich, aber Profildaten konnten nicht geladen werden."
                        Self.logger.error("loadProfileInfo failed after successful API login.")
                    } else if !collectionLoaded {
                        self.loginError = "Login erfolgreich, aber Favoriten-Ordner konnte nicht ermittelt werden."
                        Self.logger.error("fetchUserCollections failed after successful login and profile load.")
                    } else { // userNonce == nil
                        self.loginError = "Login erfolgreich, aber Session-Daten (Nonce) konnten nicht gelesen werden."
                        Self.logger.error("Login sequence failed after API success. Profile: \(profileLoaded), Collections: \(collectionLoaded), Nonce: \(self.userNonce != nil)")
                    }
                    await performLogoutCleanup()
                }
            } else { // Login API success: false
                 if loginResponse.ban?.banned == true {
                     let banReason = loginResponse.ban?.reason ?? "Unbekannter Grund"; let banEnd = loginResponse.ban?.till.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "Unbekannt"
                     self.loginError = "Login fehlgeschlagen: Benutzer ist gebannt. Grund: \(banReason) (Bis: \(banEnd))"; Self.logger.warning("Login failed: User \(username) is banned."); await performLogoutCleanup()
                 } else {
                     self.loginError = loginResponse.error ?? "Falsche Anmeldedaten oder Captcha."
                     Self.logger.warning("Login failed (API Error): \(self.loginError!) - User: \(username)")
                     if self.needsCaptcha { Self.logger.info("Fetching new captcha after failed login attempt."); await _fetchCaptcha() }
                     else { await performLogoutCleanup() }
                 }
            }
        } catch let error as URLError where error.code == .badServerResponse && error.localizedDescription.contains("status 400") {
             Self.logger.warning("Login failed with 400 Bad Request. Assuming incorrect credentials or captcha.")
             self.loginError = "Falsche Anmeldedaten oder Captcha."
             self.needsCaptcha = true
             await _fetchCaptcha()
        } catch {
            Self.logger.error("Login failed for \(username) with error: \(error.localizedDescription)")
            self.loginError = "Fehler beim Login: \(error.localizedDescription)"
            await performLogoutCleanup()
        }
        isLoading = false
        Self.logger.debug("Login attempt finished for \(username). isLoading: \(self.isLoading)")
    }

    func logout() async {
        guard self.isLoggedIn, !isLoading else { Self.logger.warning("Logout skipped: Not logged in or already loading."); return }
        Self.logger.info("Attempting logout for user: \(self.currentUser?.name ?? "Unknown")"); isLoading = true
        do { try await apiService.logout(); Self.logger.info("Logout successful via API.") }
        catch { Self.logger.error("API logout failed: \(error.localizedDescription). Proceeding with local cleanup.") }
        await performLogoutCleanup(); isLoading = false; Self.logger.info("Logout process finished.")
    }

    func checkInitialLoginStatus() async {
        Self.logger.info("Checking initial login status..."); isLoading = true; self.userNonce = nil; self.favoritesCollectionId = nil // Reset

        var sessionValidAndProfileLoaded = false
        var collectionLoaded = false
        var nonceAvailable = false // Explizit prüfen

        Self.logger.debug("[SESSION RESTORE START] Cookies BEFORE restoring from Keychain:")
        logAllCookiesForPr0gramm()

        if loadAndRestoreSessionCookie(), let username = keychainService.loadUsername(forKey: sessionUsernameKey) {
             Self.logger.info("Session cookie and username ('\(username)') restored from keychain.")

             Self.logger.debug("[SESSION RESTORE] Cookies AFTER restoring from Keychain (BEFORE nonce extraction):")
             logAllCookiesForPr0gramm()

             // Nonce aus Cookie (JSON + Kürzen) versuchen zu extrahieren
             self.userNonce = extractNonceFromCookieStorage()
             nonceAvailable = (self.userNonce != nil) // Prüfen ob erfolgreich

             // Load profile (including badges)
             sessionValidAndProfileLoaded = await loadProfileInfo(username: username, setLoadingState: false) // Updated function
             if sessionValidAndProfileLoaded {
                 collectionLoaded = await fetchUserCollections()
             }

             if !sessionValidAndProfileLoaded || !collectionLoaded || !nonceAvailable { // Alle 3 müssen klappen
                 Self.logger.warning("Cookie/Username loaded, but subsequent fetch/sync failed. Profile: \(sessionValidAndProfileLoaded), Collections: \(collectionLoaded), Nonce: \(nonceAvailable). Session might be invalid.")
                 await performLogoutCleanup()
                 sessionValidAndProfileLoaded = false
                 collectionLoaded = false
                 nonceAvailable = false
             }
        } else {
             Self.logger.info("No session cookie or username found in keychain.")
             self.currentUser = nil; sessionValidAndProfileLoaded = false; collectionLoaded = false; nonceAvailable = false
             await performLogoutCleanup()
        }

        self.isLoggedIn = sessionValidAndProfileLoaded && collectionLoaded && nonceAvailable

        if self.isLoggedIn {
             Self.logger.info("Initial check: User \(self.currentUser!.name) is logged in. Nonce available: true. Fav Collection ID: \(self.favoritesCollectionId ?? -1). Badges: \(self.currentUser?.badges?.count ?? 0)")
        } else {
            Self.logger.info("Initial check: User is not logged in (or session/profile/collection load/nonce extraction failed).")
        }
        isLoading = false
    }

    // MARK: - Private Helper Methods

    @discardableResult
    private func loadProfileInfo(username: String, setLoadingState: Bool = true) async -> Bool {
        Self.logger.debug("Attempting to load profile info for \(username)..."); if setLoadingState { isLoading = true }; loginError = nil
        self.currentUser = nil // Reset vor dem Laden

        do {
            // Use flags=31 to try and get badges
            let profileInfoResponse = try await apiService.getProfileInfo(username: username, flags: 31)

            // --- MODIFIED: Copy badges from response root level ---
            self.currentUser = UserInfo(
                id: profileInfoResponse.user.id,
                name: profileInfoResponse.user.name,
                registered: profileInfoResponse.user.registered,
                score: profileInfoResponse.user.score,
                mark: profileInfoResponse.user.mark,
                badges: profileInfoResponse.badges // <-- Kopiere Badges von der Response, nicht vom user-Objekt
            )
            // --- END MODIFICATION ---
            Self.logger.info("Successfully created UserInfo for: \(self.currentUser!.name) with \(self.currentUser?.badges?.count ?? 0) badges.")
            if setLoadingState { isLoading = false }; return true // Erfolg

        } catch {
            Self.logger.warning("Failed to load or create profile info for \(username): \(error.localizedDescription).")
            self.currentUser = nil
            if setLoadingState { isLoading = false }; return false // Fehler
        }
    }


    @discardableResult
    private func fetchUserCollections() async -> Bool {
        Self.logger.info("Fetching user collections to find favorites ID...")
        self.favoritesCollectionId = nil // Reset
        do {
            let response = try await apiService.getUserCollections()
            if let favCollection = response.collections.first(where: { $0.isDefault == 1 }) {
                self.favoritesCollectionId = favCollection.id
                Self.logger.info("Found default favorites collection: ID \(favCollection.id), Name '\(favCollection.name)'")
                return true
            } else if let favCollectionByKeyword = response.collections.first(where: { $0.keyword == "favoriten"}) {
                 self.favoritesCollectionId = favCollectionByKeyword.id
                 Self.logger.warning("Found favorites collection by keyword 'favoriten' (not marked as default): ID \(favCollectionByKeyword.id), Name '\(favCollectionByKeyword.name)'")
                 return true
            } else {
                Self.logger.error("Could not find default favorites collection (isDefault=1 or keyword='favoriten') in user collections response.")
                return false
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            Self.logger.error("Failed to fetch user collections: Authentication required. Session might be invalid.")
            return false
        } catch {
            Self.logger.error("Failed to fetch user collections: \(error.localizedDescription)")
            return false
        }
    }

    private func _fetchCaptcha() async {
        Self.logger.info("Fetching new captcha data..."); self.captchaImage = nil; self.captchaToken = nil; self.loginError = nil
        do {
            let captchaResponse = try await apiService.fetchCaptcha(); self.captchaToken = captchaResponse.token
            var base64String = captchaResponse.captcha
            if let commaRange = base64String.range(of: ",") { base64String = String(base64String[commaRange.upperBound...]); Self.logger.debug("Removed base64 prefix.") }
            else { Self.logger.debug("No base64 prefix found.") }
            if let imageData = Data(base64Encoded: base64String) {
                self.captchaImage = UIImage(data: imageData)
                 if self.captchaImage != nil { Self.logger.info("Successfully decoded captcha image.") }
                 else { Self.logger.error("Failed to create UIImage from decoded captcha data."); self.loginError = "Captcha konnte nicht angezeigt werden." }
            } else { Self.logger.error("Failed to decode base64 captcha string."); self.loginError = "Captcha konnte nicht dekodiert werden." }
        } catch { Self.logger.error("Failed to fetch captcha: \(error.localizedDescription)"); self.loginError = "Captcha konnte nicht geladen werden." }
    }

    private func performLogoutCleanup() async {
        Self.logger.debug("Performing local logout cleanup.");
        self.isLoggedIn = false;
        self.currentUser = nil; // Wichtig: UserInfo (inkl. Badges) wird gelöscht
        self.userNonce = nil;
        self.favoritesCollectionId = nil;
        self.needsCaptcha = false;
        self.captchaToken = nil;
        self.captchaImage = nil;
        clearCookies()
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)
        self.appSettings.showSFW = true
        self.appSettings.showNSFW = false
        self.appSettings.showNSFL = false
        self.appSettings.showNSFP = false
        self.appSettings.showPOL = false
        Self.logger.info("Reset content filters to SFW-only.")
    }

    private func clearCookies() {
        Self.logger.debug("Clearing cookies for pr0gramm.com domain.")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        Self.logger.debug("Found \(cookies.count) cookies for domain to potentially clear.")
        for cookie in cookies {
            Self.logger.debug("Deleting cookie: Name='\(cookie.name)', Value='\(cookie.value.prefix(50))...', Domain='\(cookie.domain)', Path='\(cookie.path)'")
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        Self.logger.info("Finished clearing cookies.")
    }

    @discardableResult
    private func findAndSaveSessionCookie() -> Bool {
        Self.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { Self.logger.warning("Could not retrieve cookies."); return false }
        Self.logger.trace("All cookies found in storage for save attempt:")
        for cookie in cookies {
            Self.logger.trace("- Name: \(cookie.name), Value: \(cookie.value.prefix(50))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path)")
        }
        guard let sessionCookie = cookies.first(where: { $0.name == self.sessionCookieName }) else { Self.logger.warning("Session cookie '\(self.sessionCookieName)' not found."); return false }

        let cookieValue = sessionCookie.value
        let parts = cookieValue.split(separator: ":")
        if parts.count != 2 {
            Self.logger.warning("Session cookie '\(self.sessionCookieName)' found but value '\(cookieValue.prefix(50))...' does NOT have expected 'id:nonce' format! Saving it anyway to overwrite potential old format in keychain.")
        } else {
             Self.logger.info("Found session cookie '\(self.sessionCookieName)' with expected format. Value: '\(cookieValue.prefix(50))...'.")
        }

        guard let properties = sessionCookie.properties else { Self.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
        Self.logger.info("Saving cookie properties to keychain...")
        return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    private func loadAndRestoreSessionCookie() -> Bool {
        Self.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { Self.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { Self.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        HTTPCookieStorage.shared.setCookie(restoredCookie)
        Self.logger.info("Successfully restored session cookie '\(restoredCookie.name)' with value '\(restoredCookie.value.prefix(50))...' into HTTPCookieStorage.")
        return true
    }


    // Angepasste Nonce Extraktion (JSON zuerst, dann Kürzen) - Unverändert
    private func extractNonceFromCookieStorage() -> String? {
        Self.logger.debug("Attempting to extract nonce from cookie storage (trying JSON format first, then shorten)...")
        guard let url = URL(string: "https://pr0gramm.com"),
              let cookies = HTTPCookieStorage.shared.cookies(for: url)
        else {
            Self.logger.warning("Could not find cookies in storage to extract nonce.")
            return nil
        }

        guard let sessionCookie = cookies.first(where: { $0.name == self.sessionCookieName }) else {
            Self.logger.warning("Could not find session cookie named '\(self.sessionCookieName)' in storage to extract nonce.")
            return nil
        }

        let cookieValue = sessionCookie.value
        Self.logger.debug("[EXTRACT NONCE] Found session cookie '\(self.sessionCookieName)' with value: \(cookieValue)")

        // VERSUCH 1: Prüfen auf URL-kodiertes JSON-Format
        Self.logger.debug("[EXTRACT NONCE] Attempting URL-decoded JSON parsing...")
        if let decodedValue = cookieValue.removingPercentEncoding, // URL-Dekodieren
           let jsonData = decodedValue.data(using: .utf8) {       // In Data umwandeln
            do {
                if let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                   let longNonceFromJson = jsonDict["id"] as? String { // Das ist der LANGE Nonce
                    Self.logger.debug("[EXTRACT NONCE] Found 'id' field in JSON: \(longNonceFromJson)")

                    let expectedNonceLength = 16
                    if longNonceFromJson.count >= expectedNonceLength {
                        let shortNonce = String(longNonceFromJson.prefix(expectedNonceLength))
                        Self.logger.info("[EXTRACT NONCE] Successfully extracted and shortened nonce from JSON 'id' field: '\(shortNonce)'")
                        return shortNonce
                    } else {
                         Self.logger.warning("[EXTRACT NONCE] Nonce from JSON 'id' field is shorter than expected length (\(expectedNonceLength)): '\(longNonceFromJson)'")
                         return nil
                    }

                } else {
                    Self.logger.warning("[EXTRACT NONCE] Failed to parse URL-decoded cookie value as JSON Dictionary or find 'id' key.")
                    return nil
                }
            } catch {
                Self.logger.warning("[EXTRACT NONCE] Error parsing URL-decoded cookie value as JSON: \(error.localizedDescription)")
                return nil
            }
        } else {
            Self.logger.warning("[EXTRACT NONCE] Failed to URL-decode cookie value or convert to Data.")
            return nil
        }
    }

    // Logging Helfer Funktion - Unverändert
    private func logAllCookiesForPr0gramm() {
        guard let url = URL(string: "https://pr0gramm.com") else { return }
        Self.logger.debug("--- Current Cookies for \(url.host ?? "pr0gramm.com") ---")
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for cookie in cookies {
                 Self.logger.debug("- Name: \(cookie.name), Value: \(cookie.value.prefix(60))..., Expires: \(cookie.expiresDate?.description ?? "Session"), Path: \(cookie.path), Secure: \(cookie.isSecure), HTTPOnly: \(cookie.isHTTPOnly)")
            }
        } else {
            Self.logger.debug("(No cookies found for domain)")
        }
        Self.logger.debug("--- End Cookie List ---")
    }
}
// --- END OF COMPLETE FILE ---
