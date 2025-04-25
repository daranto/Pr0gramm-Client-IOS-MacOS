// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigationService: NavigationService
    @State private var searchText = ""
    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false
    @State private var navigationPath = NavigationPath()
    // Track if the initial search from navigationService has been triggered
    @State private var didPerformInitialPendingSearch = false

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                // --- Content display logic (unverändert) ---
                 if isLoading {
                    ProgressView("Suche läuft...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView { Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await performSearch() } } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasSearched {
                    ContentUnavailableView("Suche nach Tags", systemImage: "tag")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                     ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView { LazyVGrid(columns: columns, spacing: 3) { ForEach(items) { item in NavigationLink(value: item) { FeedItemThumbnail(item: item) }.buttonStyle(.plain) } }.padding(.horizontal, 5).padding(.bottom) }
                }
            }
            .navigationTitle("Suche")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { Task { await performSearch() } }
            .navigationDestination(for: Item.self) { destinationItem in
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) { PagedDetailView(items: items, selectedIndex: index) } else { Text("Fehler: Item nicht in Suchergebnissen gefunden.") }
             }
            // --- MODIFIED: Check onAppear AND onChange ---
            .onAppear {
                // Check if there's a pending tag WHEN the view appears
                // and if we haven't already processed it.
                if !didPerformInitialPendingSearch, let tagToSearch = navigationService.pendingSearchTag, !tagToSearch.isEmpty {
                    Self.logger.info("SearchView appeared with pending tag: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                    didPerformInitialPendingSearch = true // Mark as processed
                }
            }
            .onChange(of: navigationService.pendingSearchTag) { _, newTag in
                // Also react to changes if the view is already visible
                if let tagToSearch = newTag, !tagToSearch.isEmpty {
                    Self.logger.info("Received pending search tag via onChange: '\(tagToSearch)'")
                    processPendingTag(tagToSearch)
                }
            }
             // --- End Modification ---
            .onChange(of: searchText) { oldValue, newValue in
                 if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                     Task { @MainActor in items = []; hasSearched = false; errorMessage = nil; didPerformInitialPendingSearch = false /* Reset on clear */ }
                 }
             }
            // Reset initial search flag when tab disappears
             .onDisappear {
                 didPerformInitialPendingSearch = false
             }
        }
    }

    // --- NEU: Helper function to process the tag ---
    private func processPendingTag(_ tagToSearch: String) {
         self.searchText = tagToSearch // Update the local search text
         Task {
             await performSearch() // Trigger the search automatically
             // Clear the pending tag in the service after processing
             await MainActor.run {
                  // Ensure we are clearing the exact tag we just processed
                  if navigationService.pendingSearchTag == tagToSearch {
                       navigationService.pendingSearchTag = nil
                  }
             }
         }
    }
    // --- ENDE NEU ---

    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            Self.logger.info("Search skipped: search text is empty.")
            await MainActor.run { items = []; hasSearched = false; errorMessage = nil; isLoading = false; didPerformInitialPendingSearch = false /* Reset on clear */ }
            return
        }

        Self.logger.info("Performing search for tags: '\(trimmedSearchText)'")
        // Set hasSearched immediately for UI feedback
        await MainActor.run { isLoading = true; errorMessage = nil; items = []; hasSearched = true }

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let fetchedItems = try await apiService.searchItems(tags: trimmedSearchText, flags: settings.apiFlags)
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Only update if the search text hasn't changed again during the async call
            if currentSearchText == trimmedSearchText {
                await MainActor.run { self.items = fetchedItems }
                Self.logger.info("Search successful, found \(fetchedItems.count) items for '\(trimmedSearchText)'.")
            } else {
                 Self.logger.info("Search results for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
            }
        } catch {
            Self.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)")
            let currentSearchText = await MainActor.run { self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
             // Only show error if the search text hasn't changed again
            if currentSearchText == trimmedSearchText {
                 await MainActor.run { self.errorMessage = "Fehler: \(error.localizedDescription)"; self.items = [] }
             } else {
                  Self.logger.info("Search error for '\(trimmedSearchText)' discarded, search text changed to '\(currentSearchText)' during fetch.")
             }
        }
    }
}

// Preview (unverändert)
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
