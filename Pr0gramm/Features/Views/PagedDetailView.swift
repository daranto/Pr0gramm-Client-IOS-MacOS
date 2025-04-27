import SwiftUI
import os
import AVKit

/// Wrapper struct used to identify the item to be shown in the link preview sheet.
struct PreviewLinkTarget: Identifiable {
    let id: Int // The item ID to preview
}

// MARK: - PagedDetailTabViewItem

/// Represents a single page (item) within the `PagedDetailView`'s `TabView`.
/// Encapsulates the `DetailViewContent` and handles loading/preloading item info.
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let tags: [ItemTag]
    let comments: [ItemComment]
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

    var body: some View {
        DetailViewContent(
            item: item,
            keyboardActionHandler: keyboardActionHandler,
            player: player, // Pass down the player instance
            onWillBeginFullScreen: onWillBeginFullScreen,
            onWillEndFullScreen: onWillEndFullScreen,
            tags: tags,
            comments: comments,
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: isFavorited,
            toggleFavoriteAction: toggleFavoriteAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the tab page
        .onAppear {
            // Load info for this item when it becomes visible
            Task { await loadInfoAction(item) }
            // Preload info for the next and previous items for smoother navigation
            if currentIndex + 1 < allItems.count { Task { await preloadInfoAction(allItems[currentIndex + 1]) } }
            if currentIndex > 0 { Task { await preloadInfoAction(allItems[currentIndex - 1]) } }
        }
    }
}

// MARK: - PagedDetailView

/// A view that displays a list of items in a swipeable, paged interface (`TabView`).
/// Manages video playback, loading item details (tags/comments), keyboard navigation,
/// fullscreen handling, and favoriting actions for the currently displayed item.
struct PagedDetailView: View {
    /// The list of items to display in the pager.
    @State var items: [Item]
    /// The index of the currently visible item.
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // MARK: State for View Logic
    /// Handles keyboard events (forwarded to `PagedDetailTabViewItem`).
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    /// The active AVPlayer instance (only one at a time).
    @State private var player: AVPlayer? = nil
    /// The ID of the item the current `player` is associated with.
    @State private var playerItemID: Int? = nil
    /// Observes the `isMuted` property of the player to sync with global settings.
    @State private var muteObserver: NSKeyValueObservation? = nil
    /// Observes when the player item finishes playing (for looping).
    @State private var loopObserver: NSObjectProtocol? = nil
    /// Tracks if the video player is currently in fullscreen mode.
    @State private var isFullscreen = false
    /// Cache for loaded item details (tags, comments). Keyed by item ID.
    @State private var loadedInfos: [Int: ItemsInfoResponse] = [:]
    /// Tracks the loading status for details of each item ID.
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
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
        // Use the local `favorited` property, defaulting to false if nil
        return items[selectedIndex].favorited ?? false
    }

    // MARK: - Body
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                let currentItem = items[index]
                // Retrieve cached info and status for the item
                let statusForItem = infoLoadingStatus[currentItem.id] ?? .idle
                let tagsForItem = loadedInfos[currentItem.id]?.tags.sorted { $0.confidence > $1.confidence } ?? []
                let commentsForItem = loadedInfos[currentItem.id]?.comments ?? []

                PagedDetailTabViewItem(
                    item: currentItem,
                    keyboardActionHandler: keyboardActionHandler,
                    // Pass the player only if its ID matches the current item's ID
                    player: currentItem.id == self.playerItemID ? self.player : nil,
                    tags: tagsForItem,
                    comments: commentsForItem,
                    infoLoadingStatus: statusForItem,
                    loadInfoAction: loadInfoIfNeeded, // Action to load info for visible item
                    preloadInfoAction: loadInfoIfNeeded, // Action to preload adjacent items
                    allItems: items,
                    currentIndex: index,
                    onWillBeginFullScreen: { // Callback for entering fullscreen
                        Self.logger.debug("Callback: willBeginFullScreen")
                        self.isFullscreen = true
                    },
                    onWillEndFullScreen: { // Callback for exiting fullscreen
                         Self.logger.debug("Callback: willEndFullScreen")
                         self.isFullscreen = false
                         // Ensure playback resumes if it was paused by fullscreen exit
                         if self.playerItemID == currentItem.id && self.player?.timeControlStatus != .playing {
                             Self.logger.debug("Ensuring player resumes after fullscreen end.")
                             self.player?.play()
                         }
                    },
                    previewLinkTarget: $previewLinkTarget,
                    isFavorited: items[index].favorited ?? false, // Pass favorite status
                    toggleFavoriteAction: toggleFavorite // Pass toggle action
                )
                .tag(index) // Associate the view with its index for TabView selection
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never)) // Use page-style swiping without index dots
        .navigationTitle(currentItemTitle) // Dynamically update title
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline) // Use inline title style on iOS
        #endif
        .onChange(of: selectedIndex) { oldValue, newValue in
             // Handle cleanup and setup when the selected item changes
             Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
             // Cleanup player for the item that is no longer visible
             if oldValue >= 0 && oldValue < items.count {
                 cleanupCurrentPlayerIfNeeded(for: items[oldValue])
             }
             // Setup player and load info for the newly selected item
             if newValue >= 0 && newValue < items.count {
                  Task { await setupAndPlayPlayerIfNeeded(for: items[newValue]) }
                  Task { await loadInfoIfNeeded(for: items[newValue]) }
             }
             isTogglingFavorite = false // Reset favorite toggle state on page change
        }
        .onAppear {
            // Initial setup when the view appears
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions.")
            isFullscreen = false
            isTogglingFavorite = false
            // Assign actions to the keyboard handler
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
            // Setup player and load info for the initially selected item
            if selectedIndex >= 0 && selectedIndex < items.count {
                 Task { await setupAndPlayPlayerIfNeeded(for: items[selectedIndex]) }
                 Task { await loadInfoIfNeeded(for: items[selectedIndex]) }
            }
        }
        .onDisappear {
            // Cleanup when the view disappears
             Self.logger.info("PagedDetailView disappearing. isFullscreen: \(self.isFullscreen)")
             // Remove keyboard actions
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
             // Only cleanup the player if *not* transitioning to/from fullscreen
             if !isFullscreen {
                 Self.logger.info("Cleaning up player because view is disappearing (not fullscreen).")
                 cleanupCurrentPlayer()
             } else {
                 Self.logger.info("Skipping player cleanup because view is entering/is in fullscreen.")
             }
        }
        .background(KeyCommandView(handler: keyboardActionHandler)) // Add keyboard handling overlay
        .sheet(item: $previewLinkTarget) { targetWrapper in // Present sheet for linked item previews
             // Wrap the preview view in a navigation stack and provide environment objects
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings)
                 .environmentObject(authService)
        }
    }

    // MARK: - Player Management Methods

    /// Sets up and starts playing the AVPlayer for a given video item if necessary.
    /// Cleans up any existing player first. Handles mute state and looping.
    /// - Parameter item: The `Item` to potentially play.
    private func setupAndPlayPlayerIfNeeded(for item: Item) async {
        // Only proceed if the item is a video
        guard item.isVideo else {
            Self.logger.debug("Item \(item.id) is not a video. Skipping player setup.")
            // If a player exists for a different item, clean it up
            if playerItemID != nil { cleanupCurrentPlayer() }
            return
        }

        // Avoid re-setup if the player already exists for this item
        guard playerItemID != item.id else {
            Self.logger.debug("Player already exists for video item \(item.id). Ensuring it plays.")
            // Ensure playback if it was paused (e.g., by backgrounding)
            if player?.timeControlStatus != .playing {
                player?.play()
            }
            return
        }

        // Cleanup existing player before creating a new one
        cleanupCurrentPlayer()
        Self.logger.debug("Setting up player for video item \(item.id)...")

        // Get the video URL
        guard let url = item.imageUrl else {
            Self.logger.error("Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        // Create and configure the new player instance
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        self.playerItemID = item.id
        newPlayer.isMuted = settings.isVideoMuted // Apply global mute setting
        Self.logger.info("Player initial mute state for item \(item.id) set to: \(settings.isVideoMuted)")

        // Observe the player's mute state to update the global setting if changed via player controls
        self.muteObserver = newPlayer.observe(\.isMuted, options: [.new]) { observedPlayer, change in
             guard let newMutedState = change.newValue,
                   observedPlayer == self.player, // Ensure observation is for the current player
                   self.playerItemID == item.id // Ensure observation is for the current item
             else { return }

             // Update global setting on the main thread if it differs
             Task { @MainActor in
                 if self.settings.isVideoMuted != newMutedState {
                     Self.logger.info("User changed mute via player controls for item \(item.id). New state: \(newMutedState). Updating global setting.")
                     self.settings.isVideoMuted = newMutedState
                 }
             }
         }
        Self.logger.debug("Added mute KVO observer for item \(item.id).")


        // Set up looping behavior
        guard let playerItem = newPlayer.currentItem else {
            Self.logger.error("Newly created player has no currentItem for item \(item.id). Cannot add loop observer.")
            cleanupCurrentPlayer() // Clean up partially set up player
            return
        }
        // Add observer for the AVPlayerItemDidPlayToEndTime notification
        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem, // Observe only the current player's item
            queue: .main // Perform action on the main queue
        ) { notification in
             // Ensure the notification is for the currently active player and item
             guard let currentPlayer = self.player,
                   (notification.object as? AVPlayerItem) == currentPlayer.currentItem,
                   self.playerItemID == item.id
             else { return }

             Self.logger.debug("Video did play to end time for item \(item.id). Seeking to zero and replaying.")
             currentPlayer.seek(to: .zero) // Seek back to the beginning
             currentPlayer.play() // Start playing again
         }
        Self.logger.debug("Added loop observer for item \(item.id).")

        // Start playback automatically, unless the view is appearing due to fullscreen transition
        if !isFullscreen {
            newPlayer.play()
            Self.logger.debug("Player started (Autoplay) for item \(item.id)")
        } else {
             Self.logger.debug("Skipping initial play because isFullscreen is true.")
        }
    }

    /// Cleans up the player associated with a specific item, usually called when swiping away.
    /// - Parameter item: The item whose player should be cleaned up.
    private func cleanupCurrentPlayerIfNeeded(for item: Item) {
        if playerItemID == item.id {
            Self.logger.debug("Cleaning up player for previous item \(item.id) due to index change.")
            cleanupCurrentPlayer()
        }
    }

    /// Stops the current player, removes observers, and resets player state variables.
    private func cleanupCurrentPlayer() {
        // Only cleanup if there's something to cleanup
        guard player != nil || muteObserver != nil || loopObserver != nil else { return }

        let currentItemID = self.playerItemID ?? -1 // Log the ID being cleaned up
        Self.logger.debug("Cleaning up player state for item \(currentItemID)...")

        // Invalidate KVO observer
        muteObserver?.invalidate()
        muteObserver = nil

        // Remove NotificationCenter observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil
        }

        // Pause and release the player instance
        player?.pause()
        player = nil
        playerItemID = nil

        Self.logger.debug("Player state cleanup finished for item \(currentItemID).")
    }

    // MARK: - Info Loading Methods

    /// Loads tags and comments for a given item if they haven't been loaded or are currently loading.
    /// - Parameter item: The item whose info needs to be loaded.
    private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        let currentStatus = infoLoadingStatus[itemId]

        // Skip if already loaded or currently loading
        guard !(currentStatus == .loading || currentStatus == .loaded) else {
            Self.logger.trace("Skipping info load for item \(itemId) - already loaded or loading.")
            return
        }

        // Log if retrying after a previous error
        if case .error = currentStatus {
            Self.logger.debug("Retrying info load for item \(itemId) after previous error.")
        }

        Self.logger.debug("Starting info load for item \(itemId)...")
        await MainActor.run { infoLoadingStatus[itemId] = .loading } // Update status to loading

        do {
            // Fetch info from the API
            let infoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            // Update state on the main thread with the fetched data
            await MainActor.run {
                loadedInfos[itemId] = infoResponse
                infoLoadingStatus[itemId] = .loaded
                Self.logger.debug("Successfully loaded info for item \(itemId). Tags: \(infoResponse.tags.count), Comments: \(infoResponse.comments.count)")
            }
        } catch {
            // Handle API errors
            Self.logger.error("Failed to load info for item \(itemId): \(error.localizedDescription)")
            await MainActor.run {
                infoLoadingStatus[itemId] = .error(error.localizedDescription) // Update status to error
            }
        }
    }

    // MARK: - Navigation Methods

    /// Selects the next item in the pager if possible.
    private func selectNext() { if canSelectNext { selectedIndex += 1 } }
    /// Checks if there is a next item to select.
    private var canSelectNext: Bool { selectedIndex < items.count - 1 }
    /// Selects the previous item in the pager if possible.
    private func selectPrevious() { if canSelectPrevious { selectedIndex -= 1 } }
    /// Checks if there is a previous item to select.
    private var canSelectPrevious: Bool { selectedIndex > 0 }

    /// Provides a dynamic title for the navigation bar based on the current item and info loading status.
    /// Uses the top tag if available, otherwise defaults to "Post [ID]".
    private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = infoLoadingStatus[currentItem.id] ?? .idle

        switch status {
        case .loaded:
            // Find the tag with the highest confidence
            let topTag = loadedInfos[currentItem.id]?.tags.max(by: { $0.confidence < $1.confidence })?.tag
            if let tag = topTag, !tag.isEmpty { return tag } // Use top tag if found
            else { return "Post \(currentItem.id)" } // Fallback to ID
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)" // Default while idle
        }
    }

    // MARK: - Favoriting Logic

    /// Toggles the favorite status of the currently selected item.
    /// Performs optimistic UI update and calls the appropriate API endpoint.
    /// Invalidates the favorites cache on success. Handles errors and potential race conditions.
    private func toggleFavorite() async {
        // Prevent concurrent calls or calls when not logged in/invalid state
        guard !isTogglingFavorite else { Self.logger.debug("Favorite toggle skipped: Action already in progress."); return }
        guard selectedIndex >= 0 && selectedIndex < items.count else { Self.logger.error("Favorite toggle failed: Invalid selected index \(selectedIndex)."); return }
        guard authService.isLoggedIn else { Self.logger.warning("Favorite toggle failed: User is not logged in."); return }
        guard let nonce = authService.userNonce else { Self.logger.error("Favorite toggle failed: User nonce is missing."); return }
        // Crucially requires the collection ID for removal
        guard let collectionId = authService.favoritesCollectionId else { Self.logger.error("Favorite toggle failed: Favorites Collection ID is missing."); return }

        let currentItemIndex = selectedIndex // Capture index at start of operation
        let itemToToggle = items[currentItemIndex]
        let itemId = itemToToggle.id
        let targetFavoriteState = !(itemToToggle.favorited ?? false) // The desired state after toggling

        Self.logger.info("Attempting to set favorite status for item \(itemId) to \(targetFavoriteState). Nonce: \(nonce)")
        isTogglingFavorite = true // Disable button

        // Optimistic UI Update: Change local state immediately
        items[currentItemIndex].favorited = targetFavoriteState

        do {
            // Call the correct API endpoint based on the target state
            if targetFavoriteState {
                // Adding to favorites (default collection)
                try await apiService.addToCollection(itemId: itemId, nonce: nonce)
            } else {
                // Removing from favorites (requires collection ID)
                try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
            }
            Self.logger.info("Successfully toggled favorite status for item \(itemId) via API.")

            // Clear the favorites cache in AppSettings as the content has changed
            await settings.clearFavoritesCache()
            // Update cache sizes (optional, but good practice)
            await settings.updateCacheSizes()

        } catch {
            Self.logger.error("Failed to toggle favorite status for item \(itemId): \(error.localizedDescription)")
            // Rollback Optimistic UI on error, but only if the user hasn't swiped away
            if selectedIndex == currentItemIndex {
                items[currentItemIndex].favorited = !targetFavoriteState
            }
            // Optional: Display an error message to the user here
        }

        // Re-enable the button, but only if the user is still viewing the same item
        if selectedIndex == currentItemIndex {
             isTogglingFavorite = false
        } else {
            // If the user swiped away while the API call was in progress,
            // the 'isTogglingFavorite' state for the *new* item should remain false.
            Self.logger.info("Favorite toggle finished, but selected index changed during operation. isTogglingFavorite remains false for new item.")
        }
    }
}

// MARK: - Wrapper View for Sheet Preview

/// A wrapper view used to present `LinkedItemPreviewView` within a `NavigationStack`
/// when shown in a sheet. It provides the necessary environment objects and toolbar.
struct LinkedItemPreviewWrapperView: View {
    let itemID: Int
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            LinkedItemPreviewView(itemID: itemID)
                // Pass down environment objects
                .environmentObject(settings)
                .environmentObject(authService)
                .navigationTitle("Vorschau")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    // Add a "Done" button to dismiss the sheet
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            dismiss()
                        }
                    }
                }
        }
    }
}


// MARK: - Preview Provider

#Preview("Preview") {
    // Sample data for the preview
    let sampleItems = [
        Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false),
        Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true), // Favorited item
        Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: Int(Date().timeIntervalSince1970) - 50, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil, favorited: nil) // Favorite status unknown/nil
    ]
    // Setup necessary services for the preview
    let settings = AppSettings()
    let authService: AuthService = {
        let auth = AuthService(appSettings: settings)
        auth.isLoggedIn = true
        auth.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1)
        auth.userNonce = "preview_nonce_12345" // Provide a dummy nonce
        auth.favoritesCollectionId = 6749 // Provide a dummy collection ID
        return auth
    }()

    // Embed PagedDetailView in NavigationStack for preview context
    return NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1) // Start at the video item
    }
    .environmentObject(settings)
    .environmentObject(authService)
}
