// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

// FeedItemThumbnail bleibt unverändert...
struct FeedItemThumbnail: View {
    let item: Item
    let isSeen: Bool
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")
    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.thumbnailUrl)
                .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
                .onFailure { error in FeedItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") }
                .cancelOnDisappear(true).resizable().aspectRatio(contentMode: .fill)
                .aspectRatio(1.0, contentMode: .fit).background(Material.ultraThin)
                .cornerRadius(5).clipped()
            if isSeen { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).font(.system(size: 18)).padding(4) }
        }
    }
}


struct FeedView: View {
    let popToRootTrigger: UUID
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()
    @State private var didLoadInitially = false

    @StateObject private var playerManager = VideoPlayerManager()
    @State private var refreshTask: Task<Void, Never>? = nil
    // --- NEW: Task for recursive loading when hiding seen items ---
    @State private var autoLoadMoreTask: Task<Void, Never>? = nil
    // --- END NEW ---

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    private var gridColumns: [GridItem] {
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }

    private var feedCacheKey: String { "feed_\(settings.feedType == .new ? "new" : "promoted")" }

    // displayedItems remains the same, it filters based on current state
    private var displayedItems: [Item] {
        if settings.hideSeenItems { return items.filter { !settings.seenItemIDs.contains($0.id) } }
        else { return items }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            feedContentView
            .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) { Text(settings.feedType.displayName).font(.title3).fontWeight(.bold) }
                 ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } }
            }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings).environmentObject(authService) }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .navigationDestination(for: Item.self) { destinationItem in
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    PagedDetailView(
                        items: $items,
                        selectedIndex: index,
                        playerManager: playerManager,
                        loadMoreAction: loadMoreItems
                    )
                } else {
                    Text("Fehler: Item nicht im aktuellen Feed gefunden.")
                }
            }
            .onChange(of: settings.feedType) { triggerRefreshTask(resetInitialLoad: true) }
            .onChange(of: settings.showSFW) { triggerRefreshTask(resetInitialLoad: true) }
            .onChange(of: settings.showNSFW) { triggerRefreshTask(resetInitialLoad: true) }
            .onChange(of: settings.showNSFL) { triggerRefreshTask(resetInitialLoad: true) }
            .onChange(of: settings.showNSFP) { triggerRefreshTask(resetInitialLoad: true) }
            .onChange(of: settings.showPOL) { triggerRefreshTask(resetInitialLoad: true) }
            .task {
                 FeedView.logger.debug("FeedView task started.")
                 playerManager.configure(settings: settings)

                 if !didLoadInitially {
                     FeedView.logger.info("FeedView task: Initial load required.")
                     try? await Task.sleep(for: .milliseconds(300))
                     guard !Task.isCancelled else {
                         FeedView.logger.info("FeedView initial task cancelled during sleep.")
                         return
                     }
                     FeedView.logger.debug("FeedView task: Delay finished, triggering initial refresh task.")
                     // --- MODIFIED: Let refreshItems handle setting didLoadInitially ---
                     await refreshItems() // Directly await refresh here
                     // didLoadInitially = true // Set inside refreshItems now
                 } else {
                     FeedView.logger.debug("FeedView task: Initial load already done, skipping refresh.")
                 }
             }
            .onDisappear {
                refreshTask?.cancel()
                // --- NEW: Cancel auto load more task ---
                autoLoadMoreTask?.cancel()
                // --- END NEW ---
                FeedView.logger.debug("FeedView disappeared, cancelling tasks if active.")
            }
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
            .onChange(of: settings.seenItemIDs) { _, _ in FeedView.logger.trace("FeedView detected change in seenItemIDs, body will update.") }
            .onChange(of: settings.hideSeenItems) { _, newValue in
                FeedView.logger.info("Hide seen items setting changed to: \(newValue)")
                // If hiding is enabled, we might need to load more immediately
                // If hiding is disabled, a refresh ensures all items are potentially visible
                triggerRefreshTask(resetInitialLoad: true)
            }
        }
    }

    private func triggerRefreshTask(resetInitialLoad: Bool = false) {
        if resetInitialLoad {
            didLoadInitially = false
            FeedView.logger.debug("Resetting didLoadInitially due to filter/feed change.")
        }
        // --- NEW: Cancel auto load more task when refreshing ---
        autoLoadMoreTask?.cancel()
        // --- END NEW ---
        refreshTask?.cancel(); FeedView.logger.debug("Cancelling previous refresh task (if any).")
        refreshTask = Task { await refreshItems() }; FeedView.logger.debug("Scheduled new refresh task.")
    }

    @ViewBuilder private var feedContentView: some View {
        if showNoFilterMessage { noFilterContentView }
        else if isLoading && (items.isEmpty || !didLoadInitially) {
            ProgressView("Lade...").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedItems.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
            // --- MODIFIED: Add check for isLoadingMore ---
            // Show loading indicator if we are auto-loading more because everything is hidden
            if isLoadingMore {
                 ProgressView("Suche frische Posts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                 let message = settings.hideSeenItems ? "Keine neuen Medien für aktuelle Filter gefunden oder alle wurden bereits gesehen." : "Keine Medien für aktuelle Filter gefunden."
                 Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // --- END MODIFICATION ---
        } else { scrollViewContent }
    }

    // scrollViewContent and noFilterContentView remain unchanged
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(displayedItems) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !displayedItems.isEmpty {
                    Color.clear.frame(height: 1).onAppear { FeedView.logger.info("Feed: End trigger appeared."); Task { await loadMoreItems() } }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await refreshItems() }
    }
    @ViewBuilder private var noFilterContentView: some View {
        VStack {
             Spacer(); Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt").font(UIConstants.headlineFont); Text("Bitte passe deine Filter an, um Inhalte zu sehen.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button("Filter anpassen") { showingFilterSheet = true }.buttonStyle(.bordered).padding(.top); Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).refreshable { await refreshItems() }
    }

    // MARK: - Data Loading Methods

    @MainActor
    func refreshItems() async {
        // Reset didLoadInitially flag here before starting the actual refresh logic
        didLoadInitially = false
        FeedView.logger.info("RefreshItems Task started.")
        guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled before starting."); return }
        guard settings.hasActiveContentFilter else { /* ... unchanged ... */ return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { /* ... unchanged ... */ return }

        let showLoadingIndicatorTask: Task<Void, Never>? = Task { @MainActor in
             try? await Task.sleep(for: .milliseconds(250))
             if !Task.isCancelled { self.isLoading = true; FeedView.logger.debug("Setting isLoading = true after delay.") }
             else { FeedView.logger.debug("isLoading indicator task cancelled before setting true.") }
        }

        await MainActor.run {
            if self.showNoFilterMessage { self.showNoFilterMessage = false };
            self.errorMessage = nil
            self.items = [] // Clear items immediately on refresh
            FeedView.logger.debug("Cleared items at start of refresh.")
        }
        canLoadMore = true; isLoadingMore = false

        // --- NEW: Cancel auto load more task ---
        autoLoadMoreTask?.cancel()
        // --- END NEW ---

        defer {
             showLoadingIndicatorTask?.cancel()
             Task { @MainActor in
                 if self.isLoading { self.isLoading = false; FeedView.logger.debug("Resetting isLoading = false in defer.") }
                 FeedView.logger.info("Finishing refresh process.")
             }
        }

        let currentApiFlags = settings.apiFlags; let currentFeedType = settings.feedType; FeedView.logger.info("Starting API fetch for refresh (Feed: \(currentFeedType.displayName), Flags: \(currentApiFlags)). Strategy: REPLACE.")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: currentApiFlags, promoted: settings.apiPromoted)
            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API fetch."); return }
            FeedView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) items received for refresh.")
            let oldFirstItemId = items.first?.id // Should be nil here
            await MainActor.run {
                 let oldItemCount = self.items.count // Should be 0 here
                 self.items = fetchedItemsFromAPI
                 self.canLoadMore = !fetchedItemsFromAPI.isEmpty
                 FeedView.logger.info("FeedView updated (REPLACED). Old count: \(oldItemCount), New count: \(self.items.count).")
                 let newFirstItemId = fetchedItemsFromAPI.first?.id
                 if !navigationPath.isEmpty { // Always reset nav on refresh if path not empty
                      navigationPath = NavigationPath()
                      FeedView.logger.info("Popped navigation due to refresh.")
                 }
                 self.showNoFilterMessage = false
                 // --- Mark initial load complete AFTER first fetch ---
                 self.didLoadInitially = true
                 // --- END ---
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey)
            await settings.updateCacheSizes()

            // --- NEW: Check if more items need to be loaded immediately ---
            checkAndLoadMoreIfAllSeen()
            // --- END NEW ---

        } catch is CancellationError { FeedView.logger.info("RefreshItems Task API call explicitly cancelled.") }
          catch { /* ... error handling unchanged ... */
            FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API error."); return }
            await MainActor.run {
                self.didLoadInitially = true // Mark as loaded even on error to prevent loop
                if self.items.isEmpty { self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)" }
                else { FeedView.logger.warning("Showing potentially stale data because API refresh failed: \(error.localizedDescription)") }
                self.canLoadMore = false
            }
          }
    }

    private func getIdForLoadMore() -> Int? { /* ... unchanged ... */
        guard let lastItem = items.last else { FeedView.logger.warning("Cannot load more: No original items to get ID from."); return nil }
        if settings.feedType == .promoted {
            guard let promotedId = lastItem.promoted else {
                 FeedView.logger.error("Cannot load more: Promoted feed active but last original item (ID: \(lastItem.id)) has no 'promoted' ID.")
                 Task { await MainActor.run { self.canLoadMore = false } }
                 return nil
            }
            FeedView.logger.info("Using PROMOTED ID \(promotedId) from last original item for 'older' parameter.")
            return promotedId
        } else {
             FeedView.logger.info("Using ITEM ID \(lastItem.id) from last original item for 'older' parameter.")
             return lastItem.id
        }
    }

    @MainActor
    func loadMoreItems() async { /* ... guards unchanged ... */
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FeedView.logger.debug("Skipping loadMoreItems: State prevents loading"); return }
        guard let olderValue = getIdForLoadMore() else { FeedView.logger.warning("Skipping loadMoreItems: Could not determine 'older' value."); await MainActor.run { canLoadMore = false }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot load more: Cache key is nil."); return }

        // --- NEW: Cancel any pending auto-load task ---
        autoLoadMoreTask?.cancel()
        // --- END NEW ---

        await MainActor.run { isLoadingMore = true }
        FeedView.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FeedView.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false via defer) ---") } } }

        do { /* ... API fetch and item appending logic unchanged ... */
            let newItems = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted, olderThanId: olderValue)
            FeedView.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).")

            var appendedItemCount = 0
            await MainActor.run {
                guard self.isLoadingMore else { FeedView.logger.info("Load more cancelled before UI update."); return }
                if newItems.isEmpty {
                    FeedView.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                    if uniqueNewItems.isEmpty {
                        FeedView.logger.warning("All loaded items (older than \(olderValue)) were duplicates.")
                        canLoadMore = false
                        FeedView.logger.info("Assuming end of feed because only duplicates were returned.")
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        FeedView.logger.info("Appended \(uniqueNewItems.count) unique items to original list. Total items: \(self.items.count)")
                        self.canLoadMore = true
                    }
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            }

            // --- NEW: Check if more items need to be loaded after this batch ---
            checkAndLoadMoreIfAllSeen()
            // --- END NEW ---

        } catch { /* ... error handling unchanged ... */
            FeedView.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                guard self.isLoadingMore else { return }
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                canLoadMore = false
            }
        }
    }

    // --- NEW HELPER FUNCTION ---
    /// Checks if 'hideSeenItems' is active and if all currently loaded items are seen.
    /// If so, triggers `loadMoreItems` automatically in a cancellable task.
    private func checkAndLoadMoreIfAllSeen() {
         // Run checks on MainActor as it reads @State and @EnvironmentObject
         guard settings.hideSeenItems, // Only run if hiding is enabled
               !items.isEmpty,         // Only run if there are items to check
               canLoadMore,            // Only run if we haven't reached the end
               !isLoading,             // Don't run if a refresh is in progress
               !isLoadingMore          // Don't run if a load more is already in progress
         else {
             return
         }

         // Check if *any* item in the current list is *not* seen
         let hasUnseenItems = items.contains { !settings.seenItemIDs.contains($0.id) }

         if !hasUnseenItems {
              FeedView.logger.info("All \(items.count) currently loaded items are marked as seen. Triggering auto-load more...")
              // Cancel previous auto-load task if any
              autoLoadMoreTask?.cancel()
              // Start a new task to load more after a very short delay (to allow UI to settle briefly)
              autoLoadMoreTask = Task { @MainActor in
                   do {
                        try await Task.sleep(for: .milliseconds(100)) // Short delay
                        await loadMoreItems() // Call the main load more function
                   } catch is CancellationError {
                        FeedView.logger.info("Auto-load more task cancelled.")
                   } catch {
                        FeedView.logger.error("Error during auto-load more sleep/task: \(error)")
                   }
              }
         } else {
             // There are unseen items, cancel any pending auto-load task
             autoLoadMoreTask?.cancel()
         }
    }
    // --- END NEW HELPER FUNCTION ---
}

// Previews bleiben unverändert...
#Preview {
    let settings = AppSettings(); let authService = AuthService(appSettings: settings); let navigationService = NavigationService()
    return MainView().environmentObject(settings).environmentObject(authService).environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
