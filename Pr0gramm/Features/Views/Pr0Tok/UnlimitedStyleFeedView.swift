// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/UnlimitedStyleFeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

// Datenmodell für die Übergabe an UnlimitedFeedItemView
struct UnlimitedFeedItemDataModel {
    let item: Item
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let comments: [ItemComment]
    let itemInfoStatus: InfoLoadingStatus
}

fileprivate struct UnlimitedVotableTagView: View {
    let tag: ItemTag
    let currentVote: Int
    let isVoting: Bool
    let truncateText: Bool
    let onUpvote: () -> Void
    let onDownvote: () -> Void
    let onTapTag: () -> Void

    @EnvironmentObject var authService: AuthService

    private let characterLimit = 10
    private var displayText: String {
        if truncateText && tag.tag.count > characterLimit {
            return String(tag.tag.prefix(characterLimit)) + "…"
        }
        return tag.tag
    }
    private let tagVoteButtonFont: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            if authService.isLoggedIn {
                Button(action: onDownvote) {
                    Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == -1 ? .red : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }

            Text(displayText)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, authService.isLoggedIn ? 2 : 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
                .onTapGesture(perform: onTapTag)


            if authService.isLoggedIn {
                Button(action: onUpvote) {
                    Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == 1 ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }
        }
        .padding(.horizontal, authService.isLoggedIn ? 6 : 0)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}


struct UnlimitedStyleFeedView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService

    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var keyboardActionHandlerInstance = KeyboardActionHandler()

    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoadingFeed = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedStyleFeedView")
    
    @State private var activeItemID: Int? = nil
    @State private var scrolledItemID: Int? = nil

    @State private var cachedDetails: [Int: ItemsInfoResponse] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
        
    @State private var showingTagSearchSheet = false
    @State private var tagForSearchSheet: String? = nil
    
    @State private var showingAllTagsSheet = false
    @State private var itemForTagSheet: Item? = nil

    @State private var showingAddTagSheet = false
    @State private var newTagTextForSheet = ""
    @State private var addTagErrorForSheet: String? = nil
    @State private var isAddingTagsInSheet: Bool = false
    
    @State private var fullscreenImageTarget: FullscreenImageTarget? = nil
    
    private let initialVisibleTagCount = 2
    @State private var flagsUsedForLastItemsLoad: Int? = nil
    
    @State private var currentRefreshFeedTask: Task<Void, Never>? = nil
    @State private var debouncedRefreshTask: Task<Void, Never>? = nil

    private let dummyStartItemID = -1
    private func createDummyStartItem() -> Item {
        return Item(id: dummyStartItemID, promoted: nil, userId: 0, down: 0, up: 0, created: 0, image: "pr0tok.png", thumb: "pr0tok.png", fullsize: "pr0tok.png", preview: nil, width: 512, height: 512, audio: false, source: nil, flags: 1, user: "Pr0Tok", mark: 0, repost: false, variants: nil, subtitles: nil)
    }
    
    init() {
        _items = State(initialValue: [createDummyStartItem()])
        _activeItemID = State(initialValue: dummyStartItemID)
        _scrolledItemID = State(initialValue: dummyStartItemID)
        Self.logger.info("UnlimitedStyleFeedView init: Set initial items with dummy, active/scrolled to dummyID.")
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                feedControls
                feedContent
            }
            .navigationTitle("Feed (Vertikal)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            Self.logger.info("Refresh button tapped for UnlimitedStyleFeedView.")
                            debouncedRefreshTask?.cancel()
                            currentRefreshFeedTask?.cancel()
                            Self.logger.debug("Cancelled previous refresh/debounced task (if any) due to manual refresh.")
                            
                            playerManager.cleanupPlayer()
                            Self.logger.info("Player cleaned up due to manual refresh.")
                            
                            await MainActor.run {
                                self.items = [createDummyStartItem()]
                                self.cachedDetails = [:]
                                self.infoLoadingStatus = [:]
                                self.activeItemID = dummyStartItemID
                                self.scrolledItemID = dummyStartItemID
                                self.errorMessage = nil
                                self.canLoadMore = true
                                self.isLoadingMore = false
                                self.flagsUsedForLastItemsLoad = nil
                            }
                            Self.logger.info("UI and data states reset for manual refresh. Scrolled to dummy.")
                            
                            currentRefreshFeedTask = Task {
                                if Task.isCancelled {
                                    Self.logger.info("New manual refresh task was cancelled before starting.")
                                    return
                                }
                                Self.logger.info("Starting new manual refresh task.")
                                await refreshItems()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .disabled(isLoadingFeed)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingFilterSheet = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterView(relevantFeedTypeForFilterBehavior: settings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingTagSearchSheet, onDismiss: { tagForSearchSheet = nil }) {
                if let tag = tagForSearchSheet {
                    NavigationStack {
                        TagSearchView(currentSearchTag: .constant(tag))
                            .environmentObject(settings)
                            .environmentObject(authService)
                            .navigationTitle("Suche: \(tag)")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Schließen") { showingTagSearchSheet = false }
                                }
                            }
                    }
                }
            }
            .sheet(item: $itemForTagSheet, onDismiss: { itemForTagSheet = nil }) { itemToShowTagsFor in
                AllTagsSheetView(
                    item: itemToShowTagsFor,
                    cachedDetails: $cachedDetails,
                    infoLoadingStatus: $infoLoadingStatus,
                    onTagTapped: { tagString in
                        self.itemForTagSheet = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            self.tagForSearchSheet = tagString
                            self.showingTagSearchSheet = true
                        }
                    },
                    onUpvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: 1) } },
                    onDownvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: -1) } },
                    onRetryLoadDetails: { Task { await loadItemDetailsIfNeeded(for: itemToShowTagsFor, forceReload: true)} },
                    onShowAddTagSheet: {
                        self.itemForTagSheet = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            self.newTagTextForSheet = ""
                            self.addTagErrorForSheet = nil
                            self.isAddingTagsInSheet = false
                            self.showingAddTagSheet = true
                        }
                    }
                )
                .environmentObject(settings)
                .environmentObject(authService)
            }
            .sheet(isPresented: $showingAddTagSheet) { addTagSheetContent() }
            .sheet(item: $fullscreenImageTarget) { (target: FullscreenImageTarget) in
                FullscreenImageView(item: target.item)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoadingFeed)) {
                 Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .onAppear {
                playerManager.configure(settings: settings)
                keyboardActionHandlerInstance.selectNextAction = self.selectNextItem
                keyboardActionHandlerInstance.selectPreviousAction = self.selectPreviousItem
                keyboardActionHandlerInstance.seekForwardAction = playerManager.seekForward
                keyboardActionHandlerInstance.seekBackwardAction = playerManager.seekBackward
                Self.logger.info("UnlimitedStyleFeedView.onAppear - Konfiguration abgeschlossen.")
                
                if items.isEmpty || items.first?.id != dummyStartItemID {
                    items = [createDummyStartItem()]
                    scrolledItemID = dummyStartItemID
                    activeItemID = dummyStartItemID
                    Self.logger.info("UnlimitedStyleFeedView.onAppear: Corrected items to ensure dummy is first and active.")
                } else if scrolledItemID == nil {
                    scrolledItemID = dummyStartItemID
                    activeItemID = dummyStartItemID
                    Self.logger.info("UnlimitedStyleFeedView.onAppear: scrolledItemID was nil, set to dummyID.")
                }
            }
            .task(id: "\(authService.isLoggedIn)-\(settings.apiFlags)-\(settings.feedType.rawValue)-\(settings.hideSeenItems)") {
                Self.logger.info("UnlimitedStyleFeedView .task triggered for state change. ID: \(authService.isLoggedIn)-\(settings.apiFlags)-\(settings.feedType.displayName)-\(settings.hideSeenItems)")
                
                debouncedRefreshTask?.cancel()
                currentRefreshFeedTask?.cancel()

                playerManager.cleanupPlayer()
                await MainActor.run {
                    self.items = [createDummyStartItem()]
                    self.cachedDetails = [:]
                    self.infoLoadingStatus = [:]
                    self.activeItemID = dummyStartItemID
                    self.scrolledItemID = dummyStartItemID
                    self.errorMessage = nil
                    self.canLoadMore = true
                    self.isLoadingMore = false
                }
                Self.logger.info("UI reset to dummy item before starting debounced refresh.")

                debouncedRefreshTask = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else {
                            Self.logger.info("Debounced refresh task was cancelled during sleep.")
                            return
                        }
                        
                        if self.isLoadingFeed {
                             Self.logger.info("Debounced refresh: isLoadingFeed is true, skipping.")
                             return
                        }

                        Self.logger.info("Starting new debounced refresh task due to parameter change.")
                        currentRefreshFeedTask = Task {
                            if Task.isCancelled {
                                Self.logger.info("Actual refresh (from debounced) was cancelled before starting.")
                                return
                            }
                            await refreshItems()
                        }
                    } catch is CancellationError {
                        Self.logger.info("Debounced refresh task (outer) was cancelled.")
                    } catch {
                        Self.logger.error("Error in debounced refresh task sleep: \(error.localizedDescription)")
                    }
                }
            }
            .onDisappear {
                Self.logger.info("UnlimitedStyleFeedView.onDisappear - Cleaning up player.")
                playerManager.cleanupPlayer()
                currentRefreshFeedTask?.cancel()
                debouncedRefreshTask?.cancel()
            }
            .onChange(of: activeItemID) { oldValue, newValue in
                guard let newActiveID = newValue, newActiveID != dummyStartItemID else { return }
                guard let currentIndex = items.firstIndex(where: { $0.id == newActiveID }) else {
                    Self.logger.warning("activeItemID \(newActiveID) changed, but not found in items. Cannot preload.")
                    return
                }

                Self.logger.info("Active item changed to ID: \(newActiveID) at index \(currentIndex). Initiating preloading for N+1 and N+2.")

                let nextIndex = currentIndex + 1
                if nextIndex < items.count && items[nextIndex].id != dummyStartItemID {
                    let itemToPreloadNext = items[nextIndex]
                    Task {
                        Self.logger.debug("Preloading details for N+1: Item ID \(itemToPreloadNext.id)")
                        await loadItemDetailsIfNeeded(for: itemToPreloadNext)
                    }
                }

                let overNextIndex = currentIndex + 2
                if overNextIndex < items.count && items[overNextIndex].id != dummyStartItemID {
                    let itemToPreloadOverNext = items[overNextIndex]
                    Task {
                        Self.logger.debug("Preloading details for N+2: Item ID \(itemToPreloadOverNext.id)")
                        await loadItemDetailsIfNeeded(for: itemToPreloadOverNext)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedControls: some View {
        Picker("Feed Typ", selection: $settings.feedType) {
            ForEach(FeedType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var feedContent: some View {
        if isLoadingFeed && items.count <= 1 && (items.first?.id == dummyStartItemID || items.isEmpty) {
            ProgressView("Lade Feed...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, items.count <= 1 && (items.first?.id == dummyStartItemID || items.isEmpty) {
            VStack {
                Text("Fehler: \(error)").foregroundColor(.red)
                Button("Erneut versuchen") { Task { await refreshItems() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.count <= 1 && !isLoadingFeed && errorMessage == nil && (items.first?.id == dummyStartItemID || items.isEmpty) {
             VStack {
                 if items.first?.id == dummyStartItemID {
                     let dummyData = prepareItemDataModel(for: items.first!)
                     UnlimitedFeedItemView(
                         itemData: dummyData,
                         playerManager: playerManager,
                         keyboardActionHandlerForVideo: keyboardActionHandlerInstance,
                         isActive: activeItemID == dummyStartItemID,
                         isDummyItem: true,
                         onToggleShowAllTags: {}, onUpvoteTag: {_ in }, onDownvoteTag: {_ in }, onTagTapped: {_ in }, onRetryLoadDetails: {}, onShowAddTagSheet: {},
                         onShowFullscreenImage: { _ in }
                     )
                     .frame(height: 200)
                 }
                Text(settings.hideSeenItems && settings.enableExperimentalHideSeen ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            let itemData = prepareItemDataModel(for: item)
                            
                            UnlimitedFeedItemView(
                                itemData: itemData,
                                playerManager: playerManager,
                                keyboardActionHandlerForVideo: keyboardActionHandlerInstance,
                                isActive: activeItemID == item.id,
                                isDummyItem: item.id == dummyStartItemID,
                                onToggleShowAllTags: {
                                    if item.id != dummyStartItemID {
                                        self.itemForTagSheet = item
                                    }
                                },
                                onUpvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: 1) } },
                                onDownvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: -1) } },
                                onTagTapped: { tagString in
                                    self.tagForSearchSheet = tagString
                                    self.showingTagSearchSheet = true
                                },
                                onRetryLoadDetails: {
                                    Task { await loadItemDetailsIfNeeded(for: item, forceReload: true) }
                                },
                                onShowAddTagSheet: {
                                    newTagTextForSheet = ""
                                    addTagErrorForSheet = nil
                                    isAddingTagsInSheet = false
                                    showingAddTagSheet = true
                                },
                                onShowFullscreenImage: { tappedItem in
                                    if !tappedItem.isVideo {
                                        self.fullscreenImageTarget = FullscreenImageTarget(item: tappedItem)
                                    }
                                }
                            )
                            .id(item.id)
                            .frame(height: geometry.size.height)
                            .onAppear {
                                if item.id != dummyStartItemID && item.id == items.last?.id && canLoadMore && !isLoadingMore && !isLoadingFeed {
                                    Task { await loadMoreItems() }
                                }
                            }
                            .scrollTransition(axis: .vertical) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1.0 : 0.7)
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.9)
                            }
                        }
                        if isLoadingMore {
                            ProgressView("Lade mehr...")
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .padding()
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: geometry.size.height)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .background(KeyCommandView(handler: keyboardActionHandlerInstance))
                .scrollPosition(id: $scrolledItemID)
                .onChange(of: scrolledItemID) { oldValue, newValue in
                    guard let newId = newValue else { return }
                    
                    if newId == dummyStartItemID {
                        if activeItemID != dummyStartItemID {
                            playerManager.cleanupPlayer()
                            activeItemID = newId
                            Self.logger.info("Scrolled to dummy start item. Player cleaned.")
                        }
                        return
                    }
                    
                    if let index = items.firstIndex(where: { $0.id == newId }) {
                        let currentItem = items[index]
                        let previousActiveItemID = activeItemID
                        activeItemID = currentItem.id

                        if oldValue != newId || (oldValue == nil && newId != items.first(where: {$0.id != dummyStartItemID})?.id && previousActiveItemID == nil) {
                            if currentItem.id != dummyStartItemID {
                                settings.markItemAsSeen(id: currentItem.id)
                            }
                        }
                        
                        if currentItem.id != dummyStartItemID {
                            playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: false)
                            
                            if currentItem.isVideo && activeItemID == currentItem.id {
                                if previousActiveItemID != currentItem.id || playerManager.player?.timeControlStatus != .playing {
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        guard self.activeItemID == currentItem.id, let player = playerManager.player else {
                                            Self.logger.debug("Player start skipped for item \(currentItem.id): activeItemID changed or player nil during delay.")
                                            return
                                        }
                                        if player.status == .readyToPlay {
                                            player.play()
                                            Self.logger.info("Explicitly started player for (newly) active video item \(currentItem.id) after delay and status check.")
                                        } else {
                                            Self.logger.warning("Player for item \(currentItem.id) not readyToPlay. Status: \(String(describing: player.status)). Play command might not be effective immediately.")
                                            player.play()
                                        }
                                    }
                                }
                            }
                            Self.logger.info("Scrolled to item \(currentItem.id), setting active. Details loading will be initiated by activeItemID change.")
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func prepareItemDataModel(for item: Item) -> UnlimitedFeedItemDataModel {
        if item.id == dummyStartItemID {
            return UnlimitedFeedItemDataModel(
                item: item,
                displayedTags: [],
                totalTagCount: 0,
                comments: [],
                itemInfoStatus: .loaded
            )
        }

        let details = cachedDetails[item.id]
        let allItemTags = details?.tags.sorted { $0.confidence > $1.confidence } ?? []
        let tagsForDisplayLogic = Array(allItemTags.prefix(initialVisibleTagCount))

        let commentsToDisplay = details?.comments ?? []
        let currentInfoStatus = infoLoadingStatus[item.id] ?? .idle

        return UnlimitedFeedItemDataModel(
            item: item,
            displayedTags: tagsForDisplayLogic,
            totalTagCount: allItemTags.count,
            comments: commentsToDisplay,
            itemInfoStatus: currentInfoStatus
        )
    }
    
    private func selectNextItem() {
        guard let currentActiveID = activeItemID, let currentIndexInAllItems = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        
        var nextRealItemIndex = currentIndexInAllItems + 1
        while nextRealItemIndex < items.count && items[nextRealItemIndex].id == dummyStartItemID {
            nextRealItemIndex += 1
        }

        if nextRealItemIndex < items.count {
            let nextItemID = items[nextRealItemIndex].id
            scrolledItemID = nextItemID
            Self.logger.debug("Keyboard: selectNextItem, scrolling to \(nextItemID)")
        } else if let lastRealItem = items.last(where: {$0.id != dummyStartItemID}), currentActiveID != lastRealItem.id {
            scrolledItemID = lastRealItem.id
            Self.logger.debug("Keyboard: selectNextItem (at end), scrolling to last real item \(lastRealItem.id)")
        }
    }

    private func selectPreviousItem() {
        guard let currentActiveID = activeItemID, let currentIndexInAllItems = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        
        var prevRealItemIndex = currentIndexInAllItems - 1
        while prevRealItemIndex >= 0 && items[prevRealItemIndex].id == dummyStartItemID {
            prevRealItemIndex -= 1
        }

        if prevRealItemIndex >= 0 {
            let previousItemID = items[prevRealItemIndex].id
            scrolledItemID = previousItemID
            Self.logger.debug("Keyboard: selectPreviousItem, scrolling to \(previousItemID)")
        } else if let firstRealItem = items.first(where: {$0.id != dummyStartItemID}), currentActiveID != firstRealItem.id {
             scrolledItemID = firstRealItem.id
             Self.logger.debug("Keyboard: selectPreviousItem (at start), scrolling to first real item \(firstRealItem.id)")
        }
    }

    @MainActor
    func refreshItems() async {
        if Task.isCancelled {
            Self.logger.info("RefreshItems (Unlimited) Task was cancelled before execution could begin.")
            return
        }
        
        await MainActor.run {
            if self.items.first?.id != dummyStartItemID || self.items.count > 1 || self.scrolledItemID != dummyStartItemID {
                self.items = [createDummyStartItem()]
                self.activeItemID = dummyStartItemID
                self.scrolledItemID = dummyStartItemID
                Self.logger.info("RefreshItems: Explicitly set UI to dummy item at the beginning of refresh logic.")
            }
            self.isLoadingFeed = true
            self.errorMessage = nil
            self.canLoadMore = true
            self.isLoadingMore = false
            self.cachedDetails = [:]
            self.infoLoadingStatus = [:]
        }
        
        let currentApiFlagsForThisRefresh = settings.apiFlags
        Self.logger.info("RefreshItems (Unlimited) Task started. Attempting with apiFlags: \(currentApiFlagsForThisRefresh)")

        defer {
            Task { @MainActor in
                self.isLoadingFeed = false
                Self.logger.info("RefreshItems (Unlimited) Task finished. isLoadingFeed set to false.")
            }
        }

        if Task.isCancelled { Self.logger.info("RefreshItems (Unlimited) Task was cancelled before guard settings.hasActiveContentFilter."); return }

        guard settings.hasActiveContentFilter || currentApiFlagsForThisRefresh != 0 else {
            await MainActor.run {
                self.errorMessage = nil
                self.canLoadMore = false
                self.flagsUsedForLastItemsLoad = currentApiFlagsForThisRefresh
            }
            Self.logger.info("Refresh (Unlimited) aborted: No active content filter (apiFlags: \(currentApiFlagsForThisRefresh)). UI shows dummy item.")
            return
        }
        
        var allFetchedUnseenItems: [Item] = []
        var currentOlderThanIdForRefreshLoop: Int? = nil
        var pagesAttemptedInLoop = 0
        var apiSaysNoMoreItems = false

        do {
            if settings.hideSeenItems && settings.enableExperimentalHideSeen {
                while allFetchedUnseenItems.isEmpty && !apiSaysNoMoreItems {
                    if Task.isCancelled { throw CancellationError() }
                    pagesAttemptedInLoop += 1
                    Self.logger.info("RefreshItems: Auto-fetching page \(pagesAttemptedInLoop) for unseen (older: \(currentOlderThanIdForRefreshLoop ?? -1)) with flags \(currentApiFlagsForThisRefresh)")

                    let apiResponse = try await apiService.fetchItems(
                        flags: currentApiFlagsForThisRefresh,
                        promoted: settings.apiPromoted,
                        olderThanId: currentOlderThanIdForRefreshLoop,
                        showJunkParameter: settings.apiShowJunk
                    )
                    
                    if Task.isCancelled { throw CancellationError() }

                    var pageItems = apiResponse.items
                    Self.logger.info("API (auto-refresh page \(pagesAttemptedInLoop)) fetched \(pageItems.count) items.")

                    pageItems.removeAll { settings.seenItemIDs.contains($0.id) }
                    Self.logger.info("Filtered \(apiResponse.items.count - pageItems.count) seen items from auto-refresh page \(pagesAttemptedInLoop). \(pageItems.count) unseen remaining.")
                    
                    allFetchedUnseenItems.append(contentsOf: pageItems)
                    
                    if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                        apiSaysNoMoreItems = true
                        Self.logger.info("API indicated end of feed during refresh loop (Page \(pagesAttemptedInLoop)).")
                    }
                    
                    if !apiResponse.items.isEmpty && !apiSaysNoMoreItems {
                         currentOlderThanIdForRefreshLoop = settings.feedType == .promoted ? apiResponse.items.last!.promoted ?? apiResponse.items.last!.id : apiResponse.items.last!.id
                    } else if apiResponse.items.isEmpty && !apiSaysNoMoreItems {
                        apiSaysNoMoreItems = true
                        Self.logger.info("API returned 0 items during refresh loop (Page \(pagesAttemptedInLoop)), assuming end.")
                    }
                }
            } else {
                let apiResponse = try await apiService.fetchItems(
                    flags: currentApiFlagsForThisRefresh,
                    promoted: settings.apiPromoted,
                    showJunkParameter: settings.apiShowJunk
                )
                allFetchedUnseenItems = apiResponse.items
                if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                    apiSaysNoMoreItems = true
                }
                Self.logger.info("API fetch (Unlimited, no hideSeenItems) completed: \(allFetchedUnseenItems.count) items. API at end: \(apiSaysNoMoreItems)")
            }
            
            if Task.isCancelled { Self.logger.info("RefreshItems (Unlimited) Task cancelled after API fetch but before UI update."); return }

            await MainActor.run {
                self.items = [createDummyStartItem()] + allFetchedUnseenItems
                self.errorMessage = nil
                self.canLoadMore = !apiSaysNoMoreItems
                
                if allFetchedUnseenItems.isEmpty {
                    Self.logger.info("Refresh (Unlimited) resulted in 0 new items. canLoadMore set to \(!apiSaysNoMoreItems) based on API signal (\(apiSaysNoMoreItems)).")
                    if self.scrolledItemID != dummyStartItemID { self.scrolledItemID = dummyStartItemID }
                    if self.activeItemID != dummyStartItemID { self.activeItemID = dummyStartItemID }
                } else {
                    // scrolledItemID should remain dummyStartItemID after a refresh,
                    // until user interaction or the .onAppear of UnlimitedFeedItemView for the first real item.
                    // This allows the dummy item to be potentially visible first.
                    Self.logger.info("Refresh (Unlimited) successful. \(allFetchedUnseenItems.count) new items added. scrolledItemID remains on dummy. canLoadMore set to \(!apiSaysNoMoreItems).")
                }
                self.flagsUsedForLastItemsLoad = currentApiFlagsForThisRefresh
            }

            if !allFetchedUnseenItems.isEmpty {
                let firstRealItemIndexAfterDummy = 1
                
                if items.indices.contains(firstRealItemIndexAfterDummy) {
                    let initialActiveItem = items[firstRealItemIndexAfterDummy]
                    Self.logger.debug("Refresh complete: Preloading details for initial active item: \(initialActiveItem.id)")
                    await loadItemDetailsIfNeeded(for: initialActiveItem)

                    let nextIndex = firstRealItemIndexAfterDummy + 1
                    if items.indices.contains(nextIndex) && items[nextIndex].id != dummyStartItemID {
                        let itemToPreloadNext = items[nextIndex]
                        Self.logger.debug("Refresh complete: Preloading details for N+1: Item ID \(itemToPreloadNext.id)")
                        await loadItemDetailsIfNeeded(for: itemToPreloadNext)
                    }

                    let overNextIndex = firstRealItemIndexAfterDummy + 2
                    if items.indices.contains(overNextIndex) && items[overNextIndex].id != dummyStartItemID {
                        let itemToPreloadOverNext = items[overNextIndex]
                        Self.logger.debug("Refresh complete: Preloading details for N+2: Item ID \(itemToPreloadOverNext.id)")
                        await loadItemDetailsIfNeeded(for: itemToPreloadOverNext)
                    }
                }
            }

        } catch is CancellationError {
            Self.logger.info("RefreshItems (Unlimited) Task API call explicitly cancelled.")
            if items.count <= 1 {
                await MainActor.run { canLoadMore = true }
            }
        } catch {
            Self.logger.error("API fetch (Unlimited) failed during refresh: \(error.localizedDescription)")
            if Task.isCancelled { Self.logger.info("RefreshItems (Unlimited) Task cancelled after API error."); return }
            await MainActor.run {
                self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                self.canLoadMore = false
            }
        }
    }
    
    @MainActor
    func loadMoreItems() async {
        guard !isLoadingMore && canLoadMore && !isLoadingFeed else { return }
        
        let lastRealItem = items.last(where: { $0.id != dummyStartItemID })
        
        let olderThanId: Int?
        if settings.feedType == .promoted {
            olderThanId = lastRealItem?.promoted ?? lastRealItem?.id
        } else {
            olderThanId = lastRealItem?.id
        }
        guard let finalOlderThanId = olderThanId else {
            Self.logger.warning("Cannot load more (Unlimited): Could not determine 'older' value from real items.")
            return
        }
        
        isLoadingMore = true
        Self.logger.info("--- Starting loadMoreItems (Unlimited) older than \(finalOlderThanId) ---")
        defer { Task { @MainActor in self.isLoadingMore = false } }

        var itemsToAppend: [Item] = []
        var apiSaysNoMoreItemsAfterLoadMore = false
        var pagesForLoadMore = 0

        do {
            var currentOlderForLoop = finalOlderThanId
            while itemsToAppend.isEmpty && !apiSaysNoMoreItemsAfterLoadMore {
                if Task.isCancelled { throw CancellationError() }
                pagesForLoadMore += 1
                Self.logger.info("LoadMore: Fetching page \(pagesForLoadMore) (older: \(currentOlderForLoop))")

                let apiResponse = try await apiService.fetchItems(
                    flags: settings.apiFlags,
                    promoted: settings.apiPromoted,
                    olderThanId: currentOlderForLoop,
                    showJunkParameter: settings.apiShowJunk
                )
                
                if Task.isCancelled { throw CancellationError() }

                var pageItems = apiResponse.items
                let rawPageItemCount = pageItems.count
                
                if settings.hideSeenItems && settings.enableExperimentalHideSeen {
                    let originalCount = pageItems.count
                    pageItems.removeAll { settings.seenItemIDs.contains($0.id) }
                    Self.logger.info("LoadMore: Filtered \(originalCount - pageItems.count) seen items. \(pageItems.count) unseen remaining.")
                }
                
                let currentItemIDs = Set(self.items.map { $0.id })
                let uniqueNewPageItems = pageItems.filter { !currentItemIDs.contains($0.id) }
                itemsToAppend.append(contentsOf: uniqueNewPageItems)

                if apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil) {
                    apiSaysNoMoreItemsAfterLoadMore = true
                    Self.logger.info("API indicated end of feed during loadMore loop (Page \(pagesForLoadMore)).")
                }
                
                if rawPageItemCount > 0 && !apiSaysNoMoreItemsAfterLoadMore {
                    currentOlderForLoop = settings.feedType == .promoted ? apiResponse.items.last!.promoted ?? apiResponse.items.last!.id : apiResponse.items.last!.id
                } else if rawPageItemCount == 0 && !apiSaysNoMoreItemsAfterLoadMore {
                    apiSaysNoMoreItemsAfterLoadMore = true
                    Self.logger.info("API returned 0 items during loadMore loop (Page \(pagesForLoadMore)), assuming end.")
                }
            }
            
            if Task.isCancelled { Self.logger.info("LoadMoreItems (Unlimited) Task cancelled after API fetch loops."); return }

            if !itemsToAppend.isEmpty {
                self.items.append(contentsOf: itemsToAppend)
                Self.logger.info("LoadMore: Appended \(itemsToAppend.count) new items.")
            }
            
            self.canLoadMore = !apiSaysNoMoreItemsAfterLoadMore
            Self.logger.info("LoadMore (Unlimited) finished. canLoadMore set to \(!apiSaysNoMoreItemsAfterLoadMore) based on API signal (\(apiSaysNoMoreItemsAfterLoadMore)).")
            
            if itemsToAppend.isEmpty && !apiSaysNoMoreItemsAfterLoadMore && (settings.hideSeenItems && settings.enableExperimentalHideSeen) {
                Self.logger.info("LoadMore: No new unseen items found after \(pagesForLoadMore) pages, but API might have more. Will allow further loading attempts.")
            }

        } catch is CancellationError {
            Self.logger.info("LoadMoreItems (Unlimited) Task API call explicitly cancelled.")
        } catch {
            Self.logger.error("API fetch (Unlimited) failed during loadMore: \(error.localizedDescription)")
             if Task.isCancelled { Self.logger.info("LoadMoreItems (Unlimited) Task cancelled after API error."); return }
            if self.items.filter({ $0.id != dummyStartItemID }).isEmpty {
                self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)"
            }
            self.canLoadMore = false
        }
    }

    private func loadItemDetailsIfNeeded(for item: Item, forceReload: Bool = false) async {
        let itemId = item.id
        if itemId == dummyStartItemID { return }

        if !forceReload && (infoLoadingStatus[itemId] == .loaded || infoLoadingStatus[itemId] == .loading) {
            return
        }
        
        Self.logger.info("Loading details for item \(itemId)... Force reload: \(forceReload)")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }

        do {
            let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
            let infoWithSortedTagsAndComments = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)
            
            await MainActor.run {
                cachedDetails[itemId] = infoWithSortedTagsAndComments
                infoLoadingStatus[itemId] = .loaded
            }
            Self.logger.info("Successfully loaded details for item \(itemId). Tags: \(infoWithSortedTagsAndComments.tags.count), Comments: \(infoWithSortedTagsAndComments.comments.count)")
        } catch {
            Self.logger.error("Failed to load details for item \(itemId): \(error.localizedDescription)")
            await MainActor.run { infoLoadingStatus[itemId] = .error(error.localizedDescription) }
        }
    }
    
    private func handleTagVoteTap(tagId: Int, voteType: Int) async {
        guard authService.isLoggedIn else { return }
        await authService.performTagVote(tagId: tagId, voteType: voteType)
    }
    
    private func handleAddTagsToActiveItem(tags: String) async -> String? {
        guard let currentActiveItemID = activeItemID, currentActiveItemID != dummyStartItemID else {
            return "Kein aktives Item ausgewählt."
        }
        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            Self.logger.warning("Tags hinzufügen übersprungen: Benutzer nicht eingeloggt oder Nonce fehlt.")
            return "Nicht eingeloggt."
        }

        let sanitizedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTags.isEmpty else {
            return "Bitte Tags eingeben."
        }

        Self.logger.info("Versuche, Tags '\(sanitizedTags)' zu Item \(currentActiveItemID) hinzuzufügen.")

        do {
            try await apiService.addTags(itemId: currentActiveItemID, tags: sanitizedTags, nonce: nonce)
            Self.logger.info("Tags erfolgreich zu Item \(currentActiveItemID) hinzugefügt. Lade Item-Infos neu.")
            
            if let itemToReload = items.first(where: { $0.id == currentActiveItemID }) {
                await loadItemDetailsIfNeeded(for: itemToReload, forceReload: true)
            }
            return nil
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            Self.logger.error("Fehler beim Hinzufügen von Tags zu Item \(currentActiveItemID): Authentifizierung erforderlich.")
            await authService.logout()
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        } catch {
            Self.logger.error("Fehler beim Hinzufügen von Tags zu Item \(currentActiveItemID): \(error.localizedDescription)")
            if let nsError = error as NSError?, nsError.domain == "APIService.addTags" {
                return nsError.localizedDescription
            }
            return "Ein unbekannter Fehler ist aufgetreten."
        }
    }

    @ViewBuilder
    private func addTagSheetContent() -> some View {
        NavigationStack {
            VStack(spacing: 15) {
                Text("Neue Tags eingeben (kommasepariert):")
                    .font(UIConstants.headlineFont)
                    .padding(.top)

                TextEditor(text: $newTagTextForSheet)
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color.gray.opacity(0.3))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Neue Tags")
                
                Text("Es kann etwas dauern, bis die neuen Tags angezeigt werden und von anderen Nutzern bewertet werden können.")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                if let error = addTagErrorForSheet {
                    Text("Fehler: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                Spacer()
                if isAddingTagsInSheet {
                    ProgressView("Speichere Tags...")
                        .padding(.bottom)
                }
            }
            .padding()
            .navigationTitle("Tags hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showingAddTagSheet = false }
                        .disabled(isAddingTagsInSheet)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            isAddingTagsInSheet = true
                            addTagErrorForSheet = nil
                            if let errorMsg = await handleAddTagsToActiveItem(tags: newTagTextForSheet) {
                                addTagErrorForSheet = errorMsg
                                Self.logger.error("Fehler beim Hinzufügen von Tags (Sheet): \(errorMsg)")
                            } else {
                                showingAddTagSheet = false
                            }
                            isAddingTagsInSheet = false
                        }
                    }
                    .disabled(newTagTextForSheet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingTagsInSheet)
                }
            }
        }
        .interactiveDismissDisabled(isAddingTagsInSheet)
    }
}

struct UnlimitedFeedItemView: View {
    let itemData: UnlimitedFeedItemDataModel
    @ObservedObject var playerManager: VideoPlayerManager
    @ObservedObject var keyboardActionHandlerForVideo: KeyboardActionHandler
    let isActive: Bool
    let isDummyItem: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedFeedItemView")

    let onToggleShowAllTags: () -> Void
    let onUpvoteTag: (Int) -> Void
    let onDownvoteTag: (Int) -> Void
    let onTagTapped: (String) -> Void
    let onRetryLoadDetails: () -> Void
    let onShowAddTagSheet: () -> Void
    let onShowFullscreenImage: (Item) -> Void

    var item: Item { itemData.item }
    
    @State private var showingCommentsSheet = false
    
    private let initialVisibleTagCountInItemView = 2


    var body: some View {
        ZStack {
            mediaContentLayer
                .zIndex(0)
                .onTapGesture {
                    if !item.isVideo && !isDummyItem {
                        onShowFullscreenImage(item)
                    }
                }
                .allowsHitTesting(!item.isVideo && !isDummyItem)

            if !isDummyItem {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("@\(item.user)")
                                .font(.headline).bold()
                                .foregroundColor(.white)
                            
                            tagSection
                        }
                        .padding(.leading)
                        .padding(.bottom, bottomSafeAreaPadding)

                        Spacer()

                        interactionButtons
                            .padding(.trailing)
                            .padding(.bottom, bottomSafeAreaPadding)
                    }
                    .padding(.bottom, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .zIndex(1)
            }
        }
        .background(Color.black)
        .clipped()
        .onChange(of: isActive) { oldValue, newValue in
            if isDummyItem { return }

            if newValue {
                if item.isVideo && playerManager.playerItemID == item.id {
                    if playerManager.player?.timeControlStatus != .playing {
                        playerManager.player?.play()
                        Self.logger.debug("UnlimitedFeedItemView: Player started via isActive change for item \(item.id)")
                    }
                } else if item.isVideo {
                    playerManager.setupPlayerIfNeeded(for: item, isFullscreen: false)
                    Self.logger.debug("UnlimitedFeedItemView: Player setup initiated via isActive for item \(item.id)")
                     Task {
                         try? await Task.sleep(for: .milliseconds(100))
                         if self.isActive && playerManager.playerItemID == item.id && playerManager.player?.timeControlStatus != .playing {
                             playerManager.player?.play()
                             Self.logger.debug("UnlimitedFeedItemView: Explicit play after setup for item \(item.id)")
                         }
                     }
                }
            } else {
                if item.isVideo && playerManager.playerItemID == item.id {
                     playerManager.player?.pause()
                     Self.logger.debug("UnlimitedFeedItemView: Player paused via isActive change for item \(item.id)")
                }
            }
        }
        .sheet(isPresented: $showingCommentsSheet) {
            ItemCommentsSheetView(
                itemId: itemData.item.id,
                uploaderName: itemData.item.user,
                initialComments: itemData.comments,
                initialInfoStatusProp: itemData.itemInfoStatus,
                onRetryLoadDetails: onRetryLoadDetails
            )
            .environmentObject(settings)
            .environmentObject(authService)
        }
    }
    
    private var bottomSafeAreaPadding: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }


    @ViewBuilder
    private var mediaContentLayer: some View {
        if isDummyItem {
            Image("pr0tok")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(50)
        } else if item.isVideo {
             if isActive, let player = playerManager.player, playerManager.playerItemID == item.id {
                 CustomVideoPlayerRepresentable(
                     player: player,
                     handler: keyboardActionHandlerForVideo,
                     onWillBeginFullScreen: { /* TODO */ },
                     onWillEndFullScreen: { /* TODO */ },
                     horizontalSizeClass: nil
                 )
                 .id("video_\(item.id)")
             } else {
                 KFImage(item.thumbnailUrl)
                     .resizable()
                     .aspectRatio(contentMode: .fill)
                     .overlay(Color.black.opacity(0.3))
                     .overlay(ProgressView().scaleEffect(1.5).tint(.white).opacity(isActive && playerManager.playerItemID != item.id ? 1 : 0))
             }
        } else {
            KFImage(item.imageUrl)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
        
    @ViewBuilder
    private var tagSection: some View {
        if isDummyItem { EmptyView() } else {
            switch itemData.itemInfoStatus {
            case .loading:
                ProgressView().tint(.white).scaleEffect(0.7)
            case .error(let msg):
                VStack(alignment: .leading) {
                    Text("Tags nicht geladen.")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Erneut versuchen") {
                        onRetryLoadDetails()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                }
            case .loaded:
                if !itemData.displayedTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(itemData.displayedTags) { tag in
                            UnlimitedVotableTagView(
                                tag: tag,
                                currentVote: authService.votedTagStates[tag.id] ?? 0,
                                isVoting: authService.isVotingTag[tag.id] ?? false,
                                truncateText: true,
                                onUpvote: { onUpvoteTag(tag.id) },
                                onDownvote: { onDownvoteTag(tag.id) },
                                onTapTag: { onTagTapped(tag.tag) }
                            )
                        }
                        if itemData.totalTagCount > itemData.displayedTags.count {
                            let remainingCount = itemData.totalTagCount - itemData.displayedTags.count
                            Button {
                                onToggleShowAllTags()
                            } label: {
                                Text("+\(remainingCount) mehr")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else if authService.isLoggedIn && itemData.totalTagCount == 0 {
                            Button {
                                onShowAddTagSheet()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.callout)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else if itemData.totalTagCount > 0 {
                    Text("Keine Tags (Filter?).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else if authService.isLoggedIn {
                     Button {
                        onShowAddTagSheet()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            default:
                Text("Lade Tags...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    @ViewBuilder
    private var interactionButtons: some View {
        if isDummyItem { EmptyView() } else {
            VStack(spacing: 25) {
                Button { /* TODO: Like Action */ } label: { Image(systemName: "heart.fill").font(.title).foregroundColor(.white) }
                Button {
                    Self.logger.info("Kommentar-Button getippt für Item \(item.id)")
                    showingCommentsSheet = true
                } label: {
                    Image(systemName: "message.fill").font(.title).foregroundColor(.white)
                }
                Button { /* TODO: Share Action */ } label: { Image(systemName: "arrowshape.turn.up.right.fill").font(.title).foregroundColor(.white) }
            }
        }
    }
}

struct ItemCommentsSheetView: View {
    let itemId: Int
    let uploaderName: String
    let initialComments: [ItemComment]
    let initialInfoStatusProp: InfoLoadingStatus
    let onRetryLoadDetails: () -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    
    @State private var commentsToDisplay: [ItemComment]
    @State private var currentInfoStatus: InfoLoadingStatus

    init(itemId: Int, uploaderName: String, initialComments: [ItemComment], initialInfoStatusProp: InfoLoadingStatus, onRetryLoadDetails: @escaping () -> Void) {
        self.itemId = itemId
        self.uploaderName = uploaderName
        self.initialComments = initialComments
        _commentsToDisplay = State(initialValue: initialComments.sorted(by: { $0.confidence ?? 0 > $1.confidence ?? 0 }))
        self.initialInfoStatusProp = initialInfoStatusProp
        _currentInfoStatus = State(initialValue: initialInfoStatusProp)
        self.onRetryLoadDetails = onRetryLoadDetails
    }


    var body: some View {
        NavigationStack {
            VStack {
                switch currentInfoStatus {
                case .loading:
                    ProgressView("Lade Kommentare...")
                case .error(let msg):
                    Text("Fehler beim Laden der Kommentare: \(msg)")
                    Button("Erneut versuchen") { onRetryLoadDetails() }
                case .loaded:
                    if commentsToDisplay.isEmpty {
                        Text("Keine Kommentare vorhanden.")
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(commentsToDisplay) { comment in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(comment.name ?? "User").bold()
                                        Text("• \(comment.up - comment.down) • \(Date(timeIntervalSince1970: TimeInterval(comment.created)), style: .relative)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(comment.content)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                default:
                    Text("Kommentare werden geladen...")
                }
            }
            .navigationTitle("Kommentare (\(commentsToDisplay.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onChange(of: initialInfoStatusProp) { _, newStatus in
                currentInfoStatus = newStatus
                if newStatus == .loaded {
                    commentsToDisplay = initialComments.sorted(by: { $0.confidence ?? 0 > $1.confidence ?? 0 })
                }
            }
        }
    }
}


#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navService = NavigationService()
    settings.enableUnlimitedStyleFeed = true
    
    return UnlimitedStyleFeedView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navService)
}
// --- END OF COMPLETE FILE ---
