// Pr0gramm/Pr0gramm/Features/Views/Profile/FavoritesView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays the user's favorited items in a grid.
/// Requires the user to be logged in. Handles loading, pagination, filtering, and navigation.
struct FavoritesView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Use AuthService directly
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    private var gridColumns: [GridItem] {
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }

    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased() else { return nil }
        return "favorites_\(username)"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            favoritesContentView
                .navigationDestination(for: Item.self) { destinationItem in
                    if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                        PagedDetailView(
                            items: $items,
                            selectedIndex: index,
                            playerManager: playerManager,
                            loadMoreAction: { Task { await loadMoreFavorites() } }
                        )
                    } else {
                        Text("Fehler: Item nicht in Favoriten gefunden.")
                             .onAppear { FavoritesView.logger.warning("Navigation destination item \(destinationItem.id) not found.") }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingFilterSheet = true } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                 .navigationTitle("Favoriten")
                 #if os(iOS)
                 .navigationBarTitleDisplayMode(.inline)
                 #endif
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView().environmentObject(settings).environmentObject(authService)
        }
        .task(id: authService.isLoggedIn) { // Re-run when login status changes
            playerManager.configure(settings: settings)
            await handleLoginOrFilterChange()
        }
        .onChange(of: settings.showSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
        .onChange(of: settings.showNSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
        .onChange(of: settings.showNSFL) { _, _ in Task { await handleLoginOrFilterChange() } }
        .onChange(of: settings.showNSFP) { _, _ in Task { await handleLoginOrFilterChange() } }
        .onChange(of: settings.showPOL) { _, _ in Task { await handleLoginOrFilterChange() } }
        .onChange(of: settings.seenItemIDs) { _, _ in FavoritesView.logger.trace("SeenItemIDs changed.") }
    }

    @ViewBuilder
    private var favoritesContentView: some View {
        Group {
            if authService.isLoggedIn {
                if showNoFilterMessage {
                    noFilterContentView
                } else if isLoading && items.isEmpty {
                    ProgressView("Lade Favoriten...").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
                    Text("Du hast noch keine Favoriten markiert (oder sie passen nicht zum Filter).")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    scrollViewContent
                }
            } else {
                loggedOutContentView
            }
        }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                             Task {
                                 try? await Task.sleep(for: .milliseconds(150))
                                 guard !isLoadingMore && canLoadMore && !isLoading else { return }
                                 FavoritesView.logger.info("Favorites: End trigger appeared (after delay).")
                                 await loadMoreFavorites()
                             }
                         }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable { await refreshFavorites() }
    }

    private var noFilterContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
            Text("Keine Favoriten ausgewählt").font(UIConstants.headlineFont)
            Text("Bitte passe deine Filter an, um deine Favoriten zu sehen.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Filter anpassen") { showingFilterSheet = true }
                .buttonStyle(.bordered).padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refreshFavorites() }
    }

    private var loggedOutContentView: some View {
        VStack {
            Spacer()
            Text("Melde dich an, um deine Favoriten zu sehen.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic Methods

    private func handleLoginOrFilterChange() async {
        if authService.isLoggedIn { await refreshFavorites() }
        else { await MainActor.run { items = []; errorMessage = nil; isLoading = false; canLoadMore = true; isLoadingMore = false; showNoFilterMessage = false }; FavoritesView.logger.info("User logged out, cleared favorites list.") }
    }

    @MainActor
    func refreshFavorites() async {
        FavoritesView.logger.info("Refreshing favorites...")
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            FavoritesView.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            self.errorMessage = "Bitte anmelden."; self.items = []; self.showNoFilterMessage = false
            return
        }
        guard settings.hasActiveContentFilter else {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter selected.")
            self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil
            return
        }
        guard let cacheKey = favoritesCacheKey else {
            FavoritesView.logger.error("Cannot refresh favorites: Cache key error."); self.errorMessage = "Interner Fehler (Cache Key)."
            return
        }
        self.showNoFilterMessage = false; self.isLoading = true; self.errorMessage = nil
        defer { Task { @MainActor in self.isLoading = false; FavoritesView.logger.info("Finished favorites refresh process.") } }
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        if items.isEmpty {
             initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
             if let cached = initialItemsFromCache, !cached.isEmpty {
                 self.items = cached.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem } // Pre-mark cached as favorited
                 FavoritesView.logger.info("Found \(self.items.count) favorite items in cache initially.")
             }
             else { FavoritesView.logger.info("No usable cache for favorites.") }
        }
        let oldFirstItemId = items.first?.id

        FavoritesView.logger.info("Performing API fetch for favorites refresh (Flags: \(settings.apiFlags))...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags);
            FavoritesView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh favorites.");
            guard !Task.isCancelled else { FavoritesView.logger.info("Refresh task cancelled."); return }

            let newFirstItemId = fetchedItemsFromAPI.first?.id
            let contentChanged = initialItemsFromCache == nil || initialItemsFromCache?.count != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId
            self.items = fetchedItemsFromAPI.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem } // Mark as favorited
            self.canLoadMore = !fetchedItemsFromAPI.isEmpty;
            FavoritesView.logger.info("FavoritesView updated. Total: \(self.items.count).");

            // --- Update global favorite set ---
            authService.favoritedItemIDs = Set(self.items.map { $0.id })
            FavoritesView.logger.info("Updated global favorite ID set in AuthService (\(authService.favoritedItemIDs.count) IDs).")
            // --- END NEW ---

            if !navigationPath.isEmpty && contentChanged { navigationPath = NavigationPath(); FavoritesView.logger.info("Popped navigation.") }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey); // Save raw API items
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required."); self.items = []; self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false; await settings.saveItemsToCache([], forKey: cacheKey); await authService.logout()
        }
        catch is CancellationError { FavoritesView.logger.info("API call cancelled.") }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)"); if self.items.isEmpty { self.errorMessage = "Fehler: \(error.localizedDescription)" } else { FavoritesView.logger.warning("Showing potentially stale cached data.") }; self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreFavorites() async {
        guard settings.hasActiveContentFilter else { FavoritesView.logger.warning("Skipping loadMore: No active filter."); self.canLoadMore = false; return }
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let lastItemId = items.last?.id else { return }
        guard let cacheKey = favoritesCacheKey else { return }
        FavoritesView.logger.info("--- Starting loadMoreFavorites older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FavoritesView.logger.info("--- Finished loadMoreFavorites ---") } } }
        do {
            let newItems = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags, olderThanId: lastItemId);
            FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API.");
            var appendedItemCount = 0;
            guard !Task.isCancelled else { FavoritesView.logger.info("Load more cancelled."); return }
            guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update."); return };

            if newItems.isEmpty { self.canLoadMore = false }
            else {
                let currentIDs = Set(self.items.map { $0.id });
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                if uniqueNewItems.isEmpty { self.canLoadMore = false; FavoritesView.logger.warning("All loaded items were duplicates.") }
                else {
                    let markedNewItems = uniqueNewItems.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem } // Mark as favorited
                    self.items.append(contentsOf: markedNewItems)
                    appendedItemCount = uniqueNewItems.count
                    FavoritesView.logger.info("Appended \(uniqueNewItems.count) unique items. Total: \(self.items.count)")
                    self.canLoadMore = true

                    // --- Update global favorite set ---
                    authService.favoritedItemIDs.formUnion(uniqueNewItems.map { $0.id })
                    FavoritesView.logger.info("Added \(uniqueNewItems.count) IDs to global favorite set (\(authService.favoritedItemIDs.count) total).")
                    // --- END NEW ---
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = self.items.map { var mutableItem = $0; mutableItem.favorited = nil; return mutableItem } // Save raw API items
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required."); self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false; await authService.logout()
        }
        catch is CancellationError { FavoritesView.logger.info("Load more cancelled.") }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)"); guard !Task.isCancelled else { return }; guard self.isLoadingMore else { return }; if items.isEmpty { errorMessage = "Fehler: \(error.localizedDescription)" }; self.canLoadMore = false
        }
    }
}

// Previews
#Preview("Logged In") {
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2, badges: [])
    // Optionally pre-populate some favorite IDs for the preview
    previewAuthService.favoritedItemIDs = [2, 4] // Example IDs
    return FavoritesView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
#Preview("Logged Out") {
    FavoritesView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}
// --- END OF COMPLETE FILE ---
