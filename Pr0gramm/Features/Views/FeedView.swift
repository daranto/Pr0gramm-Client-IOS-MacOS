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
    
    @State private var nextOlderThanIdForApiCall: Int? = nil


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
        // --- MODIFIED: Bedingung vereinfacht ---
        if settings.hideSeenItems {
            key += "_onlyfresh"
        }
        // --- END MODIFICATION ---
        return key
    }

    private var displayedItems: [Item] {
        return items
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
        // --- MODIFIED: Bedingung vereinfacht ---
        } else if displayedItems.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
             let message = settings.hideSeenItems ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden."
             Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        // --- END MODIFICATION ---
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

    @MainActor
    func refreshItems() async {
        guard !isLoading else { FeedView.logger.info("RefreshItems skipped: isLoading is true."); return }
        didLoadInitially = false
        FeedView.logger.info("RefreshItems Task started.")
        guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled before starting."); return }
        guard settings.hasActiveContentFilter else {
            await MainActor.run {
                if !self.showNoFilterMessage || !self.items.isEmpty {
                    self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil;
                    FeedView.logger.debug("Cleared items and set showNoFilterMessage.")
                }
            }; return
        }
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
            self.nextOlderThanIdForApiCall = nil
            FeedView.logger.debug("Cleared items and nextOlderThanIdForApiCall at start of refresh.")
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
        
        var fetchedItemsForThisRefresh: [Item] = []
        var lastRawItemFromApiResponse: Item? = nil
        var pagesAttemptedInLoop = 0
        var apiSaysNoMoreItems = false

        do {
            // --- MODIFIED: Bedingung vereinfacht ---
            if settings.hideSeenItems {
            // --- END MODIFICATION ---
                var olderParamForLoop: Int? = nil
                while fetchedItemsForThisRefresh.isEmpty && !apiSaysNoMoreItems {
                    if Task.isCancelled { throw CancellationError() }
                    pagesAttemptedInLoop += 1
                    FeedView.logger.info("Refresh (Grid): Auto-fetching page \(pagesAttemptedInLoop) for unseen (older: \(olderParamForLoop ?? -1))")

                    let apiResponse = try await apiService.fetchItems(
                        flags: currentApiFlags,
                        promoted: currentFeedTypePromoted,
                        olderThanId: olderParamForLoop,
                        showJunkParameter: currentShowJunk
                    )
                    if Task.isCancelled { throw CancellationError() }

                    let rawPageItems = apiResponse.items
                    lastRawItemFromApiResponse = rawPageItems.last
                    var pageItemsToFilter = rawPageItems
                    let rawPageItemCount = pageItemsToFilter.count
                    FeedView.logger.info("API (Grid auto-refresh page \(pagesAttemptedInLoop)) fetched \(rawPageItemCount) items.")

                    pageItemsToFilter.removeAll { settings.seenItemIDs.contains($0.id) }
                    FeedView.logger.info("Filtered \(rawPageItemCount - pageItemsToFilter.count) seen items from Grid auto-refresh page \(pagesAttemptedInLoop). \(pageItemsToFilter.count) unseen remaining.")
                    
                    fetchedItemsForThisRefresh.append(contentsOf: pageItemsToFilter)
                    
                    if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                        apiSaysNoMoreItems = true
                        FeedView.logger.info("API indicated end of feed during Grid refresh loop (Page \(pagesAttemptedInLoop)).")
                    }
                    
                    if rawPageItemCount > 0 && !apiSaysNoMoreItems {
                         olderParamForLoop = settings.feedType == .promoted ? rawPageItems.last!.promoted ?? rawPageItems.last!.id : rawPageItems.last!.id
                    } else if rawPageItemCount == 0 && !apiSaysNoMoreItems {
                        apiSaysNoMoreItems = true
                        FeedView.logger.info("API returned 0 items during Grid refresh loop (Page \(pagesAttemptedInLoop)), assuming end.")
                    }
                }
                 if fetchedItemsForThisRefresh.isEmpty && !apiSaysNoMoreItems {
                    FeedView.logger.warning("Scanned \(pagesAttemptedInLoop) pages for unseen items in Grid refresh, but found none. API did not report end.")
                }
            } else {
                let apiResponse = try await apiService.fetchItems(
                    flags: currentApiFlags,
                    promoted: currentFeedTypePromoted,
                    showJunkParameter: currentShowJunk
                )
                fetchedItemsForThisRefresh = apiResponse.items
                lastRawItemFromApiResponse = fetchedItemsForThisRefresh.last
                if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                    apiSaysNoMoreItems = true
                }
                FeedView.logger.info("API fetch (Grid, no hideSeenItems) completed: \(fetchedItemsForThisRefresh.count) items. API at end: \(apiSaysNoMoreItems)")
            }

            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API fetch."); return }
            
            await MainActor.run {
                 self.items = fetchedItemsForThisRefresh
                 self.canLoadMore = !apiSaysNoMoreItems
                 FeedView.logger.info("FeedView updated (REPLACED). Count: \(self.items.count). Can load more: \(self.canLoadMore)")
                 
                 if let lastRaw = lastRawItemFromApiResponse {
                     self.nextOlderThanIdForApiCall = settings.feedType == .promoted ? lastRaw.promoted ?? lastRaw.id : lastRaw.id
                 } else if !fetchedItemsForThisRefresh.isEmpty {
                     let lastInCurrent = fetchedItemsForThisRefresh.last!
                     self.nextOlderThanIdForApiCall = settings.feedType == .promoted ? lastInCurrent.promoted ?? lastInCurrent.id : lastInCurrent.id
                 } else {
                     self.nextOlderThanIdForApiCall = nil
                 }
                 FeedView.logger.info("Next older ID for API (after refresh) set to: \(self.nextOlderThanIdForApiCall ?? -1)")
                 
                 if !navigationPath.isEmpty { navigationPath = NavigationPath(); FeedView.logger.info("Popped navigation due to refresh.") }
                 self.showNoFilterMessage = false
                 self.didLoadInitially = true
            }
            // --- MODIFIED: Bedingung vereinfacht ---
            if !settings.hideSeenItems {
            // --- END MODIFICATION ---
                await settings.saveItemsToCache(fetchedItemsForThisRefresh, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            } else {
                FeedView.logger.info("Skipping cache save for Grid refresh because 'Nur Frisches anzeigen' is active.")
            }
        } catch is CancellationError { FeedView.logger.info("RefreshItems Task API call explicitly cancelled.") }
          catch {
            FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            guard !Task.isCancelled else { FeedView.logger.info("RefreshItems Task cancelled after API error."); return }
            await MainActor.run {
                self.didLoadInitially = true
                if self.items.isEmpty { self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)" }
                else { FeedView.logger.warning("Showing potentially stale data because API refresh failed: \(error.localizedDescription)") }
                self.canLoadMore = false
                self.nextOlderThanIdForApiCall = nil
            }
          }
    }

    @MainActor
    func loadMoreItems() async {
        guard settings.hasActiveContentFilter else { FeedView.logger.warning("Skipping loadMoreItems: No active content filter selected."); await MainActor.run { canLoadMore = false }; return }
        guard !isLoadingMore && canLoadMore && !isLoading else { FeedView.logger.debug("Skipping loadMoreItems: State prevents loading (isLoadingMore: \(isLoadingMore), canLoadMore: \(canLoadMore), isLoading: \(isLoading))"); return }
        
        guard let olderValueForThisApiCall = nextOlderThanIdForApiCall else {
            FeedView.logger.warning("Skipping loadMoreItems: nextOlderThanIdForApiCall is nil. End of feed likely reached or error.")
            await MainActor.run { self.canLoadMore = false }
            return
        }

        guard let currentCacheKey = Optional(self.feedCacheKey) else { FeedView.logger.error("Cannot load more: Cache key is nil."); return }
        
        await MainActor.run { isLoadingMore = true }
        FeedView.logger.info("--- Starting loadMoreItems older than \(olderValueForThisApiCall) ---")
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FeedView.logger.info("--- Finished loadMoreItems (isLoadingMore set to false via defer) ---") } } }
        
        var itemsToAppend: [Item] = []
        var apiSaysNoMoreItemsAfterLoadMore = false
        var pagesAttemptedInLoopForLoadMore = 0
        var currentOlderForLoopProgress: Int? = olderValueForThisApiCall
        var lastRawItemFromApiLoop: Item? = nil

        do {
            // --- MODIFIED: Bedingung vereinfacht ---
            if settings.hideSeenItems {
            // --- END MODIFICATION ---
                while itemsToAppend.isEmpty && !apiSaysNoMoreItemsAfterLoadMore {
                    if Task.isCancelled { throw CancellationError() }
                    pagesAttemptedInLoopForLoadMore += 1
                    FeedView.logger.info("LoadMore (Grid): Auto-fetching page \(pagesAttemptedInLoopForLoadMore) for unseen (older: \(currentOlderForLoopProgress ?? -1))")

                    let apiResponse = try await apiService.fetchItems(
                        flags: settings.apiFlags,
                        promoted: settings.apiPromoted,
                        olderThanId: currentOlderForLoopProgress,
                        showJunkParameter: settings.apiShowJunk
                    )
                    if Task.isCancelled { throw CancellationError() }
                    
                    let rawPageItems = apiResponse.items
                    lastRawItemFromApiLoop = rawPageItems.last
                    var pageItemsToFilter = rawPageItems
                    let rawPageItemCount = pageItemsToFilter.count
                    FeedView.logger.info("API (Grid loadMore page \(pagesAttemptedInLoopForLoadMore)) fetched \(rawPageItemCount) items.")

                    pageItemsToFilter.removeAll { settings.seenItemIDs.contains($0.id) }
                     FeedView.logger.info("Filtered \(rawPageItemCount - pageItemsToFilter.count) seen items from Grid loadMore page \(pagesAttemptedInLoopForLoadMore). \(pageItemsToFilter.count) unseen remaining.")

                    let currentItemIDsInState = Set(self.items.map { $0.id })
                    let uniqueNewPageItems = pageItemsToFilter.filter { !currentItemIDsInState.contains($0.id) }
                    itemsToAppend.append(contentsOf: uniqueNewPageItems)

                    if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                        apiSaysNoMoreItemsAfterLoadMore = true
                        FeedView.logger.info("API indicated end of feed during Grid loadMore loop (Page \(pagesAttemptedInLoopForLoadMore)).")
                    }
                    
                    if rawPageItemCount > 0 && !apiSaysNoMoreItemsAfterLoadMore {
                        if let lastRawItem = rawPageItems.last {
                             currentOlderForLoopProgress = settings.feedType == .promoted ?
                                                        lastRawItem.promoted ?? lastRawItem.id :
                                                        lastRawItem.id
                        } else {
                            apiSaysNoMoreItemsAfterLoadMore = true
                            FeedView.logger.warning("rawPageItemCount > 0 but apiResponse.items.last was nil in LoadMore. Assuming end.")
                        }
                    } else if rawPageItemCount == 0 && !apiSaysNoMoreItemsAfterLoadMore {
                         apiSaysNoMoreItemsAfterLoadMore = true
                         FeedView.logger.info("API returned 0 items during Grid loadMore loop (Page \(pagesAttemptedInLoopForLoadMore)), assuming end.")
                    }
                }
                if itemsToAppend.isEmpty && !apiSaysNoMoreItemsAfterLoadMore {
                    FeedView.logger.warning("Scanned \(pagesAttemptedInLoopForLoadMore) pages for unseen items in Grid loadMore, but found none. API did not report end.")
                }
            } else {
                 let apiResponse = try await apiService.fetchItems(
                    flags: settings.apiFlags,
                    promoted: settings.apiPromoted,
                    olderThanId: olderValueForThisApiCall,
                    showJunkParameter: settings.apiShowJunk
                )
                let currentItemIDs = Set(self.items.map { $0.id })
                itemsToAppend = apiResponse.items.filter { !currentItemIDs.contains($0.id) }
                lastRawItemFromApiLoop = apiResponse.items.last

                if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                    apiSaysNoMoreItemsAfterLoadMore = true
                }
                FeedView.logger.info("API fetch (Grid loadMore, no hideSeenItems) completed: \(itemsToAppend.count) new unique items. API at end: \(apiSaysNoMoreItemsAfterLoadMore)")
            }
            
            guard !Task.isCancelled else { FeedView.logger.info("LoadMoreItems Task cancelled after API fetch."); return }
            
            await MainActor.run {
                if !itemsToAppend.isEmpty {
                    self.items.append(contentsOf: itemsToAppend)
                    FeedView.logger.info("Appended \(itemsToAppend.count) unique items to list. Total items: \(self.items.count)")
                }
                
                self.canLoadMore = !apiSaysNoMoreItemsAfterLoadMore
                
                if let lastRaw = lastRawItemFromApiLoop {
                    self.nextOlderThanIdForApiCall = settings.feedType == .promoted ? lastRaw.promoted ?? lastRaw.id : lastRaw.id
                     FeedView.logger.info("Next older ID for API (after loadMore) set to: \(self.nextOlderThanIdForApiCall ?? -1)")
                } else if apiSaysNoMoreItemsAfterLoadMore {
                    self.nextOlderThanIdForApiCall = nil
                     FeedView.logger.info("Next older ID for API set to nil due to API end signal and no new items from this fetch.")
                // --- MODIFIED: Bedingung vereinfacht ---
                } else if itemsToAppend.isEmpty && settings.hideSeenItems {
                // --- END MODIFICATION ---
                    self.nextOlderThanIdForApiCall = currentOlderForLoopProgress
                     FeedView.logger.info("No unseen items found in loop, but API not at end. nextOlderThanIdForApiCall remains \(self.nextOlderThanIdForApiCall ?? -1) for next attempt.")
                }
                
                // --- MODIFIED: Bedingung vereinfacht ---
                if itemsToAppend.isEmpty && self.canLoadMore && settings.hideSeenItems {
                // --- END MODIFICATION ---
                     FeedView.logger.info("No new unseen items appended, but API doesn't signal end. Allowing further load attempts for 'Nur Frisches'. Max scan pages attempted in this run: \(pagesAttemptedInLoopForLoadMore)")
                }
                FeedView.logger.info("LoadMore (Grid) finished. canLoadMore set to \(self.canLoadMore).")
            }
            // --- MODIFIED: Bedingung vereinfacht ---
            if !itemsToAppend.isEmpty && !settings.hideSeenItems {
            // --- END MODIFICATION ---
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            } else if !itemsToAppend.isEmpty {
                 FeedView.logger.info("Skipping cache save for Grid loadMore because 'Nur Frisches anzeigen' is active.")
            }
        } catch is CancellationError {
             FeedView.logger.info("LoadMoreItems Task API call explicitly cancelled.")
        } catch {
            FeedView.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                 self.canLoadMore = false
                 self.nextOlderThanIdForApiCall = nil
            }
        }
    }
}

#Preview {
    let settings = AppSettings(); let authService = AuthService(appSettings: settings); let navigationService = NavigationService()
    return MainView().environmentObject(settings).environmentObject(authService).environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
