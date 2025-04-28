// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays a thumbnail image for an item in the feed grid using Kingfisher.
/// Shows a checkmark overlay if the item has been marked as seen.
struct FeedItemThumbnail: View {
    let item: Item
    let isSeen: Bool // <-- Flag, ob das Item gesehen wurde

    // Use explicit Type.logger instead of Self.logger
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    var body: some View {
        ZStack(alignment: .topTrailing) { // <-- ZStack für Overlay
            KFImage(item.thumbnailUrl)
                .placeholder { // Show placeholder while loading
                    Rectangle().fill(Material.ultraThin).overlay(ProgressView())
                }
                .onFailure { error in // Log errors
                    FeedItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") // Use explicit type name
                }
                .cancelOnDisappear(true) // Cancel download if view disappears
                .resizable()
                .aspectRatio(contentMode: .fill) // Fill the frame, potentially cropping
                .aspectRatio(1.0, contentMode: .fit) // Maintain 1:1 aspect ratio (square)
                .background(Material.ultraThin) // Background for transparency/loading
                .cornerRadius(5) // Rounded corners
                .clipped() // Clip content to the rounded frame

            // --- Checkmark Overlay ---
            if isSeen {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette) // Ermöglicht separate Farben
                    .foregroundStyle(.white, Color.accentColor) // Weißes Symbol, Akzentfarbe Kreis
                    .font(.system(size: 18)) // Größe anpassen
                    .padding(4) // Abstand zum Rand
                    // Optional: Hintergrund für bessere Sichtbarkeit auf dunklen Thumbnails
                    // .background(Circle().fill(.black.opacity(0.3)))
                    // .padding(2) // Weiterer Abstand, wenn Hintergrund verwendet wird
            }
            // --- End Overlay ---
        }
    }
}

/// The main view displaying the content feed (New or Promoted).
/// Shows items in a grid, handles loading, pagination, pull-to-refresh, filtering, and navigation to detail view.
struct FeedView: View {
    /// Trigger used by `MainView` to pop this view's navigation stack to root.
    let popToRootTrigger: UUID
    @EnvironmentObject var settings: AppSettings // <-- Benötigt für seenItemIDs & hideSeenItems
    @EnvironmentObject var authService: AuthService // Needed for filter sheet context
    /// Original list of items fetched from API or cache
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
    // Use explicit Type.logger instead of Self.logger
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    /// Generates the cache key based on the current feed type setting.
    private var feedCacheKey: String {
        "feed_\(settings.feedType == .new ? "new" : "promoted")"
    }

    /// Computed property to get the items to display, filtering out seen items if the setting is enabled.
    private var displayedItems: [Item] {
        if settings.hideSeenItems {
            // Filter items: keep only those whose ID is NOT in the seen set
            return items.filter { !settings.seenItemIDs.contains($0.id) }
        } else {
            // Return all items if the setting is disabled
            return items
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Use the extracted computed property for the main content area
            feedContentView
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
                // ** IMPORTANT: Use the ORIGINAL 'items' list to find the index for PagedDetailView **
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    // Pass the *original*, unfiltered list to PagedDetailView
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
             // Refresh the view if the seen items OR the hide setting changes
             .onChange(of: settings.seenItemIDs) { _, _ in
                 FeedView.logger.trace("FeedView detected change in seenItemIDs, body will update.")
             }
             .onChange(of: settings.hideSeenItems) { _, _ in
                  FeedView.logger.trace("FeedView detected change in hideSeenItems, body will update.")
             }
        }
    }

    // MARK: - Extracted Content Views

    /// Computed property that builds the main content area based on the current state.
    @ViewBuilder
    private var feedContentView: some View {
        // Display content based on state
        if showNoFilterMessage {
            noFilterContentView // Show message prompting user to select filters
        } else if isLoading && displayedItems.isEmpty { // Check displayedItems here too
            ProgressView("Lade...") // Show loading indicator only on initial load
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Check if the *filtered* list is empty after loading
        } else if displayedItems.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
            // Adjust message if hiding seen items might be the reason
            let message = settings.hideSeenItems ? "Keine neuen Medien für aktuelle Filter gefunden oder alle wurden bereits gesehen." : "Keine Medien für aktuelle Filter gefunden."
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrollViewContent // Display the main grid (using displayedItems)
        }
    }


    /// The main scrollable grid view content. Uses `displayedItems`.
    private var scrollViewContent: some View {
        ScrollView {
            // Use the filtered 'displayedItems' for the grid
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(displayedItems) { item in // <-- Iterate over displayedItems
                    // Each thumbnail is a navigation link to the detail view
                    NavigationLink(value: item) {
                        // Pass the isSeen state to the thumbnail
                        FeedItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id) // Check seen status from original ID
                        )
                    }
                    .buttonStyle(.plain) // Use plain style for the link
                }

                // Invisible element at the end to trigger loading more items
                // Trigger logic might need adjustment if hideSeenItems filters heavily
                if canLoadMore && !isLoading && !isLoadingMore && !displayedItems.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                            FeedView.logger.info("Feed: End trigger appeared.") // Use explicit type name
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

    // MARK: - Data Loading Methods (Operate on the original 'items' state variable)

    /// Reloads the feed from the API, optionally using cached data initially.
    /// Handles filter checks and updates loading/error states.
    func refreshItems() async {
        FeedView.logger.info("Pull-to-Refresh triggered or refreshItems called.") // Use explicit type name

        // Pre-condition: Check if any content filter is active
        guard settings.hasActiveContentFilter else {
            FeedView.logger.warning("Refresh blocked: No active content filter selected.") // Use explicit type name
            // Update UI to show the "no filter" message
            await MainActor.run {
                if !self.showNoFilterMessage || !self.items.isEmpty {
                    self.items = [] // Clear original items
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
        defer { Task { @MainActor in self.isLoading = false; FeedView.logger.info("Finishing refresh process (isLoading set to false via defer).") } } // Use explicit type name

        let currentCacheKey = self.feedCacheKey
        let currentApiFlags = settings.apiFlags
        FeedView.logger.info("Starting refresh data fetch for feed: \(settings.feedType.displayName) (CacheKey: \(currentCacheKey), Flags: \(currentApiFlags))...") // Use explicit type name

        // Reset pagination state
        canLoadMore = true
        isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        // Attempt to load from cache *only if* the current item list is empty (improves perceived performance)
        if items.isEmpty {
            if let cachedItems = await settings.loadItemsFromCache(forKey: currentCacheKey), !cachedItems.isEmpty {
                initialItemsFromCache = cachedItems
                FeedView.logger.info("Found \(cachedItems.count) items in cache initially.") // Use explicit type name
            } else {
                FeedView.logger.info("No usable data cache found or cache empty for key \(currentCacheKey).") // Use explicit type name
            }
        }

        // Fetch fresh data from the API
        FeedView.logger.info("Performing API fetch for refresh with flags: \(currentApiFlags)...") // Use explicit type name
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: currentApiFlags, promoted: settings.apiPromoted)
            FeedView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh items received for flags \(currentApiFlags).") // Use explicit type name

            // Update the original 'items' list
            await MainActor.run {
                self.items = fetchedItemsFromAPI
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty // Can load more only if API returned items
                self.showNoFilterMessage = false // Ensure filter message is hidden
                FeedView.logger.info("FeedView updated original 'items' with \(fetchedItemsFromAPI.count) items directly from API.") // Use explicit type name
                // If we were showing cached data and are now deep in navigation, pop back
                if !navigationPath.isEmpty && initialItemsFromCache != nil {
                    navigationPath = NavigationPath()
                    FeedView.logger.info("Popped navigation due to refresh overwriting cache.") // Use explicit type name
                }
            }
            // Save the newly fetched items to cache
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey)
            await settings.updateCacheSizes()

        } catch {
            // Handle API fetch errors
            FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)") // Use explicit type name
            await MainActor.run {
                // Only show error message if we have no original items to display
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                } else {
                    FeedView.logger.warning("Showing potentially stale cached data because API refresh failed: \(error.localizedDescription)") // Use explicit type name
                }
                self.canLoadMore = false // Stop pagination on error
            }
        }
    }

    /// Determines the correct ID to use for the `older` API parameter based on the feed type, using the *original* items list.
    private func getIdForLoadMore() -> Int? {
        // Use the original 'items' list for pagination logic
        guard let lastItem = items.last else {
            FeedView.logger.warning("Cannot load more: No original items to get ID from.") // Use explicit type name
            return nil
        }

        if settings.feedType == .promoted {
            guard let promotedId = lastItem.promoted else {
                FeedView.logger.error("Cannot load more: Promoted feed active but last original item (ID: \(lastItem.id)) has no 'promoted' ID.") // Use explicit type name
                Task { await MainActor.run { self.canLoadMore = false } }
                return nil
            }
            FeedView.logger.info("Using PROMOTED ID \(promotedId) from last original item for 'older' parameter.") // Use explicit type name
            return promotedId
        } else {
            FeedView.logger.info("Using ITEM ID \(lastItem.id) from last original item for 'older' parameter.") // Use explicit type name
            return lastItem.id
        }
    }

    /// Loads the next page of items from the API and appends to the *original* items list.
    func loadMoreItems() async {
        // Pre-conditions for loading more items
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return } // Use explicit type name
        guard !isLoadingMore && canLoadMore && !isLoading else { FeedView.logger.debug("Skipping loadMoreItems: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)"); return } // Use explicit type name
        guard let olderValue = getIdForLoadMore() else { FeedView.logger.warning("Skipping loadMoreItems: Could not determine 'older' value."); await MainActor.run { canLoadMore = false }; return } // Use explicit type name
        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot load more: Cache key is nil."); return } // Use explicit type name


        await MainActor.run { isLoadingMore = true } // Set loading indicator state
        FeedView.logger.info("--- Starting loadMoreItems older than \(olderValue) ---") // Use explicit type name

        // Ensure isLoadingMore is reset when the function exits
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FeedView.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false via defer) ---") } } } // Use explicit type name

        do {
            // Fetch next page from API
            let newItems = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted, olderThanId: olderValue)
            FeedView.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).") // Use explicit type name

            var appendedItemCount = 0
            // Update the original 'items' list on the main thread
            await MainActor.run {
                // Check if the loading process was cancelled while fetching
                guard self.isLoadingMore else {
                    FeedView.logger.info("Load more cancelled before UI update.") // Use explicit type name
                    return
                }

                if newItems.isEmpty {
                    // Reached the end of the feed
                    FeedView.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).") // Use explicit type name
                    canLoadMore = false
                } else {
                    // Filter out potential duplicates before appending to original 'items'
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                    if uniqueNewItems.isEmpty {
                        FeedView.logger.warning("All loaded items (older than \(olderValue)) were duplicates.") // Use explicit type name
                         canLoadMore = false
                         FeedView.logger.info("Assuming end of feed because only duplicates were returned.") // Use explicit type name
                    } else {
                        self.items.append(contentsOf: uniqueNewItems) // Append to original list
                        appendedItemCount = uniqueNewItems.count
                        FeedView.logger.info("Appended \(uniqueNewItems.count) unique items to original list. Total items: \(self.items.count)") // Use explicit type name
                        self.canLoadMore = true // Can continue loading
                    }
                }
            }

            // If new items were added, update the cache with the full original list
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items } // Get the updated original list
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            }

        } catch {
            // Handle API errors during pagination
            FeedView.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)") // Use explicit type name
            await MainActor.run {
                // Check if loading was cancelled
                guard self.isLoadingMore else { return }
                // Show error only if the original list is currently empty
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
// --- END OF COMPLETE FILE ---
