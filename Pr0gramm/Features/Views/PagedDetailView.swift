// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit
import Kingfisher // Import Kingfisher for Prefetcher

// PreviewLinkTarget and FullscreenImageTarget remain unchanged
struct PreviewLinkTarget: Identifiable, Equatable { let id: Int }
struct FullscreenImageTarget: Identifiable, Equatable {
    let item: Item; var id: Int { item.id }
    static func == (lhs: FullscreenImageTarget, rhs: FullscreenImageTarget) -> Bool { lhs.item.id == rhs.item.id }
}

// Cache Structure for Item Details remains unchanged
struct CachedItemDetails {
    let info: ItemsInfoResponse
    let sortedBy: CommentSortOrder
    let flatDisplayComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int
}


// PagedDetailTabViewItem remains unchanged
@MainActor
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    @ObservedObject var playerManager: VideoPlayerManager

    let visibleFlatComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool
    let infoLoadingStatus: InfoLoadingStatus
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void
    let collapsedCommentIDs: Set<Int>
    let toggleCollapseAction: (Int) -> Void

    @EnvironmentObject private var settings: AppSettings

    private func isCommentCollapsed(_ commentID: Int) -> Bool {
        collapsedCommentIDs.contains(commentID)
    }

    private var currentPlayerForView: AVPlayer? {
        return item.id == playerManager.playerItemID ? playerManager.player : nil
    }

    var body: some View {
        DetailViewContent(
            item: item,
            keyboardActionHandler: keyboardActionHandler,
            player: currentPlayerForView,
            currentSubtitleText: playerManager.currentSubtitleText,
            onWillBeginFullScreen: onWillBeginFullScreen,
            onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: displayedTags, totalTagCount: totalTagCount, showingAllTags: showingAllTags,
            flatComments: visibleFlatComments,
            totalCommentCount: totalCommentCount,
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget, fullscreenImageTarget: $fullscreenImageTarget,
            isFavorited: isFavorited, toggleFavoriteAction: toggleFavoriteAction,
            showAllTagsAction: showAllTagsAction,
            isCommentCollapsed: isCommentCollapsed,
            toggleCollapseAction: toggleCollapseAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
             PagedDetailView.logger.trace("PagedDetailTabViewItem appeared for item \(item.id)")
        }
         .overlay(alignment: .top) {
             if let subtitleError = playerManager.subtitleError, playerManager.playerItemID == item.id {
                 Text("Untertitel: \(subtitleError)")
                     .font(.caption)
                     .foregroundColor(.orange)
                     .padding(5)
                     .background(Material.ultraThin)
                     .cornerRadius(5)
                     .transition(.opacity.combined(with: .move(edge: .top)))
                     .padding(.top, 5)
                     .onAppear {
                         PagedDetailView.logger.warning("Subtitle error displayed for item \(item.id): \(subtitleError)")
                     }
             }
         }
    }
}


// MARK: - PagedDetailView
@MainActor
struct PagedDetailView: View {
    @Binding var items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Access AuthService
    @Environment(\.scenePhase) var scenePhase
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

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
    @State private var localFavoritedStatus: [Int: Bool] = [:] // Keep for immediate UI feedback
    @State private var newlyVisitedItemIDsThisSession: Set<Int> = []
    @State private var collapsedCommentIDs: Set<Int> = []

    let loadMoreAction: () async -> Void
    let commentMaxDepth = 5
    let preloadThreshold = 5
    let prefetchLookahead = 3
    let swipeSettleDelay: Duration = .milliseconds(200)

    @State private var imagePrefetcher = ImagePrefetcher(urls: [])

    init(items: Binding<[Item]>, selectedIndex: Int, playerManager: VideoPlayerManager, loadMoreAction: @escaping () async -> Void) {
        self._items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        self.playerManager = playerManager
        self.loadMoreAction = loadMoreAction
        // localFavoritedStatus starts empty
        PagedDetailView.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    private var isCurrentItemFavorited: Bool {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return false }
        let currentItemID = items[selectedIndex].id
        // 1. Check local override first (for instant UI feedback during toggle)
        if let localStatus = localFavoritedStatus[currentItemID] {
            return localStatus
        }
        // 2. Check the global set in AuthService
        return authService.favoritedItemIDs.contains(currentItemID)
    }

    // MARK: - Body
    var body: some View {
        Group { tabViewContent }
        .background(KeyCommandView(handler: keyboardActionHandler))
        .sheet(item: $previewLinkTarget) { targetWrapper in
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings).environmentObject(authService)
        }
        .onChange(of: previewLinkTarget) { oldValue, newValue in
            if newValue != nil {
                PagedDetailView.logger.info("Link preview requested for item ID \(newValue!.id). Pausing current video (if playing).")
                playerManager.player?.pause()
            }
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
             ToolbarItem(placement: .principal) {
                 Text(currentItemTitle)
                     .font(.headline)
                     .lineLimit(1)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 if selectedIndex >= 0 && selectedIndex < items.count && settings.seenItemIDs.contains(items[selectedIndex].id) {
                     Image(systemName: "checkmark.circle.fill")
                         .symbolRenderingMode(.palette)
                         .foregroundStyle(.white, Color.accentColor)
                         .font(.body)
                 } else {
                     EmptyView()
                 }
             }
        }
        .onChange(of: selectedIndex) { oldValue, newValue in
            handleIndexChangeImmediate(oldValue: oldValue, newValue: newValue)
            Task {
                try? await Task.sleep(for: swipeSettleDelay)
                if self.selectedIndex == newValue {
                     await handleIndexChangeDeferred(newValue: newValue)
                } else {
                    PagedDetailView.logger.debug("Deferred actions skipped for index \(newValue), selection changed again during settle delay.")
                }
            }
             Task { await triggerLoadMoreIfNeeded(currentIndex: newValue) }
        }
        .onAppear { setupView() }
        .onDisappear { cleanupViewAndMarkVisited() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
             handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
        .onChange(of: settings.commentSortOrder) { oldOrder, newOrder in
             handleSortOrderChange(newOrder: newOrder)
        }
        .onChange(of: items.count) { _, newCount in
             PagedDetailView.logger.info("Detected change in items count from binding. New count: \(newCount)")
         }
    }

    @ViewBuilder
    private func tabViewPage(for index: Int) -> some View {
        if index >= 0 && index < items.count {
            let currentItem = items[index]
            let pageData = preparePageData(for: index)

            if let data = pageData {
                 PagedDetailTabViewItem(
                     item: currentItem,
                     keyboardActionHandler: keyboardActionHandler,
                     playerManager: playerManager,
                     visibleFlatComments: data.visibleFlatComments,
                     totalCommentCount: data.totalCommentCount,
                     displayedTags: data.displayedTags,
                     totalTagCount: data.totalTagCount,
                     showingAllTags: data.showingAllTags,
                     infoLoadingStatus: data.status,
                     onWillBeginFullScreen: { self.isFullscreen = true },
                     onWillEndFullScreen: handleEndFullScreen,
                     previewLinkTarget: $previewLinkTarget,
                     fullscreenImageTarget: $fullscreenImageTarget,
                     isFavorited: isCurrentItemFavorited, // Use the updated computed property
                     toggleFavoriteAction: toggleFavorite,
                     showAllTagsAction: { showAllTagsForItem.insert(currentItem.id) },
                     collapsedCommentIDs: collapsedCommentIDs,
                     toggleCollapseAction: toggleCollapse
                 )
                 .tag(index)
            } else {
                EmptyView().tag(index)
                     .onAppear { PagedDetailView.logger.warning("preparePageData returned nil for index \(index).") }
            }
        } else {
             EmptyView().tag(index)
                  .onAppear { PagedDetailView.logger.error("Attempted to render tabViewPage for invalid index \(index) (items.count: \(items.count)).") }
        }
    }


    // MARK: - Data Preparation and Loading
    private func preparePageData(for index: Int) -> ( currentItem: Item, status: InfoLoadingStatus, visibleFlatComments: [FlatCommentDisplayItem], totalCommentCount: Int, displayedTags: [ItemTag], totalTagCount: Int, showingAllTags: Bool )? {
        guard index >= 0 && index < items.count else { PagedDetailView.logger.warning("preparePageData: index \(index) out of bounds (items.count: \(items.count))."); return nil }
        let currentItem = items[index]
        let itemId = currentItem.id
        let statusForItem = infoLoadingStatus[itemId] ?? .idle
        let visibleComments = calculateVisibleComments(for: itemId)
        var finalTotalCommentCount = 0
        var finalSortedTags: [ItemTag] = []

        if let cached = cachedDetails[itemId] {
            finalTotalCommentCount = cached.totalCommentCount
            finalSortedTags = cached.info.tags
        } else if statusForItem == .loaded {
             PagedDetailView.logger.warning("preparePageData: Status loaded for \(itemId), no cached details.")
        }

        let totalTagCount = finalSortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay = shouldShowAll ? finalSortedTags : Array(finalSortedTags.prefix(4))

        return (currentItem, statusForItem, visibleComments, finalTotalCommentCount, tagsToDisplay, totalTagCount, shouldShowAll)
    }

    private func loadInfoIfNeededAndPrepareHierarchy(for item: Item) async {
         let itemId = item.id
         let currentStatus = infoLoadingStatus[itemId]
         if let cached = cachedDetails[itemId], currentStatus == .loaded {
             if cached.sortedBy == settings.commentSortOrder { return }
             else {
                  PagedDetailView.logger.info("loadInfoIfNeeded: Recalculating flat list for cached item \(itemId) due to sort order change.")
                  let newFlatList = prepareFlatDisplayComments(from: cached.info.comments, sortedBy: settings.commentSortOrder, maxDepth: commentMaxDepth)
                  cachedDetails[itemId] = CachedItemDetails(info: cached.info, sortedBy: settings.commentSortOrder, flatDisplayComments: newFlatList, totalCommentCount: cached.totalCommentCount)
                  return
             }
         }
         guard !(currentStatus == .loading) else { return }
         if case .error = currentStatus { PagedDetailView.logger.debug("Retrying info load for item \(itemId).") }
         PagedDetailView.logger.debug("Starting info load & FULL FLAT prep for item \(itemId)...")
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
             PagedDetailView.logger.info("Successfully loaded/prepared FULL FLAT hierarchy (\(flatDisplayComments.count) items shown initially) for item \(itemId). Total raw: \(totalCommentCount).")
         } catch {
             PagedDetailView.logger.error("Failed load/prep FULL FLAT hierarchy for item \(itemId): \(error.localizedDescription)")
             infoLoadingStatus[itemId] = .error(error.localizedDescription)
         }
    }

    private func prepareFlatDisplayComments(from comments: [ItemComment], sortedBy sortOrder: CommentSortOrder, maxDepth: Int) -> [FlatCommentDisplayItem] {
        PagedDetailView.logger.debug("Preparing FULL FLAT display comments (\(comments.count) raw), sort: \(sortOrder.displayName), depth: \(maxDepth).")
        let startTime = Date()
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })

        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            let children = childrenByParentId[commentId] ?? []
            let hasChildren = !children.isEmpty
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren))
            guard currentLevel < maxDepth else { return }
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
        PagedDetailView.logger.info("Finished preparing FULL FLAT comments (\(flatList.count) items) in \(String(format: "%.3f", duration))s.")
        return flatList
    }

    private func calculateVisibleComments(for itemID: Int) -> [FlatCommentDisplayItem] {
         guard let details = cachedDetails[itemID] else { return [] }
         let fullList = details.flatDisplayComments
         guard !collapsedCommentIDs.isEmpty else { return fullList }
         var visibleList: [FlatCommentDisplayItem] = []
         var nearestCollapsedAncestorLevel: [Int: Int] = [:]

         for item in fullList {
             let currentLevel = item.level
             var isHiddenByAncestor = false

             if currentLevel > 0 {
                 for ancestorLevel in 0..<currentLevel {
                     if nearestCollapsedAncestorLevel[ancestorLevel] != nil {
                         isHiddenByAncestor = true
                         nearestCollapsedAncestorLevel[currentLevel] = nearestCollapsedAncestorLevel[ancestorLevel]
                         break
                     }
                 }
             }

             if isHiddenByAncestor { continue }
             visibleList.append(item)

             if collapsedCommentIDs.contains(item.id) { nearestCollapsedAncestorLevel[currentLevel] = item.id }
             else { nearestCollapsedAncestorLevel.removeValue(forKey: currentLevel) }

             let keysToRemove = nearestCollapsedAncestorLevel.keys.filter { $0 > currentLevel }
             for key in keysToRemove { nearestCollapsedAncestorLevel.removeValue(forKey: key) }
         }
         return visibleList
    }

    // MARK: - View Lifecycle and State Handling Helpers
    private func setupView() {
        PagedDetailView.logger.info("PagedDetailView appeared.")
        if isFullscreen { isFullscreen = false }
        isTogglingFavorite = false
        keyboardActionHandler.selectNextAction = self.selectNext
        keyboardActionHandler.selectPreviousAction = self.selectPrevious
        keyboardActionHandler.seekForwardAction = playerManager.seekForward
        keyboardActionHandler.seekBackwardAction = playerManager.seekBackward
        Task {
            if selectedIndex >= 0 && selectedIndex < items.count {
                 let initialItem = items[selectedIndex]
                 playerManager.setupPlayerIfNeeded(for: initialItem, isFullscreen: isFullscreen)
                 newlyVisitedItemIDsThisSession.insert(initialItem.id)
                 PagedDetailView.logger.debug("Added initial item \(initialItem.id) to visited set.")
                 await handleIndexChangeDeferred(newValue: selectedIndex)
            } else {
                 PagedDetailView.logger.warning("onAppear: Invalid selectedIndex \(selectedIndex) for items count \(items.count).")
            }
        }
    }

    private func cleanupViewAndMarkVisited() {
        PagedDetailView.logger.info("PagedDetailView disappearing.")
        imagePrefetcher.stop()
        keyboardActionHandler.selectNextAction = nil
        keyboardActionHandler.selectPreviousAction = nil
        keyboardActionHandler.seekForwardAction = nil
        keyboardActionHandler.seekBackwardAction = nil
        if !isFullscreen { playerManager.cleanupPlayer() }
        else { PagedDetailView.logger.info("Skipping player cleanup (fullscreen).") }
        showAllTagsForItem = []
        let visitedIDs = self.newlyVisitedItemIDsThisSession
        if !visitedIDs.isEmpty {
            Task {
                PagedDetailView.logger.info("Marking \(visitedIDs.count) visited items as seen (batch)...")
                await settings.markItemsAsSeen(ids: visitedIDs)
                PagedDetailView.logger.info("Finished marking visited items (batch).")
            }
        }
        newlyVisitedItemIDsThisSession = []
    }

    private func handleIndexChangeImmediate(oldValue: Int, newValue: Int) {
        PagedDetailView.logger.info("Selected index changed from \(oldValue) to \(newValue)")
        guard newValue >= 0 && newValue < items.count else {
             PagedDetailView.logger.warning("handleIndexChangeImmediate: Invalid new index \(newValue) (items.count: \(items.count)).")
             return
        }
        let newItem = items[newValue]
        PagedDetailView.logger.debug("Immediate actions for index change to \(newValue). Setting up player and marking visited.")
        playerManager.setupPlayerIfNeeded(for: newItem, isFullscreen: isFullscreen)
        newlyVisitedItemIDsThisSession.insert(newItem.id)
        isTogglingFavorite = false
        imagePrefetcher.stop()
    }

    private func handleIndexChangeDeferred(newValue: Int) async {
         PagedDetailView.logger.debug("Deferred actions executing for index \(newValue).")
         guard newValue >= 0 && newValue < items.count else {
             PagedDetailView.logger.warning("handleIndexChangeDeferred: Invalid index \(newValue) (items.count: \(items.count)).")
             return
         }
         let currentItem = items[newValue]
         await loadInfoIfNeededAndPrepareHierarchy(for: currentItem)
         var urlsToPrefetch: [URL] = []
         let startIndex = max(0, newValue - prefetchLookahead)
         let endIndex = min(items.count - 1, newValue + prefetchLookahead)
         if startIndex <= endIndex {
             for i in startIndex...endIndex {
                 if !items[i].isVideo, let imageUrl = items[i].imageUrl { urlsToPrefetch.append(imageUrl) }
                 if let thumbUrl = items[i].thumbnailUrl { urlsToPrefetch.append(thumbUrl) }
             }
         }
         if !urlsToPrefetch.isEmpty {
             PagedDetailView.logger.info("Starting prefetch for \(urlsToPrefetch.count) URLs around index \(newValue).")
             imagePrefetcher = ImagePrefetcher(urls: urlsToPrefetch)
             imagePrefetcher.start()
         } else {
             PagedDetailView.logger.debug("No valid URLs to prefetch around index \(newValue).")
         }
         async let loadNextTask: () = { if await newValue + 1 < items.count { await loadInfoIfNeededAndPrepareHierarchy(for: items[newValue + 1]) } }()
         async let loadPrevTask: () = { if newValue > 0 { await loadInfoIfNeededAndPrepareHierarchy(for: items[newValue - 1]) } }()
         _ = await [loadNextTask, loadPrevTask]
         PagedDetailView.logger.debug("Finished loading adjacent item info for index \(newValue).")
     }

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
          PagedDetailView.logger.debug("Scene phase: \(String(describing: oldPhase)) -> \(String(describing: newPhase))")
          if newPhase == .active {
              settings.transientSessionMuteState = nil
              if let player = playerManager.player, player.isMuted != settings.isVideoMuted { player.isMuted = settings.isVideoMuted }
               if isFullscreen, let player = playerManager.player, player.timeControlStatus != .playing { player.play() }
          } else if newPhase == .inactive || newPhase == .background {
              if (!isFullscreen && previewLinkTarget == nil), let player = playerManager.player, player.timeControlStatus == .playing {
                  PagedDetailView.logger.debug("Scene became inactive/background. Pausing player (not fullscreen, no link preview).")
                  player.pause()
              } else {
                  PagedDetailView.logger.debug("Scene became inactive/background. NOT pausing player (is fullscreen or link preview is active).")
              }
          }
     }

    private func handleSortOrderChange(newOrder: CommentSortOrder) {
          PagedDetailView.logger.info("Sort order changed to \(newOrder.displayName). Recalculating cached flat lists.")
          var updatedCache: [Int: CachedItemDetails] = [:]
          for (id, details) in cachedDetails where details.sortedBy != newOrder {
               let newFlatList = prepareFlatDisplayComments(from: details.info.comments, sortedBy: newOrder, maxDepth: commentMaxDepth)
               updatedCache[id] = CachedItemDetails(info: details.info, sortedBy: newOrder, flatDisplayComments: newFlatList, totalCommentCount: details.totalCommentCount)
          }
          cachedDetails.merge(updatedCache) { (_, new) in new }
          if selectedIndex >= 0 && selectedIndex < items.count {
              let currentItemID = items[selectedIndex].id
              infoLoadingStatus[currentItemID] = .idle
              Task { await loadInfoIfNeededAndPrepareHierarchy(for: items[selectedIndex]) }
          } else {
              PagedDetailView.logger.warning("Cannot force comment refresh after sort order change: invalid selectedIndex \(selectedIndex).")
          }
     }

    private func handleEndFullScreen() {
          self.isFullscreen = false
          PagedDetailView.logger.debug("[View] Callback: handleEndFullScreen")
          if selectedIndex >= 0 && selectedIndex < items.count,
             items[selectedIndex].isVideo,
             items[selectedIndex].id == playerManager.playerItemID {
              Task { @MainActor in
                  try? await Task.sleep(for: .milliseconds(100))
                  if !self.isFullscreen && self.previewLinkTarget == nil && self.playerManager.player?.timeControlStatus != .playing {
                      PagedDetailView.logger.debug("Resuming player after ending fullscreen (preview not active).")
                      self.playerManager.player?.play()
                  } else {
                      PagedDetailView.logger.debug("NOT resuming player after ending fullscreen (preview is active or player already playing/paused).")
                  }
              }
          }
     }

    private func triggerLoadMoreIfNeeded(currentIndex: Int) async {
          guard currentIndex >= items.count - preloadThreshold else { return }
          PagedDetailView.logger.info("Approaching end of list (index \(currentIndex)/\(items.count - 1)). Triggering load more action...")
          await loadMoreAction()
     }

    // MARK: - Navigation and Actions
    private func selectNext() {
        guard selectedIndex < items.count - 1 else { return }
        selectedIndex += 1
    }

    private func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
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
        guard !isTogglingFavorite else { PagedDetailView.logger.debug("Favorite toggle skipped: Already processing."); return }
        guard selectedIndex >= 0 && selectedIndex < items.count else { PagedDetailView.logger.warning("Favorite toggle skipped: Invalid selectedIndex \(selectedIndex)."); return }
        let currentItem = items[selectedIndex]
        guard authService.isLoggedIn, let nonce = authService.userNonce, let collectionId = authService.favoritesCollectionId else { PagedDetailView.logger.warning("Favorite toggle skipped: User not logged in or nonce/collectionId missing."); return }
        let itemId = currentItem.id
        let targetFavoriteState = !isCurrentItemFavorited // Determine target based on computed property

        isTogglingFavorite = true
        localFavoritedStatus[itemId] = targetFavoriteState // Optimistic local UI update

        do {
            if targetFavoriteState {
                try await apiService.addToCollection(itemId: itemId, nonce: nonce)
                PagedDetailView.logger.info("Added item \(itemId) to favorites via API.")
            } else {
                try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
                PagedDetailView.logger.info("Removed item \(itemId) from favorites via API.")
            }

            // Update global state on success
            if targetFavoriteState {
                authService.favoritedItemIDs.insert(itemId)
            } else {
                authService.favoritedItemIDs.remove(itemId)
            }

            // Clear remote favorites cache (if needed, depends if other views rely on it)
            await localSettings.clearFavoritesCache()
            await localSettings.updateCacheSizes()
            PagedDetailView.logger.info("Favorite toggled successfully for item \(itemId). Global state updated. Cache cleared.")

        } catch {
            PagedDetailView.logger.error("Failed to toggle favorite for item \(itemId): \(error.localizedDescription)")
            // Revert optimistic UI update on failure
            localFavoritedStatus.removeValue(forKey: itemId) // Remove local override on error
        }
        isTogglingFavorite = false
    }

    private func toggleCollapse(commentID: Int) {
        if collapsedCommentIDs.contains(commentID) {
            collapsedCommentIDs.remove(commentID)
            PagedDetailView.logger.trace("Expanding comment \(commentID)")
        } else {
            collapsedCommentIDs.insert(commentID)
            PagedDetailView.logger.trace("Collapsing comment \(commentID)")
        }
    }
}


// MARK: - Wrapper View
struct LinkedItemPreviewWrapperView: View {
    let itemID: Int
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View {
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
    struct PreviewWrapper: View {
         @State var previewItems: [Item] = [
             Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: 1, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, subtitles: nil, favorited: false),
             Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: 2, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, subtitles: nil, favorited: true),
             Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: 3, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, subtitles: nil, favorited: nil),
             Item(id: 4, promoted: 1004, userId: 3, down: 1, up: 10, created: 4, image: "img3.gif", thumb: "t4.gif", fullsize: nil, preview: nil, width: 500, height: 300, audio: false, source: nil, flags: 1, user: "UserC", mark: 0, repost: nil, variants: nil, subtitles: nil, favorited: false)
         ]
         @StateObject var previewSettings = AppSettings()
         @StateObject var previewAuthService = AuthService(appSettings: AppSettings())
         @StateObject var previewPlayerManager = VideoPlayerManager()

         func dummyLoadMore() async { print("Preview: Dummy Load More Action Triggered") }

         init() {
              previewAuthService.isLoggedIn = true
              previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
              previewAuthService.userNonce = "preview_nonce_12345"
              previewAuthService.favoritesCollectionId = 6749
              // Populate global favorites for preview
              previewAuthService.favoritedItemIDs = [2] // Mark item 2 as favorited
              previewPlayerManager.configure(settings: previewSettings)
         }

         var body: some View {
             NavigationStack {
                 PagedDetailView(
                    items: $previewItems,
                    selectedIndex: 0,
                    playerManager: previewPlayerManager,
                    loadMoreAction: dummyLoadMore
                 )
             }
             .environmentObject(previewSettings)
             .environmentObject(previewAuthService)
             .task {
                 await previewSettings.markItemsAsSeen(ids: [1,3])
                 print("Preview Task: Items marked as seen.")
             }
         }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
