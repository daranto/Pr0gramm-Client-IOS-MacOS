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
    @State var items: [Item] = []
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
                                if hasSearched && !isLoading { Task { await performSearch() } }
                            }
                        }
                    )
                    .disabled(isLoading)

                    if minBenisScore > 0 {
                        Button {
                            minBenisScore = 0
                            if hasSearched && !isLoading { Task { await performSearch() } }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .font(UIConstants.headlineFont) // GRÖSSERES ICON
                    } else {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(UIConstants.headlineFont) // GRÖSSERES ICON (für Konsistenz)
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
            .onSubmit(of: .search) { Task { await performSearch() } }
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
                    }
                }
            }
            .onDisappear { didPerformInitialPendingSearch = false }
            .onChange(of: settings.seenItemIDs) { _, _ in SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.") }
            .onChange(of: searchFeedType) { _, _ in
                 if hasSearched && !isLoading && !isBenisSliderEditing {
                      SearchView.logger.info("Local searchFeedType changed, re-running search for '\(searchText)'")
                      Task { await performSearch() }
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
                loadMoreAction: { SearchView.logger.trace("Load More triggered from Search detail (No-Op)") }
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in current search results.")
                 }
        }
    }

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
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
    }

    private func processPendingTag(_ tagToSearch: String) {
         Task { @MainActor in
            self.searchText = tagToSearch
         }
        Task {
             await performSearch();
             await MainActor.run {
                 if navigationService.pendingSearchTag == tagToSearch {
                     navigationService.pendingSearchTag = nil
                 }
             }
        }
    }

    @MainActor
    private func performSearch() async {
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
            if !combinedTagsForAPI.isEmpty {
                combinedTagsForAPI += " "
            }
            combinedTagsForAPI += sTag
        }
        
        if !combinedTagsForAPI.isEmpty {
            combinedTagsForAPI = "! \(combinedTagsForAPI)"
        }

        guard !combinedTagsForAPI.isEmpty else {
            SearchView.logger.info("Search skipped: effective search query is empty.");
            items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false;
            return
        }
        
        let currentFlags = settings.apiFlags
        SearchView.logger.info("Performing search with API tags: '\(combinedTagsForAPI)' (User Text: '\(userEnteredSearchText)', FeedType: \(searchFeedType.displayName), Flags: \(currentFlags), MinScore UI: \(currentMinScoreInt))");
        isLoading = true; errorMessage = nil; items = []; hasSearched = true;
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let fetchedItems = try await apiService.fetchItems(
                flags: currentFlags,
                promoted: searchFeedType.rawValue,
                tags: combinedTagsForAPI
            )

            if !fetchedItems.isEmpty {
                SearchView.logger.debug("API returned \(fetchedItems.count) items. Scores of first 5 (or fewer):")
                for item in fetchedItems.prefix(5) {
                    SearchView.logger.debug("- Item ID: \(item.id), Score: \(item.up - item.down) (Up: \(item.up), Down: \(item.down))")
                }
            } else {
                SearchView.logger.debug("API returned 0 items for query: '\(combinedTagsForAPI)'")
            }

            await MainActor.run {
                let currentUserSearchTextAfterFetch = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let searchContextStillValid = (currentUserSearchTextAfterFetch == userEnteredSearchText) && (Int(self.minBenisScore) == currentMinScoreInt)

                if searchContextStillValid {
                    self.items = fetchedItems
                    SearchView.logger.info("Search successful, found \(fetchedItems.count) items for API tags '\(combinedTagsForAPI)'.")
                } else {
                    SearchView.logger.info("Search results for API tags '\(combinedTagsForAPI)' discarded, user search text or score changed during fetch. Current text: '\(currentUserSearchTextAfterFetch)', current score UI: \(Int(self.minBenisScore))")
                }
            }
        } catch {
            SearchView.logger.error("Search failed for API tags '\(combinedTagsForAPI)': \(error.localizedDescription)");
            await MainActor.run {
                let currentUserSearchTextAfterError = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let searchContextStillValid = (currentUserSearchTextAfterError == userEnteredSearchText) && (Int(self.minBenisScore) == currentMinScoreInt)

                if searchContextStillValid {
                    self.errorMessage = "Fehler: \(error.localizedDescription)";
                    self.items = []
                } else {
                     SearchView.logger.info("Search error for API tags '\(combinedTagsForAPI)' discarded, user search text or score changed during fetch.")
                }
            }
        }
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
