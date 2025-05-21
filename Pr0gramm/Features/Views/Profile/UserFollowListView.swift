// Pr0gramm/Pr0gramm/Features/Views/Profile/UserFollowListView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher
import os

struct UserFollowListView: View {
    let username: String

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var playerManager: VideoPlayerManager

    @State private var itemNavigationValue: ItemNavigationValue? = nil
    @State private var userProfileSheetTarget: ProfileNavigationValue? = nil
    
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil

    // --- NEW: State für Filter Sheet ---
    @State private var showingFilterSheet = false
    // --- END NEW ---

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserFollowListView")
    private let apiService = APIService()

    private var sortedFollowedUsers: [FollowListItem] {
        authService.followedUsers.sorted { $0.followCreated > $1.followCreated }
    }

    var body: some View {
        List {
            if authService.isLoadingFollowList && sortedFollowedUsers.isEmpty {
                ProgressView("Lade Stelz-Liste...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else if let error = authService.followListError, sortedFollowedUsers.isEmpty {
                ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            } else if sortedFollowedUsers.isEmpty && !authService.isLoadingFollowList { // Zeige nur, wenn nicht gerade lädt
                ContentUnavailableView {
                    Label("Keine Stelzes", systemImage: "person.fill.viewfinder")
                } description: {
                    Text(authService.isLoggedIn ? "\(username) folgt bisher niemandem oder die aktuellen Filter blenden alle aus." : "Melde dich an, um Stelzes zu sehen.")
                        .multilineTextAlignment(.center)
                } actions: {
                    if authService.isLoggedIn {
                        Button("Filter anpassen") { showingFilterSheet = true }
                    }
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(sortedFollowedUsers) { followedUser in
                    followedUserRow(followedUser)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Stelzes (\(sortedFollowedUsers.count))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // --- NEW: Toolbar für Filter-Button ---
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { // Oder .primaryAction
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            // Wichtig: relevantFeedTypeForFilterBehavior ist hier nil,
            // da die Follow-Liste nicht an einen spezifischen Feed-Typ gebunden ist.
            // Die API für /user/followlist verwendet die übergebenen Flags.
            FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        // --- END NEW ---
        .refreshable {
            await authService.fetchFollowList()
        }
        .task {
            // playerManager.configure(settings: settings) // Wird jetzt in ProfileView gemacht
            if authService.isLoggedIn && authService.followedUsers.isEmpty && !authService.isLoadingFollowList {
                UserFollowListView.logger.info("UserFollowListView .task: Follow list is empty and not loading, fetching now.")
                await authService.fetchFollowList()
            } else {
                UserFollowListView.logger.info("UserFollowListView .task: Follow list not fetched (isLoggedIn: \(authService.isLoggedIn), isEmpty: \(authService.followedUsers.isEmpty), isLoading: \(authService.isLoadingFollowList))")
            }
        }
        // --- NEW: onChange für Filteränderungen ---
        .onChange(of: settings.apiFlags) { oldValue, newValue in
            if oldValue != newValue { // Nur neu laden, wenn sich die Flags tatsächlich geändert haben
                UserFollowListView.logger.info("Global apiFlags changed in UserFollowListView. Refreshing follow list.")
                Task {
                    await authService.fetchFollowList()
                }
            }
        }
        // --- END NEW ---
        .navigationDestination(item: $itemNavigationValue) { navValue in
            PagedDetailViewWrapperForItem(
                item: navValue.item,
                playerManager: playerManager,
                targetCommentID: navValue.targetCommentID
            )
            .environmentObject(settings)
            .environmentObject(authService)
        }
        .sheet(item: $userProfileSheetTarget) { target in // .sheet statt .navigationDestination
            UserProfileSheetView(username: target.username)
                .environmentObject(authService)
                .environmentObject(settings)
                .environmentObject(playerManager)
        }
        .overlay {
            if isLoadingNavigationTarget {
                ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
                    .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
            }
        }
    }

    @ViewBuilder
    private func followedUserRow(_ followedUser: FollowListItem) -> some View {
        HStack(spacing: 10) {
            Group {
                if let thumbUrl = followedUser.lastPostThumbnailUrl, let itemId = followedUser.itemId {
                    Button {
                        Task { await prepareAndNavigateToItem(itemId, targetCommentID: nil) }
                    } label: {
                        KFImage(thumbUrl)
                            .resizable()
                            .placeholder { Color.gray.opacity(0.1).frame(width: 50, height: 50).cornerRadius(4) }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipped()
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingNavigationTarget)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    self.userProfileSheetTarget = ProfileNavigationValue(username: followedUser.name)
                    UserFollowListView.logger.info("Tapped to show profile sheet for: \(followedUser.name)")
                } label: {
                    HStack(spacing: 4) {
                        UserMarkView(markValue: followedUser.mark, showName: false)
                        Text(followedUser.name)
                            .font(UIConstants.headlineFont.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)


                if let lastPostDate = followedUser.lastPost, lastPostDate > 0 {
                    Text("Letzter Post: \(Date(timeIntervalSince1970: TimeInterval(lastPostDate)), style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Noch keine Posts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Gefolgt seit: \(Date(timeIntervalSince1970: TimeInterval(followedUser.followCreated)), style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            
            if authService.isModifyingFollowStatus[followedUser.name] ?? false {
                ProgressView().scaleEffect(0.7).padding(.trailing)
            } else {
                Menu {
                    Button(role: .destructive) {
                        Task { await authService.unfollowUser(name: followedUser.name) }
                    } label: {
                        Label("Entfolgen", systemImage: "person.fill.xmark")
                    }

                    if followedUser.isSubscribed {
                        Button {
                            Task { await authService.unsubscribeFromUserNotifications(name: followedUser.name, keepFollow: true) }
                        } label: {
                            Label("Benachrichtigungen Aus", systemImage: "bell.slash.fill")
                        }
                    } else {
                        Button {
                             Task { await authService.subscribeToUserNotifications(name: followedUser.name) }
                        } label: {
                            Label("Benachrichtigen Ein", systemImage: "bell.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(settings.accentColorChoice.swiftUIColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(authService.isModifyingFollowStatus[followedUser.name] ?? false)
                .padding(.trailing)
            }
        }
    }
    
    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?, targetCommentID: Int? = nil) async {
        guard let id = itemId else {
            UserFollowListView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !self.isLoadingNavigationTarget else {
            UserFollowListView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        UserFollowListView.logger.info("Preparing navigation for item ID: \(id), targetCommentID: \(targetCommentID ?? -1)")
        self.isLoadingNavigationTarget = true
        self.navigationTargetItemId = id
        
        do {
            let flagsToFetchWith = settings.apiFlags
            UserFollowListView.logger.debug("Fetching item \(id) for navigation using global flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard self.navigationTargetItemId == id else {
                 UserFollowListView.logger.info("Navigation target changed while item \(id) was loading. Discarding result.")
                 self.isLoadingNavigationTarget = false; self.navigationTargetItemId = nil; return
            }
            if let item = fetchedItem {
                 UserFollowListView.logger.info("Successfully fetched item \(id) for navigation.")
                 self.itemNavigationValue = ItemNavigationValue(item: item, targetCommentID: targetCommentID)
            } else {
                 UserFollowListView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                 // Hier könntest du eine Fehlermeldung im UI anzeigen, z.B. über ein @State var
            }
        } catch is CancellationError {
             UserFollowListView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
        } catch {
            UserFollowListView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
            if self.navigationTargetItemId == id {
                // Zeige Fehler, wenn es noch der aktuelle Ladevorgang war
            }
        }
        if self.navigationTargetItemId == id {
             self.isLoadingNavigationTarget = false
             self.navigationTargetItemId = nil
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject private var authService: AuthService
        @StateObject private var settings = AppSettings()
        @StateObject private var navigationService = NavigationService()
        @StateObject private var playerManager = VideoPlayerManager()


        init() {
            let tempSettings = AppSettings()
            let tempAuthService = AuthService(appSettings: tempSettings)
            tempAuthService.isLoggedIn = true
            tempAuthService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: Int(Date().timeIntervalSince1970), score: 100, mark: 1, badges: [])
            let sampleFollows = [
                FollowListItem(subscribed: 1, name: "UserAlpha", mark: 2, followCreated: Int(Date().timeIntervalSince1970) - 1000, itemId: 6624389, thumb: "2025/05/20/ed02b6e3731e8f95.jpg", preview: "2025/05/20/ed02b6e3731e8f95-preview.mp4", lastPost: Int(Date().timeIntervalSince1970) - 500),
                FollowListItem(subscribed: 0, name: "Vollzeitdieb", mark: 9, followCreated: Int(Date().timeIntervalSince1970) - 2000, itemId: 6624397, thumb: "2025/05/20/08008ecbfd04e785.jpg", preview: nil, lastPost: Int(Date().timeIntervalSince1970) - 600),
                FollowListItem(subscribed: 1, name: "schonbelegt", mark: 0, followCreated: Int(Date().timeIntervalSince1970) - 3000, itemId: nil, thumb: nil, preview: nil, lastPost: nil),
                FollowListItem(subscribed: 0, name: "LangerUsernameMitVielText", mark: 1, followCreated: Int(Date().timeIntervalSince1970) - 4000, itemId: 12345, thumb: "2024/01/01/sample.jpg", preview: nil, lastPost: Int(Date().timeIntervalSince1970) - 10000)

            ]
            #if DEBUG
            tempAuthService.setFollowedUsersForPreview(sampleFollows)
            #endif
            _authService = StateObject(wrappedValue: tempAuthService)
            _settings = StateObject(wrappedValue: tempSettings)
            let pm = VideoPlayerManager()
            pm.configure(settings: tempSettings)
            _playerManager = StateObject(wrappedValue: pm)
        }

        var body: some View {
            NavigationStack {
                UserFollowListView(username: "PreviewUser")
            }
            .environmentObject(authService)
            .environmentObject(settings)
            .environmentObject(navigationService)
            .environmentObject(playerManager)
        }
    }
    return PreviewWrapper()
}

#Preview("Empty Follow List") {
     struct PreviewWrapperEmpty: View {
        @StateObject private var authService: AuthService
        @StateObject private var settings = AppSettings()
        @StateObject private var navigationService = NavigationService()
        @StateObject private var playerManager = VideoPlayerManager()

        init() {
            let tempSettings = AppSettings()
            let tempAuthService = AuthService(appSettings: tempSettings)
            tempAuthService.isLoggedIn = true
            tempAuthService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: Int(Date().timeIntervalSince1970), score: 100, mark: 1, badges: [])
            #if DEBUG
            tempAuthService.setFollowedUsersForPreview([])
            #endif
            _authService = StateObject(wrappedValue: tempAuthService)
            _settings = StateObject(wrappedValue: tempSettings)
            let pm = VideoPlayerManager()
            pm.configure(settings: tempSettings)
            _playerManager = StateObject(wrappedValue: pm)
        }
        var body: some View {
            NavigationStack {
                UserFollowListView(username: "PreviewUser")
            }
            .environmentObject(authService)
            .environmentObject(settings)
            .environmentObject(navigationService)
            .environmentObject(playerManager)
        }
    }
    return PreviewWrapperEmpty()
}
// --- END OF COMPLETE FILE ---
