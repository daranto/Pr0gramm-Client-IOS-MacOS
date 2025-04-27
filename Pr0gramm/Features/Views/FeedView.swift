import SwiftUI
import os
import Kingfisher

/// Displays a thumbnail image for an item in the feed grid using Kingfisher.
struct FeedItemThumbnail: View {
    let item: Item
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    var body: some View {
        KFImage(item.thumbnailUrl) // Load image using Kingfisher
            .placeholder { // Show placeholder while loading
                Rectangle().fill(Material.ultraThin).overlay(ProgressView())
            }
            .onFailure { error in // Log errors
                Self.logger.error("KFImage fail \(item.id): \(error.localizedDescription)")
            }
            .cancelOnDisappear(true) // Cancel download if view disappears
            .resizable()
            .aspectRatio(contentMode: .fill) // Fill the frame, potentially cropping
            .aspectRatio(1.0, contentMode: .fit) // Maintain 1:1 aspect ratio (square)
            .background(Material.ultraThin) // Background for transparency/loading
            .cornerRadius(5) // Rounded corners
            .clipped() // Clip content to the rounded frame
    }
}

/// The main view displaying the content feed (New or Promoted).
/// Shows items in a grid, handles loading, pagination, pull-to-refresh, filtering, and navigation to detail view.
struct FeedView: View {
    /// Trigger used by `MainView` to pop this view's navigation stack to root.
    let popToRootTrigger: UUID
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Needed for filter sheet context
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false // Indicates initial load or refresh
    @State private var canLoadMore = true // Flag to control pagination trigger
    @State private var isLoadingMore = false // Indicates pagination load in progress
    @State private var showNoFilterMessage = false // Shows message if no content filters are active
    @State private var showingFilterSheet = false
    /// Navigation path for programmatic navigation within this tab.
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    /// Defines the grid layout (adaptive columns with a minimum width).
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    /// Generates the cache key based on the current feed type setting.
    private var feedCacheKey: String {
        "feed_\(settings.feedType == .new ? "new" : "promoted")"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                // Display content based on state
                if showNoFilterMessage {
                    noFilterContentView // Show message prompting user to select filters
                } else if isLoading && items.isEmpty {
                    ProgressView("Lade...") // Show loading indicator only on initial load
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
                    // Show message if no items match filters after loading
                    Text("Keine Medien für aktuelle Filter gefunden.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    scrollViewContent // Display the main grid
                }
            }
            .toolbar {
                 // Display current feed type as title
                 ToolbarItem(placement: .navigationBarLeading) { Text(settings.feedType.displayName).font(.title3).fontWeight(.bold) }
                 // Button to open the filter sheet
                 ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } }
            }
            .sheet(isPresented: $showingFilterSheet) {
                // Present FilterView, providing necessary environment objects
                FilterView().environmentObject(settings).environmentObject(authService)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { // Show error alert
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .navigationDestination(for: Item.self) { destinationItem in
                // Navigate to PagedDetailView when an item is tapped
                // Find the index of the tapped item in the current list
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    PagedDetailView(items: items, selectedIndex: index)
                } else {
                    // Should not happen if navigation is triggered from the list
                    Text("Fehler: Item nicht im aktuellen Feed gefunden.")
                }
            }
            // Refresh content when feed type or any content filter changes
            .onChange(of: settings.feedType) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await refreshItems() } }
            // Initial load when the view appears
            .task { await refreshItems() }
            // Pop to root when the trigger UUID changes (tapped feed tab again)
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
        }
    }

    /// The main scrollable grid view content.
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    // Each thumbnail is a navigation link to the detail view
                    NavigationLink(value: item) {
                        FeedItemThumbnail(item: item)
                    }
                    .buttonStyle(.plain) // Use plain style for the link
                }

                // Invisible element at the end to trigger loading more items
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                            Self.logger.info("Feed: End trigger appeared.")
                            Task { await loadMoreItems() }
                        }
                }

                // Loading indicator shown while loading more items
                if isLoadingMore {
                    ProgressView("Lade mehr...")
                        .padding()
                }
            }
            .padding(.horizontal, 5) // Padding around the grid
            .padding(.bottom)
        }
        .refreshable { await refreshItems() } // Enable pull-to-refresh
    }

    /// Content shown when no content filters are selected in settings.
    private var noFilterContentView: some View {
        VStack {
             Spacer()
             Image(systemName: "line.3.horizontal.decrease.circle")
                 .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt").font(.headline)
             Text("Bitte passe deine Filter an, um Inhalte zu sehen.")
                 .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button("Filter anpassen") { showingFilterSheet = true }
                 .buttonStyle(.bordered).padding(.top)
             Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refreshItems() } // Allow refreshing even this view
    }

    /// Reloads the feed from the API, optionally using cached data initially.
    /// Handles filter checks and updates loading/error states.
    func refreshItems() async {
        Self.logger.info("Pull-to-Refresh triggered or refreshItems called.")

        // Pre-condition: Check if any content filter is active
        guard settings.hasActiveContentFilter else {
            Self.logger.warning("Refresh blocked: No active content filter selected.")
            // Update UI to show the "no filter" message
            await MainActor.run {
                if !self.showNoFilterMessage || !self.items.isEmpty {
                    self.items = [] // Clear existing items
                    self.showNoFilterMessage = true
                    self.canLoadMore = false
                    self.isLoadingMore = false
                    self.errorMessage = nil
                }
            }
            return
        }

        // Set loading state and reset errors/flags
        await MainActor.run {
            if self.showNoFilterMessage { self.showNoFilterMessage = false } // Hide filter message if shown
            self.isLoading = true
            self.errorMessage = nil
        }
        // Ensure isLoading is set back to false when the function exits
        defer { Task { @MainActor in self.isLoading = false; Self.logger.info("Finishing refresh process (isLoading set to false via defer).") } }

        let currentCacheKey = self.feedCacheKey
        let currentApiFlags = settings.apiFlags
        Self.logger.info("Starting refresh data fetch for feed: \(settings.feedType.displayName) (CacheKey: \(currentCacheKey), Flags: \(currentApiFlags))...")

        // Reset pagination state
        canLoadMore = true
        isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        // Attempt to load from cache *only if* the current item list is empty (improves perceived performance)
        if items.isEmpty {
            if let cachedItems = await settings.loadItemsFromCache(forKey: currentCacheKey), !cachedItems.isEmpty {
                initialItemsFromCache = cachedItems
                // Temporarily display cached items while fetching fresh data
                // await MainActor.run { self.items = cachedItems } // Decide if showing stale data first is desired
                Self.logger.info("Found \(cachedItems.count) items in cache initially.")
            } else {
                Self.logger.info("No usable data cache found or cache empty for key \(currentCacheKey).")
            }
        }

        // Fetch fresh data from the API
        Self.logger.info("Performing API fetch for refresh with flags: \(currentApiFlags)...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: currentApiFlags, promoted: settings.apiPromoted)
            Self.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh items received for flags \(currentApiFlags).")

            // Update UI with fetched items
            await MainActor.run {
                self.items = fetchedItemsFromAPI
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty // Can load more only if API returned items
                self.showNoFilterMessage = false // Ensure filter message is hidden
                Self.logger.info("FeedView updated with \(fetchedItemsFromAPI.count) items directly from API.")
                // If we were showing cached data and are now deep in navigation, pop back
                if !navigationPath.isEmpty && initialItemsFromCache != nil {
                    navigationPath = NavigationPath()
                    Self.logger.info("Popped navigation due to refresh overwriting cache.")
                }
            }
            // Save the newly fetched items to cache
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey)
            await settings.updateCacheSizes()

        } catch {
            // Handle API fetch errors
            Self.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            await MainActor.run {
                // Only show error message if we have no items to display (neither cached nor fetched)
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                } else {
                    // If we have items (likely from cache), log warning but don't show error overlay
                    Self.logger.warning("Showing potentially stale cached data because API refresh failed: \(error.localizedDescription)")
                }
                self.canLoadMore = false // Stop pagination on error
            }
        }
    }

    /// Determines the correct ID to use for the `older` API parameter based on the feed type.
    /// For 'promoted' feed, uses the `promoted` ID; otherwise, uses the `id`.
    /// - Returns: The ID to use for pagination, or `nil` if no items exist or required ID is missing.
    private func getIdForLoadMore() -> Int? {
        guard let lastItem = items.last else {
            Self.logger.warning("Cannot load more: No items to get ID from.")
            return nil
        }

        if settings.feedType == .promoted {
            // Promoted feed requires the 'promoted' ID for pagination
            guard let promotedId = lastItem.promoted else {
                Self.logger.error("Cannot load more: Promoted feed active but last item (ID: \(lastItem.id)) has no 'promoted' ID.")
                Task { await MainActor.run { self.canLoadMore = false } } // Disable further loading attempts
                return nil
            }
            Self.logger.info("Using PROMOTED ID \(promotedId) from last item for 'older' parameter.")
            return promotedId
        } else {
            // New feed uses the regular item 'id'
            Self.logger.info("Using ITEM ID \(lastItem.id) from last item for 'older' parameter.")
            return lastItem.id
        }
    }

    /// Loads the next page of items from the API.
    func loadMoreItems() async {
        // Pre-conditions for loading more items
        guard settings.hasActiveContentFilter else { Self.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard !isLoadingMore && canLoadMore && !isLoading else { Self.logger.debug("Skipping loadMoreItems: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)"); return }
        guard let olderValue = getIdForLoadMore() else { Self.logger.warning("Skipping loadMoreItems: Could not determine 'older' value."); await MainActor.run { canLoadMore = false }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { Self.logger.error("Cannot load more: Cache key is nil."); return }


        await MainActor.run { isLoadingMore = true } // Set loading indicator state
        Self.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")

        // Ensure isLoadingMore is reset when the function exits
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; Self.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false via defer) ---") } } }

        do {
            // Fetch next page from API
            let newItems = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted, olderThanId: olderValue)
            Self.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).")

            var appendedItemCount = 0
            // Update items list on the main thread
            await MainActor.run {
                // Check if the loading process was cancelled while fetching
                guard self.isLoadingMore else {
                    Self.logger.info("Load more cancelled before UI update.")
                    return
                }

                if newItems.isEmpty {
                    // Reached the end of the feed
                    Self.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    canLoadMore = false
                } else {
                    // Filter out potential duplicates before appending
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                    if uniqueNewItems.isEmpty {
                        // This might happen if the API returns overlapping items occasionally
                        Self.logger.warning("All loaded items (older than \(olderValue)) were duplicates.")
                        // Consider disabling canLoadMore if duplicates persist
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        Self.logger.info("Appended \(uniqueNewItems.count) unique items. Total items: \(self.items.count)")
                        self.canLoadMore = true // Can continue loading
                    }
                }
            }

            // If new items were added, update the cache
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items } // Get the updated list
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            }

        } catch {
            // Handle API errors during pagination
            Self.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                // Check if loading was cancelled
                guard self.isLoadingMore else { return }
                // Show error only if the list is currently empty
                if items.isEmpty {
                    errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)"
                }
                canLoadMore = false // Stop pagination on error
            }
        }
    }
}

// MARK: - Previews

#Preview {
    // Setup necessary services for the preview
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings) // FeedView needs AuthService via FilterView
    let navigationService = NavigationService() // MainView provides this

    // Preview MainView as it contains FeedView and sets up the environment
    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
