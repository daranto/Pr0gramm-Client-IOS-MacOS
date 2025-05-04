// Pr0gramm/Pr0gramm/Features/Views/Profile/FavoritesView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays the user's favorited items in a grid.
/// Requires the user to be logged in. Handles loading, pagination, filtering, and navigation.
struct FavoritesView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var items: [Item] = [] // Keep non-private for binding
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

    private var gridColumns: [GridItem] {
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }

    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased() else { return nil }
        return "favorites_\(username)"
    }

    // No displayedItems computed property, uses 'items' directly

    // --- MODIFIED: Apply modifiers directly to NavigationStack, ensuring destination is inside ---
    var body: some View {
        NavigationStack(path: $navigationPath) {
            favoritesContentView // The main content view defined below
                // Apply navigationDestination *inside* the stack's content view builder
                .navigationDestination(for: Item.self) { destinationItem in
                    // The logic for creating the destination view
                    if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                        PagedDetailView(
                            items: $items, // Pass the binding correctly
                            selectedIndex: index,
                            playerManager: playerManager,
                            loadMoreAction: {
                                Task { await loadMoreFavorites() }
                            }
                        )
                        // Environment objects should be inherited automatically
                    } else {
                        Text("Fehler: Item nicht in Favoriten gefunden.")
                             .onAppear {
                                 FavoritesView.logger.warning("Navigation destination item \(destinationItem.id) not found in current items list.")
                             }
                    }
                }
                // Apply toolbar *inside* the stack's content view builder
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // Use Text here if needed for layout, or leave empty if title is sufficient
                        // Text("Favoriten").font(.title3).fontWeight(.bold)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingFilterSheet = true
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                // Apply navigation title *inside* the stack's content view builder
                 .navigationTitle("Favoriten")
                 #if os(iOS)
                 .navigationBarTitleDisplayMode(.inline)
                 #endif
        }
        // Modifiers applied to the NavigationStack itself (outside the content closure)
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView() // Assuming standard filter view here
                .environmentObject(settings)
                .environmentObject(authService)
        }
        // Lifecycle and state observers attached last to the NavigationStack
        .task(id: authService.isLoggedIn) {
            playerManager.configure(settings: settings)
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
    }
    // --- END MODIFICATION ---


    // MARK: - Extracted Content Views (unchanged)

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
        // Modifiers specific to the content (like title, toolbar) are now applied *inside* the NavigationStack closure
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) { // Uses computed gridColumns
                ForEach(items) { item in
                    NavigationLink(value: item) { // Ensures the Item is the value for navigation
                        FeedItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain) // Ensure the link covers the whole item visually
                }
                // Pagination Trigger
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                             // Add a small delay before triggering load more
                             Task {
                                 try? await Task.sleep(for: .milliseconds(150)) // Slightly increased delay
                                 // Check state again after delay
                                 guard !isLoadingMore && canLoadMore && !isLoading else { return }
                                 FavoritesView.logger.info("Favorites: End trigger appeared (after delay).")
                                 await loadMoreFavorites()
                             }
                         }
                }
                // Loading Indicator for pagination
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) } // Span across columns
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable { await refreshFavorites() } // Keep refreshable
    }

    // noFilterContentView remains unchanged
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

    // loggedOutContentView remains unchanged
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

    // MARK: - Logic Methods (unchanged)

    private func handleLoginOrFilterChange() async {
        if authService.isLoggedIn {
            await refreshFavorites()
        } else {
            // This runs on the MainActor due to the Task/onChange context
            // Direct state updates are safe.
            items = []; errorMessage = nil; isLoading = false; canLoadMore = true; isLoadingMore = false; showNoFilterMessage = false
            FavoritesView.logger.info("User logged out, cleared favorites list.")
        }
    }

    @MainActor
    func refreshFavorites() async {
        FavoritesView.logger.info("Pull-to-Refresh triggered or refreshFavorites called.")
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            FavoritesView.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            // Update UI state directly (on MainActor)
            self.errorMessage = "Bitte anmelden."; self.items = []; self.showNoFilterMessage = false
            return
        }
        guard settings.hasActiveContentFilter else {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter selected.")
            // Update UI state directly (on MainActor)
            self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil
            return
        }
        guard let cacheKey = favoritesCacheKey else {
            FavoritesView.logger.error("Cannot refresh favorites: Could not generate cache key.");
            // Update UI state directly (on MainActor)
            self.errorMessage = "Interner Fehler (Cache Key)."
            return
        }
        // Update UI state directly (on MainActor)
        self.showNoFilterMessage = false; self.isLoading = true; self.errorMessage = nil
        // Use defer for final state update
        defer { Task { @MainActor in self.isLoading = false; FavoritesView.logger.info("Finishing favorites refresh process (isLoading set to false via defer).") } }

        FavoritesView.logger.info("Starting refresh data fetch for favorites (User: \(username), Flags: \(settings.apiFlags))...")
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        // Check cache outside MainActor context (if needed, though items read is mainactor)
        // If items is empty, try loading from cache
        if items.isEmpty {
             initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
             if let cached = initialItemsFromCache, !cached.isEmpty {
                  FavoritesView.logger.info("Found \(cached.count) favorite items in cache initially.")
                  // Update UI back on MainActor
                  self.items = cached
             } else {
                  FavoritesView.logger.info("No usable data cache found for favorites.")
             }
        }

        let oldFirstItemId = items.first?.id // Capture ID before potential modification

        FavoritesView.logger.info("Performing API fetch for favorites refresh with flags: \(settings.apiFlags)...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags);
            FavoritesView.logger.info("API fetch for favorites completed: \(fetchedItemsFromAPI.count) fresh items.");

            // Check for cancellation before updating UI
             guard !Task.isCancelled else { FavoritesView.logger.info("Refresh task cancelled after API fetch."); return }

            // Update UI state directly (on MainActor)
            let newFirstItemId = fetchedItemsFromAPI.first?.id // Capture new ID
            let contentChanged = initialItemsFromCache == nil || initialItemsFromCache?.count != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId
            self.items = fetchedItemsFromAPI;
            self.canLoadMore = !fetchedItemsFromAPI.isEmpty;
            FavoritesView.logger.info("FavoritesView updated with \(fetchedItemsFromAPI.count) items directly from API.");
            // Pop navigation only if content actually changed compared to cache or initial state
            if !navigationPath.isEmpty && contentChanged {
                navigationPath = NavigationPath();
                FavoritesView.logger.info("Popped navigation due to refresh resulting in different list content.")
            }

            // Save to cache outside MainActor context
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch for favorites failed: Authentication required.");
            // Update UI state directly (on MainActor)
            self.items = [];
            self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
            self.canLoadMore = false
            // Perform other async operations outside MainActor context
            await settings.saveItemsToCache([], forKey: cacheKey);
            await authService.logout()
        }
        catch is CancellationError {
            FavoritesView.logger.info("Favorites refresh API call cancelled.")
        }
        catch {
            FavoritesView.logger.error("API fetch for favorites failed: \(error.localizedDescription)");
            // Update UI state directly (on MainActor)
            if self.items.isEmpty {
                self.errorMessage = "Fehler beim Laden der Favoriten: \(error.localizedDescription)"
            } else {
                FavoritesView.logger.warning("Showing potentially stale cached favorites data because API refresh failed.")
            };
            self.canLoadMore = false
        }
    }

    @MainActor // Ensure MainActor context as it modifies @State variables
    func loadMoreFavorites() async {
        guard settings.hasActiveContentFilter else { FavoritesView.logger.warning("Skipping loadMoreFavorites: No active content filter selected."); self.canLoadMore = false; return } // Update state directly
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { FavoritesView.logger.warning("Cannot load more favorites: User not logged in."); return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FavoritesView.logger.debug("Skipping loadMoreFavorites: State prevents loading."); return }
        guard let lastItemId = items.last?.id else { FavoritesView.logger.warning("Skipping loadMoreFavorites: No last item found."); return }
        guard let cacheKey = favoritesCacheKey else { FavoritesView.logger.error("Cannot load more favorites: Could not generate cache key."); return }
        FavoritesView.logger.info("--- Starting loadMoreFavorites older than \(lastItemId) ---");
        // Update UI state directly (on MainActor)
        self.isLoadingMore = true;
        // Use defer for final state update
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FavoritesView.logger.info("--- Finished loadMoreFavorites older than \(lastItemId) (isLoadingMore set to false via defer) ---") } } }
        do {
            let newItems = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags, olderThanId: lastItemId);
            FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API (requesting older than \(lastItemId)).");
            var appendedItemCount = 0;

            // Check cancellation before UI update
             guard !Task.isCancelled else { FavoritesView.logger.info("Load more task cancelled after API fetch."); return }
             // Already on MainActor, update state directly
             guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update (isLoadingMore became false)."); return };

            // Update UI state directly (on MainActor)
            if newItems.isEmpty { FavoritesView.logger.info("Reached end of favorites feed (API returned empty list for older than \(lastItemId))."); self.canLoadMore = false }
            else {
                let currentIDs = Set(self.items.map { $0.id });
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                if uniqueNewItems.isEmpty { FavoritesView.logger.warning("All loaded favorite items (older than \(lastItemId)) were duplicates."); self.canLoadMore = false; FavoritesView.logger.info("Assuming end of feed because only duplicates were returned.") }
                else { self.items.append(contentsOf: uniqueNewItems); appendedItemCount = uniqueNewItems.count; FavoritesView.logger.info("Appended \(uniqueNewItems.count) unique favorite items. Total items: \(self.items.count)"); self.canLoadMore = true }
            }

            // Perform cache saving outside MainActor context if items were appended
            if appendedItemCount > 0 {
                let itemsToSave = self.items // Capture current items (already on MainActor)
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch for more favorites failed: Authentication required.");
             // Update UI state directly (on MainActor)
            self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
            self.canLoadMore = false;
            // Perform logout outside MainActor context
            Task { await authService.logout() }
        }
        catch is CancellationError {
             FavoritesView.logger.info("Load more favorites API call cancelled.")
        }
        catch {
            FavoritesView.logger.error("API fetch failed during loadMoreFavorites: \(error.localizedDescription)");
            // Check cancellation before UI update
             guard !Task.isCancelled else { FavoritesView.logger.info("Load more task cancelled after API error."); return }
             // Already on MainActor, update state directly
             guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update (isLoadingMore became false)."); return };
            // Update UI state directly (on MainActor)
            if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" };
            self.canLoadMore = false
        }
    }
}


// MARK: - Previews (unchanged)
#Preview("Logged In") { let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2, badges: []); return FavoritesView().environmentObject(previewSettings).environmentObject(previewAuthService) }
#Preview("Logged Out") { FavoritesView().environmentObject(AppSettings()).environmentObject(AuthService(appSettings: AppSettings())) }
// --- END OF COMPLETE FILE ---
