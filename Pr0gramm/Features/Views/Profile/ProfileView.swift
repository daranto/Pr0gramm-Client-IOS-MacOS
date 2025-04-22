// ProfileView.swift
import SwiftUI

struct ProfileView: View {
    // Wieder Zugriff auf den ECHTEN AuthService
    @EnvironmentObject var authService: AuthService

    @State private var showingLoginSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                if authService.isLoggedIn {
                    loggedInContent
                } else {
                    loggedOutContent
                }
            }
            // Titel zeigt jetzt wieder den Namen (wenn verfügbar)
            .navigationTitle(navigationTitleText)
            .sheet(isPresented: $showingLoginSheet) {
                LoginView()
                    .environmentObject(authService)
            }
            .overlay {
                 if authService.isLoading {
                      ProgressView(authService.isLoggedIn ? "Aktion läuft..." : "Lade Status...")
                         .padding().background(Material.regular).cornerRadius(10)
                 }
            }
        }
    }

    // MARK: - Logged In Content (Wieder mit UserInfo)
    @ViewBuilder
    private var loggedInContent: some View {
        List {
            Section("Benutzerinformationen") {
                if let user = authService.currentUser {
                    HStack { Text("Username"); Spacer(); Text(user.name).foregroundColor(.secondary) }
                    // Übergibt Int an UserMarkView
                    HStack { Text("Rang"); Spacer(); UserMarkView(markValue: user.mark) }
                    HStack { Text("Benis"); Spacer(); Text("\(user.score)").foregroundColor(.secondary) }
                    HStack { Text("Registriert seit"); Spacer(); Text(Date(timeIntervalSince1970: TimeInterval(user.registered)), style: .date).foregroundColor(.secondary) }
                } else {
                    HStack { Spacer(); ProgressView(); Text("Lade Profildaten...").foregroundColor(.secondary).font(.footnote); Spacer() }.listRowSeparator(.hidden)
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
       VStack(spacing: 20) {
            Spacer(); Text("Du bist nicht angemeldet.").font(.headline).foregroundColor(.secondary)
            Button { showingLoginSheet = true } label: { HStack { Image(systemName: "person.crop.circle.badge.plus"); Text("Anmelden oder Registrieren") }.padding(.horizontal) }
            .buttonStyle(.borderedProminent).disabled(authService.isLoading)
            Spacer(); Spacer()
        }.padding()
    }

    // MARK: - Computed Properties (Wieder mit Name)
    private var navigationTitleText: String {
        if authService.isLoggedIn {
            // Verwendet jetzt die sicherere Methode mit Fallback
            return authService.currentUser?.name ?? UserMarkView.getMarkName(for: authService.currentUser?.mark ?? -1)
        } else {
            return "Profil"
        }
    }
}

// MARK: - UserMarkView (Korrigierter Init und Static Func)
struct UserMarkView: View {
    let markValue: Int
    private var markEnum: Mark // Nicht-optional

    init(markValue: Int) {
        self.markValue = markValue
        // **** KORREKTUR: Verwende den sicheren Initializer aus Mark ****
        // Dieser gibt immer einen gültigen Mark zurück (ggf. .unbekannt)
        self.markEnum = Mark(rawValue: markValue)
    }

    // Statische Funktion, um Namen von außen zu bekommen
    static func getMarkName(for mark: Int) -> String {
        // **** KORREKTUR: Nutze den sicheren Initializer ****
        // Gibt den Namen für den Enum-Wert oder für .unbekannt zurück
        return Mark(rawValue: mark).displayName
    }

    private var markColor: Color {
        return markEnum.displayColor
    }

    private var markName: String {
        return markEnum.displayName
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(markColor).frame(width: 8, height: 8)
            Text(markName).font(.subheadline).foregroundColor(markColor)
        }
    }
}


// MARK: - Previews (Unverändert zur letzten Version)
private struct LoggedInPreviewWrapper: View {
    @StateObject private var authService = AuthService()
    var body: some View { let _ = setupAuthService(); ProfileView().environmentObject(authService) }
    private func setupAuthService() {
        if !authService.isLoggedIn {
            authService.isLoggedIn = true
            authService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: Int(Date().timeIntervalSince1970) - 500000, score: 1337, mark: 0) // Mark 0
        }
    }
}
#Preview("Logged In") { LoggedInPreviewWrapper() }
#Preview("Logged Out") { let authService = AuthService(); ProfileView().environmentObject(authService) }
