// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// View responsible for searching items based on tags entered by the user.
/// Displays results in a grid and allows navigation to the detail view.
/// Includes a local toggle to search in "New" or "Promoted" items and a button to adjust content filters.
struct SearchView: View {
    @EnvironmentObject var settings: AppSettings // Needed for content flags (apiFlags) and filter sheet
    @EnvironmentObject var authService: AuthService // Needed for filter sheet
    @EnvironmentObject var navigationService: NavigationService
    @State private var searchText = ""
    // --- MODIFIED: Remove private for binding ---
    @State var items: [Item] = []
    // --- END MODIFICATION ---
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    @State private var didPerformInitialPendingSearch = false

    @State private var searchFeedType: FeedType = .promoted // Default to searching 'Promoted'
    @State private var showingFilterSheet = false

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")

    private var gridColumns: [GridItem] {
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                HStack {
                    Picker("Suche in", selection: $searchFeedType) {
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Spacer(minLength: 15)

                    Button { showingFilterSheet = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .padding(.leading, -5)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                searchContentView // The main content (grid, messages, etc.)
            }
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { Task { await performSearch() } }
            .navigationDestination(for: Item.self) { destinationItem in
                // --- MODIFIED: Call helper function ---
                detailView(for: destinationItem)
                // --- END MODIFICATION ---
             }
            .onAppear { if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty { SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'"); processPendingTag(tagToSearch); didPerformInitialPendingSearch = true } }
            .task { playerManager.configure(settings: settings) }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView(hideFeedOptions: true) // Pass parameter here
                     .environmentObject(settings)
                     .environmentObject(authService)
             }
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in if let tagToSearch = newTag, !tagToSearch.isEmpty { SearchView.logger.info("Received pending search tag via onChange: '\(tagToSearch)'"); processPendingTag(tagToSearch); didPerformInitialPendingSearch = true } }
            .onChange(of: searchText) { oldValue, newValue in
                if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                    Task { @MainActor in // Ensure UI updates are on main actor
                        items = []
                        hasSearched = false
                        errorMessage = nil
                        didPerformInitialPendingSearch = false
                    }
                }
            }
            .onDisappear { didPerformInitialPendingSearch = false }
            .onChange(of: settings.seenItemIDs) { _, _ in SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.") }
            .onChange(of: searchFeedType) { _, _ in
                 if hasSearched && !isLoading {
                      SearchView.logger.info("Local searchFeedType changed, re-running search for '\(searchText)'")
                      Task { await performSearch() }
                 }
            }
        }
    }

    // --- NEW: Helper function for Navigation Destination ---
    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            // Note: Search doesn't have pagination, so a dummy action is fine.
            // If pagination were added later, this action would need to be real.
            PagedDetailView(
                items: $items, // Pass binding
                selectedIndex: index,
                playerManager: playerManager,
                loadMoreAction: { SearchView.logger.trace("Load More triggered from Search detail (No-Op)") } // Dummy action
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in current search results.")
                 }
        }
    }
    // --- END NEW ---

    // MARK: - Extracted Content View
    @ViewBuilder private var searchContentView: some View {
        if isLoading {
            ProgressView("Suche läuft...")
                .font(UIConstants.bodyFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle").font(UIConstants.headlineFont) }
            description: { Text(error).font(UIConstants.bodyFont) }
            actions: { Button("Erneut versuchen") { Task { await performSearch() } }.font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasSearched {
            ContentUnavailableView("Suche nach Tags", systemImage: "tag").font(UIConstants.headlineFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
             ContentUnavailableView { Label("Keine Ergebnisse", systemImage: "magnifyingglass").font(UIConstants.headlineFont) }
             description: { Text("Keine Posts für '\(searchText)' gefunden (\(searchFeedType.displayName)).").font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            searchResultsGrid // The ScrollView with the LazyVGrid
        }
    }

    // MARK: - ScrollView/Grid
    private var searchResultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
    }

    // MARK: - Helper Methods
    private func processPendingTag(_ tagToSearch: String) {
         Task { @MainActor in // Ensure UI updates are on main actor
            self.searchText = tagToSearch
         }
        Task {
             await performSearch();
             // Clear pending tag *after* search completes
             await MainActor.run {
                 // Check again in case it changed while searching
                 if navigationService.pendingSearchTag == tagToSearch {
                     navigationService.pendingSearchTag = nil
                 }
             }
        }
    }

    // --- MODIFIED: Function needs @MainActor because it modifies @State ---
    @MainActor
    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines);
        guard !trimmedSearchText.isEmpty else {
            SearchView.logger.info("Search skipped: search text is empty.");
            // Ensure UI updates are on main actor (already guaranteed by @MainActor)
            items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false;
            return
        }
        let currentFlags = settings.apiFlags
        SearchView.logger.info("Performing search for tags: '\(trimmedSearchText)' (FeedType: \(searchFeedType.displayName), Flags: \(currentFlags))");
        // Ensure UI updates are on main actor (already guaranteed by @MainActor)
        isLoading = true; errorMessage = nil; items = []; hasSearched = true;
        // Defer block runs regardless of how the function exits
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            // API call can be made from any thread
            let fetchedItems = try await apiService.fetchItems(
                flags: currentFlags,
                promoted: searchFeedType.rawValue,
                tags: trimmedSearchText
            )

            // Process result back on MainActor
            await MainActor.run {
                // Check if the search text is still the same before updating results
                let currentSearchTextAfterFetch = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentSearchTextAfterFetch == trimmedSearchText {
                    self.items = fetchedItems // Update @State directly
                    SearchView.logger.info("Search successful, found \(fetchedItems.count) items for '\(trimmedSearchText)' (FeedType: \(searchFeedType.displayName)).")
                } else {
                    SearchView.logger.info("Search results for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchTextAfterFetch)' during fetch.")
                }
            }
        } catch {
            SearchView.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)");
            // Process error back on MainActor
            await MainActor.run {
                // Check if the search text is still the same before showing error
                let currentSearchTextAfterError = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentSearchTextAfterError == trimmedSearchText {
                    self.errorMessage = "Fehler: \(error.localizedDescription)";
                    self.items = [] // Clear items on error
                } else {
                    SearchView.logger.info("Search error for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchTextAfterError)' during fetch.")
                }
            }
        }
    }
    // --- END MODIFICATION ---
}

// MARK: - Preview
#Preview {
    let settings = AppSettings();
    let authService = AuthService(appSettings: settings);
    let navigationService = NavigationService();
    return SearchView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
