// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

// PagedDetailView.swift
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
    let player: AVPlayer?

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
            player: player,
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
    /// The list of items to display in the pager.
    @State var items: [Item]
    /// The index of the currently visible item.
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings // <-- Now used for marking seen
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) var scenePhase
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // MARK: State for View Logic
    /// Handles keyboard events (passed down to item views).
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    /// Manages the single AVPlayer instance and its state.
    @StateObject private var playerManager = VideoPlayerManager()
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

    /// Initializes the view with the items and the starting index.
    init(items: [Item], selectedIndex: Int) {
        self._items = State(initialValue: items)
        self._selectedIndex = State(initialValue: selectedIndex)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    /// Checks if the currently selected item is marked as favorited locally.
    private var isCurrentItemFavorited: Bool {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return false }
        return items[selectedIndex].favorited ?? false
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
                 tabViewPage(for: index) // <-- Aufruf der Helper-Funktion
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never)) // Use page-style swiping without index dots
        .navigationTitle(currentItemTitle) // Dynamically update title
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline) // Use inline title style on iOS
        #endif
        .onChange(of: selectedIndex) { oldValue, newValue in
             // When the selected index changes (user swipes)
             Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
             if newValue >= 0 && newValue < items.count {
                  let currentItem = items[newValue]
                  // Tell the VideoPlayerManager to set up the player for the *new* item.
                  playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: isFullscreen)
                  // Load info for the new item if needed
                  Task { await loadInfoIfNeeded(for: currentItem) }
                  // Mark the *new* item as seen
                  Task { await settings.markItemAsSeen(id: currentItem.id) } // <-- Mark as seen
             }
             isTogglingFavorite = false // Reset favorite toggle state on page change
        }
        .onAppear {
            // When the PagedDetailView first appears
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions and initial player.")
            isFullscreen = false
            isTogglingFavorite = false
            // Assign actions to the keyboard handler
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious

            // Configure the player manager with settings and set up the initial player
            playerManager.configure(settings: settings) // Configure links settings
            if selectedIndex >= 0 && selectedIndex < items.count {
                 let initialItem = items[selectedIndex]
                 playerManager.setupPlayerIfNeeded(for: initialItem, isFullscreen: isFullscreen)
                 Task { await loadInfoIfNeeded(for: initialItem) } // Load info for initial item
                 // Mark the *initial* item as seen
                 Task { await settings.markItemAsSeen(id: initialItem.id) } // <-- Mark as seen
            }
        }
        .onDisappear {
            // When the PagedDetailView disappears (navigation back or tab switch)
            Self.logger.info("PagedDetailView disappearing.")
            // Remove keyboard actions
            keyboardActionHandler.selectNextAction = nil
            keyboardActionHandler.selectPreviousAction = nil
            // Clean up player
            Self.logger.info("Cleaning up player via manager because PagedDetailView is disappearing.")
            playerManager.cleanupPlayer()
            // Reset the state for showing all tags
            showAllTagsForItem = []
            Self.logger.debug("Reset showAllTagsForItem state on disappear.")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Self.logger.debug("Scene phase changed from \(String(describing: oldPhase)) to \(String(describing: newPhase))")
            if newPhase == .active {
                Self.logger.info("App became active. Resetting transientSessionMuteState to nil.")
                settings.transientSessionMuteState = nil
                if let player = playerManager.player, player.isMuted != settings.isVideoMuted {
                     Self.logger.debug("Applying persisted mute state (\(settings.isVideoMuted)) to current player (\(playerManager.playerItemID ?? -1)) on app activation.")
                     player.isMuted = settings.isVideoMuted
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
                player: pageData.currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                displayedTags: pageData.displayedTags,
                totalTagCount: pageData.totalTagCount,
                showingAllTags: pageData.showingAllTags,
                comments: pageData.comments,
                infoLoadingStatus: pageData.status,
                loadInfoAction: loadInfoIfNeeded,
                preloadInfoAction: loadInfoIfNeeded,
                allItems: items,
                currentIndex: index,
                onWillBeginFullScreen: {
                    Self.logger.debug("[View] Callback: willBeginFullScreen")
                    self.isFullscreen = true
                },
                onWillEndFullScreen: {
                     Self.logger.debug("[View] Callback: willEndFullScreen")
                     self.isFullscreen = false
                },
                previewLinkTarget: $previewLinkTarget,
                isFavorited: items[index].favorited ?? false,
                toggleFavoriteAction: toggleFavorite,
                showAllTagsAction: {
                    let itemId = items[index].id
                    Self.logger.info("Show all tags action triggered for item \(itemId)")
                    // Add the item ID to the set, triggering a view update
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
            return nil // Return nil if index is invalid
        }

        // --- Data Preparation ---
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
                // Find children for the current comment, sort by date (or score later)
                let children = childrenByParentId[comment.id]?.sorted { $0.created < $1.created } ?? [] // Default sort by date
                let displayChildren = buildHierarchy(for: children) // Recursively build for children
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


        // --- Tag Limiting Logic (operates on pre-sorted tags) ---
        let totalTagCount = sortedTags.count
        let shouldShowAll = showAllTagsForItem.contains(itemId)

        let tagsToDisplay: [ItemTag]
        if shouldShowAll {
            tagsToDisplay = sortedTags // Show all if requested
            if statusForItem == .loaded { Self.logger.trace("Showing ALL \(totalTagCount) pre-sorted tags for item \(itemId) (user requested).") }
        } else {
            tagsToDisplay = Array(sortedTags.prefix(4)) // Show top 4 otherwise
            if statusForItem == .loaded { Self.logger.trace("Showing TOP \(tagsToDisplay.count) of \(totalTagCount) pre-sorted tags for item \(itemId) (default).") }
        }
        // --------------------------------

        // Return the prepared data including new tag info
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

            // **CORRECTED**: Create a new sorted array using sorted()
            let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
            Self.logger.trace("Sorted \(sortedTags.count) tags for item \(itemId) after fetching.")

            // Create a new response object with the sorted tags and original comments
            let updatedInfoResponse = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)

            await MainActor.run {
                loadedInfos[itemId] = updatedInfoResponse // Store the new response with sorted tags
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
            // Get top tag from the pre-sorted list
            let topTag = loadedInfos[currentItem.id]?.tags.first?.tag // .first is now highest confidence
            if let tag = topTag, !tag.isEmpty { return tag }
            else { return "Post \(currentItem.id)" }
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }

    // Favoriting Logic
    private func toggleFavorite() async {
        let localSettings = self.settings
        guard !isTogglingFavorite else { return }
        guard selectedIndex >= 0 && selectedIndex < items.count else { return }
        guard authService.isLoggedIn else { return }
        guard let nonce = authService.userNonce else { return }
        guard let collectionId = authService.favoritesCollectionId else { return }

        let currentItemIndex = selectedIndex
        let itemToToggle = items[currentItemIndex]
        let itemId = itemToToggle.id
        let targetFavoriteState = !(itemToToggle.favorited ?? false)

        Self.logger.info("Attempting to set favorite status for item \(itemId) to \(targetFavoriteState). Nonce: \(nonce)")
        isTogglingFavorite = true
        items[currentItemIndex].favorited = targetFavoriteState // Optimistic UI

        do {
            if targetFavoriteState { try await apiService.addToCollection(itemId: itemId, nonce: nonce) }
            else { try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce) }
            Self.logger.info("Successfully toggled favorite status for item \(itemId) via API.")
            await localSettings.clearFavoritesCache()
            await localSettings.updateCacheSizes()
        } catch {
            Self.logger.error("Failed to toggle favorite status for item \(itemId): \(error.localizedDescription)")
            // Revert optimistic UI only if we are still on the same item
            if selectedIndex == currentItemIndex { items[currentItemIndex].favorited = !targetFavoriteState }
        }
        // Reset toggle state only if we are still on the same item
        if selectedIndex == currentItemIndex { isTogglingFavorite = false }
        else { Self.logger.info("Favorite toggle finished, but index changed. isTogglingFavorite remains false for new item.") }
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

// Preview Provider (Unchanged)
#Preview("Preview") {
    var sampleItems = [
        Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false),
        Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true),
        Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: Int(Date().timeIntervalSince1970) - 50, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, favorited: nil)
    ]
    let settings = AppSettings()
    let authService: AuthService = {
        let auth = AuthService(appSettings: settings)
        auth.isLoggedIn = true
        auth.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1)
        auth.userNonce = "preview_nonce_12345"
        auth.favoritesCollectionId = 6749
        return auth
    }()

    return NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1)
    }
    .environmentObject(settings)
    .environmentObject(authService)
}
// --- END OF COMPLETE FILE ---
