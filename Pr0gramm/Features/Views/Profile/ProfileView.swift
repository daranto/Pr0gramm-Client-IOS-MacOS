// Pr0gramm/Pr0gramm/Features/Views/Profile/ProfileView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher

enum ProfileNavigationTarget: Hashable {
    case uploads(username: String)
    case favoritedComments(username: String)
    case allCollections(username: String)
    case collectionItems(collection: ApiCollection, username: String)
    case allUserUploads(username: String)
    case allUserComments(username: String)
}

/// Displays the user's profile information when logged in, or prompts for login otherwise.
struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @State private var showingLoginSheet = false

    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if authService.isLoggedIn {
                    loggedInContent
                } else {
                    loggedOutContentSection
                }
            }
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
            .navigationDestination(for: ProfileNavigationTarget.self) { target in
                 switch target {
                 case .uploads(let username):
                     UserUploadsView(username: username)
                 case .favoritedComments(let username):
                     UserFavoritedCommentsView(username: username)
                 case .allCollections(let username):
                     UserCollectionsListView(username: username)
                 case .collectionItems(let collection, let username):
                     CollectionItemsView(collection: collection, username: username)
                 case .allUserUploads(let username):
                     UserUploadsView(username: username)
                 case .allUserComments(let username):
                     UserProfileCommentsView(username: username)
                 }
            }
        }
    }

    @ViewBuilder
    private var loggedInContent: some View {
        if let user = authService.currentUser, let badges = user.badges, !badges.isEmpty {
            Section {
                badgeScrollView(badges: badges)
                     .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }

        Section("Benutzerinformationen") {
            if let user = authService.currentUser {
                HStack {
                    Text("Rang")
                        .font(UIConstants.bodyFont)
                    Spacer()
                    UserMarkView(markValue: user.mark) // Hier wird UserMarkView verwendet
                }
                HStack {
                    Text("Benis")
                        .font(UIConstants.bodyFont)
                    Spacer()
                    Text("\(user.score)")
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Registriert seit")
                        .font(UIConstants.bodyFont)
                    Spacer()
                    Text(formatDateGerman(date: Date(timeIntervalSince1970: TimeInterval(user.registered))))
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                }

                NavigationLink(value: ProfileNavigationTarget.uploads(username: user.name)) {
                    Text("Meine Uploads")
                        .font(UIConstants.bodyFont)
                }
                
                if !authService.userCollections.isEmpty {
                    NavigationLink(value: ProfileNavigationTarget.allCollections(username: user.name)) {
                        Text("Meine Sammlungen (\(authService.userCollections.count))")
                            .font(UIConstants.bodyFont)
                    }
                }

                NavigationLink(value: ProfileNavigationTarget.favoritedComments(username: user.name)) {
                     Text("Favorisierte Kommentare")
                         .font(UIConstants.bodyFont)
                 }

            } else {
                HStack { Spacer(); ProgressView(); Text("Lade Profildaten...")
                        .font(UIConstants.footnoteFont)
                        .foregroundColor(.secondary); Spacer() }.listRowSeparator(.hidden)
            }
        }
        .headerProminence(.increased)

        Section("pr0gramm unterstützen") {
            VStack(alignment: .leading, spacing: 8) {
                 Text("Wenn dir die App und pr0gramm gefallen, ziehe in Erwägung, die Plattform zu unterstützen. Diese App enthält keine Werbung und ist kostenlos.")
                     .font(UIConstants.footnoteFont)
                     .foregroundColor(.secondary)
                     .padding(.bottom, 5)
                 if let url = URL(string: "https://pr0mart.com/Nach-Kategorien/Sonstiges/pr0mium/") {
                     Link(destination: url) {
                         HStack {
                             Text("pr0mium über pr0mart erwerben")
                                .font(UIConstants.bodyFont)
                                .foregroundColor(.accentColor)
                             Spacer()
                             Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                         }
                     }
                 }
            }
        }
        .headerProminence(.increased)

        Section {
             Button("Logout", role: .destructive) {
                 Task { await authService.logout() }
             }
             .disabled(authService.isLoading)
             .frame(maxWidth: .infinity, alignment: .center)
             .font(UIConstants.bodyFont)
        }
    }

    @ViewBuilder
    private func badgeScrollView(badges: [ApiBadge]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(badges, id: \.id) { badge in
                    KFImage(badge.fullImageUrl)
                        .placeholder { Circle().fill(.gray.opacity(0.2)).frame(width: 32, height: 32) }
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                        .clipShape(Circle()).overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                        .help(badge.description ?? "")
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var loggedOutContentSection: some View {
        Section {
            VStack(spacing: 20) {
                 Text("Du bist nicht angemeldet.")
                     .font(UIConstants.headlineFont)
                     .foregroundColor(.secondary)
                 Button { showingLoginSheet = true } label: {
                     HStack { Image(systemName: "person.crop.circle.badge.plus"); Text("Anmelden") }.padding(.horizontal)
                 }
                 .buttonStyle(.borderedProminent)
                 .disabled(authService.isLoading)
                 .font(UIConstants.bodyFont)
             }
             .frame(maxWidth: .infinity, alignment: .center)
             .padding(.vertical)
        }
    }

    private var navigationTitleText: String {
        if authService.isLoggedIn {
            return authService.currentUser?.name ?? "Profil"
        } else {
            return "Profil"
        }
    }

    private func formatDateGerman(date: Date) -> String {
        return germanDateFormatter.string(from: date)
    }
}

struct UserMarkView: View {
    let markValue: Int?
    private var markEnum: Mark
    init(markValue: Int?) {
        self.markValue = markValue
        self.markEnum = Mark(rawValue: markValue ?? -1)
    }
    static func getMarkName(for mark: Int) -> String { Mark(rawValue: mark).displayName }
    private var markColor: Color { markEnum.displayColor }
    // private var markName: String { markEnum.displayName } // Nicht mehr benötigt für die Anzeige

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(markColor)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                .frame(width: 8, height: 8)
            // --- MODIFIED: Text(markName) entfernt ---
            // Text(markName)
            //     .font(UIConstants.subheadlineFont)
            //     .foregroundColor(.secondary)
            // --- END MODIFICATION ---
        }
    }
}

// MARK: - Previews
private struct LoggedInProfilePreviewWrapper: View {
    @StateObject private var settings: AppSettings
    @StateObject private var authService: AuthService

    init() {
        let si = AppSettings()
        let ai = AuthService(appSettings: si)
        ai.isLoggedIn = true

        let sampleBadges = [
            ApiBadge(image: "pr0-coin.png", description: "Hat 1 Tag pr0mium erschürft", created: 1500688733, link: "#top/2043677", category: nil)
        ]
        let sampleCollections = [
            ApiCollection(id: 101, name: "Meine Favoriten", keyword: "favoriten", isPublic: 0, isDefault: 1, itemCount: 123),
            ApiCollection(id: 102, name: "Lustige Katzen", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45)
        ]

        ai.currentUser = UserInfo(
            id: 1, name: "Daranto", registered: Int(Date().timeIntervalSince1970) - 500000,
            score: 1337, mark: 2, badges: sampleBadges, collections: sampleCollections
        )
        #if DEBUG
        ai.setUserCollectionsForPreview(sampleCollections)
        #endif

        _settings = StateObject(wrappedValue: si)
        _authService = StateObject(wrappedValue: ai)
    }

    var body: some View {
        ProfileView()
            .environmentObject(settings)
            .environmentObject(authService)
    }
}

#Preview("Logged In with Badges & Collections") {
    LoggedInProfilePreviewWrapper()
}

#Preview("Logged Out") {
    ProfileView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}
// --- END OF COMPLETE FILE ---
