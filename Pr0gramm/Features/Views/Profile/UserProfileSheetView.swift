// Pr0gramm/Pr0gramm/Features/Views/Profile/UserProfileSheetView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher
import os

struct UserProfileSheetView: View {
    let username: String

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings // Wird jetzt für API Flags verwendet
    @Environment(\.dismiss) var dismiss

    @State private var profileInfo: ProfileInfoResponse?
    @State private var isLoadingProfileInfo = false
    @State private var profileInfoError: String?

    @State private var userUploads: [Item] = []
    @State private var isLoadingUploads = false
    @State private var uploadsError: String?
    private let uploadsPageLimit = 6

    @State private var userComments: [ItemComment] = []
    @State private var isLoadingComments = false
    @State private var commentsError: String?
    private let commentsPageLimit = 5

    @State private var itemToNavigate: Item? = nil
    @State private var isLoadingNavigationTarget = false
    @State private var navigationTargetItemId: Int? = nil
    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserProfileSheetView")

    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    var body: some View {
        NavigationStack { // Sheet content now wrapped in NavigationStack
            List {
                profileInfoSection()
                userUploadsSection()
                userCommentsSection()
            }
            .navigationTitle(username)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                playerManager.configure(settings: settings)
                await loadAllData()
            }
            .refreshable {
                await loadAllData(forceRefresh: true)
            }
            // --- MODIFIED: Add onChange listeners for filter changes ---
            .onChange(of: settings.apiFlags) { _, _ in
                UserProfileSheetView.logger.info("Global filters (apiFlags) changed. Reloading data for \(username) sheet.")
                Task { await loadAllData(forceRefresh: true) }
            }
            // --- END MODIFICATION ---
            .navigationDestination(item: $itemToNavigate) { loadedItem in
                 PagedDetailViewWrapperForItem(item: loadedItem, playerManager: playerManager)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
            .navigationDestination(for: ProfileNavigationTarget.self) { target in
                switch target {
                case .allUserUploads(let targetUsername):
                    UserUploadsView(username: targetUsername)
                        .environmentObject(settings)
                        .environmentObject(authService)
                case .allUserComments(let targetUsername):
                    UserProfileCommentsView(username: targetUsername)
                        .environmentObject(settings)
                        .environmentObject(authService)
                default:
                    EmptyView()
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                if let itemID = parsePr0grammLink(url: url) {
                    UserProfileSheetView.logger.info("Pr0gramm link tapped in UserProfileSheet comment, attempting to navigate to item ID: \(itemID)")
                    Task { await prepareAndNavigateToItem(itemID) }
                    return .handled
                } else {
                    UserProfileSheetView.logger.info("Non-pr0gramm link tapped in UserProfileSheet: \(url). Opening in system browser.")
                    return .systemAction
                }
            })
            .overlay {
                if isLoadingNavigationTarget {
                    ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
        }
    }

    private func loadAllData(forceRefresh: Bool = false) async {
        UserProfileSheetView.logger.info("Loading all data for user \(username). Force refresh: \(forceRefresh)")
        // Profile info loading is independent of content filters, so flags=31 is fine here.
        // Only uploads and comments lists will use settings.apiFlags.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadProfileInfo(forceRefresh: forceRefresh) } // flags=31 internally
            group.addTask { await loadUserUploads(isRefresh: forceRefresh, initialLoad: true) } // Will use settings.apiFlags
            group.addTask { await loadUserComments(isRefresh: forceRefresh, initialLoad: true) } // Will use settings.apiFlags
        }
    }

    @ViewBuilder
    private func profileInfoSection() -> some View {
        Section("Benutzerinformationen") {
            if isLoadingProfileInfo && profileInfo == nil {
                HStack { Spacer(); ProgressView(); Text("Lade Profil...").font(.footnote); Spacer() }
            } else if let error = profileInfoError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if let info = profileInfo {
                userInfoRow(label: "Rang", valueView: {
                    HStack {
                        UserMarkView(markValue: info.user.mark)
                            .font(UIConstants.subheadlineFont)
                            .foregroundColor(.secondary)
                    }
                })
                if let score = info.user.score {
                    userInfoRow(label: "Benis", value: "\(score)")
                } else {
                    userInfoRow(label: "Benis", value: "N/A")
                }
                if let registeredTimestamp = info.user.registered {
                    userInfoRow(label: "Registriert seit", value: formatDateGerman(date: Date(timeIntervalSince1970: TimeInterval(registeredTimestamp))))
                } else {
                    userInfoRow(label: "Registriert seit", value: "N/A")
                }
                if let badges = info.badges, !badges.isEmpty {
                    DisclosureGroup("Abzeichen (\(badges.count))") {
                        badgeScrollView(badges: badges)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            } else {
                Text("Keine Profilinformationen verfügbar.").foregroundColor(.secondary)
            }
        }
        .headerProminence(.increased)
    }

    private func loadProfileInfo(forceRefresh: Bool = false) async {
        if !forceRefresh && profileInfo != nil { return }
        UserProfileSheetView.logger.info("Loading profile info for \(username)...")
        await MainActor.run {
            isLoadingProfileInfo = true
            profileInfoError = nil
        }
        do {
            // Profile info itself should always load all data, hence flags=31
            let infoResponse = try await apiService.getProfileInfo(username: username, flags: 31)
            await MainActor.run { profileInfo = infoResponse }
        } catch {
            UserProfileSheetView.logger.error("Failed to load profile info for \(username): \(error.localizedDescription)")
            await MainActor.run { profileInfoError = error.localizedDescription }
        }
        await MainActor.run { isLoadingProfileInfo = false }
    }

    @ViewBuilder
    private func userUploadsSection() -> some View {
        Section {
            if isLoadingUploads && userUploads.isEmpty {
                HStack { Spacer(); ProgressView(); Text("Lade Uploads...").font(.footnote); Spacer() }
            } else if let error = uploadsError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if userUploads.isEmpty {
                Text("\(username) hat (noch) keine Uploads, die deinen Filtern entsprechen.").foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(userUploads.prefix(uploadsPageLimit)) { item in
                            Button {
                                Task { await prepareAndNavigateToItem(item.id) }
                            } label: {
                                FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                                    .frame(width: 100, height: 100)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingNavigationTarget)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 100)
            }
        } header: {
            NavigationLink(value: ProfileNavigationTarget.allUserUploads(username: username)) {
                HStack {
                    Text("Neueste Uploads")
                    Spacer()
                    if let totalUploads = profileInfo?.uploadCount {
                        Text("Alle \(totalUploads) anzeigen")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .headerProminence(.increased)
    }

    private func loadUserUploads(isRefresh: Bool = false, initialLoad: Bool = false) async {
        if !initialLoad && !isRefresh { return }
        // --- MODIFIED: Use global settings.apiFlags ---
        UserProfileSheetView.logger.info("Loading uploads for \(username) (Profile Sheet - Using global filters: \(settings.apiFlags)). Refresh: \(isRefresh), Initial: \(initialLoad)")
        // --- END MODIFICATION ---

        await MainActor.run {
            if isRefresh || initialLoad { userUploads = [] }
            isLoadingUploads = true
            uploadsError = nil
        }

        do {
            // --- MODIFIED: Use global settings.apiFlags ---
            let flagsToFetchWith = settings.apiFlags
            UserProfileSheetView.logger.debug("Fetching uploads for \(username) using global flags: \(flagsToFetchWith)")
            // --- END MODIFICATION ---
            let fetchedItems = try await apiService.fetchItems(
                flags: flagsToFetchWith,
                user: username,
                olderThanId: nil // For the preview, only load the first page
            )
            await MainActor.run {
                userUploads = Array(fetchedItems.prefix(uploadsPageLimit))
            }
        } catch {
            UserProfileSheetView.logger.error("Failed to load uploads for \(username): \(error.localizedDescription)")
            await MainActor.run { uploadsError = error.localizedDescription }
        }
        await MainActor.run { isLoadingUploads = false }
    }

    @ViewBuilder
    private func userCommentsSection() -> some View {
        Section {
            if isLoadingComments && userComments.isEmpty {
                HStack { Spacer(); ProgressView(); Text("Lade Kommentare...").font(.footnote); Spacer() }
            } else if let error = commentsError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if userComments.isEmpty {
                Text("\(username) hat (noch) keine Kommentare, die deinen Filtern entsprechen.").foregroundColor(.secondary)
            } else {
                ForEach(userComments.prefix(commentsPageLimit)) { comment in
                    Button {
                        Task { await prepareAndNavigateToItem(comment.itemId) }
                    } label: {
                        FavoritedCommentRow(
                            comment: comment,
                            overrideUsername: username,
                            overrideUserMark: profileInfo?.user.mark
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(comment.itemId == nil || isLoadingNavigationTarget)
                }
            }
        } header: {
            NavigationLink(value: ProfileNavigationTarget.allUserComments(username: username)) {
                HStack {
                    Text("Neueste Kommentare")
                    Spacer()
                    if let totalComments = profileInfo?.commentCount {
                        Text("Alle \(totalComments) anzeigen")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .headerProminence(.increased)
    }

    private func loadUserComments(isRefresh: Bool = false, initialLoad: Bool = false) async {
        if !initialLoad && !isRefresh { return }
        // --- MODIFIED: Use global settings.apiFlags ---
        UserProfileSheetView.logger.info("Loading comments for \(username) (Profile Sheet - Using global filters: \(settings.apiFlags)). Refresh: \(isRefresh), Initial: \(initialLoad)")
        // --- END MODIFICATION ---

        await MainActor.run {
            if isRefresh || initialLoad { userComments = [] }
            isLoadingComments = true
            commentsError = nil
        }

        do {
            // --- MODIFIED: Use global settings.apiFlags ---
            let flagsToFetchWith = settings.apiFlags
            UserProfileSheetView.logger.debug("Fetching profile comments for \(username) using global flags: \(flagsToFetchWith)")
            // --- END MODIFICATION ---
            let response = try await apiService.fetchProfileComments(
                username: username,
                flags: flagsToFetchWith,
                before: nil // For the preview, only load the first page
            )
            await MainActor.run {
                userComments = Array(response.comments.prefix(commentsPageLimit))
                // Ensure profileInfo's mark is used if it differs, to maintain consistency within this sheet
                if profileInfo?.user.name.lowercased() == username.lowercased() && profileInfo?.user.mark != response.user?.mark {
                    UserProfileSheetView.logger.info("Mark for \(username) in ProfileCommentsResponse (\(response.user?.mark ?? -98)) differs from ProfileInfoResponse (\(profileInfo?.user.mark ?? -99)). Using ProfileInfoResponse for consistency in this sheet.")
                }
            }
        } catch {
            UserProfileSheetView.logger.error("Failed to load comments for \(username): \(error.localizedDescription)")
            await MainActor.run { commentsError = error.localizedDescription }
        }
        await MainActor.run { isLoadingComments = false }
    }

    @ViewBuilder
    private func userInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(UIConstants.bodyFont)
            Spacer()
            Text(value).font(UIConstants.bodyFont).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func userInfoRow<ValueView: View>(label: String, @ViewBuilder valueView: () -> ValueView) -> some View {
        HStack {
            Text(label).font(UIConstants.bodyFont)
            Spacer()
            valueView()
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

    private func formatDateGerman(date: Date) -> String {
        return germanDateFormatter.string(from: date)
    }

    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if let itemID = Int(component) { return itemID }
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let itemID = Int(value) {
                    return itemID
                }
            }
        }
        UserProfileSheetView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }

    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?) async {
        guard let id = itemId else {
            UserProfileSheetView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !isLoadingNavigationTarget else {
            UserProfileSheetView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        UserProfileSheetView.logger.info("Preparing navigation for item ID: \(id)")
        isLoadingNavigationTarget = true
        navigationTargetItemId = id

        do {
            // --- MODIFIED: Use global settings.apiFlags when navigating from the sheet ---
            let flagsToFetchWith = settings.apiFlags
            UserProfileSheetView.logger.debug("Fetching item \(id) for navigation from profile sheet using global flags: \(flagsToFetchWith)")
            // --- END MODIFICATION ---
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard navigationTargetItemId == id else {
                 UserProfileSheetView.logger.info("Navigation target changed while item \(id) was loading. Discarding result.")
                 isLoadingNavigationTarget = false; navigationTargetItemId = nil; return
            }
            if let item = fetchedItem {
                UserProfileSheetView.logger.info("Successfully fetched item \(id) for navigation.")
                itemToNavigate = item
            } else {
                 UserProfileSheetView.logger.warning("Could not fetch item \(id) for navigation (using global flags).")
                 // Hier könnte man überlegen, ob man einen Fallback auf flags=31 macht,
                 // aber für Konsistenz mit der Listenanzeige bleiben wir bei settings.apiFlags.
            }
        } catch is CancellationError {
            UserProfileSheetView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
        } catch {
            UserProfileSheetView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
        }
        if navigationTargetItemId == id {
             isLoadingNavigationTarget = false
             navigationTargetItemId = nil
        }
    }
}

#Preview("UserProfileSheetView Preview") {
    struct PreviewWrapper: View {
        @StateObject private var authService: AuthService
        @StateObject private var settings = AppSettings()

        init() {
            let tempSettings = AppSettings()
            // --- MODIFIED: Set some filters for preview ---
            tempSettings.showSFW = true
            tempSettings.showNSFW = false
            // --- END MODIFICATION ---

            let tempAuth = AuthService(appSettings: tempSettings)
            tempAuth.isLoggedIn = true
            tempAuth.currentUser = UserInfo(id: 1, name: "Rockabilly", registered: 1609459200, score: 12345, mark: 2, badges: [ApiBadge(image: "pr0-coin.png", description: "Test Badge", created: 0, link: nil, category: nil)], collections: [])

            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: tempAuth)
        }

        var body: some View {
            Text("Parent View")
                .sheet(isPresented: .constant(true)) {
                    UserProfileSheetView(username: "Rockabilly")
                        .environmentObject(authService)
                        .environmentObject(settings)
                }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
