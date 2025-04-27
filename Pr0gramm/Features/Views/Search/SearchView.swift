import SwiftUI
import os

/// View responsible for searching items based on tags entered by the user.
/// Displays results in a grid and allows navigation to the detail view.
/// Also handles programmatic search requests initiated from other views (e.g., tapping a tag).
struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigationService: NavigationService // To observe pending search tags
    /// The text entered by the user in the search bar.
    @State private var searchText = ""
    /// The list of items found by the search.
    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    /// Flag indicating if a search has been performed at least once.
    @State private var hasSearched = false
    /// Navigation path for programmatic navigation within this tab.
    @State private var navigationPath = NavigationPath()
    /// Tracks if the initial search triggered by `navigationService.pendingSearchTag` on appear has run.
    @State private var didPerformInitialPendingSearch = false

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")
    /// Grid layout definition.
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                // Display content based on the current state
                 if isLoading {
                    ProgressView("Suche läuft...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    // Show error message using ContentUnavailableView
                    ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await performSearch() } } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasSearched {
                    // Initial state before any search is performed
                    ContentUnavailableView("Suche nach Tags", systemImage: "tag")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                     // State after a search yielded no results
                     ContentUnavailableView.search(text: searchText) // Use standard no search results view
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Display search results grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(items) { item in
                                NavigationLink(value: item) { FeedItemThumbnail(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Suche")
            // Integrate searchable modifier for the search bar
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            // Trigger search when user submits from keyboard
            .onSubmit(of: .search) { Task { await performSearch() } }
            // Navigation destination for tapped items
            .navigationDestination(for: Item.self) { destinationItem in
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(items: items, selectedIndex: index)
                 } else {
                     Text("Fehler: Item nicht in Suchergebnissen gefunden.")
                 }
             }
            // Handle pending search tag when the view appears
            .onAppear {
                // Check only if we haven't already processed a pending tag on this appear cycle
                if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty {
                    Self.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true // Mark as processed for this appearance
                }
            }
            // Handle pending search tag if it changes while the view is visible
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in
                if let tagToSearch = newTag, !tagToSearch.isEmpty {
                    Self.logger.info("Received pending search tag via onChange: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    // Reset the appear flag if a new tag comes in while visible
                    didPerformInitialPendingSearch = true
                }
            }
            // Reset state if search text is cleared after a search was performed
            .onChange(of: searchText) { oldValue, newValue in
                 if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                     Task { @MainActor in items = []; hasSearched = false; errorMessage = nil; didPerformInitialPendingSearch = false }
                 }
             }
             // Reset the initial search flag when the view disappears (e.g., tab switch)
             .onDisappear {
                 didPerformInitialPendingSearch = false
             }
        }
    }

    /// Updates the local search text, performs the search, and clears the pending tag in `NavigationService`.
    /// - Parameter tagToSearch: The tag received from `NavigationService`.
    private func processPendingTag(_ tagToSearch: String) {
         // Update the search bar text
         self.searchText = tagToSearch
         Task {
             // Perform the search automatically
             await performSearch()
             // Clear the pending tag in the central service *after* processing it
             await MainActor.run {
                  // Check again to avoid race conditions if the tag changed rapidly
                  if navigationService.pendingSearchTag == tagToSearch {
                       navigationService.pendingSearchTag = nil
                  }
             }
         }
    }

    /// Performs the API search based on the current `searchText`. Updates state variables for loading, results, and errors.
    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prevent search with empty or whitespace-only text
        guard !trimmedSearchText.isEmpty else {
            Self.logger.info("Search skipped: search text is empty.")
            // Reset state if search is cancelled by clearing text
            await MainActor.run { items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false }
            return
        }

        Self.logger.info("Performing search for tags: '\(trimmedSearchText)'")
        // Set loading state immediately
        await MainActor.run { isLoading = true; errorMessage = nil; items = []; hasSearched = true }

        // Ensure loading state is reset when function exits
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            // Perform the API call
            let fetchedItems = try await apiService.searchItems(tags: trimmedSearchText, flags: settings.apiFlags)
            // Check if the search text changed *during* the async API call
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Only update the UI if the search text is still the same
            if currentSearchText == trimmedSearchText {
                await MainActor.run { self.items = fetchedItems }
                Self.logger.info("Search successful, found \(fetchedItems.count) items for '\(trimmedSearchText)'.")
            } else {
                 Self.logger.info("Search results for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
            }
        } catch {
            // Handle API errors
            Self.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)")
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
             // Only show the error if the search text hasn't changed
            if currentSearchText == trimmedSearchText {
                 await MainActor.run { self.errorMessage = "Fehler: \(error.localizedDescription)"; self.items = [] }
             } else {
                  Self.logger.info("Search error for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
             }
        }
    }
}

// MARK: - Preview

#Preview {
    // Setup necessary services for the preview
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    // Preview the SearchView directly
    return SearchView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
