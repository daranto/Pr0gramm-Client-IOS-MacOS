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
            // Pass the player instance received from the parent
            player: player,
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
/// Manages video playback via `VideoPlayerManager`, loads item details (tags/comments),
/// handles keyboard navigation, fullscreen state, and favoriting actions.
struct PagedDetailView: View {
    /// The list of items to display in the pager.
    @State var items: [Item]
    /// The index of the currently visible item.
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) var scenePhase // Keep ScenePhase environment value
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // MARK: State for View Logic
    /// Handles keyboard events (passed down to item views).
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    /// Manages the single AVPlayer instance and its state.
    @StateObject private var playerManager = VideoPlayerManager()
    /// Tracks if the video player is currently in fullscreen mode (managed by callbacks).
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
                let currentItem = items[index]
                // Retrieve cached info and status for the item
                let statusForItem = infoLoadingStatus[currentItem.id] ?? .idle
                let tagsForItem = loadedInfos[currentItem.id]?.tags.sorted { $0.confidence > $1.confidence } ?? []
                let commentsForItem = loadedInfos[currentItem.id]?.comments ?? []

                PagedDetailTabViewItem(
                    item: currentItem,
                    keyboardActionHandler: keyboardActionHandler,
                    // Provide the player from the manager *only if* the item ID matches the manager's current item ID
                    player: currentItem.id == playerManager.playerItemID ? playerManager.player : nil,
                    tags: tagsForItem,
                    comments: commentsForItem,
                    infoLoadingStatus: statusForItem,
                    loadInfoAction: loadInfoIfNeeded, // Pass info loading action
                    preloadInfoAction: loadInfoIfNeeded, // Pass preloading action
                    allItems: items,
                    currentIndex: index,
                    onWillBeginFullScreen: { // Fullscreen callbacks
                        Self.logger.debug("[View] Callback: willBeginFullScreen")
                        self.isFullscreen = true
                    },
                    onWillEndFullScreen: {
                         Self.logger.debug("[View] Callback: willEndFullScreen")
                         self.isFullscreen = false
                         // Player restart after fullscreen is handled by AVPlayerViewController itself or manager if needed
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
             // When the selected index changes (user swipes)
             Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
             if newValue >= 0 && newValue < items.count {
                  // Tell the VideoPlayerManager to set up the player for the *new* item.
                  // The manager handles cleaning up the old player internally if necessary.
                  playerManager.setupPlayerIfNeeded(for: items[newValue], isFullscreen: isFullscreen)
                  // Load info for the new item if needed
                  Task { await loadInfoIfNeeded(for: items[newValue]) }
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
                 playerManager.setupPlayerIfNeeded(for: items[selectedIndex], isFullscreen: isFullscreen)
                 Task { await loadInfoIfNeeded(for: items[selectedIndex]) } // Load info for initial item
            }
        }
        .onDisappear {
            // When the PagedDetailView disappears (navigation back or tab switch)
            Self.logger.info("PagedDetailView disappearing.")
            // Remove keyboard actions
            keyboardActionHandler.selectNextAction = nil
            keyboardActionHandler.selectPreviousAction = nil

            // Crucial: Tell the VideoPlayerManager to clean up the player instance.
            // This stops playback and releases resources reliably.
            Self.logger.info("Cleaning up player via manager because PagedDetailView is disappearing.")
            playerManager.cleanupPlayer()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Self.logger.debug("Scene phase changed from \(String(describing: oldPhase)) to \(String(describing: newPhase))")
            if newPhase == .active {
                // Reset the transient session state when app becomes active.
                // The next player setup will then read the persisted setting.
                Self.logger.info("App became active. Resetting transientSessionMuteState to nil.")
                settings.transientSessionMuteState = nil

                // Also apply the persisted state to the *currently running* player immediately.
                if let player = playerManager.player, player.isMuted != settings.isVideoMuted {
                     Self.logger.debug("Applying persisted mute state (\(settings.isVideoMuted)) to current player (\(playerManager.playerItemID ?? -1)) on app activation.")
                     player.isMuted = settings.isVideoMuted
                }
            }
            // Optional: Pause player when app goes to background?
            // else if newPhase == .background || newPhase == .inactive {
            //     playerManager.player?.pause()
            //     Self.logger.debug("App became inactive/background. Paused player.")
            // }
        }
    }

    // Info Loading Methods
    private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        let currentStatus = infoLoadingStatus[itemId]
        guard !(currentStatus == .loading || currentStatus == .loaded) else {
            // Self.logger.trace("Skipping info load for item \(itemId) - already loaded or loading.") // Too verbose maybe
            return
        }
        if case .error = currentStatus {
            Self.logger.debug("Retrying info load for item \(itemId) after previous error.")
        }
        Self.logger.debug("Starting info load for item \(itemId)...")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }
        do {
            let infoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            await MainActor.run {
                loadedInfos[itemId] = infoResponse
                infoLoadingStatus[itemId] = .loaded
                // Self.logger.debug("Successfully loaded info for item \(itemId). Tags: \(infoResponse.tags.count), Comments: \(infoResponse.comments.count)") // Can be verbose
            }
        } catch {
            Self.logger.error("Failed to load info for item \(itemId): \(error.localizedDescription)")
            await MainActor.run {
                infoLoadingStatus[itemId] = .error(error.localizedDescription)
            }
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
            let topTag = loadedInfos[currentItem.id]?.tags.max(by: { $0.confidence < $1.confidence })?.tag
            if let tag = topTag, !tag.isEmpty { return tag }
            else { return "Post \(currentItem.id)" }
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }

    // Favoriting Logic
    private func toggleFavorite() async {
        let localSettings = self.settings // Capture settings

        guard !isTogglingFavorite else { Self.logger.debug("Favorite toggle skipped: Action already in progress."); return }
        guard selectedIndex >= 0 && selectedIndex < items.count else { Self.logger.error("Favorite toggle failed: Invalid selected index \(selectedIndex)."); return }
        guard authService.isLoggedIn else { Self.logger.warning("Favorite toggle failed: User is not logged in."); return }
        guard let nonce = authService.userNonce else { Self.logger.error("Favorite toggle failed: User nonce is missing."); return }
        guard let collectionId = authService.favoritesCollectionId else { Self.logger.error("Favorite toggle failed: Favorites Collection ID is missing."); return }

        let currentItemIndex = selectedIndex
        let itemToToggle = items[currentItemIndex]
        let itemId = itemToToggle.id
        let targetFavoriteState = !(itemToToggle.favorited ?? false)

        Self.logger.info("Attempting to set favorite status for item \(itemId) to \(targetFavoriteState). Nonce: \(nonce)")
        isTogglingFavorite = true
        items[currentItemIndex].favorited = targetFavoriteState // Optimistic UI

        do {
            if targetFavoriteState {
                try await apiService.addToCollection(itemId: itemId, nonce: nonce)
            } else {
                try await apiService.removeFromCollection(itemId: itemId, collectionId: collectionId, nonce: nonce)
            }
            Self.logger.info("Successfully toggled favorite status for item \(itemId) via API.")
            await localSettings.clearFavoritesCache()
            await localSettings.updateCacheSizes()

        } catch {
            Self.logger.error("Failed to toggle favorite status for item \(itemId): \(error.localizedDescription)")
            // Rollback UI only if we are still on the same item
            if selectedIndex == currentItemIndex {
                items[currentItemIndex].favorited = !targetFavoriteState
            }
        }

        // Reset flag only if we are still on the same item
        if selectedIndex == currentItemIndex {
             isTogglingFavorite = false
        } else {
            Self.logger.info("Favorite toggle finished, but selected index changed during operation. isTogglingFavorite remains false for new item.")
            // The new item will have its own isTogglingFavorite state (which starts as false)
        }
    }
}

// Wrapper View for Sheet Preview
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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// Preview Provider
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
