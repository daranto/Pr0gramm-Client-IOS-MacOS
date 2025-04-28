// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import AVKit

/// Wrapper struct used to identify the item to be shown in the link preview sheet.
struct PreviewLinkTarget: Identifiable {
    let id: Int // The item ID to preview
}

// MARK: - PagedDetailTabViewItem

/// Represents a single page (item) within the `PagedDetailView`'s `TabView`.
/// Displays the `DetailViewContent` and is responsible for triggering info loading/preloading.
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    /// The `AVPlayer` instance for this item, passed down from the `VideoPlayerManager`
    /// via `PagedDetailView`. Will be `nil` if this item is not the currently active video.
    let player: AVPlayer? // Passed down player instance

    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool
    let comments: [DisplayComment]
    let infoLoadingStatus: InfoLoadingStatus
    /// Action to load info for the *currently visible* item.
    let loadInfoAction: (Item) async -> Void
    /// Action to preload info for adjacent items.
    let preloadInfoAction: (Item) async -> Void
    /// The full list of items in the pager.
    let allItems: [Item]
    /// The index of this specific item in the `allItems` array.
    let currentIndex: Int
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    @Binding var previewLinkTarget: PreviewLinkTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void

    var body: some View {
        DetailViewContent(
            item: item,
            keyboardActionHandler: keyboardActionHandler,
            player: player, // Use the passed down player
            onWillBeginFullScreen: onWillBeginFullScreen,
            onWillEndFullScreen: onWillEndFullScreen,
            displayedTags: displayedTags,
            totalTagCount: totalTagCount,
            showingAllTags: showingAllTags,
            comments: comments,
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: isFavorited,
            toggleFavoriteAction: toggleFavoriteAction,
            showAllTagsAction: showAllTagsAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the tab page
        .onAppear {
            // Load info for this item when it becomes visible
            Task { await loadInfoAction(item) }
            // Preload info for the next and previous items for smoother navigation
            if currentIndex + 1 < allItems.count { Task { await preloadInfoAction(allItems[currentIndex + 1]) } }
            if currentIndex > 0 { Task { await preloadInfoAction(allItems[currentIndex - 1]) } }
            // Note: Marking as seen is handled in PagedDetailView's onChange(of: selectedIndex) and onAppear
        }
    }
}

// MARK: - PagedDetailView

/// A view that displays a list of items in a swipeable, paged interface (`TabView`).
/// Manages video playback via `VideoPlayerManager`, loads item details (tags/comments),
/// handles keyboard navigation, fullscreen state, favoriting actions, and marks items as seen.
struct PagedDetailView: View {
    /// The list of items to display in the pager. Passed from parent.
    let items: [Item] // Changed from @State, assuming parent manages the source list for navigation
    /// The index of the currently visible item.
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) var scenePhase
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // MARK: State for View Logic
    /// Handles keyboard events (passed down to item views).
    @StateObject private var keyboardActionHandler = KeyboardActionHandler() // Remains StateObject
    /// Manages the single AVPlayer instance and its state. Passed from parent.
    @ObservedObject var playerManager: VideoPlayerManager // <-- CHANGED to ObservedObject, passed in init
    /// Tracks if the video player is currently in fullscreen mode (managed by callbacks).
    @State private var isFullscreen = false
    /// Cache for loaded item details (tags, comments). Tags are now stored pre-sorted.
    @State private var loadedInfos: [Int: ItemsInfoResponse] = [:]
    /// Tracks the loading status for details of each item ID.
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    /// Stores the IDs of items for which the user wants to see all tags.
    @State private var showAllTagsForItem: Set<Int> = []
    /// API service instance.
    private let apiService = APIService()
    /// State variable to trigger the presentation of the linked item preview sheet.
    @State private var previewLinkTarget: PreviewLinkTarget? = nil
    /// State to prevent concurrent favorite toggle API calls.
    @State private var isTogglingFavorite = false
    /// State to manage the favorited status locally, reflecting optimistic updates.
    @State private var localFavoritedStatus: [Int: Bool] = [:]

    /// Initializes the view with the items, starting index, and the player manager.
    init(items: [Item], selectedIndex: Int, playerManager: VideoPlayerManager) { // <-- ADD playerManager parameter
        self.items = items // Store the passed items
        self._selectedIndex = State(initialValue: selectedIndex)
        self.playerManager = playerManager // <-- Store the passed manager

        // Initialize local favorite status from the initial items
        var initialFavStatus: [Int: Bool] = [:]
        for item in items {
            initialFavStatus[item.id] = item.favorited ?? false // Use nil-coalescing for safety
        }
        self._localFavoritedStatus = State(initialValue: initialFavStatus)

        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    /// Checks the local favorite status for the currently selected item.
    private var isCurrentItemFavorited: Bool {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return false }
        let currentItemID = items[selectedIndex].id
        // Return local state, fallback to original item state if not found (shouldn't happen)
        return localFavoritedStatus[currentItemID] ?? items[selectedIndex].favorited ?? false
    }

    // MARK: - Body
    var body: some View {
        // Group to apply background and sheet modifiers
        Group {
            tabViewContent // Use the extracted computed property
        }
        .background(KeyCommandView(handler: keyboardActionHandler)) // Add keyboard handling overlay
        .sheet(item: $previewLinkTarget) { targetWrapper in // Present sheet for linked item previews
             // Wrap the preview view in a navigation stack and provide environment objects
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings)
                 .environmentObject(authService)
        }
    }

    // MARK: - Extracted TabView Content
    /// The main TabView containing the pages. Extracted to help compiler diagnostics.
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
             Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
             if newValue >= 0 && newValue < items.count {
                  let currentItem = items[newValue]
                  // Use the PASSED playerManager
                  playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: isFullscreen)
                  Task { await loadInfoIfNeeded(for: currentItem) }
                  Task { await settings.markItemAsSeen(id: currentItem.id) }
             }
             isTogglingFavorite = false
        }
        .onAppear {
            Self.logger.info("PagedDetailView appeared.")
             if isFullscreen {
                 Self.logger.warning("PagedDetailView appeared while isFullscreen is true. Potential state issue.")
                 // If returning to view while fullscreen, ensure player state is correct (might already be handled by scenePhase)
                 if let currentItem = items[safe: selectedIndex], currentItem.isVideo {
                      playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: isFullscreen) // Re-validate player state
                 }
             } else {
                 isFullscreen = false // Ensure it's false on appear
             }
            isTogglingFavorite = false
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious

            // Manager should already be configured by parent view
            if selectedIndex >= 0 && selectedIndex < items.count {
                 let initialItem = items[selectedIndex]
                 // Setup player using the PASSED manager
                 playerManager.setupPlayerIfNeeded(for: initialItem, isFullscreen: isFullscreen)
                 Task { await loadInfoIfNeeded(for: initialItem) }
                 Task { await settings.markItemAsSeen(id: initialItem.id) }
            } else {
                 Self.logger.warning("PagedDetailView onAppear: Invalid selectedIndex \(selectedIndex). Cannot setup initial player.")
            }
        }
        .onDisappear {
            Self.logger.info("PagedDetailView disappearing.")
            keyboardActionHandler.selectNextAction = nil
            keyboardActionHandler.selectPreviousAction = nil

            // --- MODIFIED: Only clean up if NOT disappearing due to fullscreen ---
            if !isFullscreen {
                Self.logger.info("Cleaning up player because view is disappearing AND we are NOT in fullscreen.")
                playerManager.cleanupPlayer() // Cleanup player via the manager instance held by the parent
            } else {
                Self.logger.info("Skipping player cleanup because view is disappearing WHILE entering fullscreen.")
                // Consider pausing here if the system doesn't do it reliably,
                // although AVPlayerViewController usually handles this.
                // Task { @MainActor in playerManager.player?.pause() }
            }
            // ----------------------------------------------------------------------

            showAllTagsForItem = [] // Reset this state anyway
            Self.logger.debug("Reset showAllTagsForItem state on disappear.")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Self.logger.debug("Scene phase changed from \(String(describing: oldPhase)) to \(String(describing: newPhase))")
            if newPhase == .active {
                Self.logger.info("App became active. Resetting transientSessionMuteState to nil.")
                settings.transientSessionMuteState = nil
                // Use the passed playerManager
                if let player = playerManager.player, player.isMuted != settings.isVideoMuted {
                     Self.logger.debug("Applying persisted mute state (\(settings.isVideoMuted)) to current player (\(playerManager.playerItemID ?? -1)) on app activation.")
                     player.isMuted = settings.isVideoMuted
                }
                 // If returning to active state *while* fullscreen was active, might need to resume play
                 if isFullscreen, let player = playerManager.player, player.timeControlStatus != .playing {
                     Self.logger.info("App became active while fullscreen. Resuming player.")
                     player.play()
                 }

            } else if newPhase == .inactive || newPhase == .background {
                 // Pause when going inactive/background if not fullscreen
                  if !isFullscreen, let player = playerManager.player, player.timeControlStatus == .playing {
                     player.pause()
                     Self.logger.debug("App inactive/background, pausing non-fullscreen player.")
                  }
            }
        }
         .onChange(of: settings.commentSortOrder) { _, newOrder in
             Self.logger.info("Comment sort order changed in settings, PagedDetailView body will re-evaluate.")
         }
    }

    // MARK: - Helper Function for TabView Page Content
    /// Creates the view content for a single page in the TabView.
    @ViewBuilder
    private func tabViewPage(for index: Int) -> some View {
        // Use `if let` to get prepared data or return EmptyView if preparation fails
        if let pageData = preparePageData(for: index) {
            PagedDetailTabViewItem(
                item: pageData.currentItem,
                keyboardActionHandler: keyboardActionHandler,
                // Pass the player from the manager if the ID matches
                player: pageData.currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                displayedTags: pageData.displayedTags,
                totalTagCount: pageData.totalTagCount,
                showingAllTags: pageData.showingAllTags,
                comments: pageData.comments,
                infoLoadingStatus: pageData.status,
                loadInfoAction: loadInfoIfNeeded,
                preloadInfoAction: loadInfoIfNeeded,
                allItems: items, // Pass original items
                currentIndex: index,
                onWillBeginFullScreen: { // Fullscreen Callbacks
                    Self.logger.debug("[View] Callback: willBeginFullScreen")
                    self.isFullscreen = true
                    // System usually handles pause/resume for fullscreen AVPlayerVC
                },
                onWillEndFullScreen: {
                     Self.logger.debug("[View] Callback: willEndFullScreen")
                     self.isFullscreen = false
                     // Explicitly resume playback *after* exiting fullscreen animation completes
                     // Check if we are still on the same video item
                     if let currentItem = items[safe: self.selectedIndex], currentItem.isVideo, currentItem.id == playerManager.playerItemID {
                         Task { @MainActor in
                             // Small delay might be needed for transition to fully complete
                             try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                             // Check isFullscreen again in case state changed rapidly
                             if !self.isFullscreen && self.playerManager.player?.timeControlStatus != .playing {
                                 self.playerManager.player?.play()
                                 Self.logger.debug("[View] Explicitly calling play() on player after exiting fullscreen.")
                             } else if self.isFullscreen {
                                 Self.logger.debug("[View] Exited fullscreen callback, but isFullscreen is still true. Not playing.")
                             } else {
                                 Self.logger.debug("[View] Exited fullscreen callback, player already playing or not applicable.")
                             }
                         }
                     } else {
                         Self.logger.debug("[View] Exited fullscreen callback, but selected index/item changed or not a video. Not playing.")
                     }
                },
                previewLinkTarget: $previewLinkTarget,
                // Use the local state for the favorite button display
                isFavorited: localFavoritedStatus[pageData.currentItem.id] ?? pageData.currentItem.favorited ?? false,
                toggleFavoriteAction: toggleFavorite,
                showAllTagsAction: {
                    let itemId = pageData.currentItem.id // Use item from pageData
                    Self.logger.info("Show all tags action triggered for item \(itemId)")
                    showAllTagsForItem.insert(itemId)
                }
            )
            .tag(index)
        } else {
            EmptyView()
        }
    }

    /// Helper function to prepare hierarchical data for a single page.
    /// Works with pre-sorted tags from `loadedInfos`.
    private func preparePageData(for index: Int) -> (
        currentItem: Item,
        status: InfoLoadingStatus,
        comments: [DisplayComment],
        displayedTags: [ItemTag],
        totalTagCount: Int,
        showingAllTags: Bool
    )? {
        guard index >= 0 && index < items.count else {
            Self.logger.error("preparePageData failed: Invalid index \(index)")
            return nil
        }

        let currentItem = items[index]
        let itemId = currentItem.id
        let statusForItem = infoLoadingStatus[itemId] ?? .idle
        let baseComments = loadedInfos[itemId]?.comments ?? []
        let sortedTags = loadedInfos[itemId]?.tags ?? []

        // --- Build Comment Hierarchy ---
        let commentsById = Dictionary(grouping: baseComments, by: { $0.id }).compactMapValues { $0.first }
        var childrenByParentId: [Int: [ItemComment]] = Dictionary(grouping: baseComments, by: { $0.parent ?? 0 })
        childrenByParentId.removeValue(forKey: 0)

        func buildHierarchy(for comments: [ItemComment]) -> [DisplayComment] {
            comments.map { comment in
                let children = childrenByParentId[comment.id]?.sorted { $0.created < $1.created } ?? []
                let displayChildren = buildHierarchy(for: children)
                return DisplayComment(id: comment.id, comment: comment, children: displayChildren)
            }
        }
        let topLevelComments = baseComments.filter { $0.parent == nil || $0.parent == 0 }
        let sortedTopLevelComments: [ItemComment]
        switch settings.commentSortOrder {
        case .date: sortedTopLevelComments = topLevelComments.sorted { $0.created < $1.created }
        case .score: sortedTopLevelComments = topLevelComments.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
        }
        let displayComments = buildHierarchy(for: sortedTopLevelComments)


        // --- Tag Limiting Logic ---
        let totalTagCount = sortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)
        let tagsToDisplay: [ItemTag]
        if shouldShowAll {
            tagsToDisplay = sortedTags
            if statusForItem == .loaded { Self.logger.trace("Showing ALL \(totalTagCount) pre-sorted tags for item \(itemId) (user requested).") }
        } else {
            tagsToDisplay = Array(sortedTags.prefix(4))
            if statusForItem == .loaded { Self.logger.trace("Showing TOP \(tagsToDisplay.count) of \(totalTagCount) pre-sorted tags for item \(itemId) (default).") }
        }

        return (
            currentItem: currentItem,
            status: statusForItem,
            comments: displayComments,
            displayedTags: tagsToDisplay,
            totalTagCount: totalTagCount,
            showingAllTags: shouldShowAll
        )
    }


    // Info Loading Method - Sorts tags upon successful fetch and stores sorted result
    private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        let currentStatus = infoLoadingStatus[itemId]
        guard !(currentStatus == .loading || currentStatus == .loaded) else { return }
        if case .error = currentStatus { Self.logger.debug("Retrying info load for item \(itemId) after previous error.") }
        Self.logger.debug("Starting info load for item \(itemId)...")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }
        do {
            let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)

            let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
            Self.logger.trace("Sorted \(sortedTags.count) tags for item \(itemId) after fetching.")

            let updatedInfoResponse = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)

            await MainActor.run {
                loadedInfos[itemId] = updatedInfoResponse
                infoLoadingStatus[itemId] = .loaded
            }
        } catch {
            Self.logger.error("Failed to load info for item \(itemId): \(error.localizedDescription)")
            await MainActor.run { infoLoadingStatus[itemId] = .error(error.localizedDescription) }
        }
    }

    // Navigation Methods
    private func selectNext() { if canSelectNext { selectedIndex += 1 } }
    private var canSelectNext: Bool { selectedIndex < items.count - 1 }
    private func selectPrevious() { if canSelectPrevious { selectedIndex -= 1 } }
    private var canSelectPrevious: Bool { selectedIndex > 0 }
    private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = infoLoadingStatus[currentItem.id] ?? .idle
        switch status {
        case .loaded:
            let topTag = loadedInfos[currentItem.id]?.tags.first?.tag
            if let tag = topTag, !tag.isEmpty { return tag }
            else { return "Post \(currentItem.id)" }
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }

    // Favoriting Logic - Uses localFavoritedStatus for optimistic UI
    private func toggleFavorite() async {
        let localSettings = self.settings
        guard !isTogglingFavorite else {
            Self.logger.debug("Favorite toggle skipped: Already processing.")
            return
        }
        guard selectedIndex >= 0 && selectedIndex < items.count else {
             Self.logger.error("Cannot toggle favorite: Invalid selectedIndex \(selectedIndex)")
             return
        }
        guard authService.isLoggedIn else {
             Self.logger.warning("Cannot toggle favorite: User not logged in.")
             return
        }
        guard let nonce = authService.userNonce else {
             Self.logger.error("Cannot toggle favorite: Nonce is missing.")
             return
         }
        guard let collectionId = authService.favoritesCollectionId else {
             Self.logger.error("Cannot toggle favorite: Favorites collection ID is missing.")
             return
         }

        let currentItemIndex = selectedIndex
        let itemToToggle = items[currentItemIndex]
        let itemId = itemToToggle.id
        let currentLocalState = localFavoritedStatus[itemId] ?? itemToToggle.favorited ?? false
        let targetFavoriteState = !currentLocalState

        Self.logger.info("Attempting to set favorite status for item \(itemId) to \(targetFavoriteState). Nonce: \(nonce)")

        // Start Processing
        await MainActor.run {
             isTogglingFavorite = true
             localFavoritedStatus[itemId] = targetFavoriteState // Optimistic UI update
        }

        var success = false
        do {
            // Perform API Call
            if targetFavoriteState {
                try await apiService.addToCollection(itemId: itemId, nonce: nonce)
                Self.logger.info("API: Successfully added item \(itemId) to collection.")
            } else {
                try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
                Self.logger.info("API: Successfully removed item \(itemId) from collection \(collectionId).")
            }
            success = true
            Self.logger.info("Successfully toggled favorite status for item \(itemId) via API.")
            await localSettings.clearFavoritesCache()
            await localSettings.updateCacheSizes()

        } catch {
            success = false
            Self.logger.error("Failed to toggle favorite status for item \(itemId): \(error.localizedDescription)")
            // Revert optimistic UI
            await MainActor.run {
                 localFavoritedStatus[itemId] = !targetFavoriteState
            }
        }

        // Finally Block (Cleanup)
        await MainActor.run {
             isTogglingFavorite = false
             Self.logger.debug("Finished favorite toggle processing for item \(itemId). Success: \(success). isTogglingFavorite = false.")
        }
    }
}

// Helper extension for safe array access
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


// Wrapper View for Sheet Preview (Unchanged)
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
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                }
        }
    }
}

// Preview Provider needs adjustment to pass the PlayerManager
#Preview("Preview") {
    // --- CORRECTED PREVIEW ---
    // 1. Create instances needed for the preview
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: []) // Added badges: []
    previewAuthService.userNonce = "preview_nonce_12345"
    previewAuthService.favoritesCollectionId = 6749

    // 2. Create the PlayerManager instance for the preview
    let previewPlayerManager = VideoPlayerManager()

    // 3. Sample items
    let sampleItems = [ // Use let for preview data
        Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false),
        Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true),
        Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: Int(Date().timeIntervalSince1970) - 50, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, favorited: nil)
    ]

    // 4. Configure the manager within the preview setup
    Task { @MainActor in await previewPlayerManager.configure(settings: previewSettings) }

    // 5. Return the view hierarchy
    return NavigationStack {
        // Pass the playerManager to the PagedDetailView initializer
        PagedDetailView(items: sampleItems, selectedIndex: 1, playerManager: previewPlayerManager)
    }
    .environmentObject(previewSettings)
    .environmentObject(previewAuthService)
    // --- END CORRECTION ---
}
// --- END OF COMPLETE FILE ---
