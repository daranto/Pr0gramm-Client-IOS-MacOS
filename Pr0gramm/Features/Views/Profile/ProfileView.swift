// ProfileView.swift
import SwiftUI

struct ProfileView: View {
    // Zugriff auf den ECHTEN AuthService
    @EnvironmentObject var authService: AuthService // Korrekter Typ!

    // State-Variable zur Steuerung der LoginView-Präsentation
    @State private var showingLoginSheet = false

    var body: some View {
        NavigationStack {
            VStack { // Verwende VStack für Flexibilität
                if authService.isLoggedIn {
                    // --- Ansicht für eingeloggte Benutzer ---
                    loggedInContent
                } else {
                    // --- Ansicht für ausgeloggte Benutzer ---
                    loggedOutContent
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showingLoginSheet) {
                LoginView()
                    .environmentObject(authService) // Echten Service übergeben
            }
            .overlay {
                 if authService.isLoading {
                      ProgressView(authService.isLoggedIn ? "Aktion läuft..." : "Lade Status...")
                         .padding().background(Material.regular).cornerRadius(10)
                 }
            }
        }
    }

    // MARK: - Logged In Content (Angepasst für AccountInfo)
    @ViewBuilder
    private var loggedInContent: some View {
        List {
            Section("Account Informationen") {
                if let account = authService.currentAccount {
                    HStack { Text("Status"); Spacer(); UserMarkView(mark: account.mark) }
                    if let paidUntilTimestamp = account.paidUntil {
                         HStack { Text("Pr0mium bis"); Spacer(); Text(Date(timeIntervalSince1970: TimeInterval(paidUntilTimestamp)), style: .date).foregroundColor(.secondary) }
                    }
                    if let email = account.email, !email.isEmpty {
                         HStack { Text("E-Mail"); Spacer(); Text(email).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle) }
                    }
                    // Hinweis auf fehlende Infos
                    // Text("Weitere Benutzerdaten (Name, Score) nicht verfügbar.").font(.caption).foregroundColor(.orange)

                } else {
                    HStack { Spacer(); ProgressView(); Text("Lade Accountdaten...").foregroundColor(.secondary).font(.footnote); Spacer() }.listRowSeparator(.hidden)
                }
            }

            Section { // Logout-Button
                 Button("Logout", role: .destructive) { Task { await authService.logout() } }
                 .disabled(authService.isLoading).frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Logged Out Content (Unverändert)
    @ViewBuilder
    private var loggedOutContent: some View {
       VStack(spacing: 20) { /* ... wie zuvor ... */
            Spacer(); Text("Du bist nicht angemeldet.").font(.headline).foregroundColor(.secondary)
            Button { showingLoginSheet = true } label: { HStack { Image(systemName: "person.crop.circle.badge.plus"); Text("Anmelden oder Registrieren") }.padding(.horizontal) }
            .buttonStyle(.borderedProminent).disabled(authService.isLoading)
            Spacer(); Spacer()
        }.padding()
    }
}

// MARK: - UserMarkView (Helper - Unverändert)
struct UserMarkView: View { /* ... wie zuvor ... */
    let mark: Int
    private var markColor: Color { switch mark { case 1: return .orange; case 2: return .green; case 3: return .blue; case 4: return .purple; case 5: return .pink; case 6: return .gray; case 7: return .yellow; case 8: return .white.opacity(0.9); case 9: return Color(red: 0.6, green: 0.8, blue: 1.0); case 10: return Color(red: 1.0, green: 0.8, blue: 0.4); case 11: return Color(red: 0.4, green: 0.9, blue: 0.4); case 12: return Color(red: 1.0, green: 0.6, blue: 0.6); default: return .secondary } }
    private var markName: String { switch mark { case 1: return "Schwuchtel"; case 2: return "Neuschwuchtel"; case 3: return "Altschwuchtel"; case 4: return "Admin"; case 5: return "Gebannt"; case 6: return "Pr0mium"; case 7: return "Mittelaltschwuchtel"; case 8: return "Uraltschwuchtel"; case 9: return "Legende"; case 10: return "Wichtel"; case 11: return "Helfer"; case 12: return "Moderator"; default: return "Unbekannt (\(mark))" } }
    var body: some View { HStack(spacing: 5) { Circle().fill(markColor).frame(width: 8, height: 8); Text(markName).font(.subheadline).foregroundColor(markColor) } }
}


// MARK: - Previews (Mit Wrapper für Logged In)

// Wrapper-View speziell für die "Logged In"-Preview mit dem ECHTEN AuthService
private struct LoggedInPreviewWrapper: View {
    // Erstellt und besitzt den ECHTEN AuthService für diese Preview
    @StateObject private var authService = AuthService()

    var body: some View {
        // Führe das Setup hier aus, BEVOR die eigentliche View zurückgegeben wird
        // Die Zuweisungen passieren innerhalb der Wrapper-View's Body-Berechnung
        let _ = setupAuthService() // Ruft die Setup-Funktion auf

        ProfileView() // Die eigentliche View
            .environmentObject(authService) // Übergib den konfigurierten Service
    }

    // Hilfsfunktion, um den Body sauber zu halten
    private func setupAuthService() {
        // Nur setzen, wenn noch nicht gesetzt (verhindert Loops)
        // Verwende AccountInfo, da AuthService dies jetzt intern nutzt
        if !authService.isLoggedIn {
            authService.isLoggedIn = true
            authService.currentAccount = AccountInfo(likesArePublic: false, deviceMail: false, email: "preview@test.com", mark: 6, markDefault: 0, paidUntil: Int(Date().timeIntervalSince1970) + 86400, hasBetaAccess: false)
            print("LoggedInPreviewWrapper: Setup complete.") // Debugging
        }
    }
}

// Die "Logged In"-Preview instanziiert jetzt NUR den Wrapper
#Preview("Logged In") {
    LoggedInPreviewWrapper()
}

// Die "Logged Out"-Preview bleibt einfach
#Preview("Logged Out") {
     let authService = AuthService() // Echter Service
     ProfileView()
         .environmentObject(authService)
}
