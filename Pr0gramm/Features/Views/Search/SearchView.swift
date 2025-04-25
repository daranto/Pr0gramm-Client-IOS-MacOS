// Pr0gramm/Pr0gramm/Features/Views/Search/SearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings // To get current flags
    @State private var searchText = ""
    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false // Track if a search has been performed
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                if isLoading {
                    ProgressView("Suche läuft...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") { Task { await performSearch() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasSearched {
                    ContentUnavailableView("Suche nach Tags", systemImage: "tag")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                     ContentUnavailableView.search(text: searchText) // Standard "No Results" View
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Grid view for results
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    FeedItemThumbnail(item: item) // Reuse thumbnail
                                }
                                .buttonStyle(.plain)
                            }
                            // Add pagination logic here later if needed
                        }
                        .padding(.horizontal, 5)
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Suche")
            // --- Search Bar Integration ---
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen...")
            .onSubmit(of: .search) { // Trigger search on submit
                Task { await performSearch() }
            }
            // --- Navigation Destination ---
            .navigationDestination(for: Item.self) { destinationItem in
                 // Find index in the *current* search results
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     // Pass only the search results array to PagedDetailView
                     PagedDetailView(items: items, selectedIndex: index)
                 } else {
                     // Should ideally not happen if navigation occurs from the list
                     Text("Fehler: Item nicht in Suchergebnissen gefunden.")
                 }
             }
            // Clear results if search text becomes empty AFTER a search was done
             .onChange(of: searchText) { oldValue, newValue in
                 if hasSearched && newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                     Task { @MainActor in
                         items = []
                         hasSearched = false // Reset state to initial prompt
                         errorMessage = nil
                         isLoading = false
                     }
                 }
             }
        }
    }

    private func performSearch() async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            Self.logger.info("Search skipped: search text is empty.")
            // Optionally clear results if desired when submitting empty text
            await MainActor.run {
                 items = []
                 hasSearched = false // Show initial prompt again
                 errorMessage = nil
                 isLoading = false
            }
            return
        }

        Self.logger.info("Performing search for tags: '\(trimmedSearchText)'")
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            items = [] // Clear previous results
            hasSearched = true // Mark that a search attempt was made
        }

        do {
            let fetchedItems = try await apiService.searchItems(tags: trimmedSearchText, flags: settings.apiFlags)
            await MainActor.run {
                 self.items = fetchedItems
                 // isLoading = false will be set in the finally block (defer)
                 Self.logger.info("Search successful, found \(fetchedItems.count) items.")
            }
        } catch {
            Self.logger.error("Search failed for tags '\(trimmedSearchText)': \(error.localizedDescription)")
            await MainActor.run {
                 self.errorMessage = "Fehler: \(error.localizedDescription)"
                 self.items = [] // Ensure items are empty on error
                 // isLoading = false will be set in the finally block (defer)
            }
        }
        // Ensure isLoading is always set to false after the operation
        await MainActor.run { isLoading = false }
    }
}

#Preview {
    // Create necessary services for the preview
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings) // Auth might be needed if PagedDetailView uses it

    // Return the view within the MainView structure for context if needed,
    // or stand-alone if simpler. Stand-alone is fine here.
    SearchView()
        .environmentObject(settings)
        .environmentObject(authService) // Provide auth service as well
}
// --- END OF COMPLETE FILE ---
