// Pr0gramm/Pr0gramm/Features/Views/Profile/UserProfileCommentsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

struct UserProfileCommentsView: View {
    let username: String

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var comments: [ItemComment] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var profileUserMark: Int? = nil

    struct ItemNavigationValue: Hashable, Identifiable {
        let item: Item
        let targetCommentID: Int?
        var id: Int { item.id }
    }
    @State private var itemNavigationValue: ItemNavigationValue? = nil

    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil

    @State private var previewLinkTargetFromComment: PreviewLinkTarget? = nil
    @State private var didLoad: Bool = false

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserProfileCommentsView")

    var body: some View {
        Group {
            commentsContentView
        }
        .navigationTitle("Kommentare von \(username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil; isLoadingNavigationTarget = false; navigationTargetItemId = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            Task {
                playerManager.configure(settings: settings)
                await refreshComments()
            }
        }
        .onChange(of: settings.apiFlags) { _, _ in Task { await refreshComments() } }
        .navigationDestination(item: $itemNavigationValue) { navValue in
             PagedDetailViewWrapperForItem(
                 item: navValue.item,
                 playerManager: playerManager,
                 targetCommentID: navValue.targetCommentID // Hier wird targetCommentID übergeben
             )
             .environmentObject(settings)
             .environmentObject(authService)
             .onDisappear {
                 UserProfileCommentsView.logger.info("PagedDetailViewWrapperForItem disappeared. itemNavigationValue should now be nil.")
             }
        }
        .sheet(item: $previewLinkTargetFromComment) { target in
            LinkedItemPreviewView(itemID: target.id)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .overlay {
            if isLoadingNavigationTarget {
                ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
                    .padding()
                    .background(Material.regular)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
    }

    @ViewBuilder private var commentsContentView: some View {
        Group {
            if isLoading && comments.isEmpty {
                ProgressView("Lade Kommentare...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, comments.isEmpty {
                 ContentUnavailableView {
                     Label("Fehler", systemImage: "exclamationmark.triangle")
                 } description: { Text(error) } actions: {
                     Button("Erneut versuchen") { Task { await refreshComments() } }
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty && !isLoading && errorMessage == nil {
                Text("\(username) hat noch keine Kommentare geschrieben (oder sie passen nicht zu deinen Filtern).")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(comments) { comment in
                Button {
                    // --- MODIFIED: Hier wird comment.id als targetCommentID übergeben ---
                    Task { await prepareAndNavigateToItem(comment.itemId, targetCommentID: comment.id) }
                    // --- END MODIFICATION ---
                } label: {
                    FavoritedCommentRow( // Wiederverwendung der FavoritedCommentRow ist hier okay
                        comment: comment,
                        overrideUsername: username, // Da es die Kommentare des Profil-Users sind
                        overrideUserMark: profileUserMark
                    )
                }
                .buttonStyle(.plain)
                .disabled(comment.itemId == nil || isLoadingNavigationTarget)
                .opacity(comment.itemId == nil ? 0.5 : 1.0)
                .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                .id(comment.id) // Wichtig für ScrollViewReader, falls direkt in dieser Liste gescrollt würde
                .onAppear {
                     if comments.count >= 2 && comment.id == comments[comments.count - 2].id && canLoadMore && !isLoadingMore {
                         UserProfileCommentsView.logger.info("End trigger appeared for comment \(comment.id).")
                         Task { await loadMoreComments() }
                     } else if comments.count == 1 && comment.id == comments.first?.id && canLoadMore && !isLoadingMore {
                          UserProfileCommentsView.logger.info("End trigger appeared for the only comment \(comment.id).")
                          Task { await loadMoreComments() }
                     }
                }
            }

            if isLoadingMore {
                HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .refreshable { await refreshComments() }
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                UserProfileCommentsView.logger.info("Pr0gramm link tapped in profile comment, attempting to preview item ID: \(itemID)")
                self.previewLinkTargetFromComment = PreviewLinkTarget(id: itemID)
                return .handled
            } else {
                UserProfileCommentsView.logger.info("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
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
        UserProfileCommentsView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }


    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?, targetCommentID: Int?) async {
        guard let id = itemId else {
            UserProfileCommentsView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !isLoadingNavigationTarget else {
            UserProfileCommentsView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        UserProfileCommentsView.logger.info("Preparing navigation for item ID: \(id), targetCommentID: \(targetCommentID ?? -1)")
        isLoadingNavigationTarget = true
        navigationTargetItemId = id
        errorMessage = nil
        
        do {
            let flagsToFetchWith = settings.apiFlags // Globale Filter verwenden
            UserProfileCommentsView.logger.debug("Fetching item \(id) for navigation using global flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard navigationTargetItemId == id else {
                 UserProfileCommentsView.logger.info("Navigation target changed while item \(id) was loading. Discarding result.")
                 isLoadingNavigationTarget = false; navigationTargetItemId = nil; return
            }
            if let item = fetchedItem {
                UserProfileCommentsView.logger.info("Successfully fetched item \(id) for navigation.")
                self.itemNavigationValue = ItemNavigationValue(item: item, targetCommentID: targetCommentID)
            } else {
                UserProfileCommentsView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                errorMessage = "Post \(id) konnte nicht geladen werden oder entspricht nicht den Filtern."
            }
        } catch is CancellationError {
            UserProfileCommentsView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
        } catch {
            UserProfileCommentsView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
            if navigationTargetItemId == id {
                errorMessage = "Post \(id) konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
        if navigationTargetItemId == id {
             isLoadingNavigationTarget = false
             navigationTargetItemId = nil
        }
    }

    @MainActor
    func refreshComments() async {
        UserProfileCommentsView.logger.info("Refreshing profile comments for user: \(username)")

        self.isLoadingNavigationTarget = false
        self.navigationTargetItemId = nil
        self.itemNavigationValue = nil
        self.isLoading = true
        self.errorMessage = nil
        let initialTimestamp = Int(Date.distantFuture.timeIntervalSince1970)

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let response = try await apiService.fetchProfileComments(username: username, flags: settings.apiFlags, before: initialTimestamp)
            guard !Task.isCancelled else { return }

            self.comments = response.comments
            self.canLoadMore = response.hasOlder
            if let userFromResponse = response.user {
                self.profileUserMark = userFromResponse.mark
                UserProfileCommentsView.logger.info("Stored profile user mark: \(userFromResponse.mark) for \(username)")
            } else {
                if authService.currentUser?.name.lowercased() == username.lowercased() {
                    self.profileUserMark = authService.currentUser?.mark
                } else {
                    UserProfileCommentsView.logger.warning("User object missing in ProfileCommentsResponse for \(username). Attempting to fetch mark separately.")
                    // Optional: Separaten API Call für Profilinfo des Users, falls nicht der eingeloggte User.
                    // Für diese Ansicht ist es aber primär für die Darstellung der Kommentare des Users *username*.
                    // Wenn es der eingeloggte User ist, ist authService.currentUser.mark verfügbar.
                    // Wenn es ein anderer User ist, wird das Mark aus dem comment.mark genommen.
                    // Hier ist die `profileUserMark` Variable eher ein kleiner Bonus.
                }
                UserProfileCommentsView.logger.info("Set profile user mark to \(self.profileUserMark ?? -99) for \(username) (possibly via fallback).")
            }
            UserProfileCommentsView.logger.info("Fetched \(response.comments.count) initial profile comments. HasOlder: \(response.hasOlder)")

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserProfileCommentsView.logger.error("API fetch for profile comments failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.comments = []
            self.canLoadMore = false
        } catch {
            UserProfileCommentsView.logger.error("API fetch for profile comments failed: \(error.localizedDescription)")
            self.errorMessage = "Fehler: \(error.localizedDescription)"
            self.comments = []
            self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreComments() async {
        guard !isLoadingMore && canLoadMore && !isLoading else {
            UserProfileCommentsView.logger.debug("Skipping loadMoreComments: State prevents loading.")
            return
        }
        guard let oldestCommentTimestamp = comments.last?.created else {
            UserProfileCommentsView.logger.warning("Cannot load more profile comments: No last comment found.")
            self.canLoadMore = false
            return
        }

        UserProfileCommentsView.logger.info("--- Starting loadMoreComments for profile of \(username) before timestamp \(oldestCommentTimestamp) ---")
        self.isLoadingMore = true

        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserProfileCommentsView.logger.info("--- Finished loadMoreComments for profile of \(username) ---") } } }

        do {
            let response = try await apiService.fetchProfileComments(username: username, flags: settings.apiFlags, before: oldestCommentTimestamp)
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { UserProfileCommentsView.logger.info("Load more cancelled before UI update."); return }

            if response.comments.isEmpty {
                UserProfileCommentsView.logger.info("Reached end of profile comments feed for \(username).")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.comments.map { $0.id })
                let uniqueNewComments = response.comments.filter { !currentIDs.contains($0.id) }

                if uniqueNewComments.isEmpty {
                    UserProfileCommentsView.logger.warning("All loaded profile comments were duplicates for \(username).")
                    self.canLoadMore = response.hasOlder
                } else {
                    self.comments.append(contentsOf: uniqueNewComments)
                    UserProfileCommentsView.logger.info("Appended \(uniqueNewComments.count) unique profile comments for \(username). Total: \(self.comments.count)")
                    self.canLoadMore = response.hasOlder
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserProfileCommentsView.logger.error("API fetch for more profile comments failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
        } catch {
            UserProfileCommentsView.logger.error("API fetch failed during loadMore profile comments: \(error.localizedDescription)")
            guard self.isLoadingMore else { return }
            if self.comments.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var previewSettings = AppSettings()
        @StateObject private var previewAuthService: AuthService

        init() {
            let settings = AppSettings()
            let authService = AuthService(appSettings: settings)
            authService.isLoggedIn = true
            authService.currentUser = UserInfo(id: 1, name: "TestUserSelf", registered: 1, score: 100, mark: 1, badges: [])
            _previewAuthService = StateObject(wrappedValue: authService)
            _previewSettings = StateObject(wrappedValue: settings)
        }

        var body: some View {
            NavigationStack {
                UserProfileCommentsView(username: "Daranto")
                    .environmentObject(previewSettings)
                    .environmentObject(previewAuthService)
            }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
