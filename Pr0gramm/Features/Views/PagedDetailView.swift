// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit

// PreviewLinkTarget und FullscreenImageTarget bleiben unverändert...
struct PreviewLinkTarget: Identifiable, Equatable { let id: Int }
struct FullscreenImageTarget: Identifiable, Equatable {
    let item: Item; var id: Int { item.id }
    static func == (lhs: FullscreenImageTarget, rhs: FullscreenImageTarget) -> Bool { lhs.item.id == rhs.item.id }
}

// MARK: - Cache Structure for Item Details (unverändert)
struct CachedItemDetails {
    let info: ItemsInfoResponse
    let sortedBy: CommentSortOrder
    let flatDisplayComments: [FlatCommentDisplayItem] // Full flat list, including hasChildren
    let totalCommentCount: Int
}


// MARK: - PagedDetailTabViewItem (angepasst)

@MainActor
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    // --- MODIFIED: Takes the already filtered list ---
    let visibleFlatComments: [FlatCommentDisplayItem]
    // --- END MODIFICATION ---
    let totalCommentCount: Int
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool
    let infoLoadingStatus: InfoLoadingStatus
    let loadInfoAction: (Item) async -> Void
    let preloadInfoAction: (Item) async -> Void
    let allItems: [Item]
    let currentIndex: Int
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void
    // --- NEW: Callback and collapsed set ---
    let collapsedCommentIDs: Set<Int>
    let toggleCollapseAction: (Int) -> Void
    // --- END NEW ---

    @EnvironmentObject private var settings: AppSettings

    // --- NEW: Helper to pass down to CommentView ---
    private func isCommentCollapsed(_ commentID: Int) -> Bool {
        collapsedCommentIDs.contains(commentID)
    }
    // --- END NEW ---

    var body: some View {
        // Pass the filtered list directly to DetailViewContent
        DetailViewContent(
            item: item, keyboardActionHandler: keyboardActionHandler, player: player,
            onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: displayedTags, totalTagCount: totalTagCount, showingAllTags: showingAllTags,
            // --- MODIFIED: Pass filtered comments ---
            flatComments: visibleFlatComments,
            // --- END MODIFICATION ---
            totalCommentCount: totalCommentCount,
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget, fullscreenImageTarget: $fullscreenImageTarget,
            isFavorited: isFavorited, toggleFavoriteAction: toggleFavoriteAction,
            showAllTagsAction: showAllTagsAction,
            // --- NEW: Pass state and action down ---
            isCommentCollapsed: isCommentCollapsed, // Pass function
            toggleCollapseAction: toggleCollapseAction // Pass callback
            // --- END NEW ---
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await loadInfoAction(item) }
            // Preload direct neighbors, filtering happens in overview
            if currentIndex + 1 < allItems.count { Task { await preloadInfoAction(allItems[currentIndex + 1]) } }
            if currentIndex > 0 { Task { await preloadInfoAction(allItems[currentIndex - 1]) } }
        }
    }
}


// MARK: - PagedDetailView (angepasst)

@MainActor
struct PagedDetailView: View {
    let items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) var scenePhase
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    @ObservedObject var playerManager: VideoPlayerManager
    @State private var isFullscreen = false
    @State private var cachedDetails: [Int: CachedItemDetails] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    @State private var showAllTagsForItem: Set<Int> = []
    private let apiService = APIService()
    @State private var previewLinkTarget: PreviewLinkTarget? = nil
    @State private var isTogglingFavorite = false
    @State private var fullscreenImageTarget: FullscreenImageTarget? = nil
    @State private var localFavoritedStatus: [Int: Bool] = [:]
    @State private var visitedItemIDsThisSession: Set<Int> = []

    // --- NEW: State for collapsed comments ---
    @State private var collapsedCommentIDs: Set<Int> = []
    // --- END NEW ---

    let commentMaxDepth = 5

    init(items: [Item], selectedIndex: Int, playerManager: VideoPlayerManager) {
        self.items = items
        // Start directly at the selected index from the parent view
        self._selectedIndex = State(initialValue: selectedIndex)
        self.playerManager = playerManager
        // Initialize favorite status based on passed items
        var initialFavStatus: [Int: Bool] = [:]; for item in items { initialFavStatus[item.id] = item.favorited ?? false }; self._localFavoritedStatus = State(initialValue: initialFavStatus)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    /// Checks the local favorite status for the currently selected item.
    private var isCurrentItemFavorited: Bool {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return false }
        return localFavoritedStatus[items[selectedIndex].id] ?? items[selectedIndex].favorited ?? false
    }

    // MARK: - Body
    var body: some View {
        Group { tabViewContent }
        .background(KeyCommandView(handler: keyboardActionHandler))
        .sheet(item: $previewLinkTarget) { targetWrapper in
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings).environmentObject(authService)
        }
        // --- onChange now works because PreviewLinkTarget is Equatable ---
        .onChange(of: previewLinkTarget) { oldValue, newValue in
            if newValue != nil {
                // Sheet is about to be presented (or target changed)
                PagedDetailView.logger.info("Link preview requested for item ID \(newValue!.id). Pausing current video (if playing).")
                playerManager.player?.pause()
            }
        }
        // --- END FIX ---
        .sheet(item: $fullscreenImageTarget) { targetWrapper in
             FullscreenImageView(item: targetWrapper.item)
        }
    }

    // MARK: - TabView Content and Page Generation
    private var tabViewContent: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                 tabViewPage(for: index) // Always render the page structure
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItemTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedIndex) { oldValue, newValue in
            handleIndexChange(oldValue: oldValue, newValue: newValue)
        }
        .onAppear { setupView() }
        .onDisappear { cleanupViewAndMarkVisited() } // Mark visited on disappear
        .onChange(of: scenePhase) { oldPhase, newPhase in
             handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
        .onChange(of: settings.commentSortOrder) { oldOrder, newOrder in
             handleSortOrderChange(newOrder: newOrder)
        }
        // No longer reacting to hideSeenItems change *within* this view
    }

    /// Generates the content view for a single tab page.
    @ViewBuilder
    private func tabViewPage(for index: Int) -> some View {
        // Prepare data, including filtering comments
        if let pageData = preparePageData(for: index) {
            PagedDetailTabViewItem(
                item: pageData.currentItem,
                keyboardActionHandler: keyboardActionHandler,
                player: pageData.currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                // --- MODIFIED: Pass filtered comments ---
                visibleFlatComments: pageData.visibleFlatComments,
                // --- END MODIFICATION ---
                totalCommentCount: pageData.totalCommentCount,
                displayedTags: pageData.displayedTags,
                totalTagCount: pageData.totalTagCount, // Note: Renamed for clarity if needed (tagCount)
                showingAllTags: pageData.showingAllTags,
                infoLoadingStatus: pageData.status,
                loadInfoAction: loadInfoIfNeededAndPrepareHierarchy,
                preloadInfoAction: loadInfoIfNeededAndPrepareHierarchy,
                allItems: items,
                currentIndex: index,
                onWillBeginFullScreen: { self.isFullscreen = true },
                onWillEndFullScreen: handleEndFullScreen,
                previewLinkTarget: $previewLinkTarget,
                fullscreenImageTarget: $fullscreenImageTarget,
                isFavorited: localFavoritedStatus[pageData.currentItem.id] ?? pageData.currentItem.favorited ?? false,
                toggleFavoriteAction: toggleFavorite,
                showAllTagsAction: { showAllTagsForItem.insert(pageData.currentItem.id) },
                // --- NEW: Pass collapsed state and toggle action ---
                collapsedCommentIDs: collapsedCommentIDs,
                toggleCollapseAction: toggleCollapse
                // --- END NEW ---
            )
            .tag(index)
        } else {
            // Render an EmptyView if data preparation fails
            EmptyView().tag(index)
        }
    }


    // MARK: - Data Preparation and Loading

    /// Prepares data needed for a specific page index, returning the VISIBLE flat list.
    private func preparePageData(for index: Int) -> (
        currentItem: Item, status: InfoLoadingStatus,
        // --- MODIFIED: Return visibleFlatComments ---
        visibleFlatComments: [FlatCommentDisplayItem],
        // --- END MODIFICATION ---
        totalCommentCount: Int,
        displayedTags: [ItemTag], totalTagCount: Int, showingAllTags: Bool
    )? {
        guard index >= 0 && index < items.count else { return nil }
        let currentItem = items[index]
        let itemId = currentItem.id
        let statusForItem = infoLoadingStatus[itemId] ?? .idle
        // --- MODIFIED: Calculate visible comments here ---
        let visibleComments = calculateVisibleComments(for: itemId)
        // --- END MODIFICATION ---
        var finalTotalCommentCount = 0
        var finalSortedTags: [ItemTag] = []

        if let cached = cachedDetails[itemId] {
            finalTotalCommentCount = cached.totalCommentCount
            finalSortedTags = cached.info.tags
        } else if statusForItem == .loaded {
             Self.logger.warning("preparePageData: Status loaded for \(itemId), no cached details.")
        }

        let totalTagCount = finalSortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay = shouldShowAll ? finalSortedTags : Array(finalSortedTags.prefix(4))

        // --- MODIFIED: Return visibleComments ---
        return (currentItem, statusForItem, visibleComments, finalTotalCommentCount, tagsToDisplay, totalTagCount, shouldShowAll)
        // --- END MODIFICATION ---
    }

    /// Loads item info (if needed) and prepares/caches the FULL FLAT comment list & total count.
    private func loadInfoIfNeededAndPrepareHierarchy(for item: Item) async {
         let itemId = item.id
         let currentStatus = infoLoadingStatus[itemId]
         if let cached = cachedDetails[itemId], currentStatus == .loaded {
             if cached.sortedBy == settings.commentSortOrder { return } // Already cached and sorted correctly
             else {
                  // Re-sort and re-flatten the existing raw comments
                  Self.logger.info("loadInfoIfNeeded: Recalculating flat list for cached item \(itemId) due to sort order change.")
                  let newFlatList = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                  // Update cache with new flat list and correct sort order
                  cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: newFlatList, totalCommentCount: cached.totalCommentCount)
                  return
             }
         }
         // Prevent redundant loading
         guard !(currentStatus == .loading) else { return }
         if case .error = currentStatus { Self.logger.debug("Retrying info load for item \(itemId).") }

         Self.logger.debug("Starting info load & FULL FLAT prep for item \(itemId)...")
         infoLoadingStatus[itemId] = .loading
         do {
             let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)
             let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
             let infoWithSortedTags = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)
             // Prepare the FULL flat list, including hasChildren flag
             let flatDisplayComments = prepareFlatDisplayComments(from: fetchedInfoResponse.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
             let totalCommentCount = fetchedInfoResponse.comments.count
             let detailsToCache = CachedItemDetails(info: infoWithSortedTags, sortedBy: settings.commentSortOrder, flatDisplayComments: flatDisplayComments, totalCommentCount: totalCommentCount)
             cachedDetails[itemId] = detailsToCache // Cache the full list
             infoLoadingStatus[itemId] = .loaded
             Self.logger.info("Successfully loaded/prepared FULL FLAT hierarchy (\(flatDisplayComments.count) items shown initially) for item \(itemId). Total raw: \(totalCommentCount).")
         } catch {
             Self.logger.error("Failed load/prep FULL FLAT hierarchy for item \(itemId): \(error.localizedDescription)")
             infoLoadingStatus[itemId] = .error(error.localizedDescription)
         }
    }

    /// Helper function to build the FULL FLAT comment list, including `hasChildren`.
    private func prepareFlatDisplayComments(from comments: [ItemComment], sortedBy sortOrder: CommentSortOrder, maxDepth: Int) -> [FlatCommentDisplayItem] {
        Self.logger.debug("Preparing FULL FLAT display comments (\(comments.count) raw), sort: \(sortOrder.displayName), depth: \(maxDepth).")
        let startTime = Date()
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })

        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            // --- MODIFIED: Check for children ---
            let children = childrenByParentId[commentId] ?? []
            let hasChildren = !children.isEmpty
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren))
            // --- END MODIFICATION ---
            guard currentLevel < maxDepth else { return }
            // Sort children based on the selected order
            let sortedChildren: [ItemComment]
            switch sortOrder {
            case .date: sortedChildren = children.sorted { $0.created < $1.created }
            case .score: sortedChildren = children.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
            }
            // Recursively traverse children
            sortedChildren.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
        }

        // Process top-level comments
        let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
        let sortedTopLevelComments: [ItemComment]
        switch sortOrder {
        case .date: sortedTopLevelComments = topLevelComments.sorted { $0.created < $1.created }
        case .score: sortedTopLevelComments = topLevelComments.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
        }
        sortedTopLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }

        let duration = Date().timeIntervalSince(startTime)
        Self.logger.info("Finished preparing FULL FLAT comments (\(flatList.count) items) in \(String(format: "%.3f", duration))s.")
        return flatList
    }

    // --- MODIFIED: Function to calculate visible comments (Alternative Cleanup Logic) ---
    /// Filters the full flat comment list based on the current collapsed state.
    private func calculateVisibleComments(for itemID: Int) -> [FlatCommentDisplayItem] {
        guard let details = cachedDetails[itemID] else { return [] }
        let fullList = details.flatDisplayComments
        guard !collapsedCommentIDs.isEmpty else { return fullList } // No filtering needed if nothing is collapsed

        var visibleList: [FlatCommentDisplayItem] = []
        // --- Store level of the nearest collapsed ancestor ---
        // Key: Level, Value: ID of the collapsed comment at that level causing the collapse
        var nearestCollapsedAncestorLevel: [Int: Int] = [:]

        for item in fullList {
            let currentLevel = item.level
            var isHiddenByAncestor = false

            // Check if any ancestor *up to the parent level* is collapsed
            if currentLevel > 0 {
                for ancestorLevel in 0..<currentLevel {
                    if nearestCollapsedAncestorLevel[ancestorLevel] != nil {
                        isHiddenByAncestor = true
                        // Mark this level as hidden for its children
                        nearestCollapsedAncestorLevel[currentLevel] = nearestCollapsedAncestorLevel[ancestorLevel]
                        break // Found a collapsed ancestor, no need to check further up
                    }
                }
            }

            // If hidden by an ancestor, skip adding and continue tracking collapse state
            if isHiddenByAncestor {
                 // nearestCollapsedAncestorLevel[currentLevel] was already set above
                continue
            }

            // Add the item if it's not hidden by an ancestor
            visibleList.append(item)

            // --- Update collapse tracking for the *current* level ---
            if collapsedCommentIDs.contains(item.id) {
                // This item itself is collapsed, track it for its children
                nearestCollapsedAncestorLevel[currentLevel] = item.id
            } else {
                // This item is NOT collapsed, clear the tracker for this level
                nearestCollapsedAncestorLevel.removeValue(forKey: currentLevel)
            }

            // --- Simpler Cleanup: Remove tracking for levels deeper than current ---
            // Iterate through existing keys and remove those deeper than currentLevel
            let keysToRemove = nearestCollapsedAncestorLevel.keys.filter { $0 > currentLevel }
            for key in keysToRemove {
                nearestCollapsedAncestorLevel.removeValue(forKey: key)
            }
            // --- End Cleanup ---
        }
        return visibleList
    }
    // --- END MODIFIED ---

    // MARK: - View Lifecycle and State Handling Helpers
    private func setupView() {
        Self.logger.info("PagedDetailView appeared.")
        if isFullscreen { isFullscreen = false }
        isTogglingFavorite = false
        keyboardActionHandler.selectNextAction = self.selectNext
        keyboardActionHandler.selectPreviousAction = self.selectPrevious
        if selectedIndex >= 0 && selectedIndex < items.count {
            let initialItem = items[selectedIndex]
            playerManager.setupPlayerIfNeeded(for: initialItem, isFullscreen: isFullscreen)
            Task { await loadInfoIfNeededAndPrepareHierarchy(for: initialItem) }
            visitedItemIDsThisSession.insert(initialItem.id) // Add initial item to visited
            Self.logger.debug("Added initial item \(initialItem.id) to visited set.")
        } else { Self.logger.warning("onAppear: Invalid selectedIndex \(selectedIndex).") }
    }

    /// Cleans up AND marks visited items as seen when the view disappears.
    private func cleanupViewAndMarkVisited() {
        Self.logger.info("PagedDetailView disappearing.")
        keyboardActionHandler.selectNextAction = nil; keyboardActionHandler.selectPreviousAction = nil
        if !isFullscreen { playerManager.cleanupPlayer() }
        else { Self.logger.info("Skipping player cleanup (fullscreen).") }
        showAllTagsForItem = []

        let visitedIDs = self.visitedItemIDsThisSession
        if !visitedIDs.isEmpty {
            Task { // Mark as seen asynchronously
                Self.logger.info("Marking \(visitedIDs.count) visited items as seen...")
                for id in visitedIDs {
                    await settings.markItemAsSeen(id: id)
                }
                Self.logger.info("Finished marking visited items.")
            }
        }
        visitedItemIDsThisSession = [] // Clear the set for the next time the view appears
    }

    /// Handles index changes, loads data, adds item to visited set. NO filtering logic here.
    private func handleIndexChange(oldValue: Int, newValue: Int) {
        Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
        guard newValue >= 0 && newValue < items.count else { return }
        let newItem = items[newValue]

        Self.logger.debug("Index changed to \(newValue). Performing actions.")
        playerManager.setupPlayerIfNeeded(for: newItem, isFullscreen: isFullscreen)
        Task { await loadInfoIfNeededAndPrepareHierarchy(for: newItem) }
        visitedItemIDsThisSession.insert(newItem.id) // Add newly viewed item to set
        Self.logger.debug("Added item \(newItem.id) to visited set.")
        isTogglingFavorite = false
        // Optionally reset collapsed state when swiping
        // collapsedCommentIDs = []
    }

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
         Self.logger.debug("Scene phase: \(String(describing: oldPhase)) -> \(String(describing: newPhase))")
         if newPhase == .active {
             settings.transientSessionMuteState = nil
             if let player = playerManager.player, player.isMuted != settings.isVideoMuted {
                 player.isMuted = settings.isVideoMuted
             }
              if isFullscreen, let player = playerManager.player, player.timeControlStatus != .playing {
                  player.play()
              }
         } else if newPhase == .inactive || newPhase == .background {
             if (!isFullscreen && previewLinkTarget == nil), let player = playerManager.player, player.timeControlStatus == .playing {
                 Self.logger.debug("Scene became inactive/background. Pausing player (not fullscreen, no link preview).")
                 player.pause()
             } else {
                 Self.logger.debug("Scene became inactive/background. NOT pausing player (is fullscreen or link preview is active).")
             }
         }
    }

    private func handleSortOrderChange(newOrder: CommentSortOrder) {
         Self.logger.info("Sort order changed to \(newOrder.displayName). Recalculating cached flat lists.")
         var updatedCache: [Int: CachedItemDetails] = [:]
         for (id, details) in cachedDetails where details.sortedBy != newOrder {
              let newFlatList = prepareFlatDisplayComments(from: details.info.comments, sortedBy: newOrder, maxDepth: commentMaxDepth)
              updatedCache[id] = CachedItemDetails(info: details.info, sortedBy: newOrder, flatDisplayComments: newFlatList, totalCommentCount: details.totalCommentCount)
         }
         cachedDetails.merge(updatedCache) { (_, new) in new }
          // Important: Force a refresh of the currently visible comments after resorting
          // This is needed because the displayed comments depend on the cached flat list
          // which has just been updated. Simply updating the cache doesn't trigger a view update
          // for the *filtered* list automatically in this setup.
          let currentVisibleItemId = items[selectedIndex].id
          // Trigger a re-calculation by slightly modifying a state property the view depends on,
          // or ideally, by having calculateVisibleComments be part of the view's body logic
          // For now, just force an update by resetting the same index (less ideal but functional)
          let tempIndex = selectedIndex
          selectedIndex = -1 // Force TabView to redraw
          DispatchQueue.main.async { // Ensure update happens after state reset
              self.selectedIndex = tempIndex
          }
    }

    private func handleEndFullScreen() {
         self.isFullscreen = false
         Self.logger.debug("[View] Callback: handleEndFullScreen")
         if selectedIndex >= 0 && selectedIndex < items.count, items[selectedIndex].isVideo, items[selectedIndex].id == playerManager.playerItemID {
             Task { @MainActor in
                 try? await Task.sleep(for: .milliseconds(100))
                 if !self.isFullscreen && self.previewLinkTarget == nil && self.playerManager.player?.timeControlStatus != .playing {
                     Self.logger.debug("Resuming player after ending fullscreen (preview not active).")
                     self.playerManager.player?.play()
                 } else {
                     Self.logger.debug("NOT resuming player after ending fullscreen (preview is active or player already playing).")
                 }
             }
         }
    }

    // MARK: - Navigation and Actions
    private func selectNext() {
        guard selectedIndex < items.count - 1 else { return }
        selectedIndex += 1
    }

    private var canSelectNext: Bool { selectedIndex < items.count - 1 }

    private func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    private var canSelectPrevious: Bool { selectedIndex > 0 }

    private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = infoLoadingStatus[currentItem.id] ?? .idle
        switch status {
        case .loaded: return cachedDetails[currentItem.id]?.info.tags.first?.tag ?? "Post \(currentItem.id)"
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }

    private func toggleFavorite() async {
        let localSettings = self.settings
        guard !isTogglingFavorite else { return }
        guard selectedIndex >= 0 && selectedIndex < items.count else { return }
        let currentItem = items[selectedIndex]
        guard authService.isLoggedIn, let nonce = authService.userNonce, let collectionId = authService.favoritesCollectionId else { return }
        let itemId = currentItem.id
        let targetFavoriteState = !(localFavoritedStatus[itemId] ?? currentItem.favorited ?? false)
        isTogglingFavorite = true; localFavoritedStatus[itemId] = targetFavoriteState
        do {
            if targetFavoriteState { try await apiService.addToCollection(itemId: itemId, nonce: nonce) }
            else { try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce) }
            await localSettings.clearFavoritesCache(); await localSettings.updateCacheSizes()
            Self.logger.info("Favorite toggled successfully for item \(itemId).")
        } catch {
            Self.logger.error("Failed to toggle favorite: \(error.localizedDescription)")
            localFavoritedStatus[itemId] = !targetFavoriteState
        }
        isTogglingFavorite = false
    }

    // --- NEW: Action to toggle comment collapse state ---
    private func toggleCollapse(commentID: Int) {
        if collapsedCommentIDs.contains(commentID) {
            collapsedCommentIDs.remove(commentID)
            Self.logger.trace("Expanding comment \(commentID)")
        } else {
            collapsedCommentIDs.insert(commentID)
            Self.logger.trace("Collapsing comment \(commentID)")
        }
        // The view will automatically update because `preparePageData` reads `collapsedCommentIDs` indirectly
        // via `calculateVisibleComments`. SwiftUI's state management handles the redraw.
    }
    // --- END NEW ---
}

// MARK: - Wrapper View (unverändert)
struct LinkedItemPreviewWrapperView: View {
    let itemID: Int
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View { // Explicit return type
        NavigationStack {
            LinkedItemPreviewView(itemID: itemID)
                .environmentObject(settings).environmentObject(authService)
                .navigationTitle("Vorschau")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: - Preview Provider (unverändert)
#Preview("Preview") {
    // Setup remains the same...
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    previewAuthService.userNonce = "preview_nonce_12345"
    previewAuthService.favoritesCollectionId = 6749
    let previewPlayerManager = VideoPlayerManager()
    let sampleItems = [ Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: 1, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false), Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: 2, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true), Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: 3, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, favorited: nil), Item(id: 4, promoted: 1004, userId: 3, down: 1, up: 10, created: 4, image: "img3.gif", thumb: "t4.gif", fullsize: nil, preview: nil, width: 500, height: 300, audio: false, source: nil, flags: 1, user: "UserC", mark: 0, repost: nil, variants: nil, favorited: false) ]
    previewSettings.hideSeenItems = true
    previewSettings.seenItemIDs = [1, 3]
    previewPlayerManager.configure(settings: previewSettings)

    return NavigationStack { // Return directly
        PagedDetailView(items: sampleItems, selectedIndex: 0, playerManager: previewPlayerManager)
    }
    .environmentObject(previewSettings)
    .environmentObject(previewAuthService)
}


// --- END OF COMPLETE FILE ---
