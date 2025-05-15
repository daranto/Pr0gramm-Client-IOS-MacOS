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

    @State private var needsRefreshForTabChange = false
    @State private var needsRefreshForLoginChange = false
    @State private var needsRefreshForCollectionChange = false
    @State private var needsRefreshForFilterChange = false
    
    @State private var didPerformInitialLoadForCurrentContext = false


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
        let selectedCollection = authService.userCollections.first { $0.id == collectionId }
        guard let keyword = selectedCollection?.keyword else {
            FavoritesView.logger.warning("Could not find keyword for selected favorite collection ID \(collectionId). Using ID in cache key.")
            return "favorites_\(username)_collectionID_\(collectionId)"
        }
        return "favorites_\(username)_collection_\(keyword.replacingOccurrences(of: " ", with: "_"))"
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
                        .onDisappear {
                            if isReturningFromFullscreen {
                                isReturningFromFullscreen = false
                            }
                        }
                        .onAppear {
                            isReturningFromFullscreen = false
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            isReturningFromFullscreen = true
                            FavoritesView.logger.info("Detected return from fullscreen, preventing navigation reset")
                        }
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
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView().environmentObject(settings).environmentObject(authService)
        }
        .onAppear {
            playerManager.configure(settings: settings)
        }
        .task(id: triggerKey) {
            FavoritesView.logger.info("Main task running. Trigger Key: \(triggerKey). didPerformInitialLoad: \(didPerformInitialLoadForCurrentContext)")
            await loadDataIfNeeded()
        }
        .onChange(of: navigationService.selectedTab) { oldValue, newTab in
            if newTab == .favorites && oldValue != .favorites {
                FavoritesView.logger.info("FavoritesView: Tab switched to favorites.")
                needsRefreshForTabChange = true
                didPerformInitialLoadForCurrentContext = false
            } else if newTab != .favorites && oldValue == .favorites {
                FavoritesView.logger.info("FavoritesView: Tab changed away from favorites.")
                didPerformInitialLoadForCurrentContext = false
            }
        }
        .onChange(of: authService.isLoggedIn) { _, _ in
            FavoritesView.logger.info("FavoritesView: Login status changed.")
            needsRefreshForLoginChange = true
            didPerformInitialLoadForCurrentContext = false
        }
        .onChange(of: settings.selectedCollectionIdForFavorites) { _, _ in
            FavoritesView.logger.info("FavoritesView: Selected collection ID changed.")
            needsRefreshForCollectionChange = true
            didPerformInitialLoadForCurrentContext = false
        }
        .onChange(of: settings.apiFlags) { _, _ in
            FavoritesView.logger.info("FavoritesView: API flags changed.")
            needsRefreshForFilterChange = true
            didPerformInitialLoadForCurrentContext = false
        }
        .onChange(of: settings.seenItemIDs) { _, _ in FavoritesView.logger.trace("SeenItemIDs changed.") }
    }

    private var triggerKey: String {
        let tabActive = navigationService.selectedTab == .favorites
        let loginStatus = authService.isLoggedIn
        let collectionId = settings.selectedCollectionIdForFavorites ?? -1
        let flags = settings.apiFlags
        
        return "\(tabActive)-\(loginStatus)-\(collectionId)-\(flags)-\(needsRefreshForTabChange)-\(needsRefreshForLoginChange)-\(needsRefreshForCollectionChange)-\(needsRefreshForFilterChange)"
    }
    
    private func loadDataIfNeeded() async {
        guard navigationService.selectedTab == .favorites else {
            FavoritesView.logger.info("loadDataIfNeeded: Skipped, Favorites tab not active.")
            if didPerformInitialLoadForCurrentContext {
                didPerformInitialLoadForCurrentContext = false
            }
            return
        }

        if !didPerformInitialLoadForCurrentContext || needsRefreshForTabChange || needsRefreshForLoginChange || needsRefreshForCollectionChange || needsRefreshForFilterChange {
            FavoritesView.logger.info("loadDataIfNeeded: Proceeding with data refresh. Initial: \(!didPerformInitialLoadForCurrentContext), TabChange: \(needsRefreshForTabChange), LoginChange: \(needsRefreshForLoginChange), CollectionChange: \(needsRefreshForCollectionChange), FilterChange: \(needsRefreshForFilterChange)")
            
            needsRefreshForTabChange = false
            needsRefreshForLoginChange = false
            needsRefreshForCollectionChange = false
            needsRefreshForFilterChange = false

            await performActualDataRefresh()
            didPerformInitialLoadForCurrentContext = true
        } else {
            FavoritesView.logger.info("loadDataIfNeeded: Skipped refresh, no relevant changes or already loaded for current context.")
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
                } else if isLoading && items.isEmpty && !didPerformInitialLoadForCurrentContext {
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
            didPerformInitialLoadForCurrentContext = false
            await loadDataIfNeeded()
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
            didPerformInitialLoadForCurrentContext = false
            await loadDataIfNeeded()
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
            didPerformInitialLoadForCurrentContext = false
            await loadDataIfNeeded()
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
        
        guard navigationPath.isEmpty || isReturningFromFullscreen else {
            FavoritesView.logger.info("performActualDataRefresh skipped: User is in a detail view.")
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
            }
            FavoritesView.logger.info("User logged out, cleared favorites list.")
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
              let selectedCollection = authService.userCollections.first(where: { $0.id == selectedCollectionID }),
              let collectionKeyword = selectedCollection.keyword else {
            FavoritesView.logger.warning("Cannot refresh favorites: No collection selected in AppSettings or keyword missing for ID \(settings.selectedCollectionIdForFavorites ?? -1).")
            self.items = []; self.errorMessage = nil; self.isLoading = false; self.canLoadMore = false; self.isLoadingMore = false; self.showNoFilterMessage = false; self.showNoCollectionSelectedMessage = true
            return
        }
        self.showNoCollectionSelectedMessage = false

        guard settings.hasActiveContentFilter else {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter selected.")
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
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        if items.isEmpty && !didPerformInitialLoadForCurrentContext {
             initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
             if let cached = initialItemsFromCache, !cached.isEmpty {
                 self.items = cached.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
                 FavoritesView.logger.info("Found \(self.items.count) favorite items in cache initially for collection '\(collectionKeyword)'.")
             }
             else { FavoritesView.logger.info("No usable cache for favorites in collection '\(collectionKeyword)'.") }
        }
        let oldFirstItemId = items.first?.id

        FavoritesView.logger.info("Performing API fetch for favorites refresh (Collection Keyword: '\(collectionKeyword)', User: \(username), Flags: \(settings.apiFlags))...")
        do {
            // --- MODIFIED: Use apiResponse.items ---
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: settings.apiFlags
            )
            let fetchedItemsFromAPI = apiResponse.items
            // --- END MODIFICATION ---
            FavoritesView.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh favorites for collection '\(collectionKeyword)'.");
            guard !Task.isCancelled else { FavoritesView.logger.info("Refresh task cancelled."); return }

            let newFirstItemId = fetchedItemsFromAPI.first?.id
            let contentChanged = initialItemsFromCache == nil || (initialItemsFromCache != nil && (initialItemsFromCache?.count != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId))

            self.items = fetchedItemsFromAPI.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
            // --- MODIFIED: Use apiResponse.atEnd or apiResponse.hasOlder ---
            self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
            // --- END MODIFICATION ---
            FavoritesView.logger.info("FavoritesView updated. Total: \(self.items.count). Can load more: \(self.canLoadMore)");

            authService.favoritedItemIDs = Set(self.items.map { $0.id })
            FavoritesView.logger.info("Updated global favorite ID set in AuthService (\(authService.favoritedItemIDs.count) IDs) based on collection '\(collectionKeyword)'.")

            if !navigationPath.isEmpty && contentChanged && !isReturningFromFullscreen {
                navigationPath = NavigationPath()
                FavoritesView.logger.info("Popped navigation due to content change from refresh.")
            }
            // --- MODIFIED: Pass fetchedItemsFromAPI to saveItemsToCache ---
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            // --- END MODIFICATION ---
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
        guard settings.hasActiveContentFilter else { FavoritesView.logger.warning("Skipping loadMore: No active filter."); self.canLoadMore = false; return }
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { return }
        guard let selectedCollectionID = settings.selectedCollectionIdForFavorites,
              let selectedCollection = authService.userCollections.first(where: { $0.id == selectedCollectionID }),
              let collectionKeyword = selectedCollection.keyword else {
            FavoritesView.logger.warning("Cannot load more favorites: No collection selected or keyword missing.")
            self.canLoadMore = false
            return
        }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let lastItemId = items.last?.id else { return } // Paginierung für Favoriten erfolgt über die Item-ID, nicht über promotedId
        guard let cacheKey = favoritesCacheKey else { return }
        FavoritesView.logger.info("--- Starting loadMoreFavorites for collection '\(collectionKeyword)' older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; FavoritesView.logger.info("--- Finished loadMoreFavorites for collection '\(collectionKeyword)' ---") } } }
        do {
            // --- MODIFIED: Use apiResponse.items ---
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: settings.apiFlags,
                olderThanId: lastItemId
            )
            let newItems = apiResponse.items
            // --- END MODIFICATION ---
            FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API for collection '\(collectionKeyword)'.");
            var appendedItemCount = 0;
            guard !Task.isCancelled else { FavoritesView.logger.info("Load more cancelled."); return }
            guard self.isLoadingMore else { FavoritesView.logger.info("Load more cancelled before UI update."); return };

            if newItems.isEmpty {
                // --- MODIFIED: Use apiResponse.atEnd or apiResponse.hasOlder for canLoadMore ---
                self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                if self.canLoadMore {
                     FavoritesView.logger.warning("API returned empty list but atEnd/hasOlder suggests more items. This might be an API inconsistency.")
                } else {
                     FavoritesView.logger.info("Reached end of favorites feed for collection '\(collectionKeyword)'.")
                }
                // --- END MODIFICATION ---
            } else {
                let currentIDs = Set(self.items.map { $0.id });
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                if uniqueNewItems.isEmpty {
                    // --- MODIFIED: Check atEnd/hasOlder even if duplicates received ---
                    self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                    FavoritesView.logger.warning("All loaded items were duplicates. Can load more: \(self.canLoadMore)")
                    // --- END MODIFICATION ---
                } else {
                    let markedNewItems = uniqueNewItems.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
                    self.items.append(contentsOf: markedNewItems)
                    appendedItemCount = uniqueNewItems.count
                    FavoritesView.logger.info("Appended \(uniqueNewItems.count) unique items. Total: \(self.items.count)")
                    // --- MODIFIED: Use apiResponse.atEnd or apiResponse.hasOlder ---
                    self.canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                    // --- END MODIFICATION ---
                    authService.favoritedItemIDs.formUnion(uniqueNewItems.map { $0.id })
                    FavoritesView.logger.info("Added \(uniqueNewItems.count) IDs to global favorite set (\(authService.favoritedItemIDs.count) total) from collection '\(collectionKeyword)'.")
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = self.items.map { var mutableItem = $0; mutableItem.favorited = nil; return mutableItem }
                // --- MODIFIED: Pass itemsToSave to saveItemsToCache ---
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                // --- END MODIFICATION ---
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
