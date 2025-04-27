import SwiftUI
import Combine

/// Manages the currently selected main tab and handles navigation requests between different parts of the app.
@MainActor // Ensure all updates to published properties happen on the main thread
class NavigationService: ObservableObject {

    /// The currently active main tab (e.g., Feed, Search). Views observe this to switch content.
    @Published var selectedTab: Tab = .feed // Default to the feed tab on launch

    /// Holds a tag string requested for search, typically set when a tag is tapped in the detail view.
    /// The `SearchView` observes this property to automatically initiate a search when the tag is set and the Search tab becomes active.
    @Published var pendingSearchTag: String? = nil

    /// Call this method to switch to the Search tab and initiate a search for the given tag.
    /// - Parameter tag: The tag string to search for.
    func requestSearch(tag: String) {
        print("NavigationService: Requesting search for tag '\(tag)' and switching to Search tab.")
        // Set the tag *before* switching the tab. This ensures SearchView
        // sees the tag when its `onAppear` or `onChange` is triggered.
        self.pendingSearchTag = tag
        // Switch the active tab to Search.
        self.selectedTab = .search
    }
}
