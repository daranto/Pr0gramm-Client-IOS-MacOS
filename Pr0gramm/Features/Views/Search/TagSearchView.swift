// Pr0gramm/Pr0gramm/Features/Views/Search/TagSearchView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct TagSearchView: View {
    @Binding var currentSearchTag: String
    let onNewTagSelectedInSheet: ((String) -> Void)?

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

    @State private var loadMoreTask: Task<Void, Never>? = nil
    private let loadMoreDebounceTime: Duration = .milliseconds(500)

    init(currentSearchTag: Binding<String>, onNewTagSelectedInSheet: ((String) -> Void)? = nil) {
        self._currentSearchTag = currentSearchTag
        self.onNewTagSelectedInSheet = onNewTagSelectedInSheet
        TagSearchView.logger.info("TagSearchView init. currentSearchTag: \(currentSearchTag.wrappedValue), onNewTagSelectedInSheet is \(onNewTagSelectedInSheet == nil ? "nil" : "set")")
    }

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
            .navigationTitle("Suche: \(currentSearchTag)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task(id: currentSearchTag) { // Reagiert auf Änderungen von außen
                TagSearchView.logger.info("TagSearchView task triggered for currentSearchTag: \(currentSearchTag)")
                playerManager.configure(settings: settings)
                await performSearch(isInitialSearch: true)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .navigationDestination(for: Item.self) { destinationItem in
                detailView(for: destinationItem)
            }
            .onDisappear {
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
                loadMoreAction: { Task { await triggerLoadMoreWithDebounce() } },
                // --- MODIFIED: Hier wird die Callback von TagSearchView weitergegeben ---
                onTagTappedInSheetCallback: self.onNewTagSelectedInSheet
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
            ProgressView("Suche nach '\(currentSearchTag)'...")
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
            } description: { Text("Keine Posts für '\(currentSearchTag)' gefunden (\(settings.feedType.displayName), Filter aktiv).").font(UIConstants.bodyFont) }
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
                        TagSearchView.logger.info("TagSearchView: End trigger appeared for tag '\(currentSearchTag)'.")
                        Task { await triggerLoadMoreWithDebounce() }
                    }
                }
                if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await performSearch(isInitialSearch: true) }
    }
    
    private func triggerLoadMoreWithDebounce() async {
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            do {
                try await Task.sleep(for: loadMoreDebounceTime)
                await performSearch(isInitialSearch: false)
            } catch is CancellationError {
                TagSearchView.logger.info("Load more task cancelled for tag '\(currentSearchTag)'.")
            } catch {
                TagSearchView.logger.error("Error in load more task sleep: \(error)")
            }
        }
    }

    @MainActor
    private func performSearch(isInitialSearch: Bool) async {
        let tagToSearch = currentSearchTag
        // SearchView.addTagToGlobalSearchHistory(tagToSearch) // Wird jetzt in DetailViewContent gemacht, wenn das Sheet geöffnet wird

        let effectiveSearchQueryForAPITags = "! \(tagToSearch)"

        if isInitialSearch {
            // Beim initialen Laden (oder wenn sich currentSearchTag ändert), werden die Items zurückgesetzt
            items = [] // Wichtig, um alte Ergebnisse zu entfernen
            isLoading = true; errorMessage = nil; hasSearched = false; canLoadMore = true
            TagSearchView.logger.info("Performing INITIAL search: Tag='\(tagToSearch)', API Query='\(effectiveSearchQueryForAPITags)', FeedType=\(settings.feedType.displayName), Flags=\(settings.apiFlags)")
        } else {
            guard !isLoadingMore && canLoadMore else {
                TagSearchView.logger.debug("Load more skipped: Tag='\(tagToSearch)'"); return
            }
            isLoadingMore = true
            TagSearchView.logger.info("Performing LOAD MORE: Tag='\(tagToSearch)', API Query='\(effectiveSearchQueryForAPITags)', OlderThan=\(items.last?.id ?? -1)")
        }

        defer { Task { @MainActor in if isInitialSearch { self.isLoading = false } else { self.isLoadingMore = false }; self.hasSearched = true } }

        do {
            let olderThanIdForAPI: Int?
            if isInitialSearch { olderThanIdForAPI = nil }
            else {
                if settings.feedType == .promoted { olderThanIdForAPI = items.last?.promoted ?? items.last?.id }
                else { olderThanIdForAPI = items.last?.id }
                guard olderThanIdForAPI != nil else { TagSearchView.logger.warning("Cannot load more: Tag='\(tagToSearch)'"); canLoadMore = false; return }
            }

            // Die FeedType-Optionen (promoted/new/junk) werden hier von den globalen `settings` genommen.
            // Das ist für eine "Tag-Suche" üblich, da sie meistens im Kontext des aktuellen Feed-Typs stattfindet.
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted, // Nimmt den globalen FeedType (promoted/new)
                tags: effectiveSearchQueryForAPITags,
                olderThanId: olderThanIdForAPI,
                showJunkParameter: settings.apiShowJunk // Nimmt den globalen FeedType (junk)
            )

            if let apiError = apiResponse.error, apiError != "limitReached" {
                 if apiError == "nothingFound" {
                     if isInitialSearch { items = [] }; canLoadMore = false
                     TagSearchView.logger.info("API: nothingFound for tag '\(tagToSearch)'.")
                 } else if apiError == "tooShort" {
                     errorMessage = "Suchbegriff zu kurz."; if isInitialSearch { items = [] }; canLoadMore = false
                 } else { throw NSError(domain: "APIService.performTagSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError]) }
            } else if apiResponse.error == "limitReached" {
                TagSearchView.logger.warning("API returned 'limitReached' for tag '\(tagToSearch)'.")
                errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)."
            } else {
                 let newItems = apiResponse.items
                 if isInitialSearch { items = newItems } // Ersetze Items bei initialer Suche
                 else { // Füge hinzu bei "load more"
                     let currentIDs = Set(items.map { $0.id })
                     let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                     items.append(contentsOf: uniqueNewItems)
                 }
                 if newItems.isEmpty && !(apiResponse.atEnd == false && apiResponse.hasOlder == true) {
                     canLoadMore = false
                 } else {
                     canLoadMore = !(apiResponse.atEnd ?? false) || (apiResponse.hasOlder ?? false)
                 }
                 errorMessage = nil
                 TagSearchView.logger.info("Search for tag '\(tagToSearch)' successful. \(isInitialSearch ? "Found" : "Loaded") \(newItems.count). Total: \(items.count). More: \(canLoadMore)")
            }
        } catch let error as NSError where error.userInfo[NSLocalizedDescriptionKey] as? String == "limitReached" {
            errorMessage = "Zu viele Anfragen. Bitte später erneut versuchen (Fehler 429)."
            TagSearchView.logger.error("Search for tag '\(tagToSearch)' failed due to rate limit: \(error.localizedDescription)")
        }
        catch {
            errorMessage = "Fehler: \(error.localizedDescription)"; if isInitialSearch { items = [] }; canLoadMore = false
            TagSearchView.logger.error("Search for tag '\(tagToSearch)' failed: \(error.localizedDescription)")
        }
    }
}

struct TagSearchView_PreviewWrapper: View {
    @State private var previewTag: String = "Katze"
    
    private func handleNewTagSelectionInSheet(newTag: String) {
        print("TagSearchView_PreviewWrapper: New tag selected in sheet - \(newTag)")
        self.previewTag = newTag
    }

    var body: some View {
        let settings = AppSettings()
        let authService = AuthService(appSettings: settings)
        authService.isLoggedIn = true

        return TagSearchView(
            currentSearchTag: $previewTag,
            onNewTagSelectedInSheet: handleNewTagSelectionInSheet
        )
            .environmentObject(settings)
            .environmentObject(authService)
    }
}

#Preview {
    TagSearchView_PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
