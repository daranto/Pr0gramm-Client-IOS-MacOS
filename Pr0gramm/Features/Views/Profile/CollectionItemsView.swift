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

    @State private var navigationPath = NavigationPath()
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var showingFilterSheet = false

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
        return "collection_\(username.lowercased())_\(safeKeyword)_flags_\(settings.apiFlags)_items"
    }

    var body: some View {
        Group { collectionContentView }
        .navigationTitle(collection.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            FilterView(hideFeedOptions: true)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .navigationDestination(for: Item.self) { destinationItem in
            detailView(for: destinationItem)
        }
        .task {
            playerManager.configure(settings: settings)
            if items.isEmpty { // Load only if items are not pre-populated (e.g., by preview)
                await refreshItems()
            }
        }
        .onChange(of: settings.apiFlags) { _, _ in Task { await refreshItems() } } // Simplified from individual filter changes
        .onChange(of: settings.seenItemIDs) { _, _ in CollectionItemsView.logger.trace("CollectionItemsView detected change in seenItemIDs.") }
    }

    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            PagedDetailView(
                items: $items,
                selectedIndex: index,
                playerManager: playerManager,
                loadMoreAction: { Task { await loadMoreItems() } } // Pass the correct load more action
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in der Sammlung gefunden.")
                .onAppear {
                    CollectionItemsView.logger.warning("Navigation destination item \(destinationItem.id) not found in current collection items list.")
                }
        }
    }

    @ViewBuilder
    private var collectionContentView: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Lade Items der Sammlung...")
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty {
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
            } else if showNoFilterMessage {
                 noFilterContentView
            } else if items.isEmpty && !isLoading && errorMessage == nil {
                Text("Diese Sammlung enthält keine Items, die deinen aktuellen Filtern entsprechen.")
                    .font(UIConstants.bodyFont)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollViewContent
            }
        }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                 ForEach(items) { item in
                     NavigationLink(value: item) {
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

    // MARK: - Data Loading Methods
    @MainActor
    func refreshItems() async {
        CollectionItemsView.logger.info("Refreshing items for collection: '\(collection.name)' (Keyword: \(collection.keyword ?? "N/A")) by user: \(username)")
        let cacheKey = collectionItemsCacheKey

        self.isLoading = true
        self.errorMessage = nil
        self.showNoFilterMessage = false
        defer { Task { @MainActor in self.isLoading = false; CollectionItemsView.logger.info("Finished item refresh process for collection '\(collection.name)'.") } }

        guard settings.hasActiveContentFilter else {
            CollectionItemsView.logger.warning("Refresh items for collection '\(collection.name)' blocked: No active content filter selected.")
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
                 CollectionItemsView.logger.info("Found \(cached.count) items in cache for collection '\(collection.name)' with current filters.");
                 self.items = cached
            } else {
                 CollectionItemsView.logger.info("No usable data cache found for collection '\(collection.name)' with current filters.")
            }
        }
        let oldFirstItemId = items.first?.id

        CollectionItemsView.logger.info("Performing API fetch for collection items refresh (Collection Keyword: '\(collectionNameForAPI)', User: \(username), Flags: \(settings.apiFlags))...");
        do {
            let isOwn = authService.currentUser?.name.lowercased() == username.lowercased() && authService.isLoggedIn
            // --- MODIFIED: Use apiResponse ---
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                user: username,
                collectionNameForUser: collectionNameForAPI,
                isOwnCollection: isOwn
            )
            let fetchedItemsFromAPI = apiResponse.items
            // --- END MODIFICATION ---
            CollectionItemsView.logger.info("API fetch for collection '\(collection.name)' completed: \(fetchedItemsFromAPI.count) items.")
            guard !Task.isCancelled else { return }

            self.items = fetchedItemsFromAPI
            if fetchedItemsFromAPI.isEmpty && settings.hasActiveContentFilter {
                self.showNoFilterMessage = true
                CollectionItemsView.logger.info("API returned no items for collection '\(collection.name)' with active filters. Setting showNoFilterMessage.")
            } else {
                self.showNoFilterMessage = false
            }
            // --- MODIFIED: Use apiResponse.atEnd or hasOlder ---
            self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
            // --- END MODIFICATION ---
            CollectionItemsView.logger.info("CollectionItemsView updated with \(fetchedItemsFromAPI.count) items from API for collection '\(collection.name)'. Can load more: \(self.canLoadMore)")

            let newFirstItemId = fetchedItemsFromAPI.first?.id
            if !navigationPath.isEmpty && (initialItemsFromCache == nil || initialItemsFromCache?.count != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId) {
                navigationPath = NavigationPath()
                CollectionItemsView.logger.info("Popped navigation due to collection items refresh resulting in different list content.")
            }
            // --- MODIFIED: Pass fetchedItemsFromAPI to save ---
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            // --- END MODIFICATION ---
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            CollectionItemsView.logger.error("API fetch for collection items failed: Authentication required (Collection: '\(collection.name)').");
            self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false
            await settings.saveItemsToCache([], forKey: cacheKey)
            await authService.logout()
        }
        catch is CancellationError { CollectionItemsView.logger.info("Collection items API call cancelled.") }
        catch {
            CollectionItemsView.logger.error("API fetch for collection items failed (Collection: '\(collection.name)'): \(error.localizedDescription)");
            if self.items.isEmpty { self.errorMessage = "Fehler beim Laden der Sammlung: \(error.localizedDescription)" }
            else { CollectionItemsView.logger.warning("Showing potentially stale cached collection items data for '\(collection.name)'.") }
            self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreItems() async {
        guard settings.hasActiveContentFilter else {
            CollectionItemsView.logger.warning("Skipping loadMoreItems for collection '\(collection.name)': No active content filter selected.")
            self.canLoadMore = false; return
        }
        guard !isLoadingMore && canLoadMore && !isLoading else {
            CollectionItemsView.logger.debug("Skipping loadMoreItems for collection '\(collection.name)': State prevents loading.")
            return
        }
        guard let lastItemId = items.last?.id else { // Use item ID for pagination for collections
            CollectionItemsView.logger.warning("Skipping loadMoreItems for collection '\(collection.name)': No last item found.")
            return
        }
        guard let collectionNameForAPI = collection.keyword else {
            CollectionItemsView.logger.error("Cannot load more items: Collection keyword is nil for collection ID \(collection.id).")
            self.canLoadMore = false; return
        }

        let cacheKey = collectionItemsCacheKey
        CollectionItemsView.logger.info("--- Starting loadMoreItems for collection '\(collection.name)' by \(username) older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; CollectionItemsView.logger.info("--- Finished loadMoreItems for collection '\(collection.name)' ---") } } }

        do {
            let isOwn = authService.currentUser?.name.lowercased() == username.lowercased() && authService.isLoggedIn
            // --- MODIFIED: Use apiResponse ---
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                user: username,
                olderThanId: lastItemId,
                collectionNameForUser: collectionNameForAPI,
                isOwnCollection: isOwn
            )
            let newItems = apiResponse.items
            // --- END MODIFICATION ---
            CollectionItemsView.logger.info("Loaded \(newItems.count) more items from API for collection '\(collection.name)'.");
            var appendedItemCount = 0
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { return }

            if newItems.isEmpty {
                CollectionItemsView.logger.info("Reached end of item feed for collection '\(collection.name)'.")
                // --- MODIFIED: Use apiResponse.atEnd or hasOlder ---
                self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                if self.canLoadMore { CollectionItemsView.logger.warning("API returned empty but atEnd/hasOlder suggests more. API inconsistency?")}
                // --- END MODIFICATION ---
            } else {
                let currentIDs = Set(self.items.map { $0.id })
                // --- MODIFIED: Filter newItems ---
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                // --- END MODIFICATION ---
                if uniqueNewItems.isEmpty {
                    CollectionItemsView.logger.warning("All loaded items for collection '\(collection.name)' (older than \(lastItemId)) were duplicates.")
                    // --- MODIFIED: Use apiResponse.atEnd or hasOlder ---
                    self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                    // --- END MODIFICATION ---
                } else {
                    self.items.append(contentsOf: uniqueNewItems)
                    appendedItemCount = uniqueNewItems.count
                    CollectionItemsView.logger.info("Appended \(uniqueNewItems.count) unique items to collection '\(collection.name)'. Total items: \(self.items.count)")
                    // --- MODIFIED: Use apiResponse.atEnd or hasOlder ---
                    self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                    // --- END MODIFICATION ---
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = self.items
                // --- MODIFIED: Pass itemsToSave ---
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                // --- END MODIFICATION ---
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            CollectionItemsView.logger.error("API fetch for more collection items failed: Authentication required (Collection: '\(collection.name)').");
            self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { CollectionItemsView.logger.info("Load more collection items API call cancelled.") }
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
