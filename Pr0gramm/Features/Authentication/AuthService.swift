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
    private let appSettings: AppSettings // <-- HINZUGEFÜGT: Referenz zu AppSettings

    private let sessionCookieKey = "pr0grammSessionCookie_v1"
    private let sessionUsernameKey = "pr0grammUsername_v1" // Key für Username
    private let sessionCookieName = "me" // !! WICHTIG: Prüfen !!

    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserInfo? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loginError: String? = nil
    @Published private(set) var needsCaptcha: Bool = false
    @Published private(set) var captchaToken: String? = nil
    @Published private(set) var captchaImage: UIImage? = nil

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    // --- GEÄNDERT: Initializer nimmt AppSettings entgegen ---
    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        Self.logger.info("AuthService initialized.")
    }
    // --- ENDE ÄNDERUNG ---


    // MARK: - Public Methods

    func fetchInitialCaptcha() async {
        Self.logger.info("fetchInitialCaptcha called by LoginView.")
        self.needsCaptcha = true
        await _fetchCaptcha()
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        guard !isLoading else { Self.logger.warning("Login attempt skipped: Already loading."); return }
        Self.logger.info("Attempting login for user: \(username)"); isLoading = true; loginError = nil

        let credentials = APIService.LoginRequest(
            username: username, password: password, captcha: captchaAnswer, token: self.captchaToken
        )

        if self.needsCaptcha && (captchaAnswer?.isEmpty ?? true || self.captchaToken?.isEmpty ?? true) {
             self.loginError = "Bitte Captcha eingeben."; Self.logger.warning("Login attempt failed: Captcha required but data missing."); isLoading = false; return
        }

        do {
            // Schritt 1: API Login
            let response = try await apiService.login(credentials: credentials)

            if response.success {
                Self.logger.info("Login successful via API for user: \(username)")

                // Schritt 2: Lade Profil-Infos mit dem eingegebenen Username
                let profileLoaded = await loadProfileInfo(username: username, setLoadingState: false)

                if profileLoaded {
                    // Schritt 3: Speichere Cookie UND Username im Keychain
                    let cookieSaved = findAndSaveSessionCookie()
                    let usernameSaved = keychainService.saveUsername(username, forKey: sessionUsernameKey)
                    if cookieSaved && usernameSaved { Self.logger.info("Session cookie and username saved to keychain.") }
                    else { Self.logger.warning("Failed to save session cookie (\(cookieSaved)) or username (\(usernameSaved)) to keychain.") }

                    // Schritt 4: Setze finalen Status
                    self.isLoggedIn = true
                    self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
                    Self.logger.info("User \(self.currentUser!.name) is now logged in.") // ! ok

                } else { // Profil konnte nicht geladen werden
                    self.isLoggedIn = false // Login gilt als fehlgeschlagen, wenn Profil nicht ladbar
                    self.loginError = "Login erfolgreich, aber Profildaten konnten nicht geladen werden."
                    Self.logger.error("loadProfileInfo failed after successful API login.")
                    await performLogoutCleanup() // Alles bereinigen (inkl. Filter Reset)
                }
            } else { // success: false
                 if response.ban?.banned == true {
                     let banReason = response.ban?.reason ?? "Unbekannter Grund"; let banEnd = response.ban?.till.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "Unbekannt"
                     self.loginError = "Login fehlgeschlagen: Benutzer ist gebannt. Grund: \(banReason) (Bis: \(banEnd))"; Self.logger.warning("Login failed: User \(username) is banned."); await performLogoutCleanup()
                 } else {
                     self.loginError = response.error ?? "Falsche Anmeldedaten oder Captcha."
                     Self.logger.warning("Login failed (API Error): \(self.loginError!) - User: \(username)")
                     if self.needsCaptcha { Self.logger.info("Fetching new captcha after failed login attempt."); await _fetchCaptcha() }
                     else { await performLogoutCleanup() } // Cleanup auch bei normalen Loginfehlern, falls kein Captcha nötig
                 }
            }
        } catch let error as URLError where error.code == .badServerResponse && error.localizedDescription.contains("status 400") {
             Self.logger.warning("Login failed with 400 Bad Request. Assuming incorrect credentials or captcha.")
             self.loginError = "Falsche Anmeldedaten oder Captcha."
             self.needsCaptcha = true // Annehmen, dass Captcha jetzt benötigt wird
             await _fetchCaptcha()
             // KEIN performLogoutCleanup hier, da der User ja noch eingeloggt sein *könnte*
        } catch {
            Self.logger.error("Login failed for \(username) with error: \(error.localizedDescription)")
            self.loginError = "Fehler beim Login: \(error.localizedDescription)"
            await performLogoutCleanup() // Bei generischen Fehlern aufräumen
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
        Self.logger.info("Checking initial login status..."); isLoading = true
        var sessionValidAndProfileLoaded = false

        // Schritt 1: Lade Cookie UND Username
        if loadAndRestoreSessionCookie(), let username = keychainService.loadUsername(forKey: sessionUsernameKey) {
             Self.logger.info("Session cookie and username ('\(username)') restored from keychain.")
             // Schritt 2: Versuche Profil zu laden
             sessionValidAndProfileLoaded = await loadProfileInfo(username: username, setLoadingState: false)
             if !sessionValidAndProfileLoaded {
                 Self.logger.warning("Cookie/Username loaded, but profile fetch failed. Session might be invalid.")
                 await performLogoutCleanup() // Cleanup wenn Profil trotz Cookie nicht geht
             }
        } else {
             Self.logger.info("No session cookie or username found in keychain.")
             self.currentUser = nil; sessionValidAndProfileLoaded = false
             await performLogoutCleanup() // Cleanup wenn nichts im Keychain ist
        }

        // Schritt 3: Setze Status
        self.isLoggedIn = sessionValidAndProfileLoaded

        if self.isLoggedIn {
            Self.logger.info("Initial check: User \(self.currentUser!.name) is logged in.") // ! ok
        } else {
            Self.logger.info("Initial check: User is not logged in (or session/profile load failed).")
            // Das Cleanup wurde bereits oben bei Bedarf aufgerufen
        }
        isLoading = false
    }

    // MARK: - Private Helper Methods

    /// Lädt die Profil-Informationen und erstellt das UserInfo-Objekt. Gibt true bei Erfolg zurück.
    @discardableResult
    private func loadProfileInfo(username: String, setLoadingState: Bool = true) async -> Bool {
        Self.logger.debug("Attempting to load profile info for \(username)..."); if setLoadingState { isLoading = true }; loginError = nil
        self.currentUser = nil // Reset vor dem Laden

        do {
            // Rufe /profile/info ab -> gibt ProfileInfoResponse
            let profileInfoResponse = try await apiService.getProfileInfo(username: username)

            // Erstelle das UserInfo-Objekt aus profileInfoResponse.user
            self.currentUser = UserInfo(
                id: profileInfoResponse.user.id,
                name: profileInfoResponse.user.name,
                registered: profileInfoResponse.user.registered,
                score: profileInfoResponse.user.score,
                mark: profileInfoResponse.user.mark
            )
            Self.logger.info("Successfully created UserInfo for: \(self.currentUser!.name)")
            if setLoadingState { isLoading = false }; return true // Erfolg

        } catch {
            Self.logger.warning("Failed to load or create profile info for \(username): \(error.localizedDescription).")
            self.currentUser = nil
            if setLoadingState { isLoading = false }; return false // Fehler
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

    // --- GEÄNDERT: performLogoutCleanup setzt Filter zurück ---
    private func performLogoutCleanup() async {
        Self.logger.debug("Performing local logout cleanup.");
        // Reset Auth State
        self.isLoggedIn = false;
        self.currentUser = nil;
        self.needsCaptcha = false; // Captcha wird bei Bedarf neu geholt
        self.captchaToken = nil;
        self.captchaImage = nil;

        // Clear Network Cookies
        clearCookies()

        // Clear Keychain Data
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
        _ = keychainService.deleteUsername(forKey: sessionUsernameKey)

        // Reset Content Filters in AppSettings
        self.appSettings.showSFW = true
        self.appSettings.showNSFW = false
        self.appSettings.showNSFL = false
        self.appSettings.showNSFP = false
        self.appSettings.showPOL = false
        Self.logger.info("Reset content filters to SFW-only.")

        // Optional: Clear Data Cache? Decide if this is desired on logout.
        // await appSettings.clearFeedCache()
        // await appSettings.clearFavoritesCache()
        // await appSettings.updateCacheSizes()
        // Self.logger.info("Cleared feed and favorites data cache on logout.")
    }
    // --- ENDE ÄNDERUNG ---


    private func clearCookies() {
        Self.logger.debug("Clearing cookies for pr0gramm.com domain.")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie); Self.logger.debug("Deleted cookie: \(cookie.name)") }
        Self.logger.info("Finished clearing cookies.")
    }

    @discardableResult
    private func findAndSaveSessionCookie() -> Bool {
        Self.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { Self.logger.warning("Could not retrieve cookies."); return false }
        guard let sessionCookie = cookies.first(where: { $0.name == self.sessionCookieName }) else { Self.logger.warning("Session cookie '\(self.sessionCookieName)' not found."); return false }
        guard let properties = sessionCookie.properties else { Self.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'."); return false }
        Self.logger.info("Found session cookie '\(self.sessionCookieName)'. Saving to keychain...")
        return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    private func loadAndRestoreSessionCookie() -> Bool {
        Self.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else { return false }
        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else { Self.logger.error("Failed to create HTTPCookie from keychain properties."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() { Self.logger.info("Restored cookie from keychain has expired."); _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey); return false }
        HTTPCookieStorage.shared.setCookie(restoredCookie)
        Self.logger.info("Successfully restored session cookie '\(restoredCookie.name)' into HTTPCookieStorage.")
        return true
    }
}
// --- END OF COMPLETE FILE ---
