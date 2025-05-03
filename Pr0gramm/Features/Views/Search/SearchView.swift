// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// View responsible for searching items based on tags entered by the user.
/// Displays results in a grid and allows navigation to the detail view.
/// Also handles programmatic search requests initiated from other views (e.g., tapping a tag).
struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigationService: NavigationService
    @State private var searchText = ""
    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    @State private var didPerformInitialPendingSearch = false

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")

    // Computed property for adaptive columns
    private var gridColumns: [GridItem] {
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        let minWidth: CGFloat = isRunningOnMac ? 250 : 100 // Set to 250 for Mac
        return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            searchContentView // Use extracted view
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { Task { await performSearch() } }
            .navigationDestination(for: Item.self) { destinationItem in
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager)
                 } else { Text("Fehler: Item nicht in Suchergebnissen gefunden.") }
             }
            .onAppear { if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty { SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'"); processPendingTag(tagToSearch); didPerformInitialPendingSearch = true } }
            .task { playerManager.configure(settings: settings) }
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in if let tagToSearch = newTag, !tagToSearch.isEmpty { SearchView.logger.info("Received pending search tag via onChange: '\(tagToSearch)'"); processPendingTag(tagToSearch); didPerformInitialPendingSearch = true } }
            // --- Line 48 Area ---
            // This modifier reacts to changes in the @State variable `searchText`.
            // SwiftUI ensures that the closure provided to .onChange runs on the main actor
            // because it directly relates to UI state updates.
            .onChange(of: searchText) { oldValue, newValue in
                // Therefore, modifying other @State variables (`items`, `hasSearched`, etc.)
                // within this closure is synchronous and safe on the main actor.
                // No 'await' is needed or allowed here unless you explicitly start a new Task.
                if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                    items = [] // Synchronous State update
                    hasSearched = false // Synchronous State update
                    errorMessage = nil // Synchronous State update
                    didPerformInitialPendingSearch = false // Synchronous State update
                }
            }
            // --- End Line 48 Area ---
            .onDisappear { didPerformInitialPendingSearch = false }
            .onChange(of: settings.seenItemIDs) { _, _ in SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.") }
        }
    }

    // MARK: - Extracted Content View (Unchanged)
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
             description: { Text("Keine Posts für '\(searchText)' gefunden.").font(UIConstants.bodyFont) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            searchResultsGrid
        }
    }

    // MARK: - ScrollView/Grid (Unchanged)
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

    // MARK: - Helper Methods (Unchanged)
    private func processPendingTag(_ tagToSearch: String) {
        self.searchText = tagToSearch;
        Task {
             await performSearch();
             if navigationService.pendingSearchTag == tagToSearch {
                 navigationService.pendingSearchTag = nil
             }
        }
    }

    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines);
        guard !trimmedSearchText.isEmpty else { SearchView.logger.info("Search skipped: search text is empty.");
            items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false; return
        }
        SearchView.logger.info("Performing search for tags: '\(trimmedSearchText)'");
        isLoading = true; errorMessage = nil; items = []; hasSearched = true;
        defer { Task { @MainActor in self.isLoading = false } }
        do {
            let fetchedItems = try await apiService.fetchItems(flags: settings.apiFlags, tags: trimmedSearchText)
            let currentSearchText = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentSearchText == trimmedSearchText {
                self.items = fetchedItems
                SearchView.logger.info("Search successful, found \(fetchedItems.count) items for '\(trimmedSearchText)'.")
            }
            else { SearchView.logger.info("Search results for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.") }
        }
        catch {
            SearchView.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)");
            let currentSearchText = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentSearchText == trimmedSearchText {
                self.errorMessage = "Fehler: \(error.localizedDescription)";
                self.items = []
            }
            else { SearchView.logger.info("Search error for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.") }
        }
    }
}

// MARK: - Preview (Unchanged)
#Preview { let settings = AppSettings(); let authService = AuthService(appSettings: settings); let navigationService = NavigationService(); return SearchView().environmentObject(settings).environmentObject(authService).environmentObject(navigationService) }
// --- END OF COMPLETE FILE ---
