// Pr0gramm/Pr0gramm/Features/Views/Search/TagSearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct TagSearchView: View {
    let tag: String

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var hasSearched = false

    @StateObject private var playerManager = VideoPlayerManager()
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TagSearchView")

    // --- NEW: Debounce für Load More ---
    @State private var loadMoreTask: Task<Void, Never>? = nil
    private let loadMoreDebounceTime: Duration = .milliseconds(500)
    // --- END NEW ---

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
                searchContentView
            }
            .navigationTitle("Suche: \(tag)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task {
                playerManager.configure(settings: settings)
                SearchView.addTagToGlobalSearchHistory(tag)
                await performSearch(isInitialSearch: true)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .navigationDestination(for: Item.self) { destinationItem in
                detailView(for: destinationItem)
            }
            .onDisappear { // Wichtig: Laufende Tasks abbrechen
                loadMoreTask?.cancel()
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
                loadMoreAction: { Task { await triggerLoadMoreWithDebounce() } } // Debounced aufrufen
            )
            .environmentObject(settings)
            .environmentObject(authService)
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in Suchergebnissen gefunden.")
                 .onAppear {
                     TagSearchView.logger.warning("Navigation destination item \(destinationItem.id) not found.")
                 }
        }
    }

    @ViewBuilder
    private var searchContentView: some View {
        if isLoading && items.isEmpty {
            ProgressView("Suche nach '\(tag)'...")
                .font(UIConstants.bodyFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView {
                Label("Fehler bei der Suche", systemImage: "exclamationmark.triangle").font(UIConstants.headlineFont)
            } description: { Text(error).font(UIConstants.bodyFont) }
              actions: { Button("Erneut versuchen") { Task { await performSearch(isInitialSearch: true) } }.font(UIConstants.bodyFont) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && hasSearched {
            ContentUnavailableView {
                Label("Keine Ergebnisse", systemImage: "magnifyingglass").font(UIConstants.headlineFont)
            } description: { Text("Keine Posts für '\(tag)' gefunden (\(settings.feedType.displayName), Filter aktiv).").font(UIConstants.bodyFont) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && !hasSearched && !isLoading {
             Text("Suche wird ausgeführt...").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            searchResultsGrid
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                    }.buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                    Color.clear.frame(height: 1).onAppear {
                        TagSearchView.logger.info("TagSearchView: End trigger appeared for tag '\(tag)'.")
                        // --- MODIFIED: Debounced aufrufen ---
                        Task { await triggerLoadMoreWithDebounce() }
                        // --- END MODIFICATION ---
                    }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await performSearch(isInitialSearch: true) }
    }
    
    // --- NEW: Debounce-Methode ---
    private func triggerLoadMoreWithDebounce() async {
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            do {
                try await Task.sleep(for: loadMoreDebounceTime)
                await performSearch(isInitialSearch: false)
            } catch is CancellationError {
                TagSearchView.logger.info("Load more task cancelled for tag '\(tag)'.")
            } catch {
                TagSearchView.logger.error("Error in load more task sleep: \(error)")
            }
        }
    }
    // --- END NEW ---

    @MainActor
    private func performSearch(isInitialSearch: Bool) async {
        let effectiveSearchQueryForAPITags = "! \(tag)"

        if isInitialSearch {
            isLoading = true; errorMessage = nil; items = []; hasSearched = false; canLoadMore = true
            TagSearchView.logger.info("Performing INITIAL search: Tag='\(tag)', API Query='\(effectiveSearchQueryForAPITags)', FeedType=\(settings.feedType.displayName), Flags=\(settings.apiFlags)")
        } else {
            guard !isLoadingMore && canLoadMore else {
                TagSearchView.logger.debug("Load more skipped: Tag='\(tag)'"); return
            }
            isLoadingMore = true
            TagSearchView.logger.info("Performing LOAD MORE: Tag='\(tag)', API Query='\(effectiveSearchQueryForAPITags)', OlderThan=\(items.last?.id ?? -1)")
        }

        defer { Task { @MainActor in if isInitialSearch { self.isLoading = false } else { self.isLoadingMore = false }; self.hasSearched = true } }

        do {
            let olderThanIdForAPI: Int?
            if isInitialSearch { olderThanIdForAPI = nil }
            else {
                if settings.feedType == .promoted { olderThanIdForAPI = items.last?.promoted ?? items.last?.id }
                else { olderThanIdForAPI = items.last?.id }
                guard olderThanIdForAPI != nil else { TagSearchView.logger.warning("Cannot load more: Tag='\(tag)'"); canLoadMore = false; return }
            }

            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags, promoted: settings.apiPromoted,
                tags: effectiveSearchQueryForAPITags, olderThanId: olderThanIdForAPI,
                showJunkParameter: settings.apiShowJunk
            )

            if let apiError = apiResponse.error, apiError != "limitReached" /* Ignoriere limitReached hier kurzfristig */ {
                 if apiError == "nothingFound" {
                     if isInitialSearch { items = [] }; canLoadMore = false
                     TagSearchView.logger.info("API: nothingFound for tag '\(tag)'.")
                 } else if apiError == "tooShort" {
                     errorMessage = "Suchbegriff zu kurz."; if isInitialSearch { items = [] }; canLoadMore = false
                 } else { throw NSError(domain: "APIService.performTagSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError]) }
            } else if apiResponse.error == "limitReached" {
                // Spezifische Behandlung für limitReached, falls gewünscht, ansonsten fällt es in den Catch-Block
                TagSearchView.logger.warning("API returned 'limitReached' for tag '\(tag)'. CanLoadMore wird vorerst true gelassen für manuelle Retries.")
                errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)." // Setze Fehlermeldung
                // canLoadMore bleibt hier true, damit der User manuell refreshen kann, oder der Fehler wird im allgemeinen Catch behandelt
            } else {
                 let newItems = apiResponse.items // Holen der neuen Items
                 if isInitialSearch { items = newItems }
                 else {
                     let currentIDs = Set(items.map { $0.id })
                     let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                     items.append(contentsOf: uniqueNewItems)
                 }
                 // --- MODIFIED: Verbesserte canLoadMore Logik ---
                 if newItems.isEmpty && !(apiResponse.atEnd == false && apiResponse.hasOlder == true) {
                     canLoadMore = false // Keine neuen Items und API sagt nicht explizit, dass es mehr gibt
                 } else {
                     canLoadMore = !(apiResponse.atEnd ?? false) || (apiResponse.hasOlder ?? false) // Originale Logik, wenn Items kamen
                 }
                 // --- END MODIFICATION ---
                 errorMessage = nil
                 TagSearchView.logger.info("Search for tag '\(tag)' successful. \(isInitialSearch ? "Found" : "Loaded") \(newItems.count). Total: \(items.count). More: \(canLoadMore)")
            }
        } catch let error as NSError where error.userInfo[NSLocalizedDescriptionKey] as? String == "limitReached" {
            errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)."
            // canLoadMore bleibt true, damit der "Erneut versuchen" Button oder Pull-to-Refresh funktioniert
            TagSearchView.logger.error("Search for tag '\(tag)' failed due to rate limit: \(error.localizedDescription)")
        }
        catch {
            errorMessage = "Fehler: \(error.localizedDescription)"; if isInitialSearch { items = [] }; canLoadMore = false
            TagSearchView.logger.error("Search for tag '\(tag)' failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    struct TagSearchPreviewWrapper: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService

        init() {
            let s = AppSettings(); let a = AuthService(appSettings: s)
            a.isLoggedIn = true; s.showSFW = true; s.feedType = .promoted
            _settings = StateObject(wrappedValue: s); _authService = StateObject(wrappedValue: a)
        }
        var body: some View {
            Text("Parent View").sheet(isPresented: .constant(true)) {
                TagSearchView(tag: "Katze").environmentObject(settings).environmentObject(authService)
            }
        }
    }
    return TagSearchPreviewWrapper()
}
// --- END OF COMPLETE FILE ---
