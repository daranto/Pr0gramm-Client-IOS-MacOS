// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

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


    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    private let initialLoadDelay: Duration = .milliseconds(300)
    private let refreshIndicatorDelay: Duration = .milliseconds(250)


    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact
            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 400 : (numberOfColumns <= 3 ? 100 : 80)
            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
        }

    private var feedCacheKey: String {
        var key = "feed_\(settings.feedType.displayName.lowercased())"
        if settings.feedType != .junk {
            key += "_flags_\(settings.apiFlags)"
        }
        return key
    }


    private var displayedItems: [Item] {
        if settings.hideSeenItems {
            return items.filter { !settings.seenItemIDs.contains($0.id) }
        } else {
            return items
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("Feed Typ", selection: $settings.feedType) {
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button { showingFilterSheet = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .labelStyle(.iconOnly)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color(uiColor: .systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                feedContentView
            }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView(relevantFeedTypeForFilterBehavior: settings.feedType, hideFeedOptions: true, showHideSeenItemsToggle: true)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
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
                     try? await Task.sleep(for: initialLoadDelay)
                     guard !Task.isCancelled else { FeedView.logger.info("FeedView initial task cancelled during sleep."); return }
                     FeedView.logger.debug("FeedView task: Delay finished, triggering initial refresh task.")
                     await refreshItems()
                 } else {
                     FeedView.logger.debug("FeedView task: Initial load already done, skipping refresh.")
                 }
             }
            .onDisappear {
                refreshTask?.cancel()
                FeedView.logger.debug("FeedView disappeared, cancelling tasks if active.")
            }
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
            .onChange(of: settings.seenItemIDs) { _, _ in FeedView.logger.trace("FeedView detected change in seenItemIDs, body will update.") }
            .onChange(of: settings.hideSeenItems) { _, newValue in
                FeedView.logger.info("Hide seen items setting changed to: \(newValue)")
                triggerRefreshTask(resetInitialLoad: true)
            }
        }
    }

    private func triggerRefreshTask(resetInitialLoad: Bool = false) {
        if resetInitialLoad {
            didLoadInitially = false
            FeedView.logger.debug("Resetting didLoadInitially due to filter/feed change.")
        }
        refreshTask?.cancel(); FeedView.logger.debug("Cancelling previous refresh task (if any).")
        refreshTask = Task { await refreshItems() }; FeedView.logger.debug("Scheduled new refresh task.")
    }

    @ViewBuilder private var feedContentView: some View {
        if showNoFilterMessage { noFilterContentView }
        else if isLoading && (items.isEmpty || !didLoadInitially) {
            ProgressView("Lade...").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedItems.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
             let message = settings.hideSeenItems && settings.enableExperimentalHideSeen ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden."
             Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { scrollViewContent }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(displayedItems) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }
                        .buttonStyle(.plain)
                }

                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            FeedView.logger.info("Feed: End trigger appeared.")
                            Task { await loadMoreItems() }
                        }
                }

                if isLoadingMore {
                    ProgressView("Lade mehr...")
                        .padding()
                        .gridCellColumns(gridColumns.count)
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
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
        guard !isLoading else { FeedView.logger.info("RefreshItems skipped: isLoading is true."); return }
        didLoadInitially = false
        FeedView.logger.info("RefreshItems Task started.")
        guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled before starting."); return }
        guard settings.hasActiveContentFilter else { await MainActor.run { if !self.showNoFilterMessage || !self.items.isEmpty { self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil; FeedView.logger.debug("Cleared items and set showNoFilterMessage.") } }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { await MainActor.run { self.errorMessage = "Interner Cache-Fehler." }; return }
        
        let showLoadingIndicatorTask: Task<Void, Never>? = Task { @MainActor in
             try? await Task.sleep(for: refreshIndicatorDelay)
             if !Task.isCancelled { self.isLoading = true; FeedView.logger.debug("Setting isLoading = true after delay.") }
             else { FeedView.logger.debug("isLoading indicator task cancelled before setting true.") }
        }
        await MainActor.run {
            if self.showNoFilterMessage { self.showNoFilterMessage = false };
            self.errorMessage = nil
            self.items = []
            FeedView.logger.debug("Cleared items at start of refresh.")
        }
        canLoadMore = true; isLoadingMore = false
        
        defer {
             showLoadingIndicatorTask?.cancel()
             Task { @MainActor in
                 if self.isLoading { self.isLoading = false; FeedView.logger.debug("Resetting isLoading = false in defer.") }
                 FeedView.logger.info("Finishing refresh process.")
             }
        }
        
        let currentApiFlags = settings.apiFlags; let currentFeedTypePromoted = settings.apiPromoted; let currentShowJunk = settings.apiShowJunk
        FeedView.logger.info("Starting API fetch for refresh (FeedType: \(settings.feedType.displayName), Flags: \(currentApiFlags), Promoted: \(String(describing: currentFeedTypePromoted)), Junk: \(currentShowJunk)). Strategy: REPLACE.")
        
        do {
            let apiResponse = try await apiService.fetchItems(
                flags: currentApiFlags,
                promoted: currentFeedTypePromoted,
                showJunkParameter: currentShowJunk
            )
            let fetchedItemsFromAPI = apiResponse.items

            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API fetch."); return }
            FeedView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) items received for refresh.")
            
            await MainActor.run {
                 self.items = fetchedItemsFromAPI
                if fetchedItemsFromAPI.isEmpty {
                    self.canLoadMore = false
                    FeedView.logger.info("Refresh returned 0 items. Setting canLoadMore to false.")
                } else {
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    if atEnd {
                        self.canLoadMore = false
                        FeedView.logger.info("API indicates atEnd=true. Setting canLoadMore to false.")
                    } else if hasOlder == false { // Nur false, nicht nil
                        self.canLoadMore = false
                        FeedView.logger.info("API indicates hasOlder=false. Setting canLoadMore to false.")
                    } else {
                        self.canLoadMore = true
                        FeedView.logger.info("API indicates more items might be available for refresh (atEnd=\(atEnd), hasOlder=\(hasOlder)). Setting canLoadMore to true.")
                    }
                }
                 FeedView.logger.info("FeedView updated (REPLACED). Count: \(self.items.count). Can load more: \(self.canLoadMore)")
                 if !navigationPath.isEmpty { navigationPath = NavigationPath(); FeedView.logger.info("Popped navigation due to refresh.") }
                 self.showNoFilterMessage = false
                 self.didLoadInitially = true
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey)
            await settings.updateCacheSizes()
        } catch is CancellationError { FeedView.logger.info("RefreshItems Task API call explicitly cancelled.") }
          catch {
            FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API error."); return }
            await MainActor.run {
                self.didLoadInitially = true
                if self.items.isEmpty { self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)" }
                else { FeedView.logger.warning("Showing potentially stale data because API refresh failed: \(error.localizedDescription)") }
                self.canLoadMore = false
            }
          }
    }

    private func getIdForLoadMore() -> Int? {
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
             FeedView.logger.info("Using ITEM ID \(lastItem.id) from last original item for 'older' parameter (for New or Junk feed).")
             return lastItem.id
        }
    }

    @MainActor
    func loadMoreItems() async {
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FeedView.logger.debug("Skipping loadMoreItems: State prevents loading (isLoadingMore: \(isLoadingMore), canLoadMore: \(canLoadMore), isLoading: \(isLoading))"); return }
        guard let olderValue = getIdForLoadMore() else { FeedView.logger.warning("Skipping loadMoreItems: Could not determine 'older' value."); await MainActor.run { canLoadMore = false }; return }
        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot load more: Cache key is nil."); return }
        
        await MainActor.run { isLoadingMore = true }
        FeedView.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FeedView.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false via defer) ---") } } }
        
        do {
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                olderThanId: olderValue,
                showJunkParameter: settings.apiShowJunk
            )
            let newItems = apiResponse.items

            guard !Task.isCancelled else { FeedView.logger.info("LoadMoreItems Task cancelled after API fetch."); return }
            FeedView.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).");
            var appendedItemCount = 0
            
            await MainActor.run {
                if newItems.isEmpty {
                    FeedView.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    self.canLoadMore = false // Wenn 0 Items geladen werden, gibt es nichts mehr.
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                    if uniqueNewItems.isEmpty {
                        FeedView.logger.warning("All loaded items (older than \(olderValue)) were duplicates. Assuming end of actual new content.")
                        self.canLoadMore = false // Wenn nur Duplikate kommen, gibt es auch nichts Neues mehr.
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        FeedView.logger.info("Appended \(uniqueNewItems.count) unique items to original list. Total items: \(self.items.count)")
                        
                        let atEnd = apiResponse.atEnd ?? false
                        let hasOlder = apiResponse.hasOlder ?? true // Default to true if nil, to potentially try again
                        if atEnd {
                            self.canLoadMore = false
                            FeedView.logger.info("API indicates atEnd=true after loadMore.")
                        } else if hasOlder == false { // Nur false, nicht nil
                            self.canLoadMore = false
                            FeedView.logger.info("API indicates hasOlder=false after loadMore.")
                        } else {
                            self.canLoadMore = true
                            FeedView.logger.info("API indicates more items might be available after loadMore (atEnd=\(atEnd), hasOlder=\(hasOlder)).")
                        }
                    }
                }
            }
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            }
        } catch is CancellationError {
             FeedView.logger.info("LoadMoreItems Task API call explicitly cancelled.")
        } catch {
            FeedView.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                 FeedView.logger.warning("Load more failed, allowing potential retry on scroll. canLoadMore remains \(canLoadMore).")
            }
        }
    }
}

#Preview {
    let settings = AppSettings(); let authService = AuthService(appSettings: settings); let navigationService = NavigationService()
    return MainView().environmentObject(settings).environmentObject(authService).environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
