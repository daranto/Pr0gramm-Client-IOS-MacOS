// Pr0gramm/Pr0gramm/Shared/PagedDetailViewWrapperForItem.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// Helper wrapper view to manage the @State array needed for PagedDetailView
/// when showing only a single, pre-fetched item (e.g., in previews or navigation destinations).
@MainActor
struct PagedDetailViewWrapperForItem: View {
    @State var items: [Item] // State variable holding the array with the single item.
    @ObservedObject var playerManager: VideoPlayerManager // Pass down the player manager.
    // --- NEW: Add targetCommentID ---
    let targetCommentID: Int?
    // --- END NEW ---

    /// Initializes the wrapper with the single item and the player manager.
    // --- MODIFIED: Update initializer ---
    init(item: Item, playerManager: VideoPlayerManager, targetCommentID: Int? = nil) {
        self._items = State(initialValue: [item]) // Initialize @State array
        self.playerManager = playerManager
        self.targetCommentID = targetCommentID
    }
    // --- END MODIFICATION ---

    /// Dummy load more action, not needed for a single item view.
    func dummyLoadMore() async {
        // No operation needed here.
        // Logger can be added if monitoring is desired:
        // PagedDetailViewWrapperForItem.logger.trace("dummyLoadMore called (no-op)")
    }

    // Optional: Add a logger if needed for debugging the wrapper itself
    // private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailViewWrapperForItem")

    var body: some View {
        PagedDetailView(
            items: $items, // Pass the binding to the state array
            selectedIndex: 0, // Always index 0 for the single item
            playerManager: playerManager,
            loadMoreAction: dummyLoadMore, // Pass the dummy action
            // --- NEW: Pass targetCommentID ---
            initialTargetCommentID: targetCommentID
            // --- END NEW ---
        )
        // Environment objects like settings and authService should be passed
        // by the parent view where this wrapper is used.
    }
}
// --- END OF COMPLETE FILE ---
