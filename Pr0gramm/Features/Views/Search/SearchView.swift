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
    @State private var items: [Item] = [] // Use original items directly
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    @State private var didPerformInitialPendingSearch = false

    // --- ADD PlayerManager StateObject ---
    @StateObject private var playerManager = VideoPlayerManager()
    // ------------------------------------

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]

    // No displayedItems computed property

    var body: some View {
        NavigationStack(path: $navigationPath) {
            searchContentView // Use extracted view
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { Task { await performSearch() } }
            .navigationDestination(for: Item.self) { destinationItem in
                 // --- PASS PlayerManager to PagedDetailView ---
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager) // Pass manager
                 } else {
                     Text("Fehler: Item nicht in Suchergebnissen gefunden.")
                 }
                 // ---------------------------------------------
             }
            .onAppear {
                // Check only if we haven't already processed a pending tag on this appear cycle
                if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty {
                    SearchView.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true
                }
            }
             .task { // Configure manager on initial task
                  await playerManager.configure(settings: settings)
              }
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in
                if let tagToSearch = newTag, !tagToSearch.isEmpty {
                    SearchView.logger.info("Received pending search tag via onChange: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                 if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                     Task { @MainActor in items = []; hasSearched = false; errorMessage = nil; didPerformInitialPendingSearch = false }
                 }
             }
             .onDisappear {
                 didPerformInitialPendingSearch = false
             }
              .onChange(of: settings.seenItemIDs) { _, _ in
                  SearchView.logger.trace("SearchView detected change in seenItemIDs, body will update.")
              }
              // No onChange needed for hideSeenItems
        }
    }

    // MARK: - Extracted Content View

    @ViewBuilder
    private var searchContentView: some View {
        if isLoading {
            ProgressView("Suche läuft...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await performSearch() } } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasSearched {
            ContentUnavailableView("Suche nach Tags", systemImage: "tag")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty { // Check original items
             ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Display search results grid using original 'items'
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(items) { item in // Iterate original items
                        NavigationLink(value: item) {
                            FeedItemThumbnail(
                                item: item,
                                isSeen: settings.seenItemIDs.contains(item.id) // Check seen status
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom)
            }
        }
    }


    // MARK: - Helper Methods

    private func processPendingTag(_ tagToSearch: String) {
         self.searchText = tagToSearch
         Task {
             await performSearch()
             await MainActor.run {
                  if navigationService.pendingSearchTag == tagToSearch {
                       navigationService.pendingSearchTag = nil
                  }
             }
         }
    }

    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            SearchView.logger.info("Search skipped: search text is empty.")
            await MainActor.run { items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false }
            return
        }

        SearchView.logger.info("Performing search for tags: '\(trimmedSearchText)'")
        await MainActor.run { isLoading = true; errorMessage = nil; items = []; hasSearched = true }

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let fetchedItems = try await apiService.searchItems(tags: trimmedSearchText, flags: settings.apiFlags)
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
            if currentSearchText == trimmedSearchText {
                await MainActor.run { self.items = fetchedItems } // Update original items
                SearchView.logger.info("Search successful, found \(fetchedItems.count) items for '\(trimmedSearchText)'.")
            } else {
                 SearchView.logger.info("Search results for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
            }
        } catch {
            SearchView.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)")
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
            if currentSearchText == trimmedSearchText {
                 await MainActor.run { self.errorMessage = "Fehler: \(error.localizedDescription)"; self.items = [] }
             } else {
                  SearchView.logger.info("Search error for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
             }
        }
    }
}

// MARK: - Preview

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    return SearchView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
