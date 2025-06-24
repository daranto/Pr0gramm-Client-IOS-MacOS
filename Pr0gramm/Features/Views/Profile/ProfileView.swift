// Pr0gramm/Pr0gramm/Features/Views/Profile/ProfileView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher

enum ProfileNavigationTarget: Hashable {
    case uploads(username: String)
    case favoritedComments(username: String)
    case allCollections(username: String)
    case collectionItems(collection: ApiCollection, username: String)
    case userProfileComments(username: String) // Wieder hinzugefügt
    case postDetail(item: Item, targetCommentID: Int?)
    case userFollowList(username: String)
}

/// Displays the user's profile information when logged in, or prompts for login otherwise.
struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @State private var showingLoginSheet = false
    @State private var navigationPath = NavigationPath()

    @StateObject private var playerManager = VideoPlayerManager()

    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    .environmentObject(settings)
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
                        .environmentObject(playerManager) // PlayerManager hier übergeben
                 case .favoritedComments(let username):
                     UserFavoritedCommentsView(username: username)
                        .environmentObject(playerManager)
                 case .allCollections(let username):
                     UserCollectionsListView(username: username)
                 case .collectionItems(let collection, let username):
                     CollectionItemsView(collection: collection, username: username)
                        .environmentObject(playerManager)
                 case .userProfileComments(let username):
                     UserProfileCommentsView(username: username)
                        .environmentObject(playerManager)
                 case .postDetail(let item, let targetCommentID):
                     PagedDetailViewWrapperForItem(
                         item: item,
                         playerManager: playerManager,
                         targetCommentID: targetCommentID
                     )
                 case .userFollowList(let username):
                     UserFollowListView(username: username)
                        .environmentObject(playerManager)
                 }
            }
            // --- MODIFICATION: Entfernt von hier ---
            // .navigationDestination(for: Item.self) { item in
            //     PagedDetailViewWrapperForItem(
            //         item: item,
            //         playerManager: playerManager,
            //         targetCommentID: nil
            //     )
            //     .environmentObject(settings)
            //     .environmentObject(authService)
            // }
            // --- END MODIFICATION ---
            .task {
                playerManager.configure(settings: settings)
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
                    UserMarkView(markValue: user.mark)
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

                NavigationLink(value: ProfileNavigationTarget.userProfileComments(username: user.name)) {
                    Text("Meine Kommentare")
                        .font(UIConstants.bodyFont)
                }
                
                NavigationLink(value: ProfileNavigationTarget.userFollowList(username: user.name)) {
                    Text("Meine Stelzes (\(authService.followedUsers.count))")
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
            .padding(.leading, 1)
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

// MARK: - Previews
private struct LoggedInProfilePreviewWrapper: View {
    @StateObject private var settings: AppSettings
    @StateObject private var authService: AuthService
    @StateObject private var playerManager = VideoPlayerManager()


    init() {
        let si = AppSettings()
        let ai = AuthService(appSettings: si)
        ai.isLoggedIn = true

        let sampleBadges = [
            ApiBadge(image: "pr0-coin.png", description: "Hat 1 Tag pr0mium erschürft", created: 1500688733, link: "#top/2043677", category: nil)
        ]
        let sampleCollections = [
            ApiCollection(id: 101, name: "Meine Favoriten", keyword: "favoriten", isPublic: 0, isDefault: 1, itemCount: 1234),
            ApiCollection(id: 102, name: "Lustige Katzen Videos", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45)
        ]
        let sampleFollowed = [
            FollowListItem(subscribed: 1, name: "UserAlpha", mark: 2, followCreated: Int(Date().timeIntervalSince1970), itemId: 1, thumb: "t1.jpg", preview: nil, lastPost: Int(Date().timeIntervalSince1970)),
            FollowListItem(subscribed: 0, name: "UserBeta", mark: 0, followCreated: Int(Date().timeIntervalSince1970), itemId: 2, thumb: "t2.jpg", preview: nil, lastPost: Int(Date().timeIntervalSince1970))
        ]
        #if DEBUG
        ai.setFollowedUsersForPreview(sampleFollowed)
        #endif


        ai.currentUser = UserInfo(
            id: 1, name: "Daranto", registered: Int(Date().timeIntervalSince1970) - 500000,
            score: 1337, mark: 2, badges: sampleBadges, collections: sampleCollections
        )
        #if DEBUG
        ai.setUserCollectionsForPreview(sampleCollections)
        #endif

        _settings = StateObject(wrappedValue: si)
        _authService = StateObject(wrappedValue: ai)
        playerManager.configure(settings: si)
    }

    var body: some View {
        ProfileView()
            .environmentObject(settings)
            .environmentObject(authService)
            .environmentObject(playerManager)
    }
}

#Preview("Logged In with Badges & Collections") {
    LoggedInProfilePreviewWrapper()
}

#Preview("Logged Out") {
    ProfileView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
        .environmentObject(VideoPlayerManager())
}
// --- END OF COMPLETE FILE ---
