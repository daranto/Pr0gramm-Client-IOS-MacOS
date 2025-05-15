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
    @State var items: [Item] = [] // Keep public for PagedDetailView binding
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    @State private var didPerformInitialPendingSearch = false

    @State private var searchFeedType: FeedType = .promoted // Default to searching 'Promoted'
    @State private var showingFilterSheet = false

    @State private var minBenisScore: Double = 0 // Slider value
    @State private var isBenisSliderEditing: Bool = false // Track if user is currently dragging
    private let benisSliderRange: ClosedRange<Double> = 0...5000
    private let benisSliderStep: Double = 100

    // --- NEW: State for pagination ---
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    // --- END NEW ---

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")

    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact

            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)

            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
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
                    .disabled(isLoading || isLoadingMore) // Disable while loading

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

                HStack(spacing: 8) {
                    Text("Benis: \(Int(minBenisScore))")
                        .font(UIConstants.captionFont)
                        .frame(minWidth: 80, alignment: .leading)

                    Slider(
                        value: $minBenisScore,
                        in: benisSliderRange,
                        step: benisSliderStep,
                        onEditingChanged: { editing in
                            isBenisSliderEditing = editing
                            if !editing {
                                SearchView.logger.info("Benis slider editing finished. New value: \(Int(minBenisScore)). Triggering search.")
                                if hasSearched && !isLoading { Task { await performSearch(isInitialSearch: true) } }
                            }
                        }
                    )
                    .disabled(isLoading || isLoadingMore) // Disable while loading

                    if minBenisScore > 0 {
                        Button {
                            minBenisScore = 0
                            if hasSearched && !isLoading { Task { await performSearch(isInitialSearch: true) } }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .font(UIConstants.headlineFont)
                    } else {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(UIConstants.headlineFont)
                            .opacity(0)
                            .disabled(true)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)

                searchContentView
            }
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { Task { await performSearch(isInitialSearch: true) } }
            .navigationDestination(for: Item.self) { destinationItem in
                detailView(for: destinationItem)
             }
            .onAppear { if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty { SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'"); processPendingTag(tagToSearch); didPerformInitialPendingSearch = true } }
            .task { playerManager.configure(settings: settings) }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView(hideFeedOptions: true)
                     .environmentObject(settings)
                     .environmentObject(authService)
             }
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in
                if let tagToSearch = newTag, !tagToSearch.isEmpty {
                    SearchView.logger.info("Received pending search tag via onChange: '\(tagToSearch)'")
                    if !navigationPath.isEmpty {
                        SearchView.logger.info("Popping navigation path due to new pending search tag.")
                        navigationPath = NavigationPath()
                    }
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true
                }
            }
            .onChange(of: navigationService.selectedTab) { _, newTab in
                if newTab == .search && !navigationPath.isEmpty && navigationService.pendingSearchTag != nil {
                    SearchView.logger.info("Switched to Search tab with a pending search and active navigation. Popping path.")
                    navigationPath = NavigationPath()
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                    Task { @MainActor in
                        items = []
                        hasSearched = false
                        errorMessage = nil
                        didPerformInitialPendingSearch = false
                        canLoadMore = true // Reset for potential new search
                    }
                }
            }
            .onDisappear { didPerformInitialPendingSearch = false }
            .onChange(of: settings.seenItemIDs) { _, _ in SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.") }
            .onChange(of: searchFeedType) { _, _ in
                 if hasSearched && !isLoading && !isBenisSliderEditing {
                      SearchView.logger.info("Local searchFeedType changed, re-running search for '\(searchText)'")
                      Task { await performSearch(isInitialSearch: true) }
                 }
            }
            // --- NEW: Refresh on global filter changes ---
            .onChange(of: settings.apiFlags) { _, _ in
                 if hasSearched && !isLoading && !isBenisSliderEditing {
                      SearchView.logger.info("Global API flags changed, re-running search for '\(searchText)'")
                      Task { await performSearch(isInitialSearch: true) }
                 }
            }
            // --- END NEW ---
        }
    }

    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            PagedDetailView(
                items: $items,
                selectedIndex: index,
                playerManager: playerManager,
                // --- MODIFIED: Pass loadMoreItems for search pagination ---
                loadMoreAction: { Task { await performSearch(isInitialSearch: false) } }
                // --- END MODIFICATION ---
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in current search results.")
                 }
        }
    }

    @ViewBuilder private var searchContentView: some View {
        if isLoading && items.isEmpty { // Show main loading indicator only if no items are displayed
            ProgressView("Suche läuft...")
                .font(UIConstants.bodyFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle").font(UIConstants.headlineFont) }
            description: { Text(error).font(UIConstants.bodyFont) }
            actions: { Button("Erneut versuchen") { Task { await performSearch(isInitialSearch: true) } }.font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasSearched {
            ContentUnavailableView("Suche nach Tags", systemImage: "tag").font(UIConstants.headlineFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty { // This means a search was performed but returned no results
             ContentUnavailableView { Label("Keine Ergebnisse", systemImage: "magnifyingglass").font(UIConstants.headlineFont) }
             description: { Text("Keine Posts für '\(searchText)' gefunden (\(searchFeedType.displayName), Min. Benis: \(Int(minBenisScore))).").font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            searchResultsGrid
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                }
                // --- NEW: Load more trigger and indicator ---
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            SearchView.logger.info("Search: End trigger appeared.")
                            Task { await performSearch(isInitialSearch: false) } // isInitialSearch = false for loading more
                        }
                }
                if isLoadingMore {
                    ProgressView("Lade mehr...")
                        .padding()
                        .gridCellColumns(gridColumns.count) // Ensure it spans all columns
                }
                // --- END NEW ---
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
    }

    private func processPendingTag(_ tagToSearch: String) {
         Task { @MainActor in
            self.searchText = tagToSearch
         }
        Task {
             await performSearch(isInitialSearch: true); // Always true for a new pending tag
             await MainActor.run {
                 if navigationService.pendingSearchTag == tagToSearch {
                     navigationService.pendingSearchTag = nil
                 }
             }
        }
    }

    // --- MODIFIED: performSearch now handles initial and subsequent loads ---
    @MainActor
    private func performSearch(isInitialSearch: Bool) async {
        let userEnteredSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoreTagComponent: String?
        let currentMinScoreInt = Int(minBenisScore)

        if currentMinScoreInt > 0 {
            scoreTagComponent = "s:\(currentMinScoreInt)"
        } else {
            scoreTagComponent = nil
        }

        var combinedTagsForAPI = ""
        if !userEnteredSearchText.isEmpty {
            combinedTagsForAPI += userEnteredSearchText
        }
        if let sTag = scoreTagComponent {
            if !combinedTagsForAPI.isEmpty { combinedTagsForAPI += " " }
            combinedTagsForAPI += sTag
        }
        if !combinedTagsForAPI.isEmpty {
            combinedTagsForAPI = "! \(combinedTagsForAPI)"
        }

        guard !combinedTagsForAPI.isEmpty else {
            SearchView.logger.info("Search skipped: effective search query is empty.");
            items = []; hasSearched = false; errorMessage = nil; isLoading = false; isLoadingMore = false; canLoadMore = true; didPerformInitialPendingSearch = false;
            return
        }
        
        if isInitialSearch {
            isLoading = true; errorMessage = nil; items = []; hasSearched = true; canLoadMore = true;
            SearchView.logger.info("Performing INITIAL search with API tags: '\(combinedTagsForAPI)' (User Text: '\(userEnteredSearchText)', FeedType: \(searchFeedType.displayName), Flags: \(settings.apiFlags), MinScore UI: \(currentMinScoreInt))");
        } else {
            guard !isLoadingMore && canLoadMore else {
                SearchView.logger.debug("Load more skipped: isLoadingMore (\(isLoadingMore)) or !canLoadMore (\(!canLoadMore)).")
                return
            }
            isLoadingMore = true
            SearchView.logger.info("Performing LOAD MORE search with API tags: '\(combinedTagsForAPI)', older than ID: \(items.last?.id ?? -1)");
        }
        
        defer {
            Task { @MainActor in
                if isInitialSearch { self.isLoading = false }
                else { self.isLoadingMore = false }
            }
        }

        do {
            let olderThanIdForAPI: Int?
            if isInitialSearch {
                olderThanIdForAPI = nil
            } else {
                // For "promoted" search, use item.promoted for pagination if available
                // For "new" search, use item.id
                if searchFeedType == .promoted {
                    olderThanIdForAPI = items.last?.promoted ?? items.last?.id
                } else {
                    olderThanIdForAPI = items.last?.id
                }
                guard olderThanIdForAPI != nil else {
                    SearchView.logger.warning("Cannot load more for '\(combinedTagsForAPI)': Last item ID/promoted ID missing.")
                    canLoadMore = false
                    return
                }
            }

            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: searchFeedType.rawValue, // New or Promoted
                tags: combinedTagsForAPI,
                olderThanId: olderThanIdForAPI,
                showJunkParameter: searchFeedType == .junk // Pass showJunk if junk feed type
            )

            // Check if context changed during fetch
            let currentUserSearchTextAfterFetch = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchContextStillValid = (currentUserSearchTextAfterFetch == userEnteredSearchText) && (Int(self.minBenisScore) == currentMinScoreInt)

            guard searchContextStillValid else {
                SearchView.logger.info("Search results for API tags '\(combinedTagsForAPI)' discarded, user search text or score changed during fetch.")
                return
            }
            
            if let apiError = apiResponse.error {
                 if apiError == "nothingFound" {
                     if isInitialSearch { items = [] } // Clear if initial search
                     canLoadMore = false
                     errorMessage = "Keine Ergebnisse für '\(userEnteredSearchText)' gefunden."
                     SearchView.logger.info("API returned 'nothingFound' for API tags '\(combinedTagsForAPI)'.")
                 } else {
                     throw NSError(domain: "APIService.performSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError])
                 }
            } else {
                 if isInitialSearch {
                     items = apiResponse.items
                 } else {
                     let currentIDs = Set(items.map { $0.id })
                     let uniqueNewItems = apiResponse.items.filter { !currentIDs.contains($0.id) }
                     items.append(contentsOf: uniqueNewItems)
                 }
                 canLoadMore = !(apiResponse.atEnd ?? true) || !(apiResponse.hasOlder == false)
                 errorMessage = nil // Clear previous errors on success
                 SearchView.logger.info("Search successful. \(isInitialSearch ? "Found" : "Loaded") \(apiResponse.items.count) items for API tags '\(combinedTagsForAPI)'. Total items: \(items.count). Can load more: \(canLoadMore)")
            }

        } catch let error as NSError where error.domain == "APIService.fetchItems" && error.userInfo[NSLocalizedDescriptionKey] as? String == "Suchbegriff zu kurz (mind. 2 Zeichen)." {
            errorMessage = error.localizedDescription
            items = []
            canLoadMore = false
            SearchView.logger.warning("Search failed for API tags '\(combinedTagsForAPI)': \(error.localizedDescription)")
        }
        catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
            if isInitialSearch { items = [] } // Clear only on initial search error
            canLoadMore = false // Stop pagination on error
            SearchView.logger.error("Search failed for API tags '\(combinedTagsForAPI)': \(error.localizedDescription)");
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
