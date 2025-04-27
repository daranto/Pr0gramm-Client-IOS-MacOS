import SwiftUI
import os
import Kingfisher

/// Displays the user's favorited items in a grid.
/// Requires the user to be logged in. Handles loading, pagination, filtering, and navigation.
struct FavoritesView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Needed for login status and username
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false // For initial load/refresh
    @State private var canLoadMore = true
    @State private var isLoadingMore = false // For pagination
    @State private var showNoFilterMessage = false // If filters hide all favorites

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    /// Generates the cache key specific to the logged-in user's favorites.
    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased() else { return nil }
        return "favorites_\(username)" // User-specific cache key
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if authService.isLoggedIn {
                    // Content shown when logged in
                    if showNoFilterMessage { noFilterContentView }
                    else if isLoading && items.isEmpty { ProgressView("Lade Favoriten...").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage { Text("Du hast noch keine Favoriten markiert (oder sie passen nicht zum Filter).").foregroundColor(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { scrollViewContent }
                } else {
                    loggedOutContentView // Content shown when logged out
                }
            }
            .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) { Text("Favoriten").font(.title3).fontWeight(.bold) }
                 // Filter button (always shown, but filters might be restricted if logged out)
                 ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } }
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings).environmentObject(authService) }
            .navigationDestination(for: Item.self) { destinationItem in
                // Navigate to detail view, passing the favorites list
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    PagedDetailView(items: items, selectedIndex: index)
                } else {
                    Text("Fehler: Item nicht in Favoriten gefunden.")
                }
            }
            // React to login status changes or filter changes by refreshing
            .task(id: authService.isLoggedIn) { await handleLoginOrFilterChange() } // Use .task(id:) for login/logout changes
            .onChange(of: settings.showSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await handleLoginOrFilterChange() } }
        }
    }

    /// Decides whether to refresh favorites or clear the list based on login status.
    private func handleLoginOrFilterChange() async {
        if authService.isLoggedIn {
            await refreshFavorites()
        } else {
            // Clear state if user logs out
            await MainActor.run { items = []; errorMessage = nil; isLoading = false; canLoadMore = true; isLoadingMore = false; showNoFilterMessage = false }
            Self.logger.info("User logged out, cleared favorites list.")
        }
    }

    /// The scrollable grid view displaying favorite items.
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item) }
                        .buttonStyle(.plain)
                }
                // Trigger for loading more items
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear { Self.logger.info("Favorites: End trigger appeared."); Task { await loadMoreFavorites() } }
                }
                // Pagination loading indicator
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable { await refreshFavorites() } // Enable pull-to-refresh
    }

    /// Content shown when filters are set such that no favorites are visible.
    private var noFilterContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
            Text("Keine Favoriten ausgewählt").font(.headline) // Adjusted text
            Text("Bitte passe deine Filter an, um deine Favoriten zu sehen.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Filter anpassen") { showingFilterSheet = true }
                .buttonStyle(.bordered).padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refreshFavorites() }
    }

    /// Content shown when the user is not logged in.
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


    /// Fetches the latest list of favorites from the API, respecting current filters.
    /// Uses cached data initially if available and the list is empty.
    func refreshFavorites() async {
        Self.logger.info("Pull-to-Refresh triggered or refreshFavorites called.")

        // Guard against refreshing when logged out or username unavailable
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            Self.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            await MainActor.run { self.errorMessage = "Bitte anmelden."; self.items = []; self.showNoFilterMessage = false }
            return
        }
        // Guard against refreshing when no content filters are active
        guard settings.hasActiveContentFilter else {
            Self.logger.warning("Refresh favorites blocked: No active content filter selected.")
            await MainActor.run { self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil }
            return
        }
        // Guard against missing cache key (shouldn't happen if logged in)
        guard let cacheKey = favoritesCacheKey else {
            Self.logger.error("Cannot refresh favorites: Could not generate cache key.");
            await MainActor.run { self.errorMessage = "Interner Fehler (Cache Key)." }
            return
        }

        // Set loading state
        await MainActor.run { self.showNoFilterMessage = false; self.isLoading = true; self.errorMessage = nil }
        defer { Task { @MainActor in self.isLoading = false; Self.logger.info("Finishing favorites refresh process (isLoading set to false via defer).") } }

        Self.logger.info("Starting refresh data fetch for favorites (User: \(username), Flags: \(settings.apiFlags))...")
        // Reset pagination
        canLoadMore = true
        isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        // Try loading from cache first if the list is empty
        if items.isEmpty {
            if let cachedItems = await settings.loadItemsFromCache(forKey: cacheKey), !cachedItems.isEmpty {
                initialItemsFromCache = cachedItems
                Self.logger.info("Found \(cachedItems.count) favorite items in cache initially.")
                // Optionally display cached items immediately: await MainActor.run { self.items = cachedItems }
            } else {
                Self.logger.info("No usable data cache found for favorites.")
            }
        }

        // Fetch fresh data from API
        Self.logger.info("Performing API fetch for favorites refresh with flags: \(settings.apiFlags)...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags)
            Self.logger.info("API fetch for favorites completed: \(fetchedItemsFromAPI.count) fresh items.")

            // Update UI with fetched items
            await MainActor.run {
                self.items = fetchedItemsFromAPI
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty
                Self.logger.info("FavoritesView updated with \(fetchedItemsFromAPI.count) items directly from API.")
                // Pop navigation if refresh overwrites underlying data
                if !navigationPath.isEmpty && initialItemsFromCache != nil {
                    navigationPath = NavigationPath()
                    Self.logger.info("Popped navigation due to refresh overwriting cache.")
                }
            }
            // Update cache
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey)
            await settings.updateCacheSizes()

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // Handle expired session error
            Self.logger.error("API fetch for favorites failed: Authentication required.")
            await MainActor.run { self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false }
            await settings.saveItemsToCache([], forKey: cacheKey) // Clear invalid cache
            await authService.logout() // Log the user out

        } catch {
            // Handle other API errors
            Self.logger.error("API fetch for favorites failed: \(error.localizedDescription)")
            await MainActor.run {
                if self.items.isEmpty { // Show error only if list is empty
                    self.errorMessage = "Fehler beim Laden der Favoriten: \(error.localizedDescription)"
                } else {
                    Self.logger.warning("Showing potentially stale cached favorites data because API refresh failed.")
                }
                self.canLoadMore = false // Stop pagination
            }
        }
    }

    /// Loads the next page of favorite items.
    func loadMoreFavorites() async {
        // Pre-conditions
        guard settings.hasActiveContentFilter else { Self.logger.warning("Skipping loadMoreFavorites: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { Self.logger.warning("Cannot load more favorites: User not logged in."); return }
        guard !isLoadingMore && canLoadMore && !isLoading else { Self.logger.debug("Skipping loadMoreFavorites: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)"); return }
        guard let lastItemId = items.last?.id else { Self.logger.warning("Skipping loadMoreFavorites: No last item found."); return }
        guard let cacheKey = favoritesCacheKey else { Self.logger.error("Cannot load more favorites: Could not generate cache key."); return }

        Self.logger.info("--- Starting loadMoreFavorites older than \(lastItemId) ---")
        await MainActor.run { isLoadingMore = true }
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; Self.logger.info("--- Finished loadMoreFavorites older than \(lastItemId) (isLoadingMore set to false via defer) ---") } } }

        do {
            // Fetch next page from API using the last item's ID
            let newItems = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags, olderThanId: lastItemId)
            Self.logger.info("Loaded \(newItems.count) more favorite items from API (requesting older than \(lastItemId)).")
            var appendedItemCount = 0

            // Update UI
            await MainActor.run {
                guard self.isLoadingMore else { Self.logger.info("Load more cancelled before UI update."); return } // Check if cancelled

                if newItems.isEmpty {
                    // End of feed reached
                    Self.logger.info("Reached end of favorites feed (API returned empty list for older than \(lastItemId)).")
                    canLoadMore = false
                } else {
                    // Filter duplicates and append
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                    if uniqueNewItems.isEmpty {
                        Self.logger.warning("All loaded favorite items (older than \(lastItemId)) were duplicates.")
                        // Consider setting canLoadMore = false if this happens consistently
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        Self.logger.info("Appended \(uniqueNewItems.count) unique favorite items. Total items: \(self.items.count)")
                        self.canLoadMore = true // Continue pagination
                    }
                }
            }

            // Update cache if items were added
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey)
                await settings.updateCacheSizes()
            }

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // Handle expired session during pagination
            Self.logger.error("API fetch for more favorites failed: Authentication required.")
            await MainActor.run { self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false; Task { await authService.logout() } }

        } catch {
            // Handle other API errors during pagination
            Self.logger.error("API fetch failed during loadMoreFavorites: \(error.localizedDescription)")
            await MainActor.run {
                guard self.isLoadingMore else { return } // Check if cancelled
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                canLoadMore = false // Stop pagination
            }
        }
    }
}

// MARK: - Previews

#Preview("Logged In") {
    // Setup services for logged-in preview
    FavoritesView()
        .environmentObject(AppSettings())
        .environmentObject({
            let settings = AppSettings()
            let auth = AuthService(appSettings: settings)
            auth.isLoggedIn = true
            auth.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2)
            return auth
        }())
}

#Preview("Logged Out") {
    // Setup services for logged-out preview
    FavoritesView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}
