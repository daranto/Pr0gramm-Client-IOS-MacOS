// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher
// import UIKit // Nicht mehr benötigt für die Idiom-Prüfung hier

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
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    @StateObject private var playerManager = VideoPlayerManager()
    @State private var refreshTask: Task<Void, Never>? = nil

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    // --- CORRECTED: Computed property for adaptive columns ---
    private var gridColumns: [GridItem] {
        // Use ProcessInfo to detect if the iPad app is running ON macOS
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        // Deutlich größere Mindestbreite auf dem Mac -> weniger Spalten
        // Passe den Wert 160 ggf. an, bis es für dich passt.
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100
        // Optional: Loggen zum Debuggen
        // FeedView.logger.debug("Grid setup: isRunningOnMac=\(isRunningOnMac), minWidth=\(minWidth)")
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }
    // --- END CORRECTION ---

    private var feedCacheKey: String { "feed_\(settings.feedType == .new ? "new" : "promoted")" }

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
                    PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager)
                } else { Text("Fehler: Item nicht im aktuellen Feed gefunden.") }
            }
            .onChange(of: settings.feedType) { triggerRefreshTask() }
            .onChange(of: settings.showSFW) { triggerRefreshTask() }
            .onChange(of: settings.showNSFW) { triggerRefreshTask() }
            .onChange(of: settings.showNSFL) { triggerRefreshTask() }
            .onChange(of: settings.showNSFP) { triggerRefreshTask() }
            .onChange(of: settings.showPOL) { triggerRefreshTask() }
            .task { await playerManager.configure(settings: settings); triggerRefreshTask() }
            .onDisappear { refreshTask?.cancel(); FeedView.logger.debug("FeedView disappeared, cancelling refresh task if active.") }
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
            .onChange(of: settings.seenItemIDs) { _, _ in FeedView.logger.trace("FeedView detected change in seenItemIDs, body will update.") }
            .onChange(of: settings.hideSeenItems) { _, _ in FeedView.logger.trace("FeedView detected change in hideSeenItems, body will update.") }
        }
    }

    private func triggerRefreshTask() { /* Unverändert */
        refreshTask?.cancel(); FeedView.logger.debug("Cancelling previous refresh task (if any).")
        refreshTask = Task { await refreshItems() }; FeedView.logger.debug("Scheduled new refresh task.")
    }

    @ViewBuilder private var feedContentView: some View { /* Unverändert */
        if showNoFilterMessage { noFilterContentView }
        else if isLoading && displayedItems.isEmpty { ProgressView("Lade...").frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if displayedItems.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
            let message = settings.hideSeenItems ? "Keine neuen Medien für aktuelle Filter gefunden oder alle wurden bereits gesehen." : "Keine Medien für aktuelle Filter gefunden."
            Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { scrollViewContent }
    }
    private var scrollViewContent: some View {
        ScrollView {
            // Use computed gridColumns
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
    @ViewBuilder private var noFilterContentView: some View { /* Unverändert */
        VStack {
             Spacer(); Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt").font(UIConstants.headlineFont); Text("Bitte passe deine Filter an, um Inhalte zu sehen.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button("Filter anpassen") { showingFilterSheet = true }.buttonStyle(.bordered).padding(.top); Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).refreshable { await refreshItems() }
    }

    // MARK: - Data Loading Methods (refreshItems, getIdForLoadMore, loadMoreItems bleiben unverändert)
    func refreshItems() async { /* ... unveränderter Code ... */
        FeedView.logger.info("RefreshItems Task started.")
        guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled before starting."); return }
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Refresh blocked: No active content filter selected."); await MainActor.run { if !self.showNoFilterMessage || !self.items.isEmpty { self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil; FeedView.logger.debug("Cleared items and set showNoFilterMessage.") } }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot refresh: Cache key generation failed."); await MainActor.run { self.errorMessage = "Interner Cache-Fehler." }; return }
        var showLoadingIndicator = true; Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); if showLoadingIndicator { self.isLoading = true } }
        await MainActor.run { if self.showNoFilterMessage { self.showNoFilterMessage = false }; self.errorMessage = nil }; canLoadMore = true; isLoadingMore = false
        defer { Task { @MainActor in self.isLoading = false; showLoadingIndicator = false; FeedView.logger.info("Finishing refresh process (isLoading set to false via defer).") } }
        let currentApiFlags = settings.apiFlags; let currentFeedType = settings.feedType; FeedView.logger.info("Starting API fetch for refresh (Feed: \(currentFeedType.displayName), Flags: \(currentApiFlags)). Strategy: REPLACE.")
        do { let fetchedItemsFromAPI = try await apiService.fetchItems(flags: currentApiFlags, promoted: settings.apiPromoted); guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API fetch."); return }; FeedView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) items received for refresh."); await MainActor.run { let oldItemCount = self.items.count; self.items = fetchedItemsFromAPI; self.canLoadMore = !fetchedItemsFromAPI.isEmpty; FeedView.logger.info("FeedView updated (REPLACED). Old count: \(oldItemCount), New count: \(self.items.count)."); let oldFirstItemId = items.first?.id; let newFirstItemId = fetchedItemsFromAPI.first?.id; if !navigationPath.isEmpty && (oldItemCount != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId) { navigationPath = NavigationPath(); FeedView.logger.info("Popped navigation due to refresh resulting in different list content.") }; self.showNoFilterMessage = false }; await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey); await settings.updateCacheSizes() }
        catch is CancellationError { FeedView.logger.info("RefreshItems Task API call explicitly cancelled.") }
        catch { FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)"); guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API error."); return }; await MainActor.run { if self.items.isEmpty { self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)" } else { FeedView.logger.warning("Showing potentially stale data because API refresh failed: \(error.localizedDescription)") }; self.canLoadMore = false } }
    }
    private func getIdForLoadMore() -> Int? { /* ... unveränderter Code ... */
        guard let lastItem = items.last else { FeedView.logger.warning("Cannot load more: No original items to get ID from."); return nil }
        if settings.feedType == .promoted { guard let promotedId = lastItem.promoted else { FeedView.logger.error("Cannot load more: Promoted feed active but last original item (ID: \(lastItem.id)) has no 'promoted' ID."); Task { await MainActor.run { self.canLoadMore = false } }; return nil }; FeedView.logger.info("Using PROMOTED ID \(promotedId) from last original item for 'older' parameter."); return promotedId }
        else { FeedView.logger.info("Using ITEM ID \(lastItem.id) from last original item for 'older' parameter."); return lastItem.id }
    }
    func loadMoreItems() async { /* ... unveränderter Code ... */
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FeedView.logger.debug("Skipping loadMoreItems: State prevents loading"); return }
        guard let olderValue = getIdForLoadMore() else { FeedView.logger.warning("Skipping loadMoreItems: Could not determine 'older' value."); await MainActor.run { canLoadMore = false }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot load more: Cache key is nil."); return }
        await MainActor.run { isLoadingMore = true }; FeedView.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FeedView.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false via defer) ---") } } }
        do { let newItems = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted, olderThanId: olderValue); FeedView.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue))."); var appendedItemCount = 0; await MainActor.run { guard self.isLoadingMore else { FeedView.logger.info("Load more cancelled before UI update."); return }; if newItems.isEmpty { FeedView.logger.info("Reached end of feed (API returned empty list for older than \(olderValue))."); canLoadMore = false } else { let currentIDs = Set(self.items.map { $0.id }); let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }; if uniqueNewItems.isEmpty { FeedView.logger.warning("All loaded items (older than \(olderValue)) were duplicates."); canLoadMore = false; FeedView.logger.info("Assuming end of feed because only duplicates were returned.") } else { self.items.append(contentsOf: uniqueNewItems); appendedItemCount = uniqueNewItems.count; FeedView.logger.info("Appended \(uniqueNewItems.count) unique items to original list. Total items: \(self.items.count)"); self.canLoadMore = true } } }; if appendedItemCount > 0 { let itemsToSave = await MainActor.run { self.items }; await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey); await settings.updateCacheSizes() } }
        catch { FeedView.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)"); await MainActor.run { guard self.isLoadingMore else { return }; if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }; canLoadMore = false } }
    }
}

// Previews bleiben unverändert...
#Preview { /* ... unveränderter Code ... */
    let settings = AppSettings(); let authService = AuthService(appSettings: settings); let navigationService = NavigationService()
    return MainView().environmentObject(settings).environmentObject(authService).environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
