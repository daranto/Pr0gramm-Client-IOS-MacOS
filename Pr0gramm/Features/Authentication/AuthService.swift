// AuthService.swift

import Foundation
import Combine
import os
import UIKit

@MainActor
class AuthService: ObservableObject {

    // MARK: - Dependencies
    private let apiService = APIService()
    private let keychainService = KeychainService() // Keychain Service Instanz
    private let sessionCookieKey = "pr0grammSessionCookie_v1" // Eindeutiger Key für Keychain
    private let sessionCookieName = "me" // Erwarteter Name des Session Cookies (!! PRÜFEN !!)

    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    // **** GEÄNDERT: Typ zu AccountInfo? ****
    @Published var currentAccount: AccountInfo? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loginError: String? = nil
    @Published private(set) var needsCaptcha: Bool = false
    @Published private(set) var captchaToken: String? = nil
    @Published private(set) var captchaImage: UIImage? = nil

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")

    init() {
        Self.logger.info("AuthService initialized.")
        // Check Initial Status wird im .task der App aufgerufen
    }

    // MARK: - Public Methods

    /// Wird von der LoginView aufgerufen, wenn sie erscheint, um das Captcha vorab zu laden.
    func fetchInitialCaptcha() async {
        Self.logger.info("fetchInitialCaptcha called by LoginView.")
        self.needsCaptcha = true // Gehen davon aus, dass es immer benötigt wird
        await _fetchCaptcha()     // Ruft die private Fetch-Logik auf
    }

    func login(username: String, password: String, captchaAnswer: String? = nil) async {
        guard !isLoading else { Self.logger.warning("Login attempt skipped: Already loading."); return }
        Self.logger.info("Attempting login for user: \(username)"); isLoading = true; loginError = nil

        let credentials = APIService.LoginRequest(
            username: username, password: password,
            captcha: captchaAnswer, token: self.captchaToken
        )

        if self.needsCaptcha && (captchaAnswer?.isEmpty ?? true || self.captchaToken?.isEmpty ?? true) {
             self.loginError = "Bitte Captcha eingeben."
             Self.logger.warning("Login attempt failed: Captcha required but data missing.")
             isLoading = false
             return
        }

        do {
            let response = try await apiService.login(credentials: credentials)

            if response.success {
                Self.logger.info("Login successful via API for user: \(username)")
                await loadAccountInfo(setLoadingState: false) // Lade AccountInfo
                if self.currentAccount != nil { // Prüfe auf AccountInfo
                    if findAndSaveSessionCookie() { Self.logger.info("Successfully saved session cookie to keychain.") }
                    else { Self.logger.warning("Failed to save session cookie to keychain after successful login.") }
                    self.isLoggedIn = true
                    self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil // Reset nach Erfolg
                    Self.logger.info("User (Mark: \(self.currentAccount!.mark)) is now logged in.") // Log mit Mark
                } else {
                    self.isLoggedIn = false
                    self.loginError = "Login erfolgreich, aber Accountdaten konnten nicht geladen werden."
                    Self.logger.error("Login failed: loadAccountInfo failed after successful API login.")
                    await performLogoutCleanup()
                }
            } else { // success: false
                if response.ban?.banned == true {
                    let banReason = response.ban?.reason ?? "Unbekannter Grund"; let banEnd = response.ban?.till.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "Unbekannt"
                    self.loginError = "Login fehlgeschlagen: Benutzer ist gebannt. Grund: \(banReason) (Bis: \(banEnd))"
                    Self.logger.warning("Login failed: User \(username) is banned.")
                    await performLogoutCleanup()
                } else {
                    self.loginError = response.error ?? "Falsche Anmeldedaten oder Captcha."
                    Self.logger.warning("Login failed (API Error): \(self.loginError!) - User: \(username)")
                    if self.needsCaptcha { Self.logger.info("Fetching new captcha after failed login attempt."); await _fetchCaptcha() }
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
        // Log ohne Namen
        Self.logger.info("Attempting logout..."); isLoading = true
        do { try await apiService.logout(); Self.logger.info("Logout successful via API.") }
        catch { Self.logger.error("API logout failed: \(error.localizedDescription). Proceeding with local cleanup.") }
        await performLogoutCleanup(); isLoading = false; Self.logger.info("Logout process finished.")
    }

    func checkInitialLoginStatus() async {
        Self.logger.info("Checking initial login status..."); isLoading = true
        if loadAndRestoreSessionCookie() {
             Self.logger.info("Session cookie restored from keychain.")
             await loadAccountInfo(setLoadingState: false) // Lade AccountInfo
        } else {
             Self.logger.info("No session cookie found in keychain.")
             self.currentAccount = nil // Setze Account auf nil
        }
        // Prüfe auf currentAccount statt currentUser
        if self.currentAccount != nil {
            self.isLoggedIn = true
            // Log ohne Namen
            Self.logger.info("Initial check: User (Mark: \(self.currentAccount!.mark)) is logged in (via restored cookie).")
        } else {
            self.isLoggedIn = false
            Self.logger.info("Initial check: User is not logged in.")
            clearCookies()
            _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey) // _ hinzugefügt
        }
        isLoading = false
    }

    // MARK: - Private Helper Methods

    /// Lädt die Account-Informationen.
    private func loadAccountInfo(setLoadingState: Bool = true) async { // Umbenannt von loadUserInfo
        Self.logger.debug("Attempting to load account info..."); if setLoadingState { isLoading = true }; loginError = nil
        do {
            let userInfoResponse = try await apiService.getUserInfo()
            self.currentAccount = userInfoResponse.account // Setzt currentAccount
            // Log ohne Namen
            Self.logger.info("Successfully loaded account info (Mark: \(self.currentAccount!.mark))")
        } catch {
            Self.logger.warning("Failed to load account info: \(error.localizedDescription). Assuming user is logged out.")
            self.currentAccount = nil // Setzt currentAccount auf nil
        }
        if setLoadingState { isLoading = false }
    }

    /// Holt ein neues Captcha vom Server und aktualisiert die Published Properties.
    private func _fetchCaptcha() async { // Private Version
        Self.logger.info("Fetching new captcha data..."); self.captchaImage = nil; self.captchaToken = nil; self.loginError = nil // Reset state

        do {
            let captchaResponse = try await apiService.fetchCaptcha()
            self.captchaToken = captchaResponse.token

            // Base64 Prefix entfernen
            var base64String = captchaResponse.captcha
            if let commaRange = base64String.range(of: ",") {
                base64String = String(base64String[commaRange.upperBound...])
                Self.logger.debug("Removed base64 prefix.")
            } else { Self.logger.debug("No base64 prefix found.") }

            // Decode Base64 Image
            if let imageData = Data(base64Encoded: base64String) {
                self.captchaImage = UIImage(data: imageData)
                 if self.captchaImage != nil { Self.logger.info("Successfully decoded captcha image.") }
                 else { Self.logger.error("Failed to create UIImage from decoded captcha data."); self.loginError = "Captcha konnte nicht angezeigt werden." }
            } else {
                 Self.logger.error("Failed to decode base64 captcha string (after potential prefix removal)."); self.loginError = "Captcha konnte nicht dekodiert werden."
            }
        } catch {
             Self.logger.error("Failed to fetch captcha: \(error.localizedDescription)"); self.loginError = "Captcha konnte nicht geladen werden."
        }
    }

    /// Setzt den lokalen Authentifizierungsstatus zurück und löscht Cookies/Keychain-Daten.
    private func performLogoutCleanup() async {
        Self.logger.debug("Performing local logout cleanup."); self.isLoggedIn = false;
        self.currentAccount = nil // Setzt currentAccount auf nil
        self.needsCaptcha = false; self.captchaToken = nil; self.captchaImage = nil
        clearCookies()
        // Ignoriere Rückgabewert von delete
        _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey)
    }

    /// Löscht alle Cookies für die pr0gramm.com Domain aus dem HTTPCookieStorage.
    private func clearCookies() {
        Self.logger.debug("Clearing cookies for pr0gramm.com domain.")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
            Self.logger.debug("Deleted cookie: \(cookie.name)")
        }
        Self.logger.info("Finished clearing cookies.")
    }

    /// Sucht das Session Cookie im HTTPCookieStorage und speichert es im Keychain
    @discardableResult // Erlaubt das Ignorieren des Rückgabewerts
    private func findAndSaveSessionCookie() -> Bool {
        Self.logger.debug("Attempting to find and save session cookie '\(self.sessionCookieName)'...")
        guard let url = URL(string: "https://pr0gramm.com"), let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            Self.logger.warning("Could not retrieve cookies from HTTPCookieStorage for pr0gramm.com")
            return false
        }

        guard let sessionCookie = cookies.first(where: { $0.name == self.sessionCookieName }) else {
            Self.logger.warning("Session cookie named '\(self.sessionCookieName)' not found in HTTPCookieStorage.")
            return false
        }

        guard let properties = sessionCookie.properties else {
            Self.logger.warning("Could not get properties from session cookie '\(self.sessionCookieName)'.")
            return false
        }

        Self.logger.info("Found session cookie '\(self.sessionCookieName)'. Saving to keychain...")
        // Speichere die Eigenschaften im Keychain
        return keychainService.saveCookieProperties(properties, forKey: sessionCookieKey)
    }

    /// Lädt Cookie-Eigenschaften aus dem Keychain und stellt das Cookie im HTTPCookieStorage wieder her
    private func loadAndRestoreSessionCookie() -> Bool {
        Self.logger.debug("Attempting to load and restore session cookie from keychain...")
        guard let loadedProperties = keychainService.loadCookieProperties(forKey: sessionCookieKey) else {
            // Kein Fehler, einfach nicht gefunden
            return false
        }

        guard let restoredCookie = HTTPCookie(properties: loadedProperties) else {
            Self.logger.error("Failed to create HTTPCookie from properties loaded from keychain.")
            _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey) // Ignoriere Rückgabewert
            return false
        }

        if let expiryDate = restoredCookie.expiresDate, expiryDate < Date() {
            Self.logger.info("Restored cookie from keychain has expired (\(expiryDate)). Deleting it.")
            _ = keychainService.deleteCookieProperties(forKey: sessionCookieKey) // Ignoriere Rückgabewert
            return false
        }

        HTTPCookieStorage.shared.setCookie(restoredCookie)
        Self.logger.info("Successfully restored session cookie '\(restoredCookie.name)' into HTTPCookieStorage.")
        return true
    }
}
