// Pr0gramm/Pr0gramm/Features/Views/Profile/UserUploadsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

/// Displays the items uploaded by a specific user in a grid.
/// Handles loading, pagination, filtering (based on global settings), and navigation.
struct UserUploadsView: View {
    let username: String // Username whose uploads to display

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @EnvironmentObject var playerManager: VideoPlayerManager

    @State private var searchText = ""
    @State private var currentSearchTagForAPI: String? = nil
    @State private var searchDebounceTimer: Timer? = nil
    private let searchDebounceInterval: TimeInterval = 0.75
    @State private var hasAttemptedSearchSinceAppear = false

    @State private var primaryLoadTask: Task<Void, Never>? = nil

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserUploadsView")

    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact

            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)

            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
        }

    private var userUploadsCacheKey: String {
        var key = "uploads_\(username.lowercased())_flags_\(settings.apiFlags)"
        if let searchTerm = currentSearchTagForAPI, !searchTerm.isEmpty {
            let safeSearchTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? searchTerm
            key += "_search_\(safeSearchTerm)"
        }
        return key
    }

    var body: some View {
        uploadsContentView
            .navigationTitle("Uploads von \(username)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Uploads nach Tags filtern")
            .onSubmit(of: .search) {
                UserUploadsView.logger.info("Search submitted for user '\(username)' with: \(searchText)")
                searchDebounceTimer?.invalidate()
                triggerPrimaryLoadTask { await performSearchLogic(isInitialSearch: true) }
            }
            // --- MODIFICATION: Hinzugefügt ---
            .navigationDestination(for: Item.self) { destinationItem in
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(
                         items: $items,
                         selectedIndex: index,
                         playerManager: playerManager,
                         loadMoreAction: { Task { await loadMoreUploads() } }
                     )
                     .environmentObject(settings) // AppSettings weitergeben
                     .environmentObject(authService) // AuthService weitergeben
                 } else {
                     Text("Fehler: Item \(destinationItem.id) nicht in den Uploads gefunden.")
                         .onAppear {
                             UserUploadsView.logger.warning("Navigation destination item \(destinationItem.id) not found in UserUploadsView.")
                         }
                 }
            }
            // --- END MODIFICATION ---
        .onChange(of: searchText) { oldValue, newValue in
            UserUploadsView.logger.info("Search text for user '\(username)' changed from '\(oldValue)' to '\(newValue)'")
            searchDebounceTimer?.invalidate()
            primaryLoadTask?.cancel()

            let trimmedNewValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousAPITag = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if trimmedNewValue.isEmpty && !previousAPITag.isEmpty {
                UserUploadsView.logger.info("Search text cleared for user '\(username)', loading unfiltered uploads.")
                triggerPrimaryLoadTask { await performSearchLogic(isInitialSearch: true) }
            } else if !trimmedNewValue.isEmpty && trimmedNewValue.count >= 2 {
                UserUploadsView.logger.info("Starting debounce timer for search (user '\(username)'): '\(trimmedNewValue)'")
                searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: searchDebounceInterval, repeats: false) { _ in
                    UserUploadsView.logger.info("Debounce timer fired for search (user '\(username)'): '\(trimmedNewValue)'")
                    triggerPrimaryLoadTask { await performSearchLogic(isInitialSearch: true) }
                }
            } else if trimmedNewValue.isEmpty && previousAPITag.isEmpty && !items.isEmpty && hasAttemptedSearchSinceAppear {
                 UserUploadsView.logger.info("Search text empty for user '\(username)', no previous API tag, items exist. No API call needed.")
            } else if trimmedNewValue.isEmpty && items.isEmpty && hasAttemptedSearchSinceAppear {
                UserUploadsView.logger.info("Search text empty for user '\(username)', items empty, but a search was attempted. Showing appropriate message.")
            }
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task(id: username) {
            hasAttemptedSearchSinceAppear = false
            UserUploadsView.logger.info("UserUploadsView .task (id: username) for \(username). Current items: \(items.count)")
            if items.isEmpty && currentSearchTagForAPI == nil {
                triggerPrimaryLoadTask { await refreshUploads() }
            } else if currentSearchTagForAPI != nil {
                triggerPrimaryLoadTask { await performSearchLogic(isInitialSearch: true) }
            }
        }
        .onDisappear {
            primaryLoadTask?.cancel()
            searchDebounceTimer?.invalidate()
            UserUploadsView.logger.info("UserUploadsView onDisappear for \(username). Cancelled primaryLoadTask and searchDebounceTimer.")
        }
        .onChange(of: settings.apiFlags) { _, _ in
            UserUploadsView.logger.info("API flags changed, resetting search and refreshing uploads for \(username).")
            currentSearchTagForAPI = nil
            searchText = ""
            triggerPrimaryLoadTask { await refreshUploads() }
        }
        .onChange(of: settings.seenItemIDs) { _, _ in UserUploadsView.logger.trace("UserUploadsView detected change in seenItemIDs, body will update.") }
    }
    
    private func triggerPrimaryLoadTask(operation: @escaping () async -> Void) {
        primaryLoadTask?.cancel()
        primaryLoadTask = Task {
            await operation()
        }
    }

    @ViewBuilder private var uploadsContentView: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Lade Uploads...")
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty {
                 ContentUnavailableView {
                     Label("Fehler", systemImage: "exclamationmark.triangle")
                        .font(UIConstants.headlineFont)
                 } description: {
                     Text(error)
                        .font(UIConstants.bodyFont)
                 } actions: {
                     Button("Erneut versuchen") {
                         triggerPrimaryLoadTask { await refreshUploads() }
                     }
                        .font(UIConstants.bodyFont)
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && hasAttemptedSearchSinceAppear && !(currentSearchTagForAPI?.isEmpty ?? true) && !isLoading {
                ContentUnavailableView {
                    Label("Keine Ergebnisse", systemImage: "magnifyingglass")
                } description: {
                    Text("\(username) hat keine Uploads für den Tag '\(currentSearchTagForAPI!)' (oder sie passen nicht zu deinen Filtern).")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading && errorMessage == nil {
                Text("\(username) hat noch nichts hochgeladen (oder nichts passt zu deinen Filtern).")
                    .font(UIConstants.bodyFont)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollViewContent
            }
        }
    }
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                 ForEach(items) { item in
                     NavigationLink(value: item) {
                         FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                     }.buttonStyle(.plain)
                 }
                 if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1).onAppear { UserUploadsView.logger.info("Uploads for \(username): End trigger appeared."); Task { await loadMoreUploads() } }
                 }
                 if isLoadingMore {
                     ProgressView("Lade mehr...")
                        .font(UIConstants.bodyFont)
                        .padding()
                        .gridCellColumns(gridColumns.count)
                 }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable {
            triggerPrimaryLoadTask { await refreshUploads() }
        }
    }

    @MainActor
    private func performSearchLogic(isInitialSearch: Bool) async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSearchText.isEmpty && (currentSearchTagForAPI == nil || currentSearchTagForAPI!.isEmpty) {
            if !hasAttemptedSearchSinceAppear { hasAttemptedSearchSinceAppear = true }
            if items.isEmpty {
                if currentSearchTagForAPI != nil {
                    currentSearchTagForAPI = nil
                }
                await refreshUploads()
            }
            UserUploadsView.logger.info("performSearchLogic for user '\(username)': Search text empty, no previous API tag. No API call needed unless list is empty.")
            return
        }
        
        currentSearchTagForAPI = trimmedSearchText.isEmpty ? nil : trimmedSearchText
        
        UserUploadsView.logger.info("performSearchLogic for user '\(username)': isInitial=\(isInitialSearch). API Tag: '\(currentSearchTagForAPI ?? "nil")'")
        await refreshUploads()
        hasAttemptedSearchSinceAppear = true
    }

    @MainActor
    func refreshUploads() async {
        guard !Task.isCancelled else {
            UserUploadsView.logger.info("refreshUploads execution for \(username) cancelled at entry.")
            return
        }

        UserUploadsView.logger.info("Refreshing uploads for user: \(username), search: '\(currentSearchTagForAPI ?? "nil")'")
        let cacheKey = userUploadsCacheKey
        
        self.isLoading = true
        self.errorMessage = nil
        
        defer { Task { @MainActor in self.isLoading = false; UserUploadsView.logger.info("Finished uploads refresh process for \(username).") } }
        
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        if items.isEmpty {
            initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
            if Task.isCancelled { UserUploadsView.logger.info("Refresh task for \(username) cancelled during cache load."); return }
            if let cached = initialItemsFromCache, !cached.isEmpty {
                 UserUploadsView.logger.info("Found \(cached.count) uploaded items in cache initially for \(username) (search: '\(currentSearchTagForAPI ?? "nil")').");
                 self.items = cached
            } else {
                 UserUploadsView.logger.info("No usable data cache found for uploads for \(username) (search: '\(currentSearchTagForAPI ?? "nil")').")
            }
        }
        
        let apiTagsParameter = currentSearchTagForAPI
        UserUploadsView.logger.info("Performing API fetch for uploads refresh (User: \(username), Flags: \(settings.apiFlags), API Tags: '\(apiTagsParameter ?? "nil")')...");
        
        do {
            let apiResponse = try await apiService.fetchItems(flags: settings.apiFlags, user: username, tags: apiTagsParameter)
            if Task.isCancelled { UserUploadsView.logger.info("Refresh task for \(username) cancelled after API call but before UI update."); return }

            let fetchedItemsFromAPI = apiResponse.items
            UserUploadsView.logger.info("API fetch for uploads completed: \(fetchedItemsFromAPI.count) items for user \(username).");
            
            await MainActor.run {
                if Task.isCancelled { UserUploadsView.logger.info("Refresh task for \(username) cancelled just before UI update."); return }

                self.items = fetchedItemsFromAPI
                if fetchedItemsFromAPI.isEmpty {
                    self.canLoadMore = false
                    UserUploadsView.logger.info("Refresh returned 0 items for \(username). Setting canLoadMore to false.")
                } else {
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    if atEnd || !hasOlder {
                        self.canLoadMore = false
                        UserUploadsView.logger.info("API indicates end of feed for \(username). Setting canLoadMore to false.")
                    } else {
                        self.canLoadMore = true
                        UserUploadsView.logger.info("API indicates more items might be available for \(username) (atEnd=\(atEnd), hasOlder=\(hasOlder)). Setting canLoadMore to true.")
                    }
                }
                UserUploadsView.logger.info("UserUploadsView updated with \(fetchedItemsFromAPI.count) items from API for \(username). Can load more: \(self.canLoadMore)")
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            if Task.isCancelled { UserUploadsView.logger.info("Refresh task for \(username) cancelled after saving to cache."); return }
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for uploads failed: Authentication required (User: \(username)). Session might be invalid.");
            if Task.isCancelled { return }
            await MainActor.run {
                self.items = [];
                self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
                self.canLoadMore = false
            }
            await settings.saveItemsToCache([], forKey: cacheKey);
            await authService.logout()
        }
        catch is CancellationError {
            UserUploadsView.logger.info("Uploads refresh task API call explicitly cancelled for \(username).")
            if items.isEmpty && initialItemsFromCache == nil {
            }
        }
        catch {
            UserUploadsView.logger.error("API fetch for uploads failed (User: \(username)): \(error.localizedDescription)");
            if Task.isCancelled { return }
            await MainActor.run {
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden der Uploads: \(error.localizedDescription)"
                } else {
                    UserUploadsView.logger.warning("Showing potentially stale cached uploads data because API refresh failed for \(username).")
                };
                self.canLoadMore = false
            }
        }
    }

    @MainActor
    func loadMoreUploads() async {
        guard !Task.isCancelled else { UserUploadsView.logger.info("loadMoreUploads for \(username) cancelled at entry."); return }
        guard !isLoadingMore && canLoadMore && !isLoading else { UserUploadsView.logger.debug("Skipping loadMoreUploads for \(username): State prevents loading."); return }
        guard let lastItemId = items.last?.id else { UserUploadsView.logger.warning("Skipping loadMoreUploads for \(username): No last item found."); return }
        let cacheKey = userUploadsCacheKey; UserUploadsView.logger.info("--- Starting loadMoreUploads for user \(username), search '\(currentSearchTagForAPI ?? "nil")' older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserUploadsView.logger.info("--- Finished loadMoreUploads for user \(username) ---") } } }
        
        let apiTagsParameter = currentSearchTagForAPI

        do {
            let apiResponse = try await apiService.fetchItems(flags: settings.apiFlags, user: username, tags: apiTagsParameter, olderThanId: lastItemId)
            if Task.isCancelled { UserUploadsView.logger.info("Load more uploads task cancelled after API call for \(username)."); return }

            let newItems = apiResponse.items
            UserUploadsView.logger.info("Loaded \(newItems.count) more uploaded items from API for \(username) (requesting older than \(lastItemId)).");
            var appendedItemCount = 0
            
            await MainActor.run {
                if Task.isCancelled { UserUploadsView.logger.info("Load more task for \(username) cancelled just before UI update."); return }
                guard self.isLoadingMore else { UserUploadsView.logger.info("Load more for \(username) cancelled before UI update (isLoadingMore became false)."); return }

                if newItems.isEmpty {
                    UserUploadsView.logger.info("Reached end of uploads feed for \(username) because API returned 0 items for loadMore.")
                    self.canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                    if uniqueNewItems.isEmpty {
                        UserUploadsView.logger.warning("All loaded uploaded items (older than \(lastItemId)) were duplicates for \(username). Assuming end of actual new content.")
                        self.canLoadMore = false
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        UserUploadsView.logger.info("Appended \(uniqueNewItems.count) unique uploaded items for \(username). Total items: \(self.items.count)")

                        let atEnd = apiResponse.atEnd ?? false
                        let hasOlder = apiResponse.hasOlder ?? true
                        if atEnd || !hasOlder {
                            self.canLoadMore = false
                            UserUploadsView.logger.info("API indicates end of feed after loadMore for \(username).")
                        } else {
                            self.canLoadMore = true
                            UserUploadsView.logger.info("API indicates more items might be available after loadMore for \(username) (atEnd=\(atEnd), hasOlder=\(hasOlder)).")
                        }
                    }
                }
            }
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                if Task.isCancelled { UserUploadsView.logger.info("Load more uploads task cancelled after saving to cache for \(username)."); return }
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for more uploads failed: Authentication required (User: \(username)). Session might be invalid.");
            if Task.isCancelled { return }
            await MainActor.run {
                self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
                self.canLoadMore = false;
            }
            await authService.logout()
        }
        catch is CancellationError { UserUploadsView.logger.info("Load more uploads API call explicitly cancelled for \(username).") }
        catch {
            UserUploadsView.logger.error("API fetch failed during loadMoreUploads for \(username): \(error.localizedDescription)");
            if Task.isCancelled { return }
            await MainActor.run {
                guard self.isLoadingMore else { return };
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" };
                self.canLoadMore = false
            }
        }
    }
}

// MARK: - Previews
#Preview {
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 123, name: "PreviewUser", registered: 1, score: 100, mark: 2, badges: []);
    let playerManager = VideoPlayerManager()
    playerManager.configure(settings: previewSettings)
    
    return NavigationStack { UserUploadsView(username: "PreviewUser").environmentObject(previewSettings).environmentObject(previewAuthService).environmentObject(playerManager) }
}
// --- END OF COMPLETE FILE ---
