// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit
import Kingfisher

struct PreviewLinkTarget: Identifiable, Equatable { let id: Int }
struct FullscreenImageTarget: Identifiable, Equatable {
    let item: Item; var id: Int { item.id }
    static func == (lhs: FullscreenImageTarget, rhs: FullscreenImageTarget) -> Bool { lhs.item.id == rhs.item.id }
}

struct UserProfileSheetTarget: Identifiable, Equatable {
    let username: String
    var id: String { username }
}

struct CollectionSelectionSheetTarget: Identifiable, Equatable {
    let id = UUID()
    let item: Item

    static func == (lhs: CollectionSelectionSheetTarget, rhs: CollectionSelectionSheetTarget) -> Bool {
        lhs.id == rhs.id && lhs.item.id == rhs.item.id
    }
}


struct CachedItemDetails {
    let info: ItemsInfoResponse
    let sortedBy: CommentSortOrder
    let flatDisplayComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int
}

struct ReplyTarget: Identifiable {
    let id = UUID()
    let itemId: Int
    let parentId: Int
}

@MainActor
struct PagedDetailTabViewItem: View {
    struct DataModel {
        let item: Item
        let visibleFlatComments: [FlatCommentDisplayItem]
        let totalCommentCount: Int
        let displayedTags: [ItemTag]
        let totalTagCount: Int
        let showingAllTags: Bool
        let infoLoadingStatus: InfoLoadingStatus
        let currentSubtitleText: String?
        let isFavorited: Bool
        let currentVote: Int
        let collapsedCommentIDs: Set<Int>
        let targetCommentID: Int?
    }

    let dataModel: DataModel
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    @ObservedObject var playerManager: VideoPlayerManager

    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    let toggleFavoriteAction: () async -> Void
    let showCollectionSelectionAction: () -> Void
    let showAllTagsAction: () -> Void
    let toggleCollapseAction: (Int) -> Void
    let upvoteAction: () -> Void
    let downvoteAction: () -> Void
    let showCommentInputAction: (Int, Int) -> Void
    let onHighlightCompletedForCommentID: (Int) -> Void
    // --- NEW: Callbacks für Tag-Voting ---
    let upvoteTagAction: (Int) -> Void // tagId
    let downvoteTagAction: (Int) -> Void // tagId
    // --- END NEW ---


    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var userProfileSheetTarget: UserProfileSheetTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?

    private func isCommentCollapsed(_ commentID: Int) -> Bool {
        dataModel.collapsedCommentIDs.contains(commentID)
    }

    var body: some View {
        DetailViewContent(
            item: dataModel.item,
            keyboardActionHandler: keyboardActionHandler,
            playerManager: playerManager,
            currentSubtitleText: dataModel.currentSubtitleText,
            onWillBeginFullScreen: onWillBeginFullScreen,
            onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: dataModel.displayedTags,
            totalTagCount: dataModel.totalTagCount,
            showingAllTags: dataModel.showingAllTags,
            flatComments: dataModel.visibleFlatComments,
            totalCommentCount: dataModel.totalCommentCount,
            infoLoadingStatus: dataModel.infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget,
            userProfileSheetTarget: $userProfileSheetTarget,
            fullscreenImageTarget: $fullscreenImageTarget,
            isFavorited: dataModel.isFavorited,
            toggleFavoriteAction: toggleFavoriteAction,
            showCollectionSelectionAction: showCollectionSelectionAction,
            showAllTagsAction: showAllTagsAction,
            isCommentCollapsed: isCommentCollapsed,
            toggleCollapseAction: toggleCollapseAction,
            currentVote: dataModel.currentVote,
            upvoteAction: upvoteAction,
            downvoteAction: downvoteAction,
            showCommentInputAction: showCommentInputAction,
            targetCommentID: dataModel.targetCommentID,
            onHighlightCompletedForCommentID: onHighlightCompletedForCommentID,
            // --- NEW: Pass tag vote actions ---
            upvoteTagAction: upvoteTagAction,
            downvoteTagAction: downvoteTagAction
            // --- END NEW ---
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
             PagedDetailView.logger.trace("PagedDetailTabViewItem appeared for item \(dataModel.item.id)")
        }
         .overlay(alignment: .top) {
             if let subtitleError = playerManager.subtitleError, playerManager.playerItemID == dataModel.item.id {
                 Text("Untertitel: \(subtitleError)")
                     .font(.caption)
                     .foregroundColor(.orange)
                     .padding(5)
                     .background(Material.ultraThin)
                     .cornerRadius(5)
                     .transition(.opacity.combined(with: .move(edge: .top)))
                     .padding(.top, 5)
                     .onAppear {
                         PagedDetailView.logger.warning("Subtitle error displayed for item \(dataModel.item.id): \(subtitleError)")
                     }
             }
         }
    }
}

@MainActor
struct PagedDetailView: View {
    @Binding var items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    @ObservedObject var playerManager: VideoPlayerManager
    @State private var isFullscreen = false
    @State private var cachedDetails: [Int: CachedItemDetails] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    @State private var showAllTagsForItem: Set<Int> = []
    private let apiService = APIService()

    @State private var previewLinkTarget: PreviewLinkTarget? = nil
    @State private var userProfileSheetTarget: UserProfileSheetTarget? = nil
    @State private var wasPlayingBeforeAnySheet: Bool = false
    @State private var fullscreenImageTarget: FullscreenImageTarget? = nil
    @State private var collectionSelectionSheetTarget: CollectionSelectionSheetTarget? = nil

    @State private var isTogglingFavorite = false
    @State private var localFavoritedStatus: [Int: Bool] = [:]
    @State private var collapsedCommentIDs: Set<Int> = []
    @State private var commentReplyTarget: ReplyTarget? = nil

    @State private var previouslySelectedItemForMarking: Item? = nil
    @State private var currentItemTargetCommentID: Int?

    let loadMoreAction: () async -> Void
    let commentMaxDepth = 5
    let preloadThreshold = 5
    let prefetchLookahead = 3
    let swipeSettleDelay: Duration = .milliseconds(200)

    @State private var imagePrefetcher = ImagePrefetcher(urls: [])

    init(items: Binding<[Item]>, selectedIndex: Int, playerManager: VideoPlayerManager, loadMoreAction: @escaping () async -> Void, initialTargetCommentID: Int? = nil) {
        self._items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        self.playerManager = playerManager
        self.loadMoreAction = loadMoreAction
        self._currentItemTargetCommentID = State(initialValue: initialTargetCommentID)

        if selectedIndex >= 0 && selectedIndex < items.wrappedValue.count {
            self._previouslySelectedItemForMarking = State(initialValue: items.wrappedValue[selectedIndex])
        }
        PagedDetailView.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex), initialTargetCommentID: \(initialTargetCommentID ?? -1)")
    }

    var body: some View {
        tabViewContent
        .background(KeyCommandView(handler: keyboardActionHandler))
        .sheet(item: $previewLinkTarget, onDismiss: resumePlayerIfNeeded) { targetWrapper in
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings).environmentObject(authService)
        }
        .sheet(item: $userProfileSheetTarget, onDismiss: resumePlayerIfNeeded) { target in
            UserProfileSheetView(username: target.username)
                .environmentObject(authService)
                .environmentObject(settings)
        }
        .sheet(item: $fullscreenImageTarget, onDismiss: resumePlayerIfNeeded) { targetWrapper in
             FullscreenImageView(item: targetWrapper.item)
        }
        .sheet(item: $collectionSelectionSheetTarget, onDismiss: resumePlayerIfNeeded) { target in
            CollectionSelectionView(
                item: target.item,
                onCollectionSelected: { selectedCollection in
                    Task {
                        await addCurrentItemToSelectedCollection(collection: selectedCollection)
                    }
                }
            )
            .environmentObject(authService)
            .environmentObject(settings)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $commentReplyTarget) { target in
            CommentInputView(
                itemId: target.itemId,
                parentId: target.parentId,
                onSubmit: { commentText in
                    try await submitComment(text: commentText, itemId: target.itemId, parentId: target.parentId)
                }
            )
             .presentationDetents([.medium, .large])
        }
        .onChange(of: previewLinkTarget) { _, newValue in
            if newValue != nil { pausePlayerForSheet() }
        }
        .onChange(of: userProfileSheetTarget) { _, newValue in
            if newValue != nil { pausePlayerForSheet() }
        }
        .onChange(of: fullscreenImageTarget) { _, newValue in
            if newValue != nil { pausePlayerForSheet() }
        }
        .onChange(of: collectionSelectionSheetTarget) { _, newValue in
            if newValue != nil { pausePlayerForSheet() }
        }
        .onChange(of: horizontalSizeClass) { oldValue, newValue in
            PagedDetailView.logger.error("!!! HORIZONTAL SIZE CLASS CHANGED in PagedDetailView from \(String(describing: oldValue)) to \(String(describing: newValue)) !!!")
        }
    }
    
    private func pausePlayerForSheet() {
        if playerManager.player?.timeControlStatus == .playing {
            wasPlayingBeforeAnySheet = true
            playerManager.player?.pause()
            PagedDetailView.logger.debug("Player paused because a sheet is about to open.")
        } else {
            wasPlayingBeforeAnySheet = false
        }
    }

    private func resumePlayerIfNeeded() {
        if wasPlayingBeforeAnySheet {
            if selectedIndex >= 0 && selectedIndex < items.count && items[selectedIndex].isVideo && items[selectedIndex].id == playerManager.playerItemID {
                if !isFullscreen {
                    playerManager.player?.play()
                    PagedDetailView.logger.debug("Player resumed after sheet dismissed (not fullscreen).")
                } else {
                    PagedDetailView.logger.debug("Sheet dismissed, but view is in fullscreen. Player state managed by system.")
                }
            } else {
                PagedDetailView.logger.debug("Not resuming player: current item is not the video or player changed.")
            }
        }
        wasPlayingBeforeAnySheet = false
    }
    
    private var tabViewPages: some View {
        ForEach(items.indices, id: \.self) { index in
             tabViewPage(for: index)
                .tag(index)
        }
    }

    @ViewBuilder
    private var tabViewContent: some View {
        TabView(selection: $selectedIndex) {
            tabViewPages
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
             ToolbarItem(placement: .principal) { Text(currentItemTitle).font(.headline).lineLimit(1) }
             ToolbarItem(placement: .navigationBarTrailing) {
                 if selectedIndex >= 0 && selectedIndex < items.count && settings.seenItemIDs.contains(items[selectedIndex].id) {
                     Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).font(.body)
                 } else { EmptyView() }
             }
        }
        .onChange(of: selectedIndex) { oldValue, newValue in
            if oldValue >= 0 && oldValue < items.count {
                let previousItem = items[oldValue]
                settings.markItemAsSeen(id: previousItem.id)
                PagedDetailView.logger.info("Marked PREVIOUS item \(previousItem.id) as seen due to swipe.")
            }
            if newValue >= 0 && newValue < items.count {
                previouslySelectedItemForMarking = items[newValue]
            } else {
                previouslySelectedItemForMarking = nil
            }
            
            if oldValue != newValue {
                currentItemTargetCommentID = nil
                PagedDetailView.logger.debug("Swiped to new item, resetting currentItemTargetCommentID.")
            }

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
        .onDisappear { cleanupViewAndMarkLastActiveItemVisited() }
        .onChange(of: scenePhase) { oldPhase, newPhase in handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase) }
        .onChange(of: settings.commentSortOrder) { oldOrder, newOrder in handleSortOrderChange(newOrder: newOrder) }
        .onChange(of: items.count) { _, newCount in PagedDetailView.logger.info("Detected change in items count from binding. New count: \(newCount)") }
        .onChange(of: authService.votedItemStates) { _, _ in
            PagedDetailView.logger.trace("Detected change in authService.votedItemStates")
        }
        // --- NEW: Observe votedTagStates for UI updates ---
        .onChange(of: authService.votedTagStates) { _, _ in
            PagedDetailView.logger.trace("Detected change in authService.votedTagStates (PagedDetailView)")
        }
        // --- END NEW ---
    }

    private func preparePageData(for index: Int) -> PagedDetailTabViewItem.DataModel? {
        guard index >= 0 && index < items.count else {
            PagedDetailView.logger.warning("preparePageData: index \(index) out of bounds (items.count: \(items.count)).")
            return nil
        }
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
            PagedDetailView.logger.warning("preparePageData: Status loaded for item \(itemId), but no cached details found.")
        }

        let totalTagCount = finalSortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay = shouldShowAll ? finalSortedTags : Array(finalSortedTags.prefix(4))
        
        let currentVoteState = authService.votedItemStates[itemId] ?? 0
        let isCurrentlyFavorited = localFavoritedStatus[itemId] ?? authService.favoritedItemIDs.contains(itemId)
        let currentSubText = (playerManager.playerItemID == itemId) ? playerManager.currentSubtitleText : nil
        
        let itemSpecificTargetCommentID = (self.selectedIndex == index) ? self.currentItemTargetCommentID : nil

        return PagedDetailTabViewItem.DataModel(
            item: currentItem,
            visibleFlatComments: visibleComments,
            totalCommentCount: finalTotalCommentCount,
            displayedTags: tagsToDisplay,
            totalTagCount: totalTagCount,
            showingAllTags: shouldShowAll,
            infoLoadingStatus: statusForItem,
            currentSubtitleText: currentSubText,
            isFavorited: isCurrentlyFavorited,
            currentVote: currentVoteState,
            collapsedCommentIDs: collapsedCommentIDs,
            targetCommentID: itemSpecificTargetCommentID
        )
    }

    @ViewBuilder
    private func tabViewPage(for index: Int) -> some View {
        if let dataModel = preparePageData(for: index) {
            PagedDetailTabViewItem(
                 dataModel: dataModel,
                 keyboardActionHandler: keyboardActionHandler,
                 playerManager: playerManager,
                 onWillBeginFullScreen: { self.isFullscreen = true },
                 onWillEndFullScreen: handleEndFullScreen,
                 toggleFavoriteAction: toggleFavorite,
                 showCollectionSelectionAction: {
                     guard self.selectedIndex >= 0 && self.selectedIndex < self.items.count else { return }
                     let itemForSheet = self.items[self.selectedIndex]
                     self.collectionSelectionSheetTarget = CollectionSelectionSheetTarget(item: itemForSheet)
                 },
                 showAllTagsAction: { showAllTagsForItem.insert(dataModel.item.id) },
                 toggleCollapseAction: toggleCollapse,
                 upvoteAction: { Task { await handleVoteTap(voteType: 1) } },
                 downvoteAction: { Task { await handleVoteTap(voteType: -1) } },
                 showCommentInputAction: { itemId, parentId in
                     self.commentReplyTarget = ReplyTarget(itemId: itemId, parentId: parentId)
                     PagedDetailView.logger.debug("Setting comment reply target: itemId=\(itemId), parentId=\(parentId)")
                 },
                 onHighlightCompletedForCommentID: { completedCommentID in
                     if self.currentItemTargetCommentID == completedCommentID {
                         self.currentItemTargetCommentID = nil
                         PagedDetailView.logger.info("Highlight completed for comment \(completedCommentID), resetting currentItemTargetCommentID in PagedDetailView.")
                     }
                 },
                 // --- NEW: Pass tag vote actions ---
                 upvoteTagAction: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: 1) } },
                 downvoteTagAction: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: -1) } },
                 // --- END NEW ---
                 previewLinkTarget: $previewLinkTarget,
                 userProfileSheetTarget: $userProfileSheetTarget,
                 fullscreenImageTarget: $fullscreenImageTarget
             )
        } else {
            EmptyView()
                .onAppear {
                    PagedDetailView.logger.error("Attempted to render tabViewPage for invalid index \(index) or preparePageData failed.")
                }
        }
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

    private func setupView() {
        PagedDetailView.logger.info("PagedDetailView appeared.")
        if isFullscreen {
            PagedDetailView.logger.debug("PagedDetailView appeared, isFullscreen is true. Player state managed by system or handleEndFullScreen.")
        } else {
            PagedDetailView.logger.debug("PagedDetailView appeared, isFullscreen is false.")
        }
        isTogglingFavorite = false
        keyboardActionHandler.selectNextAction = self.selectNext
        keyboardActionHandler.selectPreviousAction = self.selectPrevious
        keyboardActionHandler.seekForwardAction = playerManager.seekForward
        keyboardActionHandler.seekBackwardAction = playerManager.seekBackward
        
        if selectedIndex >= 0 && selectedIndex < items.count {
            let initialItem = items[selectedIndex]
            playerManager.setupPlayerIfNeeded(for: initialItem, isFullscreen: self.isFullscreen)
            previouslySelectedItemForMarking = initialItem
            PagedDetailView.logger.debug("Initial item \(initialItem.id) set for potential marking on disappear. isFullscreen: \(self.isFullscreen). Current targetCommentID: \(self.currentItemTargetCommentID ?? -1)")
            Task {
                await handleIndexChangeDeferred(newValue: selectedIndex)
            }
        } else {
            PagedDetailView.logger.warning("onAppear: Invalid selectedIndex \(selectedIndex) for items count \(items.count).")
        }
    }

    private func cleanupViewAndMarkLastActiveItemVisited() {
        PagedDetailView.logger.info("PagedDetailView disappearing.")
        imagePrefetcher.stop()
        keyboardActionHandler.selectNextAction = nil
        keyboardActionHandler.selectPreviousAction = nil
        keyboardActionHandler.seekForwardAction = nil
        keyboardActionHandler.seekBackwardAction = nil
        
        if !isFullscreen {
            playerManager.cleanupPlayer()
        } else {
            PagedDetailView.logger.info("Skipping player cleanup (PagedDetailView disappearing but isFullscreen is true).")
        }
        showAllTagsForItem = []
        
        if let itemToMark = previouslySelectedItemForMarking {
            settings.markItemAsSeen(id: itemToMark.id)
            PagedDetailView.logger.info("Marked last active item \(itemToMark.id) as seen on disappear.")
            previouslySelectedItemForMarking = nil
        }
    }

    private func handleIndexChangeImmediate(oldValue: Int, newValue: Int) {
        PagedDetailView.logger.info("Selected index changed from \(oldValue) to \(newValue)")
        guard newValue >= 0 && newValue < items.count else {
             PagedDetailView.logger.warning("handleIndexChangeImmediate: Invalid new index \(newValue) (items.count: \(items.count)).")
             return
        }
        let newItem = items[newValue]
        PagedDetailView.logger.debug("Immediate actions for index change to \(newValue). Setting up player.")
        playerManager.setupPlayerIfNeeded(for: newItem, isFullscreen: self.isFullscreen)
        
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

         Task {
             let nextIndex = newValue + 1
             if nextIndex < self.items.count { await self.loadInfoIfNeededAndPrepareHierarchy(for: self.items[nextIndex]) }
         }
         Task {
             let prevIndex = newValue - 1
             if prevIndex >= 0 { await self.loadInfoIfNeededAndPrepareHierarchy(for: self.items[prevIndex]) }
         }

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

         PagedDetailView.logger.debug("Finished launching adjacent item info loads for index \(newValue).")
     }

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
          PagedDetailView.logger.debug("Scene phase: \(String(describing: oldPhase)) -> \(String(describing: newPhase))")
          if newPhase == .active {
              settings.transientSessionMuteState = nil
              if !isFullscreen, let player = playerManager.player, player.isMuted != settings.isVideoMuted {
                  player.isMuted = settings.isVideoMuted
              }
              if !isFullscreen, let player = playerManager.player, player.timeControlStatus != .playing {
                  player.play()
                  PagedDetailView.logger.debug("Scene became active. Resuming player (not fullscreen).")
              }
          } else if newPhase == .inactive || newPhase == .background {
              if !isFullscreen && previewLinkTarget == nil && userProfileSheetTarget == nil && collectionSelectionSheetTarget == nil,
                 let player = playerManager.player, player.timeControlStatus == .playing {
                  PagedDetailView.logger.debug("Scene became inactive/background. Pausing player (not fullscreen, no sheets active).")
                  player.pause()
              } else {
                  PagedDetailView.logger.debug("Scene became inactive/background. NOT pausing player (is fullscreen or a sheet is active or player not playing).")
              }
              
              PagedDetailView.logger.info("App going to background/inactive. Forcing save of seen items.")
              handleAppBackgrounding()
          }
     }

    private func handleAppBackgrounding() {
        let currentSettings = self.settings
        Task { @MainActor in
            await currentSettings.forceSaveSeenItems()
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
        PagedDetailView.logger.debug("[View] Callback: handleEndFullScreen. isFullscreen set to false.")
        
        if selectedIndex >= 0 && selectedIndex < items.count && items[selectedIndex].isVideo {
            let currentItem = items[selectedIndex]
            if currentItem.id == playerManager.playerItemID {
                if !wasPlayingBeforeAnySheet && previewLinkTarget == nil && userProfileSheetTarget == nil && collectionSelectionSheetTarget == nil {
                    playerManager.player?.play()
                    PagedDetailView.logger.debug("Resuming player after ending fullscreen (no sheets active, was not playing due to sheet).")
                } else if wasPlayingBeforeAnySheet {
                    PagedDetailView.logger.debug("Player was paused for a sheet; resumePlayerIfNeeded will handle it.")
                } else {
                     PagedDetailView.logger.debug("Not resuming player after fullscreen: conditions not met (sheet might be active or player state already handled).")
                }
            } else {
                PagedDetailView.logger.debug("Not resuming player after fullscreen: current item is not the one that was playing or player changed.")
            }
        }
    }

    private func triggerLoadMoreIfNeeded(currentIndex: Int) async {
          guard currentIndex >= items.count - preloadThreshold else { return }
          PagedDetailView.logger.info("Approaching end of list (index \(currentIndex)/\(items.count - 1)). Triggering load more action...")
          await loadMoreAction()
     }

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

        guard authService.isLoggedIn,
              let nonce = authService.userNonce,
              let collectionId = localSettings.selectedCollectionIdForFavorites else {
            PagedDetailView.logger.warning("Favorite toggle skipped: User not logged in, nonce missing, or no favorite collection selected in AppSettings.");
            return
        }

        let itemId = currentItem.id
        let currentIsFavorited: Bool
        if let localStatus = localFavoritedStatus[itemId] { currentIsFavorited = localStatus }
        else { currentIsFavorited = authService.favoritedItemIDs.contains(itemId) }
        let targetFavoriteState = !currentIsFavorited

        isTogglingFavorite = true
        localFavoritedStatus[itemId] = targetFavoriteState

        do {
            if targetFavoriteState {
                try await apiService.addToCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
                PagedDetailView.logger.info("Added item \(itemId) to collection \(collectionId) via API.")
            } else {
                try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
                PagedDetailView.logger.info("Removed item \(itemId) from collection \(collectionId) via API.")
            }

            if targetFavoriteState { authService.favoritedItemIDs.insert(itemId) }
            else { authService.favoritedItemIDs.remove(itemId) }

            await localSettings.clearFavoritesCache(username: authService.currentUser?.name, collectionId: collectionId)
            await localSettings.updateCacheSizes()
            PagedDetailView.logger.info("Favorite toggled successfully for item \(itemId) in collection \(collectionId). Global state updated. Cache for collection \(collectionId) cleared.")
        } catch {
            PagedDetailView.logger.error("Failed to toggle favorite for item \(itemId) in collection \(collectionId): \(error.localizedDescription)")
            localFavoritedStatus.removeValue(forKey: itemId)
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 PagedDetailView.logger.warning("Favorite toggle failed due to auth error. Logging out.")
                 await authService.logout()
            }
        }
        isTogglingFavorite = false
    }

    private func addCurrentItemToSelectedCollection(collection: ApiCollection) async {
        guard !isTogglingFavorite else {
            PagedDetailView.logger.debug("Add to collection '\(collection.name)' skipped: Favorite toggle already processing.")
            return
        }
        guard selectedIndex >= 0 && selectedIndex < items.count else {
            PagedDetailView.logger.warning("Add to collection '\(collection.name)' skipped: Invalid selectedIndex \(selectedIndex).")
            return
        }
        let currentItem = items[selectedIndex]
        let itemId = currentItem.id

        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            PagedDetailView.logger.warning("Add to collection '\(collection.name)' skipped: User not logged in or nonce missing.")
            return
        }

        isTogglingFavorite = true

        if collection.id == settings.selectedCollectionIdForFavorites {
            localFavoritedStatus[itemId] = true
        }

        do {
            try await apiService.addToCollection(itemId: itemId, collectionId: collection.id, nonce: nonce)
            PagedDetailView.logger.info("Successfully added item \(itemId) to collection '\(collection.name)' (ID: \(collection.id)) via API.")

            if collection.id == settings.selectedCollectionIdForFavorites {
                authService.favoritedItemIDs.insert(itemId)
            }

            await settings.clearFavoritesCache(username: authService.currentUser?.name, collectionId: collection.id)
            await settings.updateCacheSizes()
            PagedDetailView.logger.info("Cache for collection '\(collection.name)' (ID: \(collection.id)) cleared.")

        } catch {
            PagedDetailView.logger.error("Failed to add item \(itemId) to collection '\(collection.name)' (ID: \(collection.id)): \(error.localizedDescription)")
            if collection.id == settings.selectedCollectionIdForFavorites {
                localFavoritedStatus.removeValue(forKey: itemId)
            }
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 PagedDetailView.logger.warning("Add to collection failed due to auth error. Logging out.")
                 await authService.logout()
            }
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

    private func handleVoteTap(voteType: Int) async {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return }
        let itemIndex = selectedIndex
        let itemId = items[itemIndex].id
        
        let previousVoteStateForRevert = authService.votedItemStates[itemId] ?? 0
        
        await authService.performVote(itemId: itemId, voteType: voteType)

        guard selectedIndex == itemIndex, selectedIndex < items.count else {
             PagedDetailView.logger.warning("Could not update local item score for \(itemId): selectedIndex changed or index out of bounds.")
             return
        }

        let newVoteState = authService.votedItemStates[itemId] ?? 0

        if previousVoteStateForRevert != newVoteState {
            var deltaUp = 0
            var deltaDown = 0
            
            if newVoteState == 1 && previousVoteStateForRevert == 0 { deltaUp = 1 }
            else if newVoteState == 1 && previousVoteStateForRevert == -1 { deltaUp = 1; deltaDown = -1 }
            else if newVoteState == 0 && previousVoteStateForRevert == 1 { deltaUp = -1 }
            else if newVoteState == 0 && previousVoteStateForRevert == -1 { deltaDown = -1 }
            else if newVoteState == -1 && previousVoteStateForRevert == 0 { deltaDown = 1 }
            else if newVoteState == -1 && previousVoteStateForRevert == 1 { deltaUp = -1; deltaDown = 1 }

            if itemIndex < items.count {
                var mutableItem = items[itemIndex]
                mutableItem.up += deltaUp
                mutableItem.down += deltaDown
                items[itemIndex] = mutableItem
                PagedDetailView.logger.info("Updated local item \(itemId) score based on final vote state: deltaUp=\(deltaUp), deltaDown=\(deltaDown). New counts: up=\(items[itemIndex].up), down=\(items[itemIndex].down)")
            }
        } else {
            PagedDetailView.logger.info("Vote state for item \(itemId) did not effectively change after API call and potential revert. No local score update needed.")
        }
    }
    
    // --- NEW: handleTagVoteTap method ---
    private func handleTagVoteTap(tagId: Int, voteType: Int) async {
        guard authService.isLoggedIn else {
            PagedDetailView.logger.warning("Tag vote skipped: User not logged in.")
            return
        }
        PagedDetailView.logger.debug("Tag vote tapped: tagId=\(tagId), voteType=\(voteType)")
        await authService.performTagVote(tagId: tagId, voteType: voteType)
        // Die UI aktualisiert sich automatisch durch @Published votedTagStates in AuthService
    }
    // --- END NEW ---

    private func submitComment(text: String, itemId: Int, parentId: Int) async throws {
        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            PagedDetailView.logger.error("Cannot submit comment: User not logged in or nonce missing.")
            throw NSError(domain: "PagedDetailView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nicht angemeldet"])
        }

        PagedDetailView.logger.info("Submitting comment via PagedDetailView for itemId: \(itemId), parentId: \(parentId)")
        do {
            let updatedComments = try await apiService.postComment(itemId: itemId, parentId: parentId, comment: text, nonce: nonce)
            if let currentDetails = cachedDetails[itemId] {
                PagedDetailView.logger.info("Updating cached comments for item \(itemId). Previous count: \(currentDetails.info.comments.count), New count: \(updatedComments.count)")
                 let updatedItemComments = updatedComments.map {
                    ItemComment(id: $0.id, parent: $0.parent, content: $0.content, created: $0.created, up: $0.up, down: $0.down, confidence: $0.confidence, name: $0.name, mark: $0.mark, itemId: itemId)
                 }
                let updatedInfo = ItemsInfoResponse(tags: currentDetails.info.tags, comments: updatedItemComments)
                let newFlatList = prepareFlatDisplayComments(from: updatedItemComments, sortedBy: currentDetails.sortedBy, maxDepth: commentMaxDepth)
                cachedDetails[itemId] = CachedItemDetails(info: updatedInfo, sortedBy: currentDetails.sortedBy, flatDisplayComments: newFlatList, totalCommentCount: updatedItemComments.count)
                PagedDetailView.logger.info("Successfully updated cache and flat list for item \(itemId) after posting comment.")
            } else {
                PagedDetailView.logger.warning("Comment posted successfully for item \(itemId), but no cached details found to update.")
                 infoLoadingStatus[itemId] = .idle
                 if selectedIndex >= 0 && selectedIndex < items.count {
                     Task { await loadInfoIfNeededAndPrepareHierarchy(for: items[selectedIndex]) }
                 } else {
                     PagedDetailView.logger.error("Cannot reload hierarchy after posting comment: Invalid selectedIndex \(selectedIndex)")
                 }
            }
        } catch {
            PagedDetailView.logger.error("Failed to submit comment for item \(itemId): \(error.localizedDescription)")
            throw error
        }
    }

}

@MainActor
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

#Preview("Preview") {
    struct PreviewWrapper: View {
         @State var previewItems: [Item] = [
             Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: 1, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, subtitles: nil, favorited: false),
             Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: 2, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, subtitles: nil, favorited: true),
             Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: 3, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, subtitles: nil, favorited: nil),
             Item(id: 4, promoted: 1004, userId: 3, down: 1, up: 10, created: 4, image: "img3.gif", thumb: "t4.gif", fullsize: nil, preview: nil, width: 500, height: 300, audio: false, source: nil, flags: 1, user: "UserC", mark: 0, repost: nil, variants: nil, subtitles: nil, favorited: false)
         ]
         @StateObject var previewSettings: AppSettings
         @StateObject var previewAuthService: AuthService
         @StateObject var previewPlayerManager = VideoPlayerManager()

        init() {
            let tempSettings = AppSettings()
            _previewSettings = StateObject(wrappedValue: tempSettings)
            let tempAuthService = AuthService(appSettings: tempSettings)
            _previewAuthService = StateObject(wrappedValue: tempAuthService)
            
            previewAuthService.isLoggedIn = true
            let collections = [
                ApiCollection(id: 6749, name: "Standard", keyword: "standard", isPublic: 0, isDefault: 1, itemCount: 10),
                ApiCollection(id: 6750, name: "Lustig", keyword: "lustig", isPublic: 0, isDefault: 0, itemCount: 5)
            ]
            previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [], collections: collections)
            #if DEBUG
            previewAuthService.setUserCollectionsForPreview(collections)
            #endif
            previewAuthService.userNonce = "preview_nonce_12345"
            tempSettings.selectedCollectionIdForFavorites = 6749
            previewAuthService.favoritedItemIDs = [2]
            previewAuthService.votedItemStates = [1: 1, 3: -1]
            previewPlayerManager.configure(settings: tempSettings)
        }


         func dummyLoadMore() async { print("Preview: Dummy Load More Action Triggered") }

         var body: some View {
             NavigationStack {
                 PagedDetailView(
                    items: $previewItems,
                    selectedIndex: 0,
                    playerManager: previewPlayerManager,
                    loadMoreAction: dummyLoadMore,
                    initialTargetCommentID: nil
                 )
             }
             .environmentObject(previewSettings)
             .environmentObject(previewAuthService)
             .task {
                 print("Preview Task: Initial setup done.")
             }
         }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
