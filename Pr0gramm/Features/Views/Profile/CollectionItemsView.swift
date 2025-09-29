// Pr0gramm/Pr0gramm/Features/Views/Profile/CollectionItemsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays the items within a specific user collection in a grid.
/// Handles loading, pagination, filtering (based on global settings), and navigation.
struct CollectionItemsView: View {
    let collection: ApiCollection
    let username: String

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State var items: [Item]
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false

    @StateObject private var playerManager = VideoPlayerManager()
    @State private var showingFilterSheet = false

    @State private var searchText = ""
    @State private var currentSearchTagForAPI: String? = nil
    @State private var searchDebounceTimer: Timer? = nil
    private let searchDebounceInterval: TimeInterval = 0.75
    @State private var hasAttemptedSearchSinceAppear = false

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CollectionItemsView")

    init(collection: ApiCollection, username: String, initialItemsForPreview: [Item]? = nil) {
        self.collection = collection
        self.username = username
        self._items = State(initialValue: initialItemsForPreview ?? [])
    }

    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact

            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)

            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
        }

    private var collectionItemsCacheKey: String {
        let safeKeyword = collection.keyword?.replacingOccurrences(of: " ", with: "_") ?? "id_\(collection.id)"
        var key = "collection_\(username.lowercased())_\(safeKeyword)_flags_\(settings.apiFlags)_items"
        if let searchTerm = currentSearchTagForAPI, !searchTerm.isEmpty {
            let safeSearchTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? searchTerm
            key += "_search_\(safeSearchTerm)"
        }
        return key
    }

    var body: some View {
        content
        .navigationTitle(collection.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sammlung nach Tags filtern")
        .onSubmit(of: .search) {
            CollectionItemsView.logger.info("Search submitted for collection '\(collection.name)' with: \(searchText)")
            searchDebounceTimer?.invalidate()
            Task {
                await performSearchLogic(isInitialSearch: true)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            CollectionItemsView.logger.info("Search text for collection '\(collection.name)' changed from '\(oldValue)' to '\(newValue)'")
            searchDebounceTimer?.invalidate()

            let trimmedNewValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousAPITag = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if trimmedNewValue.isEmpty && !previousAPITag.isEmpty {
                CollectionItemsView.logger.info("Search text cleared for collection '\(collection.name)', loading unfiltered items.")
                Task {
                    await performSearchLogic(isInitialSearch: true)
                }
            } else if !trimmedNewValue.isEmpty && trimmedNewValue.count >= 2 {
                 CollectionItemsView.logger.info("Starting debounce timer for search (collection '\(collection.name)'): '\(trimmedNewValue)'")
                searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: searchDebounceInterval, repeats: false) { _ in
                     CollectionItemsView.logger.info("Debounce timer fired for search (collection '\(collection.name)'): '\(trimmedNewValue)'")
                    Task {
                        await performSearchLogic(isInitialSearch: true)
                    }
                }
            } else if trimmedNewValue.isEmpty && previousAPITag.isEmpty && !items.isEmpty && hasAttemptedSearchSinceAppear {
                 CollectionItemsView.logger.info("Search text empty for collection '\(collection.name)', no previous API tag, items exist. No API call needed.")
            } else if trimmedNewValue.isEmpty && items.isEmpty && hasAttemptedSearchSinceAppear {
                 CollectionItemsView.logger.info("Search text empty for collection '\(collection.name)', items empty, but a search was attempted. Showing appropriate message.")
            }
        }
        .navigationDestination(for: Item.self) { destinationItem in
            if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                PagedDetailView(
                    items: $items,
                    selectedIndex: index,
                    playerManager: playerManager,
                    loadMoreAction: { Task { await loadMoreItems() } }
                )
                .environmentObject(settings)
                .environmentObject(authService)
            } else {
                Text("Fehler: Item \(destinationItem.id) nicht in dieser Sammlung gefunden.")
                    .onAppear { CollectionItemsView.logger.warning("Navigation destination item \(destinationItem.id) not found in CollectionItemsView.") }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task {
            playerManager.configure(settings: settings)
            hasAttemptedSearchSinceAppear = false
            if items.isEmpty && currentSearchTagForAPI == nil {
                await refreshItems()
            } else if currentSearchTagForAPI != nil {
                await performSearchLogic(isInitialSearch: true)
            }
        }
        .onChange(of: settings.apiFlags) { _, _ in
            CollectionItemsView.logger.info("API flags changed, resetting search and refreshing collection '\(collection.name)'.")
            currentSearchTagForAPI = nil
            searchText = ""
            Task { await refreshItems() }
        }
        .onChange(of: settings.seenItemIDs) { _, _ in CollectionItemsView.logger.trace("CollectionItemsView detected change in seenItemIDs for collection '\(collection.name)'.") }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            loadingView
        } else if let error = errorMessage, items.isEmpty {
            errorView(error: error)
        } else if showNoFilterMessage {
            noFilterContentView
        } else if items.isEmpty && hasAttemptedSearchSinceAppear && !(currentSearchTagForAPI?.isEmpty ?? true) && !isLoading {
            ContentUnavailableView {
                Label("Keine Ergebnisse", systemImage: "magnifyingglass")
            } description: {
                Text("Die Sammlung '\(collection.name)' enthält keine Items für den Tag '\(currentSearchTagForAPI!)' (oder sie passen nicht zu deinen Filtern).")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && !isLoading && errorMessage == nil {
            emptyContentView
        } else {
            scrollViewContent
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        ProgressView("Lade Items der Sammlung...")
            .font(UIConstants.bodyFont)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(error: String) -> some View {
        ContentUnavailableView {
            Label("Fehler", systemImage: "exclamationmark.triangle")
               .font(UIConstants.headlineFont)
        } description: {
            Text(error)
               .font(UIConstants.bodyFont)
        } actions: {
            Button("Erneut versuchen") { Task { await refreshItems() } }
               .font(UIConstants.bodyFont)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyContentView: some View {
        Text("Diese Sammlung enthält keine Items, die deinen aktuellen Filtern entsprechen.")
            .font(UIConstants.bodyFont)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                 ForEach(items) { item in
                     NavigationLink(value: item) { // value ist Item, wird von ProfileView gehandhabt
                         FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                     }
                     .buttonStyle(.plain)
                 }
                 if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1)
                         .onAppear {
                             CollectionItemsView.logger.info("Collection '\(collection.name)': End trigger appeared.")
                             Task { await loadMoreItems() }
                         }
                 }
                 if isLoadingMore {
                     ProgressView("Lade mehr...")
                        .font(UIConstants.bodyFont)
                        .padding()
                        .gridCellColumns(gridColumns.count)
                 }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable { await refreshItems() }
    }

    @ViewBuilder
    private var noFilterContentView: some View {
        VStack {
             Spacer()
             Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
             Text("Keine Items für Filter").font(UIConstants.headlineFont)
             Text("Bitte passe deine globalen Inhaltsfilter an, um möglicherweise mehr Items in dieser Sammlung zu sehen.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button("Filter anpassen") {
                 showingFilterSheet = true
             }
             .buttonStyle(.bordered)
             .padding(.top)
             Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refreshItems() }
    }

    @MainActor
    private func performSearchLogic(isInitialSearch: Bool) async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSearchText.isEmpty && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
            if !hasAttemptedSearchSinceAppear { hasAttemptedSearchSinceAppear = true }
            if showNoFilterMessage {
                CollectionItemsView.logger.info("performSearchLogic for collection '\(collection.name)': Search text empty, no previous tag, but 'no filter' message is shown. Skipping API call.")
                return
            }
            if items.isEmpty {
                if currentSearchTagForAPI != nil {
                    currentSearchTagForAPI = nil
                    await refreshItems()
                }
            }
            CollectionItemsView.logger.info("performSearchLogic for collection '\(collection.name)': Search text empty, no previous API tag. No API call needed unless list is empty.")
            return
        }
        
        currentSearchTagForAPI = trimmedSearchText.isEmpty ? nil : trimmedSearchText
        
        CollectionItemsView.logger.info("performSearchLogic for collection '\(collection.name)': isInitial=\(isInitialSearch). API Tag: '\(currentSearchTagForAPI ?? "nil")'")
        await refreshItems()
        hasAttemptedSearchSinceAppear = true
    }

    // MARK: - Data Loading Methods
    @MainActor
    func refreshItems() async {
        CollectionItemsView.logger.info("Refreshing items for collection: '\(collection.name)' (Keyword: \(collection.keyword ?? "N/A")) by user: \(username), search: '\(currentSearchTagForAPI ?? "nil")'")
        let cacheKey = collectionItemsCacheKey

        self.isLoading = true
        self.errorMessage = nil
        self.showNoFilterMessage = false
        defer { Task { @MainActor in self.isLoading = false; CollectionItemsView.logger.info("Finished item refresh process for collection '\(collection.name)'.") } }

        let currentApiFlags = settings.apiFlags
        
        if currentApiFlags == 0 && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
            CollectionItemsView.logger.warning("Refresh items for collection '\(collection.name)' blocked: No active content filter selected (apiFlags is 0) and no search term.")
            self.items = []
            self.showNoFilterMessage = true
            self.canLoadMore = false
            self.isLoadingMore = false
            return
        }
        
        guard let collectionNameForAPI = collection.keyword else {
            CollectionItemsView.logger.error("Cannot refresh items: Collection keyword is nil for collection ID \(collection.id).")
            self.items = []; self.errorMessage = "Sammlungs-Name (Keyword) fehlt."; self.canLoadMore = false; self.isLoadingMore = false
            return
        }

        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        if self.items.isEmpty {
            initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
            if let cached = initialItemsFromCache, !cached.isEmpty {
                 CollectionItemsView.logger.info("Found \(cached.count) items in cache for collection '\(collection.name)' (search: '\(currentSearchTagForAPI ?? "nil")').");
                 self.items = cached
            } else {
                 CollectionItemsView.logger.info("No usable data cache found for collection '\(collection.name)' (search: '\(currentSearchTagForAPI ?? "nil")').")
            }
        }
        
        let apiTagsParameter = currentSearchTagForAPI
        CollectionItemsView.logger.info("Performing API fetch for collection items refresh (Collection Keyword: '\(collectionNameForAPI)', User: \(username), Flags: \(currentApiFlags), API Tags: '\(apiTagsParameter ?? "nil")')...");
        do {
            let isOwn = authService.currentUser?.name.lowercased() == username.lowercased() && authService.isLoggedIn
            let apiResponse = try await apiService.fetchItems(
                flags: currentApiFlags,
                user: username,
                tags: apiTagsParameter,
                collectionNameForUser: collectionNameForAPI,
                isOwnCollection: isOwn
            )
            let fetchedItemsFromAPI = apiResponse.items
            CollectionItemsView.logger.info("API fetch for collection '\(collection.name)' completed: \(fetchedItemsFromAPI.count) items.");
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.items = fetchedItemsFromAPI
                if fetchedItemsFromAPI.isEmpty && currentApiFlags != 0 && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
                    self.showNoFilterMessage = true
                    CollectionItemsView.logger.info("API returned no items for collection '\(collection.name)' with active global filters (no search term). Setting showNoFilterMessage.")
                } else if fetchedItemsFromAPI.isEmpty && !(currentSearchTagForAPI?.isEmpty ?? true) {
                     CollectionItemsView.logger.info("API returned no items for collection '\(collection.name)' with search term '\(currentSearchTagForAPI!)'. 'showNoFilterMessage' remains false.")
                     self.showNoFilterMessage = false
                } else {
                    self.showNoFilterMessage = false
                }
                
                if fetchedItemsFromAPI.isEmpty {
                    self.canLoadMore = false
                    CollectionItemsView.logger.info("Refresh returned 0 items for collection '\(collection.name)'. Setting canLoadMore to false.")
                } else {
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    if atEnd || !hasOlder {
                        self.canLoadMore = false
                        CollectionItemsView.logger.info("API indicates end of feed for collection '\(collection.name)'. Setting canLoadMore to false.")
                    } else {
                        self.canLoadMore = true
                        CollectionItemsView.logger.info("API indicates more items might be available for collection '\(collection.name)' (atEnd=\(atEnd), hasOlder=\(hasOlder)). Setting canLoadMore to true.")
                    }
                }
                CollectionItemsView.logger.info("CollectionItemsView updated with \(fetchedItemsFromAPI.count) items from API for collection '\(collection.name)'. Can load more: \(self.canLoadMore)")
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            CollectionItemsView.logger.error("API fetch for collection items failed: Authentication required (Collection: '\(collection.name)').");
            await MainActor.run {
                self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false
            }
            await settings.saveItemsToCache([], forKey: cacheKey)
            await authService.logout()
        }
        catch is CancellationError { CollectionItemsView.logger.info("Collection items API call cancelled for '\(collection.name)'.") }
        catch {
            CollectionItemsView.logger.error("API fetch for collection items failed (Collection: '\(collection.name)'): \(error.localizedDescription)");
            await MainActor.run {
                if self.items.isEmpty { self.errorMessage = "Fehler beim Laden der Sammlung: \(error.localizedDescription)" }
                else { CollectionItemsView.logger.warning("Showing potentially stale cached collection items data for '\(collection.name)'.") }
                self.canLoadMore = false
            }
        }
    }

    @MainActor
    func loadMoreItems() async {
        let currentApiFlags = settings.apiFlags
        let apiTagsParameter = currentSearchTagForAPI

        if currentApiFlags == 0 && (apiTagsParameter == nil || apiTagsParameter!.isEmpty) {
            CollectionItemsView.logger.warning("Skipping loadMoreItems for collection '\(collection.name)': No active content filter selected and no search.")
            self.canLoadMore = false; return
        }
        
        guard !isLoadingMore && canLoadMore && !isLoading else {
            CollectionItemsView.logger.debug("Skipping loadMoreItems for collection '\(collection.name)': State prevents loading.")
            return
        }
        guard let lastItemId = items.last?.id else {
            CollectionItemsView.logger.warning("Skipping loadMoreItems for collection '\(collection.name)': No last item found.")
            return
        }
        guard let collectionNameForAPI = collection.keyword else {
            CollectionItemsView.logger.error("Cannot load more items: Collection keyword is nil for collection ID \(collection.id).")
            self.canLoadMore = false; return
        }

        let cacheKey = collectionItemsCacheKey
        CollectionItemsView.logger.info("--- Starting loadMoreItems for collection '\(collection.name)' by \(username), search '\(apiTagsParameter ?? "nil")' older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; CollectionItemsView.logger.info("--- Finished loadMoreItems for collection '\(collection.name)' ---") } } }

        do {
            let isOwn = authService.currentUser?.name.lowercased() == username.lowercased() && authService.isLoggedIn
            let apiResponse = try await apiService.fetchItems(
                flags: currentApiFlags,
                user: username,
                tags: apiTagsParameter,
                olderThanId: lastItemId,
                collectionNameForUser: collectionNameForAPI,
                isOwnCollection: isOwn
            )
            let newItems = apiResponse.items
            CollectionItemsView.logger.info("Loaded \(newItems.count) more items from API for collection '\(collection.name)'.");
            var appendedItemCount = 0
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { return }

            if newItems.isEmpty {
                CollectionItemsView.logger.info("Reached end of item feed for collection '\(collection.name)' because API returned 0 items for loadMore.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.items.map { $0.id })
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                if uniqueNewItems.isEmpty {
                    CollectionItemsView.logger.warning("All loaded items for collection '\(collection.name)' (older than \(lastItemId)) were duplicates. Assuming end of actual new content.")
                    self.canLoadMore = false
                } else {
                    self.items.append(contentsOf: uniqueNewItems)
                    appendedItemCount = uniqueNewItems.count
                    CollectionItemsView.logger.info("Appended \(uniqueNewItems.count) unique items to collection '\(collection.name)'. Total items: \(self.items.count)")
                    
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    if atEnd || !hasOlder {
                        self.canLoadMore = false
                        CollectionItemsView.logger.info("API indicates end of feed after loadMore for collection '\(collection.name)'.")
                    } else {
                        self.canLoadMore = true
                        CollectionItemsView.logger.info("API indicates more items might be available after loadMore for collection '\(collection.name)' (atEnd=\(atEnd), hasOlder=\(hasOlder)).")
                    }
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = self.items
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            CollectionItemsView.logger.error("API fetch for more collection items failed: Authentication required (Collection: '\(collection.name)').");
            self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { CollectionItemsView.logger.info("Load more collection items API call cancelled for '\(collection.name)'.") }
        catch {
            CollectionItemsView.logger.error("API fetch failed during loadMoreItems for collection '\(collection.name)': \(error.localizedDescription)");
            guard !Task.isCancelled else { return }; guard self.isLoadingMore else { return };
            if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" };
            self.canLoadMore = false
        }
    }
}

// MARK: - Previews
#Preview("Collection With Items") {
    struct Previewer: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService

        let sampleCollection: ApiCollection
        let sampleItems: [Item]
        let username: String

        init() {
            let tempSettings = AppSettings()
            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: AuthService(appSettings: tempSettings))

            self.sampleCollection = ApiCollection(id: 102, name: "Lustige Katzen Videos", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45)
            self.sampleItems = [
                Item(id: 1, promoted: nil, userId: 1, down: 0, up: 10, created: 1, image: "cat1.jpg", thumb: "cat1_thumb.jpg", fullsize: nil, preview: nil, width: 100, height: 100, audio: false, source: nil, flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, subtitles: nil, favorited: nil),
                Item(id: 2, promoted: nil, userId: 1, down: 0, up: 10, created: 1, image: "cat2.mp4", thumb: "cat2_thumb.jpg", fullsize: nil, preview: nil, width: 100, height: 100, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, subtitles: nil, favorited: nil)
            ]
            self.username = "Daranto"
            
            authService.isLoggedIn = true
            authService.currentUser = UserInfo(id:1, name: username, registered: 1, score: 1, mark:1, badges: [])
        }

        var body: some View {
            NavigationStack {
                CollectionItemsView(collection: sampleCollection, username: username, initialItemsForPreview: sampleItems)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
        }
    }
    return Previewer()
}

#Preview("Empty Collection - No Filter Active") {
    struct Previewer: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService
        let emptyCollection: ApiCollection
        let username: String

        init() {
            let tempSettings = AppSettings()
            tempSettings.showSFW = false
            tempSettings.showNSFW = false
            tempSettings.showNSFL = false
            tempSettings.showNSFP = false
            tempSettings.showPOL = false

            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: AuthService(appSettings: tempSettings))
            
            self.emptyCollection = ApiCollection(id: 103, name: "Leere Sammlung", keyword: "empty", isPublic: 0, isDefault: 0, itemCount: 10)
            self.username = "Daranto"

            authService.isLoggedIn = true
            authService.currentUser = UserInfo(id:1, name: username, registered: 1, score: 1, mark:1, badges: [])
        }
        
        var body: some View {
            NavigationStack {
                CollectionItemsView(collection: emptyCollection, username: username, initialItemsForPreview: [])
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
        }
    }
    return Previewer()
}
// --- END OF COMPLETE FILE ---

