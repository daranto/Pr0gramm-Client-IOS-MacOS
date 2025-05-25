// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/UnlimitedStyleFeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher
import UIKit // Für UIPasteboard

// Datenmodell für die Übergabe an UnlimitedFeedItemView
struct UnlimitedFeedItemDataModel {
    let item: Item
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let comments: [ItemComment]
    let itemInfoStatus: InfoLoadingStatus
    let isFavorited: Bool
    let currentVote: Int
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
    
    private let initialVisibleTagCountInItemView = 2
    @State private var flagsUsedForLastItemsLoad: Int? = nil
    @State private var feedTypeUsedForLastLoad: FeedType? = nil
    @State private var hideSeenUsedForLastLoad: Bool? = nil
    @State private var loggedInUsedForLastLoad: Bool? = nil

    @State private var currentRefreshFeedTask: Task<Void, Never>? = nil
    @State private var debouncedRefreshTask: Task<Void, Never>? = nil

    @State private var showingShareOptionsForItemID: Int? = nil
    @State private var itemToShareWrapper: ShareableItemWrapper? = nil
    @State private var isPreparingShareGlobal = false
    @State private var sharePreparationErrorGlobal: String? = nil
    @State private var collectionSelectionSheetTarget: CollectionSelectionSheetTarget? = nil
    @State private var isProcessingFavoriteGlobal: [Int: Bool] = [:]
    
    @State private var userProfileSheetUsername: String? = nil
    
    @State private var wasPlayingBeforeFullscreen: Bool = false
    @State private var isCurrentlyInSystemFullscreen: Bool = false


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
            .navigationTitle("pr0Tok")
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
                                self.isProcessingFavoriteGlobal = [:]
                                self.flagsUsedForLastItemsLoad = nil
                                self.feedTypeUsedForLastLoad = nil
                                self.hideSeenUsedForLastLoad = nil
                                self.loggedInUsedForLastLoad = nil
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
            .sheet(item: $itemToShareWrapper, onDismiss: {
                if let tempUrl = itemToShareWrapper?.temporaryFileUrlToDelete {
                    deleteTemporaryFile(at: tempUrl)
                }
            }) { shareableItemWrapper in
                ShareSheet(activityItems: shareableItemWrapper.itemsToShare)
            }
            .sheet(item: $collectionSelectionSheetTarget) { target in
                CollectionSelectionView(
                    item: target.item,
                    onCollectionSelected: { selectedCollection in
                        Task {
                            await addActiveItemToSelectedCollection(collection: selectedCollection)
                        }
                    }
                )
                .environmentObject(authService)
                .environmentObject(settings)
                .presentationDetents([.medium, .large])
            }
            .onChange(of: collectionSelectionSheetTarget) { oldValue, newValue in
                Self.logger.info("DEBUG: collectionSelectionSheetTarget changed from \(String(describing: oldValue?.item.id)) to \(String(describing: newValue?.item.id)). Sheet should appear: \(newValue != nil)")
            }
            .sheet(item: $userProfileSheetUsername) { usernameToDisplay in
                UserProfileSheetView(username: usernameToDisplay)
                    .environmentObject(authService)
                    .environmentObject(settings)
                    .environmentObject(playerManager)
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
                
                let isInitialOrResetState = items.isEmpty || (items.count == 1 && items.first?.id == dummyStartItemID)
                
                if isInitialOrResetState && flagsUsedForLastItemsLoad == nil {
                     Self.logger.info("UnlimitedStyleFeedView.onAppear: Initial launch or full reset state. Active/Scrolled set to dummy.")
                     activeItemID = dummyStartItemID
                     scrolledItemID = dummyStartItemID
                } else if scrolledItemID == nil {
                     Self.logger.info("UnlimitedStyleFeedView.onAppear: scrolledItemID was nil, reset to activeItemID or dummyID.")
                     scrolledItemID = activeItemID ?? dummyStartItemID
                }
            }
            .task(id: "\(authService.isLoggedIn)-\(settings.apiFlags)-\(settings.feedType.rawValue)-\(settings.hideSeenItems)") {
                guard !isCurrentlyInSystemFullscreen else {
                    Self.logger.info("Task for parameter change skipped: Currently in system fullscreen.")
                    return
                }

                let currentApiFlags = settings.apiFlags
                let currentFeedType = settings.feedType
                let currentHideSeen = settings.hideSeenItems
                let currentLoggedIn = authService.isLoggedIn

                Self.logger.info("UnlimitedStyleFeedView .task triggered. Current ID: \(currentLoggedIn)-\(currentApiFlags)-\(currentFeedType.displayName)-\(currentHideSeen). Previous ID: \(loggedInUsedForLastLoad ?? false)-\(flagsUsedForLastItemsLoad ?? -1)-\(feedTypeUsedForLastLoad?.displayName ?? "nil")-\(hideSeenUsedForLastLoad ?? false)")

                let parametersActuallyChanged = (flagsUsedForLastItemsLoad != currentApiFlags ||
                                                 feedTypeUsedForLastLoad != currentFeedType ||
                                                 hideSeenUsedForLastLoad != currentHideSeen ||
                                                 loggedInUsedForLastLoad != currentLoggedIn)
                
                let isConsideredInitialLaunch = flagsUsedForLastItemsLoad == nil
                let performFullResetAndLoad = isConsideredInitialLaunch || parametersActuallyChanged

                if !performFullResetAndLoad && !(items.isEmpty || (items.count == 1 && items.first?.id == dummyStartItemID)) {
                     Self.logger.info("Task triggered, but no relevant parameters changed and items already loaded. Skipping feed reset and refresh.")
                     return
                }
                Self.logger.info("Parameters changed or initial load. Proceeding with task logic. PerformFullResetAndLoad: \(performFullResetAndLoad)")

                debouncedRefreshTask?.cancel()
                currentRefreshFeedTask?.cancel()
                
                if performFullResetAndLoad {
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
                        self.isProcessingFavoriteGlobal = [:]
                    }
                    Self.logger.info("UI reset to dummy item before starting debounced refresh due to parameter change or initial load.")
                }

                debouncedRefreshTask = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else {
                            Self.logger.info("Debounced refresh task was cancelled during sleep.")
                            return
                        }
                        
                        if self.isLoadingFeed && !performFullResetAndLoad {
                             Self.logger.info("Debounced refresh: isLoadingFeed is true (and no full reset), skipping.")
                             return
                        }

                        Self.logger.info("Starting new debounced refresh task.")
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
                Self.logger.info("UnlimitedStyleFeedView.onDisappear.")
                if !isCurrentlyInSystemFullscreen {
                    playerManager.cleanupPlayer()
                    Self.logger.info("Player cleaned up because view disappeared and not in system fullscreen.")
                } else {
                    Self.logger.info("Player NOT cleaned up on disappear: Currently in system fullscreen.")
                }
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
    
    private func handleWillBeginFullscreen() {
        Self.logger.info("handleWillBeginFullscreen called.")
        self.wasPlayingBeforeFullscreen = playerManager.player?.timeControlStatus == .playing
        self.isCurrentlyInSystemFullscreen = true
    }

    private func handleWillEndFullscreen() {
        Self.logger.info("handleWillEndFullscreen called.")
        self.isCurrentlyInSystemFullscreen = false
        if self.wasPlayingBeforeFullscreen {
            if let currentActiveId = self.activeItemID,
               let currentItem = self.items.first(where: { $0.id == currentActiveId }),
               currentItem.isVideo {
                
                playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: false)
                
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    if playerManager.playerItemID == currentItem.id && playerManager.player?.timeControlStatus != .playing {
                        Self.logger.info("Attempting to resume player for item \(currentItem.id) after exiting fullscreen.")
                        playerManager.player?.play()
                    }
                }
            }
        }
        self.wasPlayingBeforeFullscreen = false
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
        // --- MODIFIED: Bedingung vereinfacht ---
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
                         onShowFullscreenImage: { _ in },
                         onToggleFavorite: {},
                         onShowCollectionSelection: {},
                         onShareTapped: {},
                         isProcessingFavorite: false,
                         onShowUserProfile: { _ in },
                         onWillBeginFullScreenPr0Tok: handleWillBeginFullscreen,
                         onWillEndFullScreenPr0Tok: handleWillEndFullscreen
                     )
                     .frame(height: 200)
                 }
                Text(settings.hideSeenItems ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // --- END MODIFICATION ---
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
                                },
                                onToggleFavorite: {
                                    if item.id != dummyStartItemID {
                                        Task { await toggleFavoriteForActiveItem() }
                                    }
                                },
                                onShowCollectionSelection: {
                                    Self.logger.debug("onShowCollectionSelection callback TRIGGERED in UnlimitedStyleFeedView for item.id \(item.id). Current activeItemID: \(String(describing: self.activeItemID))")
                                    if let activeId = self.activeItemID, activeId != dummyStartItemID,
                                       let currentItem = self.items.first(where: { $0.id == activeId }) {
                                        Self.logger.info("Long press on favorite for item \(currentItem.id) (active). Setting collectionSelectionSheetTarget.")
                                        self.collectionSelectionSheetTarget = CollectionSelectionSheetTarget(item: currentItem)
                                    } else if item.id != dummyStartItemID {
                                        Self.logger.warning("Long press on favorite for item \(item.id) (cell's item, activeItemID was \(String(describing: self.activeItemID))). Setting collectionSelectionSheetTarget via cell's item.")
                                        self.collectionSelectionSheetTarget = CollectionSelectionSheetTarget(item: item)
                                    } else {
                                        Self.logger.warning("onShowCollectionSelection: Could not determine item for collection sheet. activeItemID: \(String(describing: self.activeItemID)), cell's item.id: \(item.id)")
                                    }
                                },
                                onShareTapped: {
                                    if item.id != dummyStartItemID {
                                        self.showingShareOptionsForItemID = item.id
                                        self.sharePreparationErrorGlobal = nil
                                    }
                                },
                                isProcessingFavorite: isProcessingFavoriteGlobal[item.id] ?? false,
                                onShowUserProfile: { username in
                                    Self.logger.info("Request to show profile for \(username) from item \(item.id)")
                                    self.userProfileSheetUsername = username
                                },
                                onWillBeginFullScreenPr0Tok: handleWillBeginFullscreen,
                                onWillEndFullScreenPr0Tok: handleWillEndFullscreen
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
                        
                        if currentItem.id != dummyStartItemID && !isCurrentlyInSystemFullscreen {
                            playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: false)
                            
                            if currentItem.isVideo && activeItemID == currentItem.id {
                                if previousActiveItemID != currentItem.id || playerManager.player?.timeControlStatus != .playing {
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        guard self.activeItemID == currentItem.id, let player = playerManager.player, !self.isCurrentlyInSystemFullscreen else {
                                            Self.logger.debug("Player start skipped for item \(currentItem.id): activeItemID changed, player nil, or in fullscreen during delay.")
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
                        } else if isCurrentlyInSystemFullscreen {
                            Self.logger.info("Scrolled to item \(currentItem.id) but currently in system fullscreen. Player setup deferred.")
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func prepareItemDataModel(for item: Item) -> UnlimitedFeedItemDataModel {
        let isFavoritedState = authService.favoritedItemIDs.contains(item.id)
        let currentVoteState = authService.votedItemStates[item.id] ?? 0

        if item.id == dummyStartItemID {
            return UnlimitedFeedItemDataModel(
                item: item,
                displayedTags: [],
                totalTagCount: 0,
                comments: [],
                itemInfoStatus: .loaded,
                isFavorited: false,
                currentVote: 0
            )
        }

        let details = cachedDetails[item.id]
        let allItemTags = details?.tags.sorted { $0.confidence > $1.confidence } ?? []
        let tagsForDisplayLogic = Array(allItemTags.prefix(initialVisibleTagCountInItemView))

        let commentsToDisplay = details?.comments ?? []
        let currentInfoStatus = infoLoadingStatus[item.id] ?? .idle

        return UnlimitedFeedItemDataModel(
            item: item,
            displayedTags: tagsForDisplayLogic,
            totalTagCount: allItemTags.count,
            comments: commentsToDisplay,
            itemInfoStatus: currentInfoStatus,
            isFavorited: isFavoritedState,
            currentVote: currentVoteState
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
            if !(self.items.count == 1 && self.items.first?.id == dummyStartItemID) && !self.items.isEmpty {
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
            self.isProcessingFavoriteGlobal = [:]
        }
        
        let currentApiFlagsForThisRefresh = settings.apiFlags
        let currentFeedTypeForThisRefresh = settings.feedType
        let currentHideSeenForThisRefresh = settings.hideSeenItems
        let currentLoggedInForThisRefresh = authService.isLoggedIn

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
                self.feedTypeUsedForLastLoad = currentFeedTypeForThisRefresh
                self.hideSeenUsedForLastLoad = currentHideSeenForThisRefresh
                self.loggedInUsedForLastLoad = currentLoggedInForThisRefresh
            }
            Self.logger.info("Refresh (Unlimited) aborted: No active content filter (apiFlags: \(currentApiFlagsForThisRefresh)). UI shows dummy item.")
            return
        }
        
        var allFetchedUnseenItems: [Item] = []
        var currentOlderThanIdForRefreshLoop: Int? = nil
        var pagesAttemptedInLoop = 0
        var apiSaysNoMoreItems = false

        do {
            // --- MODIFIED: Bedingung vereinfacht ---
            if settings.hideSeenItems {
            // --- END MODIFICATION ---
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
                    Self.logger.info("Refresh (Unlimited) successful. \(allFetchedUnseenItems.count) new items added. scrolledItemID remains on dummy. canLoadMore set to \(!apiSaysNoMoreItems).")
                }
                self.flagsUsedForLastItemsLoad = currentApiFlagsForThisRefresh
                self.feedTypeUsedForLastLoad = currentFeedTypeForThisRefresh
                self.hideSeenUsedForLastLoad = currentHideSeenForThisRefresh
                self.loggedInUsedForLastLoad = currentLoggedInForThisRefresh
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
                
                // --- MODIFIED: Bedingung vereinfacht ---
                if settings.hideSeenItems {
                // --- END MODIFICATION ---
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
            
            // --- MODIFIED: Bedingung vereinfacht ---
            if itemsToAppend.isEmpty && !apiSaysNoMoreItemsAfterLoadMore && settings.hideSeenItems {
            // --- END MODIFICATION ---
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

    private func toggleFavoriteForActiveItem() async {
        guard let activeId = activeItemID, activeId != dummyStartItemID, let item = items.first(where: { $0.id == activeId }) else {
            Self.logger.warning("Toggle Favorite: No active item or item not found.")
            return
        }
        guard !(isProcessingFavoriteGlobal[item.id] ?? false) else {
            Self.logger.debug("Favorite toggle skipped for item \(item.id): Already processing.")
            return
        }
        guard authService.isLoggedIn,
              let nonce = authService.userNonce,
              let collectionId = settings.selectedCollectionIdForFavorites else {
            Self.logger.warning("Favorite toggle skipped for item \(item.id): User not logged in, nonce missing, or no favorite collection selected in AppSettings.")
            return
        }

        let currentIsFavorited = authService.favoritedItemIDs.contains(item.id)
        let targetFavoriteState = !currentIsFavorited

        isProcessingFavoriteGlobal[item.id] = true

        do {
            if targetFavoriteState {
                try await apiService.addToCollection(itemId: item.id, collectionId: collectionId, nonce: nonce)
            } else {
                try await apiService.removeFromCollection(itemId: item.id, collectionId: collectionId, nonce: nonce)
            }

            if targetFavoriteState { authService.favoritedItemIDs.insert(item.id) }
            else { authService.favoritedItemIDs.remove(item.id) }
            
            await settings.clearFavoritesCache(username: authService.currentUser?.name, collectionId: collectionId)
            Self.logger.info("Favorite toggled successfully for item \(item.id) in collection \(collectionId). Cache cleared.")
        } catch {
            Self.logger.error("Failed to toggle favorite for item \(item.id): \(error.localizedDescription)")
            if targetFavoriteState { authService.favoritedItemIDs.remove(item.id) }
            else { authService.favoritedItemIDs.insert(item.id) }

            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                 await authService.logout()
            }
        }
        isProcessingFavoriteGlobal[item.id] = false
    }

    private func addActiveItemToSelectedCollection(collection: ApiCollection) async {
        guard let activeId = activeItemID, activeId != dummyStartItemID, let item = items.first(where: { $0.id == activeId }) else {
            Self.logger.warning("Add to Collection: No active item or item not found.")
            return
        }
        guard !(isProcessingFavoriteGlobal[item.id] ?? false) else {
            Self.logger.debug("Add to collection '\(collection.name)' skipped: Favorite toggle already processing.")
            return
        }
        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            Self.logger.warning("Add to collection '\(collection.name)' skipped: User not logged in or nonce missing.")
            return
        }

        isProcessingFavoriteGlobal[item.id] = true

        do {
            try await apiService.addToCollection(itemId: item.id, collectionId: collection.id, nonce: nonce)
            if collection.id == settings.selectedCollectionIdForFavorites {
                authService.favoritedItemIDs.insert(item.id)
            }
            await settings.clearFavoritesCache(username: authService.currentUser?.name, collectionId: collection.id)
            Self.logger.info("Successfully added item \(item.id) to collection '\(collection.name)'. Cache cleared.")
        } catch {
            Self.logger.error("Failed to add item \(item.id) to collection '\(collection.name)': \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                await authService.logout()
            }
        }
        isProcessingFavoriteGlobal[item.id] = false
    }

    private func prepareAndShareMediaForActiveItem() async {
        guard let activeId = activeItemID, activeId != dummyStartItemID, let item = items.first(where: { $0.id == activeId }) else {
            Self.logger.error("Cannot share media: No active item or item not found.")
            sharePreparationErrorGlobal = "Kein aktives Item zum Teilen."
            return
        }
        guard let mediaUrl = item.imageUrl else {
            Self.logger.error("Cannot share media: URL is nil for item \(item.id)")
            sharePreparationErrorGlobal = "Medien-URL nicht verfügbar."
            return
        }

        isPreparingShareGlobal = true
        sharePreparationErrorGlobal = nil
        var temporaryFileToDelete: URL? = nil

        defer { isPreparingShareGlobal = false }

        if item.isVideo {
            do {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                let fileName = mediaUrl.lastPathComponent
                let localUrl = temporaryDirectory.appendingPathComponent(fileName)
                temporaryFileToDelete = localUrl

                let (downloadedUrl, response) = try await URLSession.shared.download(from: mediaUrl)
                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    sharePreparationErrorGlobal = "Video-Download fehlgeschlagen (Code: \((response as? HTTPURLResponse)?.statusCode ?? -1))."
                    return
                }
                if FileManager.default.fileExists(atPath: localUrl.path) { try FileManager.default.removeItem(at: localUrl) }
                try FileManager.default.moveItem(at: downloadedUrl, to: localUrl)
                itemToShareWrapper = ShareableItemWrapper(itemsToShare: [localUrl], temporaryFileUrlToDelete: localUrl)
            } catch {
                sharePreparationErrorGlobal = "Video-Download fehlgeschlagen."
                itemToShareWrapper = ShareableItemWrapper(itemsToShare: [mediaUrl])
            }
        } else {
            let result: Result<ImageLoadingResult, KingfisherError> = await withCheckedContinuation { continuation in
                KingfisherManager.shared.downloader.downloadImage(with: mediaUrl, options: nil) { result in
                    continuation.resume(returning: result)
                }
            }
            switch result {
            case .success(let imageLoadingResult):
                itemToShareWrapper = ShareableItemWrapper(itemsToShare: [imageLoadingResult.image])
            case .failure(let error):
                if !error.isTaskCancelled && !error.isNotCurrentTask {
                    sharePreparationErrorGlobal = "Bild-Download fehlgeschlagen."
                }
            }
        }
    }

    private func copyPostLinkForActiveItem() {
        guard let activeId = activeItemID, activeId != dummyStartItemID else { return }
        let urlString = "https://pr0gramm.com/new/\(activeId)"
        UIPasteboard.general.string = urlString
        Self.logger.info("Copied Post-Link to clipboard: \(urlString)")
    }

    private func copyMediaLinkForActiveItem() {
        guard let activeId = activeItemID, activeId != dummyStartItemID, let item = items.first(where: { $0.id == activeId }) else { return }
        if let urlString = item.imageUrl?.absoluteString {
            UIPasteboard.general.string = urlString
            Self.logger.info("Copied Media-Link to clipboard: \(urlString)")
        } else {
            Self.logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)")
        }
    }

    private func deleteTemporaryFile(at url: URL) {
        Task(priority: .background) {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                Self.logger.error("Error deleting temporary shared file \(url.path): \(error.localizedDescription)")
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
