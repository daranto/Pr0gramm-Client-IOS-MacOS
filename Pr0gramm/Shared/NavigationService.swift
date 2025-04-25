// Pr0gramm/Shared/NavigationService.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Combine

@MainActor // Ensure updates happen on the main thread
class NavigationService: ObservableObject {

    // Published property for the currently selected main tab
    @Published var selectedTab: Tab = .feed // Default to feed

    // Published property to hold a tag requested for search from another view
    @Published var pendingSearchTag: String? = nil

    // Function to request navigation to search with a specific tag
    func requestSearch(tag: String) {
        print("NavigationService: Requesting search for tag '\(tag)' and switching to Search tab.")
        // Set the tag *before* switching the tab to ensure SearchView sees it when it appears
        self.pendingSearchTag = tag
        // Switch the tab
        self.selectedTab = .search
    }
}
// --- END OF COMPLETE FILE ---
