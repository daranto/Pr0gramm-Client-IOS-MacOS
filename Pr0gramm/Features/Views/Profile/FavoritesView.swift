import SwiftUI
import os
import Kingfisher

struct FavoritesItemThumbnail: View, Equatable {
    let item: Item
    let isSeen: Bool
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesItemThumbnail")

    static func == (lhs: FavoritesItemThumbnail, rhs: FavoritesItemThumbnail) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSeen == rhs.isSeen
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.thumbnailUrl)
                .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
                .onFailure { error in FavoritesItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") }
                .cancelOnDisappear(true)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .aspectRatio(1.0, contentMode: .fit)
                .background(Material.ultraThin)
                .cornerRadius(5)
                .clipped()
            
            if isSeen {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
                    .padding(4)
            }
        }
    }
}


struct FavoritesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService

    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    @StateObject private var playerManager = VideoPlayerManager()
    
    private let preloadRowsAhead: Int = 5

    @State private var searchText = ""
    @State private var currentSearchTagForAPI: String? = nil
    @State private var hasAttemptedSearchSinceAppear = false
    
    // Video player state management like SearchView
    @State private var wasPlayingBeforeTabSwitch = false
    @State private var playerStateBeforeModal: (itemID: Int, isPlaying: Bool)? = nil

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    private var gridColumns: [GridItem] {
        let isMac = ProcessInfo.processInfo.isiOSAppOnMac
        let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact
        let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
        let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)
        return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            favoritesContentView
                .safeAreaInset(edge: .bottom) {
                    // Create invisible spacer that matches tab bar height
                    Color.clear
                        .frame(height: calculateTabBarHeight())
                }
                .navigationDestination(for: Item.self) { destinationItem in
                    if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                        PagedDetailView(
                            items: $items,
                            selectedIndex: index,
                            playerManager: playerManager,
                            loadMoreAction: { Task { await loadMoreFavorites() } }
                        )
                        .environmentObject(settings)
                        .environmentObject(authService)
                    } else {
                        Text("Fehler: Item nicht in Favoriten gefunden.")
                            .onAppear { FavoritesView.logger.warning("Navigation destination item \(destinationItem.id) not found in favorites.") }
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
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Favoriten nach Tags filtern")
                .onChange(of: searchText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        currentSearchTagForAPI = nil
                        // Wenn leer, Favoriten ohne Filter laden (aber nur wenn wir bereits Items haben)
                        if !items.isEmpty {
                            Task { await performFavoritesLogic(isInitialLoad: true) }
                        }
                    }
                }
                .onSubmit(of: .search) {
                    FavoritesView.logger.info("Search submitted with: \(searchText)")
                    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    currentSearchTagForAPI = trimmed.isEmpty ? nil : trimmed
                    Task { await performFavoritesLogic(isInitialLoad: true) }
                }
                .sheet(isPresented: $showingFilterSheet) {
                    FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
                        .environmentObject(settings)
                        .environmentObject(authService)
                }
        }
        .onAppear {
            playerManager.configure(settings: settings)
            hasAttemptedSearchSinceAppear = false
            
            FavoritesView.logger.info("FavoritesView onAppear: VideoPlayerManager configured, current player: \(playerManager.player != nil ? "exists" : "nil")")
            
            // Check if we need to restore a player that was disrupted by a modal
            if navigationService.selectedTab == .favorites && playerManager.player == nil {
                // If we're in favorites but have no player, something might have disrupted it
                // This is a safety mechanism to ensure video playback can continue
                FavoritesView.logger.info("FavoritesView onAppear: No player found, reconfiguring VideoPlayerManager")
                playerManager.configure(settings: settings)
            }
            
            // Only load favorites if we have never loaded them before AND user is logged in
            if items.isEmpty && authService.isLoggedIn && settings.selectedCollectionIdForFavorites != nil {
                FavoritesView.logger.info("FavoritesView onAppear: Loading initial favorites because items are empty.")
                Task { await performFavoritesLogic(isInitialLoad: true) }
            } else {
                FavoritesView.logger.info("FavoritesView onAppear: Skipping load - items: \(items.count), loggedIn: \(authService.isLoggedIn), selectedCollection: \(settings.selectedCollectionIdForFavorites?.description ?? "nil")")
            }
        }
        .task(id: authService.isLoggedIn) {
            FavoritesView.logger.info("FavoritesView: .task(id: authService.isLoggedIn) triggered. isLoggedIn: \(authService.isLoggedIn)")
            // When user logs in, load favorites if items are empty
            if authService.isLoggedIn && items.isEmpty && settings.selectedCollectionIdForFavorites != nil {
                FavoritesView.logger.info("User is logged in and items are empty, loading initial favorites.")
                await performFavoritesLogic(isInitialLoad: true)
            } else if !authService.isLoggedIn {
                // User logged out, clear items
                FavoritesView.logger.info("User logged out, clearing favorites.")
                items = []
                errorMessage = nil
                canLoadMore = false
                isLoadingMore = false
                isLoading = false
                hasAttemptedSearchSinceAppear = false
                currentSearchTagForAPI = nil
                searchText = ""
            }
        }
        .task(id: authService.currentUser?.name) {
            FavoritesView.logger.info("FavoritesView: .task(id: currentUser.name) triggered. Username: \(authService.currentUser?.name ?? "nil")")
            // When currentUser is loaded and we're logged in but have no items, load favorites
            if authService.isLoggedIn && authService.currentUser?.name != nil && items.isEmpty && settings.selectedCollectionIdForFavorites != nil {
                FavoritesView.logger.info("User profile loaded and items are empty, loading initial favorites.")
                await performFavoritesLogic(isInitialLoad: true)
            }
        }
        .onChange(of: settings.showSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFL) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showPOL) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.selectedCollectionIdForFavorites) { oldValue, newValue in
            // Only reload if the collection actually changed and we have items loaded
            if oldValue != newValue && !items.isEmpty {
                FavoritesView.logger.info("Collection ID changed from \(oldValue ?? -1) to \(newValue ?? -1), reloading favorites.")
                Task { await performFavoritesLogic(isInitialLoad: true) }
            }
        }
        .task(id: navigationService.selectedTab) {
            let newTab = navigationService.selectedTab
            if newTab == .favorites {
                if wasPlayingBeforeTabSwitch {
                    // Small delay to ensure Favorites is fully active
                    try? await Task.sleep(for: .milliseconds(150))
                    if playerManager.player?.timeControlStatus != .playing {
                        playerManager.player?.play()
                        FavoritesView.logger.info("Resumed player after returning to Favorites tab.")
                    }
                    wasPlayingBeforeTabSwitch = false
                }
            } else {
                if let player = playerManager.player, player.timeControlStatus == .playing {
                    player.pause()
                    wasPlayingBeforeTabSwitch = true
                    FavoritesView.logger.info("Paused player because user switched away from Favorites tab.")
                } else {
                    // Keep previous intent to resume; do NOT reset the flag here when hopping between other tabs
                    FavoritesView.logger.debug("Favorites not active and player not playing; preserving wasPlayingBeforeTabSwitch=\(wasPlayingBeforeTabSwitch).")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // When app comes back from background, reconfigure the player manager
            // This helps with cases where modal views may have interfered with the player
            if navigationService.selectedTab == .favorites {
                FavoritesView.logger.info("App entering foreground, reconfiguring VideoPlayerManager for Favorites")
                playerManager.configure(settings: settings)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlayerPausedForSheet"))) { notification in
            // Save the current player state before a sheet opens
            if navigationService.selectedTab == .favorites,
               let player = playerManager.player,
               let itemID = playerManager.playerItemID {
                let isPlaying = player.timeControlStatus == .playing
                playerStateBeforeModal = (itemID: itemID, isPlaying: isPlaying)
                FavoritesView.logger.info("Saved player state before modal: itemID \(itemID), isPlaying: \(isPlaying)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SheetDismissed"))) { _ in
            // Restore the player state after a sheet closes
            if navigationService.selectedTab == .favorites,
               let savedState = playerStateBeforeModal {
                // Small delay to ensure the sheet is fully dismissed
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    
                    // Check if we need to restore the player for the saved item
                    if let currentItemID = playerManager.playerItemID,
                       currentItemID == savedState.itemID {
                        // Same item, just resume if it was playing
                        if savedState.isPlaying && playerManager.player?.timeControlStatus != .playing {
                            playerManager.player?.play()
                            FavoritesView.logger.info("Resumed player for same item \(savedState.itemID)")
                        }
                    } else {
                        // Different item or no player, need to recreate
                        if let item = items.first(where: { $0.id == savedState.itemID }) {
                            FavoritesView.logger.info("Recreating player for item \(savedState.itemID) after modal")
                            // The VideoPlayerManager should handle recreating the player
                            // This might require additional logic depending on your implementation
                        }
                    }
                    
                    playerStateBeforeModal = nil
                }
            }
        }
    }
    
    private func handleApiFlagsChange() {
        FavoritesView.logger.info("FavoritesView: Relevant global filter flag changed. Auto-reloading favorites...")
        // Only reload if we have items loaded (avoid unnecessary API calls on initial load)
        if !items.isEmpty && authService.isLoggedIn && settings.selectedCollectionIdForFavorites != nil {
            Task { await performFavoritesLogic(isInitialLoad: true) }
        }
    }

    @ViewBuilder
    private var favoritesContentView: some View {
        Group {
            if !authService.isLoggedIn {
                loggedOutContentView
            } else if settings.selectedCollectionIdForFavorites == nil {
                noCollectionSelectedContentView
            } else if isLoading && items.isEmpty {
                ProgressView("Lade Favoriten...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty {
                VStack {
                    Text("Fehler: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Erneut versuchen") { 
                        Task { await performFavoritesLogic(isInitialLoad: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading && apiFlagsForFavorites == 0 {
                noFilterContentView
            } else if items.isEmpty && !isLoading && !(currentSearchTagForAPI?.isEmpty ?? true) {
                ContentUnavailableView {
                    Label("Keine Ergebnisse", systemImage: "magnifyingglass")
                } description: {
                    Text("Keine Favoriten für den Tag '\(currentSearchTagForAPI!)' gefunden.")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("Keine Favoriten", systemImage: "heart")
                } description: {
                    Text("Du hast noch keine Favoriten in dieser Sammlung.")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollViewContent
            }
        }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        FavoritesItemThumbnail(
                            item: item,
                            isSeen: settings.seenItemIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if gridColumns.count > 0, index % gridColumns.count == 0 {
                            let nextPrefetchCount = gridColumns.count * 2
                            let start = min(index + gridColumns.count, items.count)
                            let end = min(start + nextPrefetchCount, items.count)
                            if start < end {
                                let urls: [URL] = items[start..<end].compactMap { $0.thumbnailUrl }
                                if !urls.isEmpty {
                                    let prefetcher = ImagePrefetcher(urls: urls)
                                    prefetcher.start()
                                }
                            }
                        }

                        let offset = max(1, gridColumns.count) * preloadRowsAhead
                        let thresholdIndex = max(0, items.count - offset)
                        if index >= thresholdIndex && canLoadMore && !isLoadingMore && !isLoading {
                            Task { await loadMoreFavorites() }
                        }
                    }
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear {
                            Task { await loadMoreFavorites() }
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
        .refreshable {
            Task { await performFavoritesLogic(isInitialLoad: true) }
        }
    }

    private var noFilterContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)
            Text("Keine Favoriten für Filter")
                .font(.headline)
            Text("Bitte passe deine Filter an, um deine Favoriten zu sehen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Filter anpassen") { showingFilterSheet = true }
                .buttonStyle(.bordered)
                .padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noCollectionSelectedContentView: some View {
        VStack {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)
            Text("Kein Favoriten-Ordner ausgewählt")
                .font(.headline)
            Text("Bitte wähle in den Einstellungen einen Ordner aus, der als Standard für deine Favoriten verwendet werden soll.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Zu den Einstellungen") {
                FavoritesView.logger.info("User tapped 'Zu den Einstellungen'. Navigating to Settings tab.")
                navigationService.selectedTab = .settings
            }
            .buttonStyle(.bordered)
            .padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @MainActor
    private func performFavoritesLogic(isInitialLoad: Bool) async {
        guard authService.isLoggedIn else {
            items = []
            errorMessage = nil
            canLoadMore = false
            isLoadingMore = false
            isLoading = false
            hasAttemptedSearchSinceAppear = false
            return
        }
        
        guard settings.selectedCollectionIdForFavorites != nil else {
            items = []
            errorMessage = nil
            canLoadMore = false
            isLoadingMore = false
            isLoading = false
            hasAttemptedSearchSinceAppear = false
            return
        }
        
        FavoritesView.logger.info("performFavoritesLogic: isInitialLoad=\(isInitialLoad). Search Tag: '\(currentSearchTagForAPI ?? "nil")'")
        await refreshFavorites()
        hasAttemptedSearchSinceAppear = true
    }

    @MainActor
    private func refreshFavorites() async {
        FavoritesView.logger.info("Refreshing favorites...")
        guard !isLoading else { return }
        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            FavoritesView.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            return
        }
        guard let selectedCollectionID = settings.selectedCollectionIdForFavorites,
              let selectedCollectionInstance = authService.userCollections.first(where: { $0.id == selectedCollectionID }),
              let collectionKeyword = selectedCollectionInstance.keyword else {
            FavoritesView.logger.warning("Cannot refresh favorites: No collection selected or keyword missing.")
            return
        }

        let currentApiFlags = apiFlagsForFavorites
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Allow search if we have content filters OR a search term
        if currentApiFlags == 0 && (effectiveSearchTerm == nil || effectiveSearchTerm!.isEmpty) {
            FavoritesView.logger.warning("Refresh favorites blocked: No active content filter and no search term.")
            self.items = []
            self.errorMessage = nil
            self.isLoading = false
            self.canLoadMore = false
            self.isLoadingMore = false
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        self.canLoadMore = true
        self.isLoadingMore = false

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: currentApiFlags,
                tags: effectiveSearchTerm
            )
            let fetchedItems = apiResponse.items.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
            self.items = fetchedItems

            if fetchedItems.isEmpty {
                self.canLoadMore = false
            } else {
                let atEnd = apiResponse.atEnd ?? false
                let hasOlder = apiResponse.hasOlder ?? true
                self.canLoadMore = !(atEnd || !hasOlder)
            }
            
            // Update global favorites set
            authService.favoritedItemIDs = Set(self.items.map { $0.id })
            
            self.errorMessage = nil
            FavoritesView.logger.info("Favorites updated for collection '\(collectionKeyword)'. Total: \(self.items.count). Can load more: \(self.canLoadMore)")
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required.")
            self.items = []
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { 
            FavoritesView.logger.info("API call cancelled.") 
        }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)")
            if self.items.isEmpty { 
                self.errorMessage = "Fehler: \(error.localizedDescription)" 
            }
            self.canLoadMore = false
        }
    }

    @MainActor
    private func loadMoreFavorites() async {
        let currentApiFlags = apiFlagsForFavorites
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if currentApiFlags == 0 && (effectiveSearchTerm == nil || effectiveSearchTerm!.isEmpty) {
            FavoritesView.logger.warning("Skipping loadMore: No active filter and no search term.")
            self.canLoadMore = false
            return
        }
        
        guard authService.isLoggedIn, let username = authService.currentUser?.name else { return }
        guard let selectedCollectionID = settings.selectedCollectionIdForFavorites,
              let selectedCollectionInstance = authService.userCollections.first(where: { $0.id == selectedCollectionID }),
              let collectionKeyword = selectedCollectionInstance.keyword else {
            FavoritesView.logger.warning("Cannot load more favorites: No collection selected or keyword missing.")
            self.canLoadMore = false
            return
        }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let lastItemId = items.last?.id else { return }

        FavoritesView.logger.info("--- Starting loadMoreFavorites for collection '\(collectionKeyword)' older than \(lastItemId) ---")
        self.isLoadingMore = true
        defer { Task { @MainActor in self.isLoadingMore = false } }

        do {
            let apiResponse = try await apiService.fetchFavorites(
                username: username,
                collectionKeyword: collectionKeyword,
                flags: currentApiFlags,
                olderThanId: lastItemId,
                tags: effectiveSearchTerm
            )
            let newItems = apiResponse.items
            FavoritesView.logger.info("Loaded \(newItems.count) more favorite items from API.")

            if newItems.isEmpty {
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.items.map { $0.id })
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                if uniqueNewItems.isEmpty {
                    self.canLoadMore = false
                } else {
                    let markedNewItems = uniqueNewItems.map { var mutableItem = $0; mutableItem.favorited = true; return mutableItem }
                    self.items.append(contentsOf: markedNewItems)
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    self.canLoadMore = !(atEnd || !hasOlder)
                    
                    // Update global favorites set
                    authService.favoritedItemIDs.formUnion(uniqueNewItems.map { $0.id })
                }
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            FavoritesView.logger.error("API fetch failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { 
            FavoritesView.logger.info("Load more cancelled.") 
        }
        catch {
            FavoritesView.logger.error("API fetch failed: \(error.localizedDescription)")
            if items.isEmpty { 
                errorMessage = "Fehler: \(error.localizedDescription)" 
            }
            self.canLoadMore = false
        }
    }
    
    // Calculate tab bar height to match MainView
    private func calculateTabBarHeight() -> CGFloat {
        let verticalPadding: CGFloat = 32 // 16 top + 16 bottom
        let buttonHeight: CGFloat = 40
        let bottomMargin: CGFloat = UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8
        return verticalPadding + buttonHeight + bottomMargin
    }
}
