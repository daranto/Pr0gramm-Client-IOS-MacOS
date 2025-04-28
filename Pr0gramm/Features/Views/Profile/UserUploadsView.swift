// Pr0gramm/Pr0gramm/Features/Views/Profile/UserUploadsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays the items uploaded by a specific user in a grid.
/// Handles loading, pagination, filtering (based on global settings), and navigation.
struct UserUploadsView: View {
    let username: String // Username whose uploads to display

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Needed for settings/playerManager config
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    // Filters are applied globally, no need for local filter sheet state

    @State private var navigationPath = NavigationPath()

    // --- ADD PlayerManager StateObject ---
    @StateObject private var playerManager = VideoPlayerManager()
    // ------------------------------------

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserUploadsView")

    private var userUploadsCacheKey: String {
        return "uploads_\(username.lowercased())"
    }

    // Use original 'items' directly, filtered by global settings if needed outside the view?
    // No, this view should just display what the API returns based on global flags.
    // The 'hide seen' logic is applied in the thumbnail view itself.

    var body: some View {
        // Use a Group to avoid redundant NavigationStack if it's already pushed
        Group {
            uploadsContentView // Use extracted view
        }
        .navigationTitle("Uploads von \(username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline) // Prefer inline title when pushed
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .navigationDestination(for: Item.self) { destinationItem in
            // --- PASS PlayerManager to PagedDetailView ---
            if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager) // Pass manager
            } else {
                Text("Fehler: Item nicht in Uploads gefunden.")
            }
            // ---------------------------------------------
        }
        .task { // Use .task for initial setup
             // Configure manager
             await playerManager.configure(settings: settings)
             // Load initial items
             await refreshUploads()
         }
        .onChange(of: settings.showSFW) { _, _ in Task { await refreshUploads() } } // Refresh if global filters change
        .onChange(of: settings.showNSFW) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showNSFL) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showNSFP) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showPOL) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.seenItemIDs) { _, _ in
            UserUploadsView.logger.trace("UserUploadsView detected change in seenItemIDs, body will update.")
        }
        // No need to react to hideSeenItems, grid filtering happens naturally
    }

    // MARK: - Extracted Content Views

    @ViewBuilder
    private var uploadsContentView: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Lade Uploads...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty { // Show error only if list is empty
                 ContentUnavailableView { Label("Fehler", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await refreshUploads() } } }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading && errorMessage == nil {
                Text("\(username) hat noch nichts hochgeladen (oder nichts passt zu deinen Filtern).")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollViewContent
            }
        }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id) // Apply seen indicator
                        )
                    }
                    .buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear { UserUploadsView.logger.info("Uploads: End trigger appeared."); Task { await loadMoreUploads() } }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable { await refreshUploads() }
    }

    // MARK: - Data Loading Methods

    func refreshUploads() async {
        UserUploadsView.logger.info("Refreshing uploads for user: \(username)")

        // No need to check authService.isLoggedIn here, as this view is reached via ProfileView which requires login
        // No need to check settings.hasActiveContentFilter, we load based on global filters

        let cacheKey = userUploadsCacheKey

        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in self.isLoading = false; UserUploadsView.logger.info("Finished uploads refresh process for \(username).") } }

        UserUploadsView.logger.info("Starting refresh data fetch for uploads (User: \(username), Flags: \(settings.apiFlags))...")
        canLoadMore = true
        isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        // Load from cache first if the list is currently empty
        if items.isEmpty {
            if let cachedItems = await settings.loadItemsFromCache(forKey: cacheKey), !cachedItems.isEmpty {
                initialItemsFromCache = cachedItems
                 UserUploadsView.logger.info("Found \(cachedItems.count) uploaded items in cache initially for \(username).")
                 // Display cached items immediately for better perceived performance
                 await MainActor.run { self.items = cachedItems }
            } else {
                UserUploadsView.logger.info("No usable data cache found for uploads for \(username).")
            }
        }

        UserUploadsView.logger.info("Performing API fetch for uploads refresh (User: \(username), Flags: \(settings.apiFlags))...")
        do {
            // Use the updated fetchItems call
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: settings.apiFlags, user: username)
            UserUploadsView.logger.info("API fetch for uploads completed: \(fetchedItemsFromAPI.count) items for user \(username).")

            await MainActor.run {
                self.items = fetchedItemsFromAPI // Overwrite with fresh data
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty // API indicates end if empty
                UserUploadsView.logger.info("UserUploadsView updated with \(fetchedItemsFromAPI.count) items directly from API for \(username).")
                // Pop navigation if refresh overwrites cache that was potentially being viewed
                if !navigationPath.isEmpty && initialItemsFromCache != nil && initialItemsFromCache != fetchedItemsFromAPI {
                    navigationPath = NavigationPath()
                    UserUploadsView.logger.info("Popped navigation due to uploads refresh overwriting cache.")
                }
            }
            // Save the fresh data to cache
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey)
            await settings.updateCacheSizes()

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for uploads failed: Authentication required (User: \(username)). Session might be invalid.")
            await MainActor.run { self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false }
            await settings.saveItemsToCache([], forKey: cacheKey) // Clear cache on auth error
            await authService.logout() // Log out the user

        } catch {
            UserUploadsView.logger.error("API fetch for uploads failed (User: \(username)): \(error.localizedDescription)")
            await MainActor.run {
                // Only show error if we didn't even have cached items
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden der Uploads: \(error.localizedDescription)"
                } else {
                     UserUploadsView.logger.warning("Showing potentially stale cached uploads data because API refresh failed for \(username).")
                }
                self.canLoadMore = false // Assume we can't load more on error
            }
        }
    }

    func loadMoreUploads() async {
        guard !isLoadingMore && canLoadMore && !isLoading else { UserUploadsView.logger.debug("Skipping loadMoreUploads: State prevents loading."); return }
        guard let lastItemId = items.last?.id else { UserUploadsView.logger.warning("Skipping loadMoreUploads: No last item found."); return }

        let cacheKey = userUploadsCacheKey

        UserUploadsView.logger.info("--- Starting loadMoreUploads for user \(username) older than \(lastItemId) ---")
        await MainActor.run { isLoadingMore = true }
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserUploadsView.logger.info("--- Finished loadMoreUploads for user \(username) ---") } } }

        do {
            // Use the updated fetchItems call with 'olderThanId'
            let newItems = try await apiService.fetchItems(flags: settings.apiFlags, user: username, olderThanId: lastItemId)
            UserUploadsView.logger.info("Loaded \(newItems.count) more uploaded items from API (requesting older than \(lastItemId)).")
            var appendedItemCount = 0

            await MainActor.run {
                guard self.isLoadingMore else { UserUploadsView.logger.info("Load more cancelled before UI update."); return }

                if newItems.isEmpty {
                    UserUploadsView.logger.info("Reached end of uploads feed for \(username).")
                    canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                    if uniqueNewItems.isEmpty {
                        UserUploadsView.logger.warning("All loaded uploaded items (older than \(lastItemId)) were duplicates for \(username).")
                        canLoadMore = false // Assume end of feed if only duplicates
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        UserUploadsView.logger.info("Appended \(uniqueNewItems.count) unique uploaded items for \(username). Total items: \(self.items.count)")
                        self.canLoadMore = true
                    }
                }
            }

            // Save appended items to cache if any were added
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey)
                await settings.updateCacheSizes()
            }

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for more uploads failed: Authentication required (User: \(username)). Session might be invalid.")
            await MainActor.run { self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false; Task { await authService.logout() } }

        } catch {
            UserUploadsView.logger.error("API fetch failed during loadMoreUploads for \(username): \(error.localizedDescription)")
            await MainActor.run {
                guard self.isLoadingMore else { return }
                // Don't overwrite main error message unless list is empty
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                canLoadMore = false
            }
        }
    }
}

// MARK: - Previews

#Preview {
    // Setup necessary services for the preview
    let settings = AppSettings()
    let authService = {
        let auth = AuthService(appSettings: settings)
        auth.isLoggedIn = true
        auth.currentUser = UserInfo(id: 123, name: "PreviewUser", registered: 1, score: 100, mark: 2)
        return auth
    }()

    // Wrap in NavigationStack for the preview to function correctly
    return NavigationStack {
        UserUploadsView(username: "PreviewUser")
            .environmentObject(settings)
            .environmentObject(authService)
    }
}
// --- END OF COMPLETE FILE ---
