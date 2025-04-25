// Pr0gramm/Pr0gramm/Features/Views/Profile/ProfileView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService // AuthService wird aus Environment geholt
    @EnvironmentObject var settings: AppSettings // Settings auch benötigt für Preview

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
            .navigationTitle(navigationTitleText)
            .sheet(isPresented: $showingLoginSheet) {
                // Übergebe hier NUR AuthService, da LoginView AppSettings nicht braucht
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

    @ViewBuilder
    private var loggedInContent: some View {
        List {
            Section("Benutzerinformationen") {
                if let user = authService.currentUser {
                    HStack { Text("Username"); Spacer(); Text(user.name).foregroundColor(.secondary) }
                    HStack { Text("Rang"); Spacer(); UserMarkView(markValue: user.mark) }
                    HStack { Text("Benis"); Spacer(); Text("\(user.score)").foregroundColor(.secondary) }
                    HStack { Text("Registriert seit"); Spacer(); Text(Date(timeIntervalSince1970: TimeInterval(user.registered)), style: .date).foregroundColor(.secondary) }
                } else {
                    HStack { Spacer(); ProgressView(); Text("Lade Profildaten...").foregroundColor(.secondary).font(.footnote); Spacer() }.listRowSeparator(.hidden)
                }
            }
            Section {
                 Button("Logout", role: .destructive) { Task { await authService.logout() } }
                 .disabled(authService.isLoading).frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // --- ÄNDERUNG HIER ---
    @ViewBuilder
    private var loggedOutContent: some View {
       VStack(spacing: 20) {
            Spacer(); Text("Du bist nicht angemeldet.").font(.headline).foregroundColor(.secondary)
            Button { showingLoginSheet = true } label: {
                // Nur Icon und Text "Anmelden"
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Anmelden") // Text geändert
                }.padding(.horizontal)
            }
            .buttonStyle(.borderedProminent).disabled(authService.isLoading)
            Spacer(); Spacer()
        }.padding()
    }
    // --- ENDE ÄNDERUNG ---

    private var navigationTitleText: String {
        if authService.isLoggedIn {
            return authService.currentUser?.name ?? UserMarkView.getMarkName(for: authService.currentUser?.mark ?? -1)
        } else {
            return "Profil"
        }
    }
}

// MARK: - UserMarkView (Unverändert)
struct UserMarkView: View {
    let markValue: Int; private var markEnum: Mark
    init(markValue: Int) { self.markValue = markValue; self.markEnum = Mark(rawValue: markValue) }
    static func getMarkName(for mark: Int) -> String { Mark(rawValue: mark).displayName }
    private var markColor: Color { markEnum.displayColor }; private var markName: String { markEnum.displayName }
    var body: some View { HStack(spacing: 5) { Circle().fill(markColor).overlay(Circle().stroke(Color.black, lineWidth: 0.5)).frame(width: 8, height: 8); Text(markName).font(.subheadline).foregroundColor(.secondary) } }
}


// MARK: - Previews (Unverändert)
private struct LoggedInPreviewWrapper: View {
    @StateObject private var settings: AppSettings
    @StateObject private var authService: AuthService
    init() { let si = AppSettings(); let ai = AuthService(appSettings: si); ai.isLoggedIn = true; ai.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: Int(Date().timeIntervalSince1970) - 500000, score: 1337, mark: 0); _settings = StateObject(wrappedValue: si); _authService = StateObject(wrappedValue: ai) }
    var body: some View { ProfileView().environmentObject(settings).environmentObject(authService) }
}
#Preview("Logged In") { LoggedInPreviewWrapper() }
#Preview("Logged Out") { ProfileView().environmentObject(AppSettings()).environmentObject(AuthService(appSettings: AppSettings())) }
// --- END OF COMPLETE FILE ---
