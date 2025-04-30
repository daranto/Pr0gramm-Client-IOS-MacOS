// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit

/// Wrapper struct used to identify the item to be shown in the link preview sheet.
struct PreviewLinkTarget: Identifiable {
    let id: Int // The item ID to preview
}

/// Wrapper struct for fullscreen image sheet
struct FullscreenImageTarget: Identifiable {
    let item: Item
    var id: Int { item.id } // Use item ID for Identifiable conformance
}

// MARK: - Cache Structure for Item Details
/// Structure to hold fetched item info along with the pre-calculated FLAT comment list.
struct CachedItemDetails {
    let info: ItemsInfoResponse // Raw tags and comments (tags pre-sorted by confidence)
    let sortedBy: CommentSortOrder // Which sort order was used for flatDisplayComments
    let flatDisplayComments: [FlatCommentDisplayItem] // Pre-calculated FLAT comment list
}


// MARK: - PagedDetailTabViewItem

@MainActor
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let flatCommentsToDisplay: [FlatCommentDisplayItem]
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

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        DetailViewContent(
            item: item, keyboardActionHandler: keyboardActionHandler, player: player,
            onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: displayedTags, totalTagCount: totalTagCount, showingAllTags: showingAllTags,
            flatComments: flatCommentsToDisplay, infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget, fullscreenImageTarget: $fullscreenImageTarget,
            isFavorited: isFavorited, toggleFavoriteAction: toggleFavoriteAction,
            showAllTagsAction: showAllTagsAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await loadInfoAction(item) }
            // Check result before accessing array to avoid out-of-bounds
            if let nextVisibleIndex = findNextVisibleIndex(from: currentIndex, in: allItems, settings: settings), nextVisibleIndex < allItems.count {
                 Task { await preloadInfoAction(allItems[nextVisibleIndex]) }
             }
            if let prevVisibleIndex = findPreviousVisibleIndex(from: currentIndex, in: allItems, settings: settings), prevVisibleIndex >= 0 {
                 Task { await preloadInfoAction(allItems[prevVisibleIndex]) }
             }
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
    @State private var isCorrectingIndex = false

    let commentMaxDepth = 5

    init(items: [Item], selectedIndex: Int, playerManager: VideoPlayerManager) {
        self.items = items
        self.playerManager = playerManager
        let initialSettingsCheck = AppSettings()
        var effectiveStartIndex = selectedIndex

        if initialSettingsCheck.hideSeenItems,
           selectedIndex >= 0, selectedIndex < items.count,
           initialSettingsCheck.seenItemIDs.contains(items[selectedIndex].id) {
            Self.logger.info("[Init] Initial index \(selectedIndex) points to a hidden item. Searching.")
            if let nextVisible = findNextVisibleIndex(from: selectedIndex - 1, in: items, settings: initialSettingsCheck) { effectiveStartIndex = nextVisible }
            else if let prevVisible = findPreviousVisibleIndex(from: selectedIndex + 1, in: items, settings: initialSettingsCheck) { effectiveStartIndex = prevVisible }
            else { Self.logger.error("[Init] Could not find ANY visible item.") }
            Self.logger.info("[Init] Adjusted start index to \(effectiveStartIndex).")
        }
        self._selectedIndex = State(initialValue: effectiveStartIndex)
        var initialFavStatus: [Int: Bool] = [:]; for item in items { initialFavStatus[item.id] = item.favorited ?? false }; self._localFavoritedStatus = State(initialValue: initialFavStatus)
        Self.logger.info("PagedDetailView init with final selectedIndex: \(effectiveStartIndex)")
    }

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
        .sheet(item: $fullscreenImageTarget) { targetWrapper in
             FullscreenImageView(item: targetWrapper.item)
        }
    }

    // MARK: - TabView Content and Page Generation
    private var tabViewContent: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                 tabViewPage(for: index)
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
        .onDisappear { cleanupView() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
             handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
        .onChange(of: settings.commentSortOrder) { newOrder in
             handleSortOrderChange(newOrder: newOrder)
        }
        .onChange(of: settings.hideSeenItems) { newValue in
             handleHideSeenChange(newValue: newValue)
        }
    }

    /// Generates the content view for a single tab page.
    @ViewBuilder
    private func tabViewPage(for index: Int) -> some View {
        if let pageData = preparePageData(for: index) {
            PagedDetailTabViewItem(
                item: pageData.currentItem,
                keyboardActionHandler: keyboardActionHandler,
                player: pageData.currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                flatCommentsToDisplay: pageData.flatComments,
                displayedTags: pageData.displayedTags,
                totalTagCount: pageData.totalTagCount,
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
            EmptyView().tag(index)
        }
    }


    // MARK: - Data Preparation and Loading
    /// Prepares data needed for a specific page index, utilizing cached flat comment lists.
    private func preparePageData(for index: Int) -> (
        currentItem: Item, status: InfoLoadingStatus, flatComments: [FlatCommentDisplayItem],
        displayedTags: [ItemTag], totalTagCount: Int, showingAllTags: Bool
    )? {
        guard index >= 0 && index < items.count else {
             Self.logger.error("preparePageData failed: Invalid index \(index)")
             return nil
        }
        let currentItem = items[index]
        let itemId = currentItem.id
        let statusForItem = infoLoadingStatus[itemId] ?? .idle
        var finalFlatComments: [FlatCommentDisplayItem] = []
        var finalSortedTags: [ItemTag] = []

        if let cached = cachedDetails[itemId] {
            if cached.sortedBy == settings.commentSortOrder {
                 finalFlatComments = cached.flatDisplayComments
            } else {
                 Self.logger.info("Recalculating flat comment list for item \(itemId) due to sort order change.")
                 finalFlatComments = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                 cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: finalFlatComments)
            }
            finalSortedTags = cached.info.tags
        } else if statusForItem == .loaded {
             Self.logger.warning("preparePageData: Status loaded for \(itemId), but no cached details found.")
             finalFlatComments = []; finalSortedTags = []
        }

        let totalTagCount = finalSortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay = shouldShowAll ? finalSortedTags : Array(finalSortedTags.prefix(4))

        return (currentItem, statusForItem, finalFlatComments, tagsToDisplay, totalTagCount, shouldShowAll)
    }

    /// Loads item info (if needed) and prepares/caches the FLAT comment list.
    private func loadInfoIfNeededAndPrepareHierarchy(for item: Item) async {
         let itemId = item.id
         let currentStatus = infoLoadingStatus[itemId]
         if let cached = cachedDetails[itemId], currentStatus == .loaded {
             if cached.sortedBy == settings.commentSortOrder { return }
             else {
                  Self.logger.info("loadInfoIfNeeded: Recalculating flat list for cached item \(itemId).")
                  let newFlatList = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                  cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: newFlatList)
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
             let detailsToCache = CachedItemDetails(info: infoWithSortedTags, sortedBy: settings.commentSortOrder, flatDisplayComments: flatDisplayComments)
             cachedDetails[itemId] = detailsToCache
             infoLoadingStatus[itemId] = .loaded
             Self.logger.info("Successfully loaded/prepared FLAT hierarchy for item \(itemId). Count: \(flatDisplayComments.count)")
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
        return flatList // Ensure return statement is present
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
            Task { await settings.markItemAsSeen(id: initialItem.id) }
        } else { Self.logger.warning("onAppear: Invalid selectedIndex \(selectedIndex).") }
    }

    private func cleanupView() {
        Self.logger.info("PagedDetailView disappearing.")
        keyboardActionHandler.selectNextAction = nil; keyboardActionHandler.selectPreviousAction = nil
        if !isFullscreen { playerManager.cleanupPlayer() }
        else { Self.logger.info("Skipping player cleanup (entering fullscreen).") }
        showAllTagsForItem = []
    }

    private func handleIndexChange(oldValue: Int, newValue: Int) {
         guard !isCorrectingIndex else { return }
         Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
         guard newValue >= 0 && newValue < items.count else { return }
         let newItem = items[newValue]
         if settings.hideSeenItems && settings.seenItemIDs.contains(newItem.id) {
              Self.logger.debug("Index -> \(newValue), item hidden. Correcting...")
              isCorrectingIndex = true
              let directionForward = newValue > oldValue
              let targetIndex = directionForward ? findNextVisibleIndex(from: newValue, in: items, settings: settings)
                                                 : findPreviousVisibleIndex(from: newValue, in: items, settings: settings)
              DispatchQueue.main.async {
                 if self.selectedIndex == newValue {
                     if let correctedIndex = targetIndex { self.selectedIndex = correctedIndex }
                     else { self.selectedIndex = oldValue; Self.logger.warning("No visible item found, snapping back.") }
                 }
                 self.isCorrectingIndex = false
              }
         } else {
              Self.logger.debug("Index -> \(newValue), item visible. Performing actions.")
              playerManager.setupPlayerIfNeeded(for: newItem, isFullscreen: isFullscreen)
              Task { await loadInfoIfNeededAndPrepareHierarchy(for: newItem) }
              Task { await settings.markItemAsSeen(id: newItem.id) }
              isTogglingFavorite = false
         }
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
             if !isFullscreen, let player = playerManager.player, player.timeControlStatus == .playing {
                 player.pause()
             }
         }
    }

    private func handleSortOrderChange(newOrder: CommentSortOrder) {
         Self.logger.info("Sort order changed to \(newOrder.displayName). Recalculating visible flat lists.")
         var updatedCache: [Int: CachedItemDetails] = [:]
         for (id, details) in cachedDetails where details.sortedBy != newOrder {
              let newFlatList = prepareFlatDisplayComments(from: details.info.comments, sortedBy: newOrder, maxDepth: commentMaxDepth)
              updatedCache[id] = CachedItemDetails(info: details.info, sortedBy: newOrder, flatDisplayComments: newFlatList)
         }
         cachedDetails.merge(updatedCache) { (_, new) in new }
    }

    private func handleHideSeenChange(newValue: Bool) {
         Self.logger.info("Hide seen items setting changed to \(newValue).")
         guard !isCorrectingIndex, newValue, selectedIndex >= 0 && selectedIndex < items.count, settings.seenItemIDs.contains(items[selectedIndex].id) else { return }
         Self.logger.debug("Current item \(items[selectedIndex].id) became hidden. Navigating away.")
         isCorrectingIndex = true
         let targetIndex = findPreviousVisibleIndex(from: selectedIndex, in: items, settings: settings)
                        ?? findNextVisibleIndex(from: selectedIndex, in: items, settings: settings)
         DispatchQueue.main.async {
             if let visibleIndex = targetIndex { self.selectedIndex = visibleIndex }
             else { Self.logger.warning("No visible items left nearby after hiding.") }
             self.isCorrectingIndex = false
         }
    }

    private func handleEndFullScreen() {
         self.isFullscreen = false
         Self.logger.debug("[View] Callback: handleEndFullScreen")
         if selectedIndex >= 0 && selectedIndex < items.count, items[selectedIndex].isVideo, items[selectedIndex].id == playerManager.playerItemID {
             Task { @MainActor in
                 try? await Task.sleep(for: .milliseconds(100))
                 if !self.isFullscreen && self.playerManager.player?.timeControlStatus != .playing {
                     self.playerManager.player?.play()
                 }
             }
         }
    }

    // MARK: - Navigation and Actions
    private func selectNext() {
        if let nextIndex = findNextVisibleIndex(from: selectedIndex, in: items, settings: settings) {
             selectedIndex = nextIndex
        } else { Self.logger.debug("selectNext: End reached.") }
    }

    private var canSelectNext: Bool {
        return findNextVisibleIndex(from: selectedIndex, in: items, settings: settings) != nil
    }

    private func selectPrevious() {
        if let prevIndex = findPreviousVisibleIndex(from: selectedIndex, in: items, settings: settings) {
             selectedIndex = prevIndex
        } else { Self.logger.debug("selectPrevious: Start reached.") }
    }

    private var canSelectPrevious: Bool {
        return findPreviousVisibleIndex(from: selectedIndex, in: items, settings: settings) != nil
    }

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

// MARK: - Global Helper Functions (Marked @MainActor)
@MainActor fileprivate func findNextVisibleIndex(from currentIndex: Int, in items: [Item], settings: AppSettings) -> Int? {
    guard currentIndex < items.count - 1 else { return nil }
    if settings.hideSeenItems {
        for i in (currentIndex + 1)..<items.count { if !settings.seenItemIDs.contains(items[i].id) { return i } }
        return nil
    } else { return currentIndex + 1 }
}
@MainActor fileprivate func findPreviousVisibleIndex(from currentIndex: Int, in items: [Item], settings: AppSettings) -> Int? {
    guard currentIndex > 0 else { return nil }
    if settings.hideSeenItems {
        for i in (0..<currentIndex).reversed() { if !settings.seenItemIDs.contains(items[i].id) { return i } }
        return nil
    } else { return currentIndex - 1 }
}

// MARK: - Helper Extension & Wrapper View
// No longer needed as we use direct index checking
// extension Collection { /* ... */ }

struct LinkedItemPreviewWrapperView: View {
    let itemID: Int
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            LinkedItemPreviewView(itemID: itemID)
                .environmentObject(settings)
                .environmentObject(authService)
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

    return NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 0, playerManager: previewPlayerManager)
    }
    .environmentObject(previewSettings)
    .environmentObject(previewAuthService)
}

// --- END OF COMPLETE FILE ---
