// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

// Wrapper struct for identifiable search history items
struct SearchHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let term: String
}

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService
    
    @State private var searchText = ""
    @State private var items: [Item] = []
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

    @State private var searchHistoryItems: [SearchHistoryItem] = []
    private static let searchHistoryKey = "searchHistory_v1"
    private static let maxSearchHistoryCount = 10

    @StateObject private var playerManager = VideoPlayerManager()

    @State private var loadMoreTask: Task<Void, Never>? = nil
    private let loadMoreDebounceTime: Duration = .milliseconds(500)

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")
    
    private var gridColumns: [GridItem] {
        let isMac = ProcessInfo.processInfo.isiOSAppOnMac
        let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact
        let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
        let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)
        return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
    }

    private var apiFlagsForSearch: Int {
        let loggedIn = authService.isLoggedIn
        if !loggedIn { return 1 }

        if self.searchFeedType == .junk { return 9 }

        var flags = 0
        if settings.showSFW { flags |= 1; flags |= 8 }
        if settings.showNSFW { flags |= 2 }
        if settings.showNSFL { flags |= 4 }
        if settings.showPOL { flags |= 16 }
        return flags == 0 ? 1 : flags
    }

    private var apiPromotedForSearch: Int? {
        switch self.searchFeedType {
        case .new: return 0
        case .promoted: return 1
        case .junk: return nil
        }
    }

    private var apiShowJunkForSearch: Bool {
        return self.searchFeedType == .junk
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                searchControls
                searchContentView
            }
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) {
                Self.addTagToGlobalSearchHistory(searchText)
                loadSearchHistoryItemsFromUserDefaults()
                Task { await performSearch(isInitialSearch: true) }
            }
            .navigationDestination(for: Item.self) { destinationItem in
                detailView(for: destinationItem)
             }
            .onAppear {
                loadSearchHistoryItemsFromUserDefaults()
                
                if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty {
                    SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true
                }
            }
            .task { playerManager.configure(settings: settings) }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView(relevantFeedTypeForFilterBehavior: self.searchFeedType, hideFeedOptions: true, showHideSeenItemsToggle: false)
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
            .onDisappear {
                didPerformInitialPendingSearch = false
                loadMoreTask?.cancel()
            }
            .onChange(of: searchFeedType) { _, _ in
                 if !isLoading && !isBenisSliderEditing && (hasSearched || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || minBenisScore > 0) {
                      SearchView.logger.info("Local searchFeedType changed, re-running search.")
                      Task { await performSearch(isInitialSearch: true) }
                 }
            }
            .onChange(of: settings.showSFW) { _, _ in triggerSearchOnFilterChange() }
            .onChange(of: settings.showNSFW) { _, _ in triggerSearchOnFilterChange() }
            .onChange(of: settings.showNSFL) { _, _ in triggerSearchOnFilterChange() }
            .onChange(of: settings.showPOL) { _, _ in triggerSearchOnFilterChange() }
        }
    }
    
    private func triggerSearchOnFilterChange() {
        if !isLoading && !isBenisSliderEditing && (hasSearched || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || minBenisScore > 0) {
             SearchView.logger.info("Global SFW/NSFW/NSFL/POL filter changed, re-running search.")
             Task { await performSearch(isInitialSearch: true) }
        }
    }
    
    @ViewBuilder
    private var searchControls: some View {
        VStack {
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
        }
    }

    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            PagedDetailView(
                items: $items,
                selectedIndex: index,
                playerManager: playerManager,
                loadMoreAction: { Task { await triggerLoadMoreWithDebounce() } }
            )
            .environmentObject(settings)
            .environmentObject(authService)
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in current search results.")
                 }
        }
    }

    @ViewBuilder
    private var searchContentView: some View {
        Group {
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
                if !searchHistoryItems.isEmpty {
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
    }
    
    @ViewBuilder
    private var searchHistoryView: some View {
        List {
            Section {
                ForEach(searchHistoryItems) { historyItem in
                    Button(action: {
                        searchText = historyItem.term
                        Self.addTagToGlobalSearchHistory(historyItem.term)
                        loadSearchHistoryItemsFromUserDefaults()
                        Task { await performSearch(isInitialSearch: true) }
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            Text(historyItem.term).foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left").foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSearchHistoryItem)
            } header: {
                HStack {
                    Text("Letzte Suchen"); Spacer()
                    if !searchHistoryItems.isEmpty {
                        Button("Alle löschen", role: .destructive) { clearSearchHistory() }.font(.caption)
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
                    Color.clear.frame(height: 1).onAppear {
                        SearchView.logger.info("Search: End trigger appeared.")
                        Task { await triggerLoadMoreWithDebounce() }
                    }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
    }

    private func triggerLoadMoreWithDebounce() async {
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            do {
                try await Task.sleep(for: loadMoreDebounceTime)
                await performSearch(isInitialSearch: false)
            } catch is CancellationError {
                SearchView.logger.info("Load more task cancelled.")
            } catch {
                SearchView.logger.error("Error in load more task sleep: \(error)")
            }
        }
    }

    private func processPendingTag(_ tagToSearch: String) {
        let trimmedTag = tagToSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        
        searchText = trimmedTag
        Self.addTagToGlobalSearchHistory(trimmedTag)
        loadSearchHistoryItemsFromUserDefaults()
        
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

        if currentMinScoreInt > 0 { scoreTagComponent = "s:\(currentMinScoreInt)" }
        else { scoreTagComponent = nil }

        var combinedTagsForAPI = ""
        if !userEnteredSearchText.isEmpty { combinedTagsForAPI += userEnteredSearchText }
        if let sTag = scoreTagComponent {
            if !combinedTagsForAPI.isEmpty { combinedTagsForAPI += " " }
            combinedTagsForAPI += sTag
        }
        
        let effectiveSearchQueryForAPITags: String
        if !combinedTagsForAPI.isEmpty { effectiveSearchQueryForAPITags = "! \(combinedTagsForAPI)" }
        else {
            if userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && isInitialSearch { effectiveSearchQueryForAPITags = "" }
            else if userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && !isInitialSearch {
                SearchView.logger.info("Load more skipped: Text and Benis are empty."); canLoadMore = false; isLoadingMore = false; return
            } else {
                SearchView.logger.info("Search effectively skipped: query empty."); items = []; hasSearched = true; errorMessage = nil; isLoading = false; isLoadingMore = false; canLoadMore = false; return
            }
        }
        
        guard !effectiveSearchQueryForAPITags.isEmpty || (userEnteredSearchText.isEmpty && currentMinScoreInt == 0 && isInitialSearch) else {
             SearchView.logger.info("performSearch guard: Final check, effective query empty."); items = []; hasSearched = true; errorMessage = nil; isLoading = false; isLoadingMore = false; canLoadMore = false; return
        }
        
        if isInitialSearch {
            isLoading = true; errorMessage = nil; items = []; self.hasSearched = true; canLoadMore = true;
            SearchView.logger.info("Performing INITIAL search: API Tags='\(effectiveSearchQueryForAPITags)', User Text='\(userEnteredSearchText)', FeedType=\(searchFeedType.displayName), Flags=\(apiFlagsForSearch), MinScore UI=\(currentMinScoreInt)");
        } else {
            guard !isLoadingMore && canLoadMore else { SearchView.logger.debug("Load more skipped."); return }
            isLoadingMore = true
            SearchView.logger.info("Performing LOAD MORE: API Tags='\(effectiveSearchQueryForAPITags)', OlderThan=\(items.last?.id ?? -1)");
        }
        
        defer { Task { @MainActor in if isInitialSearch { self.isLoading = false } else { self.isLoadingMore = false }; self.hasSearched = true } }

        do {
            let olderThanIdForAPI: Int?
            if isInitialSearch { olderThanIdForAPI = nil }
            else {
                if searchFeedType == .promoted { olderThanIdForAPI = items.last?.promoted ?? items.last?.id }
                else { olderThanIdForAPI = items.last?.id }
                guard olderThanIdForAPI != nil else { SearchView.logger.warning("Cannot load more."); canLoadMore = false; return }
            }

            let apiResponse = try await apiService.fetchItems(
                flags: apiFlagsForSearch,
                promoted: apiPromotedForSearch,
                tags: effectiveSearchQueryForAPITags,
                olderThanId: olderThanIdForAPI,
                showJunkParameter: apiShowJunkForSearch
            )
            
            let currentUserSearchTextAfterFetch = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchContextStillValid = (currentUserSearchTextAfterFetch == userEnteredSearchText) && (Int(self.minBenisScore) == currentMinScoreInt)

            guard searchContextStillValid else { SearchView.logger.info("Search results discarded, context changed."); return }
            
            if let apiError = apiResponse.error, apiError != "limitReached" {
                 if apiError == "nothingFound" {
                     if isInitialSearch { items = [] }
                     canLoadMore = false
                     SearchView.logger.info("API: nothingFound.")
                 } else if apiError == "tooShort" {
                     errorMessage = "Suchbegriff zu kurz."; if isInitialSearch { items = [] }; canLoadMore = false
                 } else { throw NSError(domain: "APIService.performSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError]) }
            } else if apiResponse.error == "limitReached" {
                SearchView.logger.warning("API returned 'limitReached'.")
                errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)."
            } else {
                 let newItems = apiResponse.items
                 if isInitialSearch { items = newItems }
                 else {
                     let currentIDs = Set(items.map { $0.id })
                     let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                     items.append(contentsOf: uniqueNewItems)
                 }
                
                 if newItems.isEmpty {
                     self.canLoadMore = false
                     SearchView.logger.info("\(isInitialSearch ? "Search" : "LoadMore") returned 0 items. Setting canLoadMore to false.")
                 } else {
                     let atEnd = apiResponse.atEnd ?? false
                     let hasOlder = apiResponse.hasOlder ?? true
                     if atEnd {
                         self.canLoadMore = false
                         SearchView.logger.info("API indicates atEnd=true. Setting canLoadMore to false.")
                     } else if hasOlder == false {
                         self.canLoadMore = false
                         SearchView.logger.info("API indicates hasOlder=false. Setting canLoadMore to false.")
                     } else {
                         self.canLoadMore = true
                         SearchView.logger.info("API indicates more items might be available (atEnd=\(atEnd), hasOlder=\(hasOlder)). Setting canLoadMore to true.")
                     }
                 }
                 errorMessage = nil
                 SearchView.logger.info("Search successful. \(isInitialSearch ? "Found" : "Loaded") \(newItems.count). Total: \(items.count). More: \(canLoadMore)")
            }
        } catch let error as NSError where error.localizedDescription.contains("limitReached") || error.userInfo[NSLocalizedDescriptionKey] as? String == "limitReached" {
            errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)."
            SearchView.logger.error("Search failed due to rate limit: \(error.localizedDescription)")
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"; if isInitialSearch { items = [] }; canLoadMore = false
            SearchView.logger.error("Search failed: \(error.localizedDescription)");
        }
    }

    private func loadSearchHistoryItemsFromUserDefaults() {
        if let historyStrings = UserDefaults.standard.stringArray(forKey: Self.searchHistoryKey) {
            DispatchQueue.main.async {
                self.searchHistoryItems = historyStrings.map { SearchHistoryItem(term: $0) }
            }
            SearchView.logger.info("Loaded \(historyStrings.count) items into searchHistoryItems from UserDefaults.")
        } else {
            DispatchQueue.main.async {
                self.searchHistoryItems = []
            }
        }
    }

    static func addTagToGlobalSearchHistory(_ term: String) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }

        var currentGlobalHistory = UserDefaults.standard.stringArray(forKey: searchHistoryKey) ?? []
        
        currentGlobalHistory.removeAll { $0.lowercased() == trimmedTerm.lowercased() }
        currentGlobalHistory.insert(trimmedTerm, at: 0)

        if currentGlobalHistory.count > maxSearchHistoryCount {
            currentGlobalHistory = Array(currentGlobalHistory.prefix(maxSearchHistoryCount))
        }
        
        UserDefaults.standard.set(currentGlobalHistory, forKey: searchHistoryKey)
        logger.info("Tag '\(trimmedTerm)' added to GLOBAL search history (UserDefaults). Count: \(currentGlobalHistory.count)")
    }

    // --- MODIFIED: deleteSearchHistoryItem with forced rebuild ---
    private func deleteSearchHistoryItem(at offsets: IndexSet) {
        var temporaryCopy = searchHistoryItems
        temporaryCopy.remove(atOffsets: offsets)
        
        // Force SwiftUI to rebuild the list by briefly emptying and then repopulating
        // This is a workaround for potential UICollectionView inconsistency issues.
        searchHistoryItems = [] // Empty it first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { // Short delay
            self.searchHistoryItems = temporaryCopy // Repopulate
            
            // Persist the actual change to UserDefaults
            let historyStrings = self.searchHistoryItems.map { $0.term }
            UserDefaults.standard.set(historyStrings, forKey: Self.searchHistoryKey)
            SearchView.logger.info("Deleted item from search history. Saved updated history to UserDefaults. Count: \(self.searchHistoryItems.count)")
        }
    }
    // --- END MODIFICATION ---


    private func clearSearchHistory() {
        searchHistoryItems.removeAll()
        UserDefaults.standard.set([String](), forKey: Self.searchHistoryKey)
        SearchView.logger.info("Cleared all search history.")
    }
}

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
