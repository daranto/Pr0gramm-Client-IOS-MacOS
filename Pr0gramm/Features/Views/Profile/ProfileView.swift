// Pr0gramm/Pr0gramm/Features/Views/Profile/ProfileView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Displays the user's profile information when logged in, or prompts for login otherwise.
struct ProfileView: View {
    @EnvironmentObject var authService: AuthService // Access authentication state
    @EnvironmentObject var settings: AppSettings // Required for preview setup
    /// State to control the presentation of the login sheet.
    @State private var showingLoginSheet = false

    // Date formatter for German locale
    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long // e.g., "3. Mai 2014"
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            VStack {
                // Show different content based on login status
                if authService.isLoggedIn {
                    loggedInContent
                } else {
                    loggedOutContent
                }
            }
            .navigationTitle(navigationTitleText) // Dynamic title
            .sheet(isPresented: $showingLoginSheet) {
                // Present the LoginView sheet
                LoginView()
                    .environmentObject(authService) // Pass only AuthService
            }
            .overlay { // Show loading indicator during login/logout
                 if authService.isLoading {
                      ProgressView(authService.isLoggedIn ? "Aktion läuft..." : "Lade Status...")
                         .padding().background(Material.regular).cornerRadius(10)
                 }
            }
            // Add navigation destination for UserUploadsView
            .navigationDestination(for: String.self) { username in
                 UserUploadsView(username: username)
                     // EnvironmentObjects are typically passed down automatically in NavigationStack destinations
            }
        }
    }

    /// Content displayed when the user is logged in. Shows user details and logout button.
    @ViewBuilder
    private var loggedInContent: some View {
        List {
            Section("Benutzerinformationen") {
                if let user = authService.currentUser {
                    // --- REMOVED Username HStack ---
                    // HStack {
                    //     Text("Username")
                    //     Spacer()
                    //     Text(user.name).foregroundColor(.secondary)
                    // }
                    // --- END REMOVAL ---

                    HStack {
                        Text("Rang")
                        Spacer()
                        UserMarkView(markValue: user.mark)
                    }
                    HStack {
                        Text("Benis")
                        Spacer()
                        Text("\(user.score)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Registriert seit")
                        Spacer()
                        Text(formatDateGerman(date: Date(timeIntervalSince1970: TimeInterval(user.registered))))
                             .foregroundColor(.secondary)
                    }

                    // NavigationLink to uploads remains unchanged
                    NavigationLink(value: user.name) {
                        Text("Meine Uploads") // Use plain Text for precise alignment
                    }

                } else {
                    // Show placeholder while user data might still be loading initially
                    HStack { Spacer(); ProgressView(); Text("Lade Profildaten...").foregroundColor(.secondary).font(.footnote); Spacer() }.listRowSeparator(.hidden)
                }
            }
            Section {
                 // Logout button
                 Button("Logout", role: .destructive) {
                     Task { await authService.logout() } // Perform logout asynchronously
                 }
                 .disabled(authService.isLoading) // Disable during loading
                 .frame(maxWidth: .infinity, alignment: .center) // Center the button text
            }
        }
    }

    /// Content displayed when the user is logged out. Shows a login prompt.
    @ViewBuilder
    private var loggedOutContent: some View {
       VStack(spacing: 20) {
            Spacer() // Push content towards center
            Text("Du bist nicht angemeldet.")
                .font(.headline)
                .foregroundColor(.secondary)
            // Button to open the login sheet
            Button { showingLoginSheet = true } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Anmelden")
                }.padding(.horizontal)
            }
            .buttonStyle(.borderedProminent) // Use prominent style for primary action
            .disabled(authService.isLoading) // Disable if already loading auth state
            Spacer() // Push content towards center
            Spacer()
        }.padding()
    }

    /// Determines the navigation title based on login status and user data.
    private var navigationTitleText: String {
        if authService.isLoggedIn {
            // Use username if available, otherwise fallback to rank name
            return authService.currentUser?.name ?? UserMarkView.getMarkName(for: authService.currentUser?.mark ?? -1)
        } else {
            return "Profil" // Default title when logged out
        }
    }

    // Helper function for date formatting (unchanged)
    private func formatDateGerman(date: Date) -> String {
        return germanDateFormatter.string(from: date)
    }
}

// MARK: - Helper View: UserMarkView (unchanged)

/// A small reusable view to display the user's rank (mark) with its corresponding color indicator and name.
struct UserMarkView: View {
    let markValue: Int
    private var markEnum: Mark

    init(markValue: Int) {
        self.markValue = markValue
        self.markEnum = Mark(rawValue: markValue) // Initialize enum from raw value
    }

    /// Static helper to get the mark name without creating an instance.
    static func getMarkName(for mark: Int) -> String { Mark(rawValue: mark).displayName }

    private var markColor: Color { markEnum.displayColor }
    private var markName: String { markEnum.displayName }

    var body: some View {
        HStack(spacing: 5) {
            Circle() // Color indicator
                .fill(markColor)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5)) // Subtle border
                .frame(width: 8, height: 8)
            Text(markName) // Rank name
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}


// MARK: - Previews (unchanged)

/// Wrapper view for creating a logged-in state for the ProfileView preview.
private struct LoggedInProfilePreviewWrapper: View {
    @StateObject private var settings: AppSettings
    @StateObject private var authService: AuthService

    init() {
        let si = AppSettings()
        let ai = AuthService(appSettings: si)
        ai.isLoggedIn = true // Simulate logged in
        // Provide dummy user data
        ai.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: Int(Date().timeIntervalSince1970) - 500000, score: 1337, mark: 2) // Altschwuchtel
        _settings = StateObject(wrappedValue: si)
        _authService = StateObject(wrappedValue: ai)
    }

    var body: some View {
        ProfileView()
            .environmentObject(settings)
            .environmentObject(authService)
    }
}

#Preview("Logged In") {
    LoggedInProfilePreviewWrapper()
}

#Preview("Logged Out") {
    // Provide default (logged out) services for the preview
    ProfileView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}
// --- END OF COMPLETE FILE ---
