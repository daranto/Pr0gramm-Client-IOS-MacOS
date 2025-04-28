// Pr0gramm/Pr0gramm/Features/Views/Profile/ProfileView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher // Import Kingfisher

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
            // Use List directly for standard iOS profile appearance
            List {
                // Show different content based on login status
                if authService.isLoggedIn {
                    loggedInContent
                } else {
                    loggedOutContentSection // Embed logged out content in a section
                }
            }
            .navigationTitle(navigationTitleText)
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
            }
        }
    }

    /// Content displayed when the user is logged in. Structured as List Sections.
    @ViewBuilder
    private var loggedInContent: some View {
        // Section for Badges (optional)
        // --- MODIFIED: Check authService.currentUser for badges ---
        if let user = authService.currentUser, let badges = user.badges, !badges.isEmpty {
            Section { // No header text for badges section
                badgeScrollView(badges: badges)
                     .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)) // Adjust insets
            }
        }
        // --- END MODIFICATION ---

        Section("Benutzerinformationen") {
            if let user = authService.currentUser {
                // HStacks with Spacer for right-alignment
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

                // NavigationLink to uploads
                NavigationLink(value: user.name) {
                    Text("Meine Uploads")
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

    // ViewBuilder function for displaying badges horizontally
    @ViewBuilder
    private func badgeScrollView(badges: [ApiBadge]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // --- MODIFIED: Use badge.id (which is the image filename) ---
                ForEach(badges, id: \.id) { badge in
                    // --- MODIFIED: Use computed property for full URL ---
                    KFImage(badge.fullImageUrl)
                        .placeholder { // Optional: Add placeholder
                            Circle().fill(.gray.opacity(0.2)).frame(width: 32, height: 32)
                        }
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32) // Badge size
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                        .help(badge.description ?? "")
                }
            }
            .padding(.horizontal)
        }
    }


    /// Content displayed when the user is logged out, now structured as a List Section.
    @ViewBuilder
    private var loggedOutContentSection: some View {
        Section { // Wrap in Section for proper List display
            VStack(spacing: 20) {
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
                 .buttonStyle(.borderedProminent)
                 .disabled(authService.isLoading)
             }
             .frame(maxWidth: .infinity, alignment: .center) // Center content within the VStack
             .padding(.vertical) // Add some vertical padding
        }
    }


    /// Determines the navigation title based on login status and user data.
    private var navigationTitleText: String {
        if authService.isLoggedIn {
            return authService.currentUser?.name ?? "Profil"
        } else {
            return "Profil"
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


// MARK: - Previews (unverändert, zeigt jetzt Badges, da UserInfo angepasst wurde)

/// Wrapper view for creating a logged-in state for the ProfileView preview.
private struct LoggedInProfilePreviewWrapper: View {
    @StateObject private var settings: AppSettings
    @StateObject private var authService: AuthService

    init() {
        let si = AppSettings()
        let ai = AuthService(appSettings: si)
        ai.isLoggedIn = true // Simulate logged in

        // Sample badges using the updated structure
        let sampleBadges = [
            ApiBadge(image: "pr0-coin.png", description: "Hat 1 Tag pr0mium erschürft", created: 1500688733, link: "#top/2043677", category: nil),
            ApiBadge(image: "connect4-red.png", description: "Ging am 1. April 2018 siegreich hervor", created: 1522620001, link: "#top/2472492", category: nil),
            ApiBadge(image: "krebs-donation.png", description: "Hat gegen Krebs gespendet", created: 1525794290, link: "#top/Das%20pr0%20spendet", category: nil),
            ApiBadge(image: "benitrator-lose.png", description: "Hat im März 2019 nach 17 Drehs 16 Benis verzockt", created: 1554060600, link: "#top/3084263", category: nil),
            ApiBadge(image: "shopping-cart.png", description: "Kommerzhure", created: 1569425891, link: "https://pr0mart.com", category: nil)
        ]

        ai.currentUser = UserInfo(
            id: 1,
            name: "PreviewUser",
            registered: Int(Date().timeIntervalSince1970) - 500000,
            score: 1337,
            mark: 2,
            badges: sampleBadges // Include badges in preview user
        )

        _settings = StateObject(wrappedValue: si)
        _authService = StateObject(wrappedValue: ai)
    }

    var body: some View {
        ProfileView()
            .environmentObject(settings)
            .environmentObject(authService)
    }
}

#Preview("Logged In with Badges") {
    LoggedInProfilePreviewWrapper()
}

#Preview("Logged Out") {
    ProfileView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}
// --- END OF COMPLETE FILE ---
