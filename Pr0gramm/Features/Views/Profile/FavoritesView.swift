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
    @EnvironmentObject var navigationService: NavigationService
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false
    @State private var showNoCollectionSelectedMessage = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false
    
    @State private var isReturningFromFullscreen = false

    @StateObject private var playerManager = VideoPlayerManager()
    
    @State private var needsDataRefresh = true

    // --- NEW: State für Suche ---
    @State private var searchText = ""
    @State private var currentSearchTagForAPI: String? = nil // Für API-Calls und Cache-Key
    @State private var searchDebounceTimer: Timer? = nil
    private let searchDebounceInterval: TimeInterval = 0.75 // Sekunden
    @State private var hasAttemptedSearchSinceAppear = false // Trackt, ob eine Suche (auch erfolglos) gemacht wurde
    // --- END NEW ---


    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact

            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)

            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
        }

    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased(),
              let collectionId = settings.selectedCollectionIdForFavorites else { return nil }
        let selectedCollectionCache = authService.userCollections.first { $0.id == collectionId } // Umbenannt, um Konflikt zu vermeiden
        
        var baseKeyPart: String
        if let keyword = selectedCollectionCache?.keyword {
            baseKeyPart = "favorites_\(username)_collection_\(keyword.replacingOccurrences(of: " ", with: "_"))"
        } else {
            FavoritesView.logger.warning("Could not find keyword for selected favorite collection ID \(collectionId). Using ID in cache key.")
            baseKeyPart = "favorites_\(username)_collectionID_\(collectionId)"
        }
        
        var key = "\(baseKeyPart)_flags_\(apiFlagsForFavorites)"
        
        if let searchTerm = currentSearchTagForAPI, !searchTerm.isEmpty {
            let safeSearchTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? searchTerm
            key += "_search_\(safeSearchTerm)"
        }
        return key
    }

    private var apiFlagsForFavorites: Int {
        let loggedIn = authService.isLoggedIn
        if !loggedIn { return 1 }

        var flags = 0
        if settings.showSFW { flags |= 1; flags |= 8 }
        if settings.showNSFW { flags |= 2 }
        if settings.showNSFL { flags |= 4 }
        if settings.showPOL { flags |= 16 }
        return flags == 0 ? 1 : flags
    }

    private func tabDisplayName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "Feed"
        case .favorites: return "Favorites"
        case .search: return "Search"
        case .inbox: return "Inbox"
        case .profile: return "Profile"
        case .settings: return "Settings"
        case .calendar: return "Calendar"
            
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            favoritesContentView
                .navigationDestination(for: Item.self) { destinationItem in
                    if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                        PagedDetailView(
                            items: $items,
                            selectedIndex: index,
                            playerManager: playerManager,
                            loadMoreAction: { Task { await loadMoreFavorites() } }
                        )
                    } else {
                        Text("Fehler: Item nicht in Favoriten gefunden.")
                             .onAppear { FavoritesView.logger.warning("Navigation destination item \(destinationItem.id) not found.") }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingFilterSheet = true } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                 .navigationTitle("Favoriten")
                 #if os(iOS)
                 .navigationBarTitleDisplayMode(.inline)
                 #endif
                 .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Favoriten nach Tags filtern")
                .onSubmit(of: .search) {
                    FavoritesView.logger.info("Search submitted with: \(searchText)")
                    searchDebounceTimer?.invalidate()
                    Task {
                        await performSearchLogic(isInitialSearch: true)
                    }
                }
                .onChange(of: searchText) { oldValue, newValue in
                    FavoritesView.logger.info("Search text changed from '\(oldValue)' to '\(newValue)'")
                    searchDebounceTimer?.invalidate()

                    let trimmedNewValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let previousAPITag = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if trimmedNewValue.isEmpty && !previousAPITag.isEmpty {
                        FavoritesView.logger.info("Search text cleared, loading unfiltered favorites.")
                        Task {
                            await performSearchLogic(isInitialSearch: true)
                        }
                    } else if !trimmedNewValue.isEmpty && trimmedNewValue.count >= 2 {
                        FavoritesView.logger.info("Starting debounce timer for search: '\(trimmedNewValue)'")
                        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: searchDebounceInterval, repeats: false) { _ in
                            FavoritesView.logger.info("Debounce timer fired for search: '\(trimmedNewValue)'")
                            Task {
                                await performSearchLogic(isInitialSearch: true)
                            }
                        }
                    } else if trimmedNewValue.isEmpty && previousAPITag.isEmpty && !items.isEmpty && hasAttemptedSearchSinceAppear {
                         FavoritesView.logger.info("Search text empty, no previous API tag, items exist. No API call needed.")
                    } else if trimmedNewValue.isEmpty && items.isEmpty && hasAttemptedSearchSinceAppear {
                        FavoritesView.logger.info("Search text empty, items empty, but a search was attempted. Showing appropriate message.")
                    }
                }
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .onAppear {
            playerManager.configure(settings: settings)
            FavoritesView.logger.info("FavoritesView onAppear. Current tab: \(tabDisplayName(for: navigationService.selectedTab)). needsDataRefresh: \(needsDataRefresh)")
            hasAttemptedSearchSinceAppear = false
            if navigationService.selectedTab == .favorites && needsDataRefresh {
                Task {
                    FavoritesView.logger.info("FavoritesView onAppear: Triggering initial data load because tab is active and needs refresh.")
                    await performActualDataRefresh()
                    needsDataRefresh = false
                }
            }
        }
        .task(id: navigationService.selectedTab) {
            await handleTabChange(newTab: navigationService.selectedTab)
        }
        .task(id: authService.isLoggedIn) {
             await handleLoginStatusChange()
        }
        .task(id: settings.selectedCollectionIdForFavorites) {
            await handleCollectionChange()
        }
        .onChange(of: settings.showSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFL) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showPOL) { _, _ in handleApiFlagsChange() }
    }
    
    @MainActor
    private func performSearchLogic(isInitialSearch: Bool) async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSearchText.isEmpty && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
            if !hasAttemptedSearchSinceAppear { hasAttemptedSearchSinceAppear = true }
            if showNoCollectionSelectedMessage || showNoFilterMessage {
                FavoritesView.logger.info("performSearchLogic: Search text empty, no previous tag, but a message is already shown. Skipping API call.")
                return
            }
            if items.isEmpty {
                if currentSearchTagForAPI != nil {
                    currentSearchTagForAPI = nil
                    needsDataRefresh = true
                    await performActualDataRefresh()
                    needsDataRefresh = false
                }
            }
            FavoritesView.logger.info("performSearchLogic: Search text empty and no previous API tag. No API call needed.")
            return
        }
        
        currentSearchTagForAPI = trimmedSearchText.isEmpty ? nil : trimmedSearchText
        
        FavoritesView.logger.info("performSearchLogic: isInitial=\(isInitialSearch). API Tag: '\(currentSearchTagForAPI ?? "nil")'")
        needsDataRefresh = true
        await performActualDataRefresh()
        needsDataRefresh = false
        hasAttemptedSearchSinceAppear = true
    }

    private func handleTabChange(newTab: Tab) async {
        FavoritesView.logger.info("FavoritesView: selectedTab changed to \(tabDisplayName(for: newTab)).")
        if newTab == .favorites {
            if needsDataRefresh {
                FavoritesView.logger.info("Tab changed to Favorites and refresh needed. Calling performActualDataRefresh.")
                await performActualDataRefresh()
                needsDataRefresh = false
            } else {
                FavoritesView.logger.info("Tab changed to Favorites, but no refresh needed currently.")
            }
        } else {
            needsDataRefresh = true
            FavoritesView.logger.info("Tab changed away from Favorites. Setting needsDataRefresh to true.")
        }
    }

    private func handleLoginStatusChange() async {
        FavoritesView.logger.info("FavoritesView: isLoggedIn changed. Setting needsDataRefresh to true.")
        needsDataRefresh = true
        if navigationService.selectedTab == .favorites {
            FavoritesView.logger.info("Login status changed while Favorites tab is active. Calling performActualDataRefresh.")
            await performActualDataRefresh()
            needsDataRefresh = false
        }
    }

    private func handleCollectionChange() async {
        FavoritesView.logger.info("FavoritesView: selectedCollectionIdForFavorites changed. Setting needsDataRefresh to true.")
        needsDataRefresh = true
        // --- MODIFIED: Suche zurücksetzen, wenn Sammlung wechselt ---
        currentSearchTagForAPI = nil
        searchText = ""
        // --- END MODIFICATION ---
        if navigationService.selectedTab == .favorites {
            FavoritesView.logger.info("Collection ID changed while Favorites tab is active. Calling performActualDataRefresh.")
            await performActualDataRefresh()
            needsDataRefresh = false
        }
    }
    
    private func handleApiFlagsChange() {
        FavoritesView.logger.info("FavoritesView: Relevant global filter flag changed. Setting needsDataRefresh to true.")
        needsDataRefresh = true
        if navigationService.selectedTab == .favorites {
            FavoritesView.logger.info("A global filter flag changed while Favorites tab is active. Calling performActualDataRefresh.")
            Task {
                await performActualDataRefresh()
                needsDataRefresh = false
            }
        }
    }


    @ViewBuilder
    private var favoritesContentView: some View {
        Group {
            if authService.isLoggedIn {
                if showNoCollectionSelectedMessage {
                    noCollectionSelectedContentView
                } else if showNoFilterMessage {
                    noFilterContentView
                } else if items.isEmpty && hasAttemptedSearchSinceAppear && !(currentSearchTagForAPI?.isEmpty ?? true) && !isLoading {
                    ContentUnavailableView {
                        Label("Keine Ergebnisse", systemImage: "magnifyingglass")
                    } description: {
                        // --- MODIFIED: Verwende currentSearchTagForAPI für die Meldung ---
                        Text("Keine Favoriten für den Tag '\(currentSearchTagForAPI!)' gefunden (oder sie passen nicht zu deinen globalen Filtern).")
                        // --- END MODIFICATION ---
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading && items.isEmpty && needsDataRefresh {
                    ProgressView("Lade Favoriten...").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage && !showNoCollectionSelectedMessage {
                    Text("Du hast noch keine Favoriten in dieser Sammlung (oder sie passen nicht zum Filter).")
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
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                             Task {
                                 try? await Task.sleep(for: .milliseconds(150))
                                 guard !isLoadingMore && canLoadMore && !isLoading else { return }
                                 FavoritesView.logger.info("Favorites: End trigger appeared (after delay).")
                                 await loadMoreFavorites()
                             }
                         }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
            }
            .padding(.horizontal, 5)
            .padding(.bottom)
        }
        .refreshable {
            needsDataRefresh = true
            await performActualDataRefresh()
            needsDataRefresh = false
        }
    }

    private var noFilterContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
            Text("Keine Favoriten für Filter").font(UIConstants.headlineFont)
            Text("Bitte passe deine Filter an, um deine Favoriten zu sehen.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Filter anpassen") { showingFilterSheet = true }
                .buttonStyle(.bordered).padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            needsDataRefresh = true
            await performActualDataRefresh()
            needsDataRefresh = false
        }
    }
    
    private var noCollectionSelectedContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash.fill")
                .font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
            Text("Kein Favoriten-Ordner ausgewählt").font(UIConstants.headlineFont)
            Text("Bitte wähle in den Einstellungen einen Ordner aus, der als Standard für deine Favoriten verwendet werden soll.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Zu den Einstellungen") {
                FavoritesView.logger.info("User tapped 'Zu den Einstellungen'. Navigating to Settings tab.")
                navigationService.selectedTab = .settings
            }
            .buttonStyle(.bordered).padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            needsDataRefresh = true
            await performActualDataRefresh()
            needsDataRefresh = false
        }
    }

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

    private func performActualDataRefresh() async {
        FavoritesView.logger.info("performActualDataRefresh called. isLoading: \(isLoading)")
        guard !isLoading else {
            FavoritesView.logger.info("performActualDataRefresh skipped: isLoading is true.")
            return
        }
        
        if authService.isLoggedIn {
            if settings.selectedCollectionIdForFavorites != nil {
                self.showNoCollectionSelectedMessage = false
                await refreshFavorites()
            } else {
                FavoritesView.logger.warning("Cannot refresh favorites: No collection selected in AppSettings.")
                await MainActor.run {
                    self.items = []
                    self.errorMessage = nil
                    self.isLoading = false
                    self.canLoadMore = false
                    self.isLoadingMore = false
                    self.showNoFilterMessage = false
                    self.showNoCollectionSelectedMessage = true
                }
            }
        } else {
            await MainActor.run {
                items = []
                errorMessage = nil
                isLoading = false
                canLoadMore = true
                isLoadingMore = false
                showNoFilterMessage = false
                showNoCollectionSelectedMessage = false
                currentSearchTagForAPI = nil
                searchText = ""
            }
            FavoritesView.logger.info("User logged out, cleared favorites list and search.")
        }
    }

    @MainActor
    func refreshFavorites() async {
        FavoritesView.logger.info("Refreshing favorites...")
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            FavoritesView.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            self.errorMessage = "Bitte anmelden."; self.items = []; self.showNoFilterMessage = false; self.showNoCollectionSelectedMessage = false
            return
        }
        guard let selectedCollectionID = settings.selectedCollectionIdForFavorites,
              let selectedCollectionInstance = authService.userCollections.first(where: { $0.id == selectedCollectionID }), // Umbenannt um Namenskonflikt zu vermeiden
              let collectionKeyword = selectedCollectionInstance.keyword else {
            FavoritesView.logger.warning("Cannot refresh favorites: No collection selected in AppSettings or keyword missing for ID \(settings.selectedCollectionIdForFavorites ?? -1).")
            self.items = []; self.errorMessage = nil; self.isLoading = false; self.canLoadMore = false; self.isLoadingMore = false; self.showNoFilterMessage = false; self.showNoCollectionSelectedMessage = true
            return
        }
        self.showNoCollectionSelectedMessage = false

        let currentApiFlags = apiFlagsForFavorites
        
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentApiFlags == 0 && (effectiveSearchTerm == nil || effectiveSearchTerm!.isEmpty) {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter selected and no search term provided.")
            self.items = []; self.showNoFilterMessage = true; self.canLoadMore = false; self.isLoadingMore = false; self.errorMessage = nil
            return
        }
        
        guard let cacheKey = favoritesCacheKey else {
            FavoritesView.logger.error("Cannot refresh favorites: Cache key error."); self.errorMessage = "Interner Fehler (Cache Key)."
            return
        }
        self.showNoFilterMessage = false; self.isLoading = true; self.errorMessage = nil
        
        defer {
            Task { @MainActor in
                self.isLoading = false
                FavoritesView.logger.info("Finished favorites refresh process.")
            }
        }
        canLoadMore = true; isLoadingMore = false;

        if items.isEmpty {
             if let cached = await settings.loadItemsFromCache(forKey: cacheKey), !cached.isEmpty {
                 self.items = cached.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
                 FavoritesView.logger.info("Found \(self.items.count) favorite items in cache initially for collection '\(collectionKeyword)', search: '\(currentSearchTagForAPI ?? "nil")'.")
             }
             else { FavoritesView.logger.info("No usable cache for favorites in collection '\(collectionKeyword)', search: '\(currentSearchTagForAPI ?? "nil")'.") }
        }
        
        let oldFirstItemId = items.first?.id
        FavoritesView.logger.info("Performing API fetch for favorites refresh (Collection: '\(collectionKeyword)', User: \(username), Flags: \(currentApiFlags), Tags: '\(currentSearchTagForAPI ?? "nil")')...");
        
        do {
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: currentApiFlags,
                tags: currentSearchTagForAPI
            )
            let fetchedItemsFromAPI = apiResponse.items
            // --- MODIFIED: Korrekter Variablenname für Log ---
            FavoritesView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh favorites for collection '\(collectionKeyword)', search: '\(currentSearchTagForAPI ?? "nil")'.");
            // --- END MODIFICATION ---
            guard !Task.isCancelled else { FavoritesView.logger.info("Refresh task cancelled."); return }

            let contentChanged = items.map { $0.id }.elementsEqual(fetchedItemsFromAPI.map { $0.id }) == false

            self.items = fetchedItemsFromAPI.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
            
            // --- MODIFIED: Korrekter Variablenname für Log ---
            if fetchedItemsFromAPI.isEmpty && currentApiFlags != 0 && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
                 self.showNoFilterMessage = true
                 FavoritesView.logger.info("API returned no items for collection '\(collectionKeyword)' with active global filters (no search term). Setting showNoFilterMessage.")
            } else if fetchedItemsFromAPI.isEmpty && !(currentSearchTagForAPI?.isEmpty ?? true) {
                 FavoritesView.logger.info("API returned no items for collection '\(collectionKeyword)' with search term '\(currentSearchTagForAPI!)'.")
            } else {
                 self.showNoFilterMessage = false
            }
            // --- END MODIFICATION ---
            
            if fetchedItemsFromAPI.isEmpty {
                self.canLoadMore = false
                FavoritesView.logger.info("Refresh returned 0 items. Setting canLoadMore to false.")
            } else {
                let atEnd = apiResponse.atEnd ?? false
                let hasOlder = apiResponse.hasOlder ?? true
                if atEnd || !hasOlder {
                    self.canLoadMore = false
                    FavoritesView.logger.info("API indicates end of feed. Setting canLoadMore to false.")
                } else {
                    self.canLoadMore = true
                    FavoritesView.logger.info("API indicates more items might be available. Setting canLoadMore to true.")
                }
            }
            FavoritesView.logger.info("FavoritesView updated. Total: \(self.items.count). Can load more: \(self.canLoadMore)");

            authService.favoritedItemIDs = Set(self.items.map { $0.id })
            FavoritesView.logger.info("Updated global favorite ID set in AuthService (\(authService.favoritedItemIDs.count) IDs).")

            if !navigationPath.isEmpty && contentChanged {
                navigationPath = NavigationPath()
                FavoritesView.logger.info("Popped navigation due to content change from refresh.")
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required."); self.items = []; self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false; await settings.saveItemsToCache([], forKey: cacheKey); await authService.logout()
        }
        catch is CancellationError { FavoritesView.logger.info("API call cancelled.") }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)"); if self.items.isEmpty { self.errorMessage = "Fehler: \(error.localizedDescription)" } else { FavoritesView.logger.warning("Showing potentially stale cached data.") }; self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreFavorites() async {
        let currentApiFlags = apiFlagsForFavorites
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentApiFlags == 0 && (effectiveSearchTerm == nil || effectiveSearchTerm!.isEmpty) {
            FavoritesView.logger.warning("Skipping loadMore: No active filter and no search term.")
            self.canLoadMore = false; return
        }
        
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { return }
        guard let selectedCollectionID = settings.selectedCollectionIdForFavorites,
              let selectedCollectionInstance = authService.userCollections.first(where: { $0.id == selectedCollectionID }), // Umbenannt
              let collectionKeyword = selectedCollectionInstance.keyword else {
            FavoritesView.logger.warning("Cannot load more favorites: No collection selected or keyword missing.")
            self.canLoadMore = false
            return
        }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let lastItemId = items.last?.id else { return }
        guard let cacheKey = favoritesCacheKey else { return }
        FavoritesView.logger.info("--- Starting loadMoreFavorites for collection '\(collectionKeyword)', search '\(currentSearchTagForAPI ?? "nil")' older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FavoritesView.logger.info("--- Finished loadMoreFavorites for collection '\(collectionKeyword)' ---") } } }
        do {
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: currentApiFlags,
                olderThanId: lastItemId,
                tags: currentSearchTagForAPI
            )
            let newItems = apiResponse.items
            FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API.");
            var appendedItemCount = 0;
            guard !Task.isCancelled else { FavoritesView.logger.info("Load more cancelled."); return }
            guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update."); return };

            if newItems.isEmpty {
                FavoritesView.logger.info("Reached end of favorites feed.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.items.map { $0.id });
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                if uniqueNewItems.isEmpty {
                    FavoritesView.logger.warning("All loaded items were duplicates. Assuming end of actual new content.")
                    self.canLoadMore = false
                } else {
                    let markedNewItems = uniqueNewItems.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
                    self.items.append(contentsOf: markedNewItems)
                    appendedItemCount = uniqueNewItems.count
                    FavoritesView.logger.info("Appended \(uniqueNewItems.count) unique items. Total: \(self.items.count)")
                    
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    if atEnd || !hasOlder {
                        self.canLoadMore = false
                        FavoritesView.logger.info("API indicates end of feed after loadMore.")
                    } else {
                        self.canLoadMore = true
                        FavoritesView.logger.info("API indicates more items might be available after loadMore.")
                    }
                    authService.favoritedItemIDs.formUnion(uniqueNewItems.map { $0.id })
                    FavoritesView.logger.info("Added \(uniqueNewItems.count) IDs to global favorite set.")
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = self.items.map { var mutableItem = $0; mutableItem.favorited = nil; return mutableItem }
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required."); self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false; await authService.logout()
        }
        catch is CancellationError { FavoritesView.logger.info("Load more cancelled.") }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)"); guard !Task.isCancelled else { return }; guard self.isLoadingMore else { return }; if items.isEmpty { errorMessage = "Fehler: \(error.localizedDescription)" }; self.canLoadMore = false
        }
    }
}

// Previews
#Preview("Logged In - Collection Selected") {
    let previewSettings = AppSettings()
    previewSettings.selectedCollectionIdForFavorites = 101
    let previewAuthService = AuthService(appSettings: previewSettings)
    let previewNavigationService = NavigationService()
    previewAuthService.isLoggedIn = true
    let sampleCollections = [
        ApiCollection(id: 101, name: "Meine Favoriten", keyword: "favoriten", isPublic: 0, isDefault: 1, itemCount: 123),
        ApiCollection(id: 102, name: "Lustige Katzen", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45)
    ]
    previewAuthService.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2, badges: [], collections: sampleCollections)
    #if DEBUG
    previewAuthService.setUserCollectionsForPreview(sampleCollections)
    #endif
    previewAuthService.favoritedItemIDs = [2, 4]

    return FavoritesView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
        .environmentObject(previewNavigationService)
}

#Preview("Logged In - No Collection Selected") {
    let previewSettings = AppSettings()
    previewSettings.selectedCollectionIdForFavorites = nil
    let previewAuthService = AuthService(appSettings: previewSettings)
    let previewNavigationService = NavigationService()
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2, badges: [])
    #if DEBUG
    previewAuthService.setUserCollectionsForPreview([])
    #endif

    return FavoritesView()
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
        .environmentObject(previewNavigationService)
}

#Preview("Logged Out") {
    FavoritesView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
        .environmentObject(NavigationService())
}
// --- END OF COMPLETE FILE ---
