// Pr0gramm/Pr0gramm/Features/Views/Profile/UserFavoritedCommentsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher // Import Kingfisher

/// Zeigt die vom Benutzer favorisierten ("Favorisierten") Kommentare an.
/// Erfordert, dass der Benutzer angemeldet ist. Handhabt Laden, Paginierung und Filterung.
struct UserFavoritedCommentsView: View {
    let username: String // Benutzername, dessen Favorisierte Kommentare angezeigt werden sollen

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var comments: [ItemComment] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var itemToNavigate: Item? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserFavoritedCommentsView")

    var body: some View {
        Group {
            commentsContentView
        }
        .navigationTitle("Favorisierte Kommentare")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil; isLoadingNavigationTarget = false; navigationTargetItemId = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task {
            playerManager.configure(settings: settings)
            await refreshComments()
        }
        .onChange(of: settings.showSFW) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showNSFW) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showNSFL) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showNSFP) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showPOL) { _, _ in Task { await refreshComments() } }
        .navigationDestination(item: $itemToNavigate) { loadedItem in
             PagedDetailViewWrapperForItem(item: loadedItem, playerManager: playerManager) // Use the shared wrapper
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
                Text("\(username) hat noch keine Kommentare geliket (oder sie passen nicht zu deinen Filtern).")
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
                    Task { await prepareAndNavigateToItem(comment.itemId) }
                } label: {
                    FavoritedCommentRow(comment: comment)
                }
                .buttonStyle(.plain)
                .disabled(comment.itemId == nil || isLoadingNavigationTarget)
                .opacity(comment.itemId == nil ? 0.5 : 1.0)
                .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                .id(comment.id)
                .onAppear {
                     if comments.count >= 2 && comment.id == comments[comments.count - 2].id && canLoadMore && !isLoadingMore {
                         UserFavoritedCommentsView.logger.info("End trigger appeared for comment \(comment.id).")
                         Task { await loadMoreComments() }
                     } else if comments.count == 1 && comment.id == comments.first?.id && canLoadMore && !isLoadingMore {
                          UserFavoritedCommentsView.logger.info("End trigger appeared for the only comment \(comment.id).")
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
    }

    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?) async {
        guard let id = itemId else {
            UserFavoritedCommentsView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !isLoadingNavigationTarget else {
            UserFavoritedCommentsView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        UserFavoritedCommentsView.logger.info("Preparing navigation for item ID: \(id)")
        isLoadingNavigationTarget = true
        navigationTargetItemId = id
        errorMessage = nil

        do {
            let fetchedItem = try await apiService.fetchItem(id: id, flags: settings.apiFlags)
            guard navigationTargetItemId == id else {
                 UserFavoritedCommentsView.logger.info("Navigation target changed while item \(id) was loading. Discarding result.")
                 isLoadingNavigationTarget = false; navigationTargetItemId = nil; return
            }
            if let item = fetchedItem {
                UserFavoritedCommentsView.logger.info("Successfully fetched item \(id) for navigation.")
                itemToNavigate = item
            } else {
                UserFavoritedCommentsView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                errorMessage = "Post \(id) konnte nicht geladen werden oder entspricht nicht den Filtern."
            }
        } catch is CancellationError {
            UserFavoritedCommentsView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
        } catch {
            UserFavoritedCommentsView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
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
        UserFavoritedCommentsView.logger.info("Refreshing favorited comments for user: \(username)")
        guard authService.isLoggedIn else {
            UserFavoritedCommentsView.logger.warning("Cannot refresh liked comments: User not logged in.")
            self.comments = []; self.errorMessage = "Bitte anmelden."
            return
        }

        self.isLoadingNavigationTarget = false
        self.navigationTargetItemId = nil
        self.isLoading = true
        self.errorMessage = nil
        let initialTimestamp = Int(Date.distantFuture.timeIntervalSince1970)

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let response = try await apiService.fetchFavoritedComments(username: username, flags: settings.apiFlags, before: initialTimestamp)
            guard !Task.isCancelled else { return }

            self.comments = response.comments
            self.canLoadMore = response.hasOlder
            UserFavoritedCommentsView.logger.info("Fetched \(response.comments.count) initial liked comments. HasOlder: \(response.hasOlder)")

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserFavoritedCommentsView.logger.error("API fetch failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.comments = []
            self.canLoadMore = false
            await authService.logout()
        } catch {
            UserFavoritedCommentsView.logger.error("API fetch failed: \(error.localizedDescription)")
            self.errorMessage = "Fehler: \(error.localizedDescription)"
            self.comments = []
            self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreComments() async {
        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else {
            UserFavoritedCommentsView.logger.debug("Skipping loadMoreComments: State prevents loading (isLoadingMore: \(isLoadingMore), canLoadMore: \(canLoadMore), isLoading: \(isLoading))")
            return
        }
        guard let oldestCommentTimestamp = comments.last?.created else {
            UserFavoritedCommentsView.logger.warning("Cannot load more liked comments: No last comment found to get timestamp.")
            self.canLoadMore = false
            return
        }

        UserFavoritedCommentsView.logger.info("--- Starting loadMoreComments before timestamp \(oldestCommentTimestamp) ---")
        self.isLoadingMore = true

        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserFavoritedCommentsView.logger.info("--- Finished loadMoreComments ---") } } }

        do {
            let response = try await apiService.fetchFavoritedComments(username: username, flags: settings.apiFlags, before: oldestCommentTimestamp)
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { UserFavoritedCommentsView.logger.info("Load more cancelled before UI update."); return }

            if response.comments.isEmpty {
                UserFavoritedCommentsView.logger.info("Reached end of liked comments feed.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.comments.map { $0.id })
                let uniqueNewComments = response.comments.filter { !currentIDs.contains($0.id) }

                if uniqueNewComments.isEmpty {
                    UserFavoritedCommentsView.logger.warning("All loaded liked comments were duplicates.")
                    self.canLoadMore = response.hasOlder
                } else {
                    self.comments.append(contentsOf: uniqueNewComments)
                    UserFavoritedCommentsView.logger.info("Appended \(uniqueNewComments.count) unique liked comments. Total: \(self.comments.count)")
                    self.canLoadMore = response.hasOlder
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserFavoritedCommentsView.logger.error("API fetch failed during loadMore: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        } catch {
            UserFavoritedCommentsView.logger.error("API fetch failed during loadMore: \(error.localizedDescription)")
            guard self.isLoadingMore else { return }
            if self.comments.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }
}

struct FavoritedCommentRow: View {
    let comment: ItemComment
    var overrideUsername: String? = nil
    var overrideUserMark: Int? = nil

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var score: Int { comment.up - comment.down }

    private var displayName: String {
        overrideUsername ?? comment.name ?? "Unbekannt"
    }

    private var displayMarkValue: Int {
        overrideUserMark ?? comment.mark ?? -1
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KFImage(comment.itemThumbnailUrl)
                .resizable()
                .placeholder { Color.gray.opacity(0.1) }
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipped()
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.content)
                    .font(UIConstants.footnoteFont)
                    .lineLimit(4)

                HStack(spacing: 6) {
                    UserMarkView(markValue: displayMarkValue)
                    Text(displayName)
                    Text("•")
                    Text("\(score)")
                        .foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                    Text("•")
                    Text(relativeTime)
                }
                .font(UIConstants.captionFont)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    // The preview wrapper is now defined *inside* the #Preview block
    // to avoid redeclaration issues if this pattern is used elsewhere.
    struct UserFavoritedCommentsPreviewWrapper: View {
        @StateObject private var previewSettings = AppSettings()
        @StateObject private var previewAuthService: AuthService

        init() {
            let settings = AppSettings()
            let authService = AuthService(appSettings: settings)
            authService.isLoggedIn = true
            authService.currentUser = UserInfo(id: 1, name: "Daranto", registered: 1, score: 1337, mark: 2, badges: [])
            _previewAuthService = StateObject(wrappedValue: authService)
            _previewSettings = StateObject(wrappedValue: settings)
        }

        var body: some View {
            NavigationStack {
                UserFavoritedCommentsView(username: "Daranto")
                    .environmentObject(previewSettings)
                    .environmentObject(previewAuthService)
            }
        }
    }
    return UserFavoritedCommentsPreviewWrapper()
}

// --- REMOVED Preview Wrapper Struct ---
// The struct PreviewWrapper definition that was here previously
// has been removed to fix the redeclaration error.
// --- END REMOVED ---

// --- END OF COMPLETE FILE ---
