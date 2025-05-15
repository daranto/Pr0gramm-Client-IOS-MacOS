// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// View responsible for searching items based on tags entered by the user.
/// Displays results in a grid and allows navigation to the detail view.
/// Includes a local toggle to search in "New" or "Promoted" items and a button to adjust content filters.
struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService
    @State private var searchText = ""
    @State var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    @State private var didPerformInitialPendingSearch = false

    @State private var searchFeedType: FeedType = .promoted
    @State private var showingFilterSheet = false

    @State private var minBenisScore: Double = 0
    @State private var isBenisSliderEditing: Bool = false
    private let benisSliderRange: ClosedRange<Double> = 0...5000
    private let benisSliderStep: Double = 100

    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var searchHistory: [String] = []
    private let searchHistoryKey = "searchHistory_v1"
    private let maxSearchHistoryCount = 10

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
                    .disabled(isLoading || isLoadingMore)

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
                                SearchView.logger.info("Benis slider editing finished. New value: \(Int(minBenisScore)).")
                                if !isLoading && (hasSearched || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                    SearchView.logger.info("Triggering search due to Benis slider change.")
                                    Task { await performSearch(isInitialSearch: true) }
                                }
                            }
                        }
                    )
                    .disabled(isLoading || isLoadingMore)

                    if minBenisScore > 0 {
                        Button {
                            minBenisScore = 0
                            if !isLoading && (hasSearched || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                SearchView.logger.info("Triggering search due to Benis slider reset.")
                                Task { await performSearch(isInitialSearch: true) }
                            }
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
            .onSubmit(of: .search) {
                addToSearchHistory(searchText)
                Task { await performSearch(isInitialSearch: true) }
            }
            .navigationDestination(for: Item.self) { destinationItem in
                detailView(for: destinationItem)
             }
            .onAppear {
                loadSearchHistory()
                if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty {
                    SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true
                }
            }
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
                let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if newTrimmed.isEmpty && oldTrimmed.isEmpty && minBenisScore > 0 && !isBenisSliderEditing && !isLoading {
                    SearchView.logger.info("Search text is empty, but Benis filter is active. Triggering search.")
                    Task { await performSearch(isInitialSearch: true) }
                } else if hasSearched && newTrimmed.isEmpty && !isLoading && minBenisScore == 0 {
                    Task { @MainActor in
                        items = []
                        hasSearched = false
                        errorMessage = nil
                        didPerformInitialPendingSearch = false
                        canLoadMore = true
                    }
                }
            }
            .onDisappear { didPerformInitialPendingSearch = false }
            .onChange(of: settings.seenItemIDs) { _, _ in SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.") }
            .onChange(of: searchFeedType) { _, _ in
                 if !isLoading && !isBenisSliderEditing && (hasSearched || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || minBenisScore > 0) {
                      SearchView.logger.info("Local searchFeedType changed, re-running search.")
                      Task { await performSearch(isInitialSearch: true) }
                 }
            }
            .onChange(of: settings.apiFlags) { _, _ in
                 if !isLoading && !isBenisSliderEditing && (hasSearched || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || minBenisScore > 0) {
                      SearchView.logger.info("Global API flags changed, re-running search.")
                      Task { await performSearch(isInitialSearch: true) }
                 }
            }
        }
    }

    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            PagedDetailView(
                items: $items,
                selectedIndex: index,
                playerManager: playerManager,
                loadMoreAction: { Task { await performSearch(isInitialSearch: false) } }
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in current search results.")
                 }
        }
    }

    @ViewBuilder private var searchContentView: some View {
        if isLoading && items.isEmpty {
            ProgressView("Suche läuft...")
                .font(UIConstants.bodyFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle").font(UIConstants.headlineFont) }
            description: { Text(error).font(UIConstants.bodyFont) }
            actions: { Button("Erneut versuchen") { Task { await performSearch(isInitialSearch: true) } }.font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasSearched && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !searchHistory.isEmpty {
                searchHistoryView
            } else if minBenisScore > 0 {
                ContentUnavailableView("Filter aktiv", systemImage: "slider.horizontal.3", description: Text("Min. Benis: \(Int(minBenisScore)). Drücke Suchen oder gib Tags ein."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Suche nach Tags", systemImage: "tag").font(UIConstants.headlineFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if items.isEmpty && hasSearched {
             ContentUnavailableView { Label("Keine Ergebnisse", systemImage: "magnifyingglass").font(UIConstants.headlineFont) }
             description: { Text("Keine Posts für '\(searchText)' gefunden (\(searchFeedType.displayName), Min. Benis: \(Int(minBenisScore))).").font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            searchResultsGrid
        }
    }
    
    @ViewBuilder
    private var searchHistoryView: some View {
        List {
            Section {
                ForEach(searchHistory, id: \.self) { term in
                    // --- MODIFIED: Make entire row tappable ---
                    Button(action: {
                        searchText = term
                        addToSearchHistory(term) // Move to top and submit
                        Task { await performSearch(isInitialSearch: true) }
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass") // Icon for search history item
                                .foregroundColor(.secondary)
                            Text(term)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle()) // Ensure the whole HStack area is tappable
                    }
                    .buttonStyle(.plain) // Use plain style to make it look like a list item
                    // --- END MODIFICATION ---
                }
                .onDelete(perform: deleteSearchHistoryItem)
            } header: {
                HStack {
                    Text("Letzte Suchen")
                    Spacer()
                    if !searchHistory.isEmpty {
                        Button("Alle löschen", role: .destructive) {
                            clearSearchHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }


    private var searchResultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            SearchView.logger.info("Search: End trigger appeared.")
                            Task { await performSearch(isInitialSearch: false) }
                        }
                }
                if isLoadingMore {
                    ProgressView("Lade mehr...")
                        .padding()
                        .gridCellColumns(gridColumns.count)
                }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
    }

    private func processPendingTag(_ tagToSearch: String) {
        let trimmedTag = tagToSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        
        Task { @MainActor in
            self.searchText = trimmedTag
        }
        addToSearchHistory(trimmedTag)
        Task {
             await performSearch(isInitialSearch: true);
             await MainActor.run {
                 if navigationService.pendingSearchTag == trimmedTag {
                     navigationService.pendingSearchTag = nil
                 }
             }
        }
    }

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
        
        let effectiveSearchQueryForAPITags: String
        if !combinedTagsForAPI.isEmpty {
            effectiveSearchQueryForAPITags = "! \(combinedTagsForAPI)"
        } else {
            if userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && isInitialSearch {
                effectiveSearchQueryForAPITags = ""
            } else if userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && !isInitialSearch {
                SearchView.logger.info("Load more skipped: Text and Benis are empty, nothing more to load for this 'empty' query.")
                canLoadMore = false
                isLoadingMore = false
                return
            } else {
                SearchView.logger.info("Search effectively skipped: query is empty and not an initial empty browse scenario.");
                items = []; hasSearched = true; errorMessage = nil; isLoading = false; isLoadingMore = false; canLoadMore = false;
                return
            }
        }
        
        guard !effectiveSearchQueryForAPITags.isEmpty || (userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && isInitialSearch) else {
             SearchView.logger.info("performSearch guard: Final check, effective query empty and not initial empty browse. Clearing state.");
             items = []; hasSearched = true; errorMessage = nil; isLoading = false; isLoadingMore = false; canLoadMore = false;
             return
        }
        
        if isInitialSearch {
            isLoading = true; errorMessage = nil; items = []; hasSearched = true; canLoadMore = true;
            SearchView.logger.info("Performing INITIAL search with API tags: '\(effectiveSearchQueryForAPITags)' (User Text: '\(userEnteredSearchText)', FeedType: \(searchFeedType.displayName), Flags: \(settings.apiFlags), MinScore UI: \(currentMinScoreInt))");
        } else {
            guard !isLoadingMore && canLoadMore else {
                SearchView.logger.debug("Load more skipped: isLoadingMore (\(isLoadingMore)) or !canLoadMore (\(!canLoadMore)).")
                return
            }
            isLoadingMore = true
            SearchView.logger.info("Performing LOAD MORE search with API tags: '\(effectiveSearchQueryForAPITags)', older than ID: \(items.last?.id ?? -1)");
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
                if searchFeedType == .promoted {
                    olderThanIdForAPI = items.last?.promoted ?? items.last?.id
                } else {
                    olderThanIdForAPI = items.last?.id
                }
                guard olderThanIdForAPI != nil else {
                    SearchView.logger.warning("Cannot load more for '\(effectiveSearchQueryForAPITags)': Last item ID/promoted ID missing.")
                    canLoadMore = false
                    return
                }
            }

            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: searchFeedType.rawValue,
                tags: effectiveSearchQueryForAPITags,
                olderThanId: olderThanIdForAPI,
                showJunkParameter: searchFeedType == .junk
            )

            let currentUserSearchTextAfterFetch = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchContextStillValid = (currentUserSearchTextAfterFetch == userEnteredSearchText) && (Int(self.minBenisScore) == currentMinScoreInt)

            guard searchContextStillValid else {
                SearchView.logger.info("Search results for API tags '\(effectiveSearchQueryForAPITags)' discarded, user search text or score changed during fetch.")
                return
            }
            
            if let apiError = apiResponse.error {
                 if apiError == "nothingFound" {
                     if isInitialSearch { items = [] }
                     canLoadMore = false
                     // errorMessage = "Keine Ergebnisse für '\(userEnteredSearchText)' gefunden." // Do not set error for "nothingFound"
                     SearchView.logger.info("API returned 'nothingFound' for API tags '\(effectiveSearchQueryForAPITags)'.")
                 } else if apiError == "tooShort" {
                      errorMessage = "Suchbegriff zu kurz (mind. 2 Zeichen)."
                      if isInitialSearch { items = [] }
                      canLoadMore = false
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
                 errorMessage = nil
                 SearchView.logger.info("Search successful. \(isInitialSearch ? "Found" : "Loaded") \(apiResponse.items.count) items for API tags '\(effectiveSearchQueryForAPITags)'. Total items: \(items.count). Can load more: \(canLoadMore)")
            }

        } catch let error as NSError where error.domain == "APIService.fetchItems" && error.localizedDescription.contains("Suchbegriff zu kurz") {
            errorMessage = error.localizedDescription
            items = []
            canLoadMore = false
            SearchView.logger.warning("Search failed for API tags '\(effectiveSearchQueryForAPITags)': \(error.localizedDescription)")
        }
        catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
            if isInitialSearch { items = [] }
            canLoadMore = false
            SearchView.logger.error("Search failed for API tags '\(effectiveSearchQueryForAPITags)': \(error.localizedDescription)");
        }
    }

    private func loadSearchHistory() {
        if let history = UserDefaults.standard.stringArray(forKey: searchHistoryKey) {
            searchHistory = history
            SearchView.logger.info("Loaded \(history.count) items from search history.")
        }
    }

    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: searchHistoryKey)
        SearchView.logger.info("Saved \(searchHistory.count) items to search history.")
    }

    private func addToSearchHistory(_ term: String) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }

        searchHistory.removeAll { $0.lowercased() == trimmedTerm.lowercased() }
        searchHistory.insert(trimmedTerm, at: 0)

        if searchHistory.count > maxSearchHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxSearchHistoryCount))
        }
        saveSearchHistory()
    }

    private func deleteSearchHistoryItem(at offsets: IndexSet) {
        searchHistory.remove(atOffsets: offsets)
        saveSearchHistory()
    }

    private func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }
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
