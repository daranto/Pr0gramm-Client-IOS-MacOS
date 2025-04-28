// Pr0gramm/Pr0gramm/Features/Views/Profile/FavoritesView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher
// import UIKit // Nicht mehr benötigt

/// Displays the user's favorited items in a grid.
/// Requires the user to be logged in. Handles loading, pagination, filtering, and navigation.
struct FavoritesView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    // --- ADD PlayerManager StateObject ---
    @StateObject private var playerManager = VideoPlayerManager()
    // ------------------------------------

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    // --- MODIFIED: Computed property for adaptive columns ---
    private var gridColumns: [GridItem] {
        // Use ProcessInfo to detect if the iPad app is running ON macOS
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        // Deutlich größere Mindestbreite auf dem Mac -> weniger Spalten
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100 // Set to 250 for Mac
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }
    // --- END MODIFICATION ---

    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased() else { return nil }
        return "favorites_\(username)"
    }

    // No displayedItems computed property, uses 'items' directly

    var body: some View {
        NavigationStack(path: $navigationPath) {
            favoritesContentView // Use extracted view
            .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) { Text("Favoriten").font(.title3).fontWeight(.bold) }
                 ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } }
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings).environmentObject(authService) }
            .navigationDestination(for: Item.self) { destinationItem in
                // --- PASS PlayerManager to PagedDetailView ---
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager) // Pass manager
                } else {
                    Text("Fehler: Item nicht in Favoriten gefunden.")
                }
                // ---------------------------------------------
            }
            .task(id: authService.isLoggedIn) { // Use .task(id:) for login/logout changes and initial setup
                 // Configure manager whenever login status might change
                 await playerManager.configure(settings: settings)
                 await handleLoginOrFilterChange()
             }
            .onChange(of: settings.showSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await handleLoginOrFilterChange() } }
             .onChange(of: settings.seenItemIDs) { _, _ in
                 FavoritesView.logger.trace("FavoritesView detected change in seenItemIDs, body will update.")
             }
             // No onChange needed for hideSeenItems as it doesn't affect this view's filtering
        }
    }

    // MARK: - Extracted Content Views

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
            // --- MODIFIED: Use computed gridColumns ---
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
                        .onAppear { FavoritesView.logger.info("Favorites: End trigger appeared."); Task { await loadMoreFavorites() } }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            // --- END MODIFICATION ---
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
            Text("Keine Favoriten ausgewählt").font(.headline)
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

    // MARK: - Logic Methods (handleLoginOrFilterChange, refreshFavorites, loadMoreFavorites bleiben unverändert)

    private func handleLoginOrFilterChange() async {
        if authService.isLoggedIn {
            await refreshFavorites()
        } else {
            await MainActor.run { items = []; errorMessage = nil; isLoading = false; canLoadMore = true; isLoadingMore = false; showNoFilterMessage = false }
            FavoritesView.logger.info("User logged out, cleared favorites list.")
        }
    }

    func refreshFavorites() async {
        FavoritesView.logger.info("Pull-to-Refresh triggered or refreshFavorites called.")
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            FavoritesView.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            await MainActor.run { self.errorMessage = "Bitte anmelden."; self.items = []; self.showNoFilterMessage = false }
            return
        }
        guard settings.hasActiveContentFilter else {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter selected.")
            await MainActor.run { self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil }
            return
        }
        guard let cacheKey = favoritesCacheKey else {
            FavoritesView.logger.error("Cannot refresh favorites: Could not generate cache key.");
            await MainActor.run { self.errorMessage = "Interner Fehler (Cache Key)." }
            return
        }
        await MainActor.run { self.showNoFilterMessage = false; self.isLoading = true; self.errorMessage = nil }
        defer { Task { @MainActor in self.isLoading = false; FavoritesView.logger.info("Finishing favorites refresh process (isLoading set to false via defer).") } }
        FavoritesView.logger.info("Starting refresh data fetch for favorites (User: \(username), Flags: \(settings.apiFlags))...")
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil
        if items.isEmpty { if let cachedItems = await settings.loadItemsFromCache(forKey: cacheKey), !cachedItems.isEmpty { initialItemsFromCache = cachedItems; FavoritesView.logger.info("Found \(cachedItems.count) favorite items in cache initially.") } else { FavoritesView.logger.info("No usable data cache found for favorites.") } }
        FavoritesView.logger.info("Performing API fetch for favorites refresh with flags: \(settings.apiFlags)...")
        do { let fetchedItemsFromAPI = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags); FavoritesView.logger.info("API fetch for favorites completed: \(fetchedItemsFromAPI.count) fresh items."); await MainActor.run { self.items = fetchedItemsFromAPI; self.canLoadMore = !fetchedItemsFromAPI.isEmpty; FavoritesView.logger.info("FavoritesView updated with \(fetchedItemsFromAPI.count) items directly from API."); if !navigationPath.isEmpty && initialItemsFromCache != nil { navigationPath = NavigationPath(); FavoritesView.logger.info("Popped navigation due to refresh overwriting cache.") } }; await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey); await settings.updateCacheSizes() }
        catch let error as URLError where error.code == .userAuthenticationRequired { FavoritesView.logger.error("API fetch for favorites failed: Authentication required."); await MainActor.run { self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false }; await settings.saveItemsToCache([], forKey: cacheKey); await authService.logout() }
        catch { FavoritesView.logger.error("API fetch for favorites failed: \(error.localizedDescription)"); await MainActor.run { if self.items.isEmpty { self.errorMessage = "Fehler beim Laden der Favoriten: \(error.localizedDescription)" } else { FavoritesView.logger.warning("Showing potentially stale cached favorites data because API refresh failed.") }; self.canLoadMore = false } }
    }

    func loadMoreFavorites() async {
        guard settings.hasActiveContentFilter else { FavoritesView.logger.warning("Skipping loadMoreFavorites: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { FavoritesView.logger.warning("Cannot load more favorites: User not logged in."); return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FavoritesView.logger.debug("Skipping loadMoreFavorites: State prevents loading."); return }
        guard let lastItemId = items.last?.id else { FavoritesView.logger.warning("Skipping loadMoreFavorites: No last item found."); return }
        guard let cacheKey = favoritesCacheKey else { FavoritesView.logger.error("Cannot load more favorites: Could not generate cache key."); return }
        FavoritesView.logger.info("--- Starting loadMoreFavorites older than \(lastItemId) ---"); await MainActor.run { isLoadingMore = true }; defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FavoritesView.logger.info("--- Finished loadMoreFavorites older than \(lastItemId) (isLoadingMore set to false via defer) ---") } } }
        do { let newItems = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags, olderThanId: lastItemId); FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API (requesting older than \(lastItemId))."); var appendedItemCount = 0; await MainActor.run { guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update."); return }; if newItems.isEmpty { FavoritesView.logger.info("Reached end of favorites feed (API returned empty list for older than \(lastItemId))."); canLoadMore = false } else { let currentIDs = Set(self.items.map { $0.id }); let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }; if uniqueNewItems.isEmpty { FavoritesView.logger.warning("All loaded favorite items (older than \(lastItemId)) were duplicates."); canLoadMore = false; FavoritesView.logger.info("Assuming end of feed because only duplicates were returned.") } else { self.items.append(contentsOf: uniqueNewItems); appendedItemCount = uniqueNewItems.count; FavoritesView.logger.info("Appended \(uniqueNewItems.count) unique favorite items. Total items: \(self.items.count)"); self.canLoadMore = true } } }; if appendedItemCount > 0 { let itemsToSave = await MainActor.run { self.items }; await settings.saveItemsToCache(itemsToSave, forKey: cacheKey); await settings.updateCacheSizes() } }
        catch let error as URLError where error.code == .userAuthenticationRequired { FavoritesView.logger.error("API fetch for more favorites failed: Authentication required."); await MainActor.run { self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false; Task { await authService.logout() } } }
        catch { FavoritesView.logger.error("API fetch failed during loadMoreFavorites: \(error.localizedDescription)"); await MainActor.run { guard self.isLoadingMore else { return }; if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }; canLoadMore = false } }
    }
}

// MARK: - Previews (unverändert)
#Preview("Logged In") { let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2, badges: []); return FavoritesView().environmentObject(previewSettings).environmentObject(previewAuthService) }
#Preview("Logged Out") { FavoritesView().environmentObject(AppSettings()).environmentObject(AuthService(appSettings: AppSettings())) }
// --- END OF COMPLETE FILE ---
