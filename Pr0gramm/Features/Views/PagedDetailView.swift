// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit

/// Wrapper struct used to identify the item to be shown in the link preview sheet.
// --- MODIFIED: Add Equatable conformance ---
struct PreviewLinkTarget: Identifiable, Equatable {
// --- END MODIFICATION ---
    let id: Int // The item ID to preview
}

/// Wrapper struct for fullscreen image sheet
// --- MODIFIED: Add Equatable conformance (using item.id) ---
struct FullscreenImageTarget: Identifiable, Equatable {
// --- END MODIFICATION ---
    let item: Item
    var id: Int { item.id } // Use item ID for Identifiable conformance

    // Explicitly define == for Equatable conformance based on the item's ID
    static func == (lhs: FullscreenImageTarget, rhs: FullscreenImageTarget) -> Bool {
        lhs.item.id == rhs.item.id
    }
}

// MARK: - Cache Structure for Item Details
/// Structure to hold fetched item info along with the pre-calculated FLAT comment list.
struct CachedItemDetails {
    let info: ItemsInfoResponse // Raw tags and comments (tags pre-sorted by confidence)
    let sortedBy: CommentSortOrder // Which sort order was used for flatDisplayComments
    let flatDisplayComments: [FlatCommentDisplayItem] // Pre-calculated FLAT comment list
    let totalCommentCount: Int // Store total count here
}


// MARK: - PagedDetailTabViewItem

@MainActor
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let flatCommentsToDisplay: [FlatCommentDisplayItem] // Expect flat list from parent
    let totalCommentCount: Int // Total count for the "Show All" button logic
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool
    let infoLoadingStatus: InfoLoadingStatus
    let loadInfoAction: (Item) async -> Void // Action to trigger loading/preparation
    let preloadInfoAction: (Item) async -> Void // Action to trigger preloading/preparation
    let allItems: [Item]
    let currentIndex: Int
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void

    @EnvironmentObject private var settings: AppSettings // Needed for settings access

    var body: some View {
        DetailViewContent(
            item: item, keyboardActionHandler: keyboardActionHandler, player: player,
            onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: displayedTags, totalTagCount: totalTagCount, showingAllTags: showingAllTags,
            flatComments: flatCommentsToDisplay, // Pass the flat list down
            totalCommentCount: totalCommentCount, // Pass total count down
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget, fullscreenImageTarget: $fullscreenImageTarget,
            isFavorited: isFavorited, toggleFavoriteAction: toggleFavoriteAction,
            showAllTagsAction: showAllTagsAction
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

// MARK: - PagedDetailView

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
    @State private var visitedItemIDsThisSession: Set<Int> = [] // Collect visited items

    let commentMaxDepth = 5 // Max depth for comment flattening

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
        // Prepare data (including potentially cached flat comments)
        if let pageData = preparePageData(for: index) {
            PagedDetailTabViewItem(
                item: pageData.currentItem,
                keyboardActionHandler: keyboardActionHandler,
                player: pageData.currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                flatCommentsToDisplay: pageData.flatComments, // Pass the flat list
                totalCommentCount: pageData.totalCommentCount, // Pass the total count
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
                showAllTagsAction: { showAllTagsForItem.insert(pageData.currentItem.id) }
            )
            .tag(index)
        } else {
            // Render an EmptyView if data preparation fails
            EmptyView().tag(index)
        }
    }


    // MARK: - Data Preparation and Loading

    /// Prepares data needed for a specific page index, returning FLAT list and TOTAL comment count.
    private func preparePageData(for index: Int) -> (
        currentItem: Item, status: InfoLoadingStatus,
        flatComments: [FlatCommentDisplayItem], totalCommentCount: Int,
        displayedTags: [ItemTag], totalTagCount: Int, showingAllTags: Bool
    )? {
        guard index >= 0 && index < items.count else { return nil }
        let currentItem = items[index]
        let itemId = currentItem.id
        let statusForItem = infoLoadingStatus[itemId] ?? .idle
        var finalFlatComments: [FlatCommentDisplayItem] = []
        var finalTotalCommentCount = 0
        var finalSortedTags: [ItemTag] = []

        if let cached = cachedDetails[itemId] {
            finalTotalCommentCount = cached.totalCommentCount
            if cached.sortedBy == settings.commentSortOrder {
                 finalFlatComments = cached.flatDisplayComments
            } else {
                 Self.logger.info("Recalculating flat comment list for item \(itemId).")
                 finalFlatComments = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                 cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: finalFlatComments, totalCommentCount: finalTotalCommentCount)
            }
            finalSortedTags = cached.info.tags
        } else if statusForItem == .loaded {
             Self.logger.warning("preparePageData: Status loaded for \(itemId), no cached details.")
        }

        let totalTagCount = finalSortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay = shouldShowAll ? finalSortedTags : Array(finalSortedTags.prefix(4))

        return (currentItem, statusForItem, finalFlatComments, finalTotalCommentCount, tagsToDisplay, totalTagCount, shouldShowAll)
    }

    /// Loads item info (if needed) and prepares/caches the FLAT comment list & total count.
    private func loadInfoIfNeededAndPrepareHierarchy(for item: Item) async {
         let itemId = item.id
         let currentStatus = infoLoadingStatus[itemId]
         if let cached = cachedDetails[itemId], currentStatus == .loaded {
             if cached.sortedBy == settings.commentSortOrder { return }
             else {
                  Self.logger.info("loadInfoIfNeeded: Recalculating flat list for cached item \(itemId).")
                  let newFlatList = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                  cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: newFlatList, totalCommentCount: cached.totalCommentCount)
                  return
             }
         }
         guard !(currentStatus == .loading) else { return }
         if case .error = currentStatus { Self.logger.debug("Retrying info load for item \(itemId).") }
         Self.logger.debug("Starting info load & FLAT prep for item \(itemId)...")
         infoLoadingStatus[itemId] = .loading
         do {
             let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)
             let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
             let infoWithSortedTags = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)
             let flatDisplayComments = prepareFlatDisplayComments(from: fetchedInfoResponse.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
             let totalCommentCount = fetchedInfoResponse.comments.count
             let detailsToCache = CachedItemDetails(info: infoWithSortedTags, sortedBy: settings.commentSortOrder, flatDisplayComments: flatDisplayComments, totalCommentCount: totalCommentCount)
             cachedDetails[itemId] = detailsToCache
             infoLoadingStatus[itemId] = .loaded
             Self.logger.info("Successfully loaded/prepared FLAT hierarchy (\(flatDisplayComments.count) items shown) for item \(itemId). Total raw: \(totalCommentCount).")
         } catch {
             Self.logger.error("Failed load/prep FLAT hierarchy for item \(itemId): \(error.localizedDescription)")
             infoLoadingStatus[itemId] = .error(error.localizedDescription)
         }
    }

    /// Helper function to build the FLAT comment list from raw comments. Includes sorting and depth limit.
    private func prepareFlatDisplayComments(from comments: [ItemComment], sortedBy sortOrder: CommentSortOrder, maxDepth: Int) -> [FlatCommentDisplayItem] {
        Self.logger.debug("Preparing FLAT display comments (\(comments.count) raw), sort: \(sortOrder.displayName), depth: \(maxDepth).")
        let startTime = Date()
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })

        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel))
            guard currentLevel < maxDepth else { return }
            let children = childrenByParentId[commentId] ?? []
            let sortedChildren: [ItemComment]
            switch sortOrder {
            case .date: sortedChildren = children.sorted { $0.created < $1.created }
            case .score: sortedChildren = children.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
            }
            sortedChildren.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
        }

        let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
        let sortedTopLevelComments: [ItemComment]
        switch sortOrder {
        case .date: sortedTopLevelComments = topLevelComments.sorted { $0.created < $1.created }
        case .score: sortedTopLevelComments = topLevelComments.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
        }
        sortedTopLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }

        let duration = Date().timeIntervalSince(startTime)
        Self.logger.info("Finished preparing FLAT comments (\(flatList.count) items) in \(String(format: "%.3f", duration))s.")
        return flatList
    }

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
             // --- MODIFICATION: Also pause if link preview is visible ---
             if (!isFullscreen && previewLinkTarget == nil), let player = playerManager.player, player.timeControlStatus == .playing {
                 Self.logger.debug("Scene became inactive/background. Pausing player (not fullscreen, no link preview).")
                 player.pause()
             } else {
                 Self.logger.debug("Scene became inactive/background. NOT pausing player (is fullscreen or link preview is active).")
             }
             // --- END MODIFICATION ---
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
    }

    // handleHideSeenChange removed

    private func handleEndFullScreen() {
         self.isFullscreen = false
         Self.logger.debug("[View] Callback: handleEndFullScreen")
         if selectedIndex >= 0 && selectedIndex < items.count, items[selectedIndex].isVideo, items[selectedIndex].id == playerManager.playerItemID {
             Task { @MainActor in
                 try? await Task.sleep(for: .milliseconds(100))
                 // --- MODIFICATION: Check previewLinkTarget before resuming ---
                 if !self.isFullscreen && self.previewLinkTarget == nil && self.playerManager.player?.timeControlStatus != .playing {
                     Self.logger.debug("Resuming player after ending fullscreen (preview not active).")
                     self.playerManager.player?.play()
                 } else {
                     Self.logger.debug("NOT resuming player after ending fullscreen (preview is active or player already playing).")
                 }
                 // --- END MODIFICATION ---
             }
         }
    }

    // MARK: - Navigation and Actions (Simplified - No Filtering)
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
}

// MARK: - Wrapper View (Corrected Definition)
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

// MARK: - Preview Provider
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
    Task { @MainActor in await previewPlayerManager.configure(settings: previewSettings) }

    return NavigationStack { // Return directly
        PagedDetailView(items: sampleItems, selectedIndex: 0, playerManager: previewPlayerManager)
    }
    .environmentObject(previewSettings)
    .environmentObject(previewAuthService)
}


// --- END OF COMPLETE FILE ---
