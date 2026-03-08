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
    case inbox
}

/// Displays the user's profile information when logged in, or prompts for login otherwise.
struct ProfileView: View {
    @Environment(AuthService.self) var authService
    @Environment(AppSettings.self) var settings
    @State private var showingLoginSheet = false
    @State private var showingCalendar = false
    @State private var showingInbox = false
    @State private var navigationPath = NavigationPath()

    @State private var playerManager = VideoPlayerManager()
    @State private var navigationService = NavigationService()

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
            .safeAreaInset(edge: .bottom) {
                // Create invisible spacer that matches tab bar height
                Color.clear
                    .frame(height: 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8))
            }
            .navigationTitle(navigationTitleText)
            .toolbar {
                if authService.isLoggedIn {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingInbox = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "envelope")
                                    .foregroundColor(.accentColor)
                                    .imageScale(.large)
                                
                                if authService.unreadInboxTotal > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 6, y: -6)
                                }
                            }
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingCalendar = true
                        } label: {
                            Image(systemName: "calendar")
                                .foregroundColor(.accentColor)
                                .imageScale(.large)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                LoginView()
                    .environment(authService)
                    .environment(settings)
            }
            .sheet(isPresented: $showingCalendar) {
                CalendarView()
                    .environment(authService)
                    .environment(settings)
            }
            .sheet(isPresented: $showingInbox) {
                NavigationStack {
                    InboxContentOnlyView()
                        .environment(settings)
                        .environment(authService)
                        .environment(playerManager)
                        .environment(navigationService)
                        .navigationTitle("Nachrichten")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fertig") {
                                    showingInbox = false
                                }
                            }
                        }
                }
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
                        .environment(playerManager) // PlayerManager hier übergeben
                 case .favoritedComments(let username):
                     UserFavoritedCommentsView(username: username)
                        .environment(playerManager)
                 case .allCollections(let username):
                     UserCollectionsListView(username: username)
                 case .collectionItems(let collection, let username):
                     CollectionItemsView(collection: collection, username: username)
                        .environment(playerManager)
                 case .userProfileComments(let username):
                     UserProfileCommentsView(username: username)
                        .environment(playerManager)
                 case .postDetail(let item, let targetCommentID):
                     PagedDetailViewWrapperForItem(
                         item: item,
                         playerManager: playerManager,
                         targetCommentID: targetCommentID
                     )
                 case .userFollowList(let username):
                     UserFollowListView(username: username)
                        .environment(playerManager)
                 case .inbox:
                     InboxContentOnlyView()
                        .environment(settings)
                        .environment(authService)
                        .environment(playerManager)
                        .environment(navigationService)
                 }
            }
            // --- MODIFICATION: Entfernt von hier ---
            // .navigationDestination(for: Item.self) { item in
            //     PagedDetailViewWrapperForItem(
            //         item: item,
            //         playerManager: playerManager,
            //         targetCommentID: nil
            //     )
            //     .environment(settings)
            //     .environment(authService)
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
                    Label {
                        Text("Rang")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    UserMarkView(markValue: user.mark)
                }
                HStack {
                    Label {
                        Text("Benis")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("\(user.score)")
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Label {
                        Text("Registriert seit")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.blue)
                    }
                    Spacer()
                    Text(formatDateGerman(date: Date(timeIntervalSince1970: TimeInterval(user.registered))))
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                }

                NavigationLink(value: ProfileNavigationTarget.uploads(username: user.name)) {
                    Label {
                        Text("Meine Uploads")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.purple)
                    }
                }

                NavigationLink(value: ProfileNavigationTarget.userProfileComments(username: user.name)) {
                    Label {
                        Text("Meine Kommentare")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                NavigationLink(value: ProfileNavigationTarget.userFollowList(username: user.name)) {
                    Label {
                        Text("Meine Stelzes (\(authService.followedUsers.count))")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.pink)
                    }
                }


                if !authService.userCollections.isEmpty {
                    NavigationLink(value: ProfileNavigationTarget.allCollections(username: user.name)) {
                        Label {
                            Text("Meine Sammlungen (\(authService.userCollections.count))")
                                .font(UIConstants.bodyFont)
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }

                NavigationLink(value: ProfileNavigationTarget.favoritedComments(username: user.name)) {
                    Label {
                        Text("Favorisierte Kommentare")
                            .font(UIConstants.bodyFont)
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    }
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
    @State private var settings: AppSettings
    @State private var authService: AuthService
    @State private var playerManager = VideoPlayerManager()


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

        _settings = State(wrappedValue: si)
        _authService = State(wrappedValue: ai)
        playerManager.configure(settings: si)
    }

    var body: some View {
        ProfileView()
            .environment(settings)
            .environment(authService)
            .environment(playerManager)
    }
}

#Preview("Logged In with Badges & Collections") {
    LoggedInProfilePreviewWrapper()
}

#Preview("Logged Out") {
    ProfileView()
        .environment(AppSettings())
        .environment(AuthService(appSettings: AppSettings()))
        .environment(VideoPlayerManager())
}
// --- END OF COMPLETE FILE ---
