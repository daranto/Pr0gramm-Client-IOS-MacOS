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
    @EnvironmentObject var authService: AuthService // Needed for settings/playerManager config
    @State var items: [Item] = [] // Keep non-private for binding
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var navigationPath = NavigationPath()
    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserUploadsView")

    private var gridColumns: [GridItem] {
            let isMac = ProcessInfo.processInfo.isiOSAppOnMac
            let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact

            let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
            let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)

            return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
        }

    private var userUploadsCacheKey: String { return "uploads_\(username.lowercased())_flags_\(settings.apiFlags)" } // Include flags in cache key

    var body: some View {
        Group { uploadsContentView }
        .navigationTitle("Uploads von \(username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .navigationDestination(for: Item.self) { destinationItem in
            detailView(for: destinationItem)
        }
        .task { playerManager.configure(settings: settings); await refreshUploads() }
        .onChange(of: settings.apiFlags) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.seenItemIDs) { _, _ in UserUploadsView.logger.trace("UserUploadsView detected change in seenItemIDs, body will update.") }
    }

    @ViewBuilder
    private func detailView(for destinationItem: Item) -> some View {
        if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
            PagedDetailView(
                items: $items,
                selectedIndex: index,
                playerManager: playerManager,
                loadMoreAction: { Task { await loadMoreUploads() } }
            )
        } else {
            Text("Fehler: Item \(destinationItem.id) nicht mehr in der Uploads-Liste gefunden.")
                .onAppear {
                    UserUploadsView.logger.warning("Navigation destination item \(destinationItem.id) not found in current items list.")
                }
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
                     Button("Erneut versuchen") { Task { await refreshUploads() } }
                        .font(UIConstants.bodyFont)
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
                     NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                 }
                 if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1).onAppear { UserUploadsView.logger.info("Uploads: End trigger appeared."); Task { await loadMoreUploads() } }
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
        .refreshable { await refreshUploads() }
    }


    @MainActor
    func refreshUploads() async {
        UserUploadsView.logger.info("Refreshing uploads for user: \(username)")
        let cacheKey = userUploadsCacheKey
        self.isLoading = true; self.errorMessage = nil
        defer { Task { @MainActor in self.isLoading = false; UserUploadsView.logger.info("Finished uploads refresh process for \(username).") } }
        
        canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil

        if items.isEmpty {
            initialItemsFromCache = await settings.loadItemsFromCache(forKey: cacheKey)
            if let cached = initialItemsFromCache, !cached.isEmpty {
                 UserUploadsView.logger.info("Found \(cached.count) uploaded items in cache initially for \(username) with flags \(settings.apiFlags).");
                 self.items = cached
            } else {
                 UserUploadsView.logger.info("No usable data cache found for uploads for \(username) with flags \(settings.apiFlags).")
            }
        }
        let oldFirstItemId = items.first?.id
        UserUploadsView.logger.info("Performing API fetch for uploads refresh (User: \(username), Flags: \(settings.apiFlags))...");
        
        do {
            let apiResponse = try await apiService.fetchItems(flags: settings.apiFlags, user: username)
            let fetchedItemsFromAPI = apiResponse.items
            UserUploadsView.logger.info("API fetch for uploads completed: \(fetchedItemsFromAPI.count) items for user \(username).")
            
            await MainActor.run {
                self.items = fetchedItemsFromAPI
                if fetchedItemsFromAPI.isEmpty {
                    self.canLoadMore = false
                    UserUploadsView.logger.info("Refresh returned 0 items. Setting canLoadMore to false.")
                } else {
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true // Default to true if nil
                    if atEnd {
                        self.canLoadMore = false
                        UserUploadsView.logger.info("API indicates atEnd=true. Setting canLoadMore to false.")
                    } else if hasOlder == false { // Nur false, nicht nil
                        self.canLoadMore = false
                        UserUploadsView.logger.info("API indicates hasOlder=false. Setting canLoadMore to false.")
                    } else {
                        self.canLoadMore = true
                        UserUploadsView.logger.info("API indicates more items might be available for refresh (atEnd=\(atEnd), hasOlder=\(hasOlder)). Setting canLoadMore to true.")
                    }
                }
                UserUploadsView.logger.info("UserUploadsView updated with \(fetchedItemsFromAPI.count) items directly from API for \(username). Can load more: \(self.canLoadMore)")
                
                let newFirstItemId = fetchedItemsFromAPI.first?.id
                if !navigationPath.isEmpty && (initialItemsFromCache == nil || initialItemsFromCache?.count != fetchedItemsFromAPI.count || oldFirstItemId != newFirstItemId) {
                    navigationPath = NavigationPath()
                    UserUploadsView.logger.info("Popped navigation due to uploads refresh resulting in different list content.")
                }
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey);
            await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for uploads failed: Authentication required (User: \(username)). Session might be invalid.");
            await MainActor.run {
                self.items = [];
                self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
                self.canLoadMore = false
            }
            await settings.saveItemsToCache([], forKey: cacheKey);
            await authService.logout()
        }
        catch {
            UserUploadsView.logger.error("API fetch for uploads failed (User: \(username)): \(error.localizedDescription)");
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
        guard !isLoadingMore && canLoadMore && !isLoading else { UserUploadsView.logger.debug("Skipping loadMoreUploads: State prevents loading."); return }
        guard let lastItemId = items.last?.id else { UserUploadsView.logger.warning("Skipping loadMoreUploads: No last item found."); return }
        let cacheKey = userUploadsCacheKey; UserUploadsView.logger.info("--- Starting loadMoreUploads for user \(username) older than \(lastItemId) ---");
        self.isLoadingMore = true;
        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserUploadsView.logger.info("--- Finished loadMoreUploads for user \(username) ---") } } }
        
        do {
            let apiResponse = try await apiService.fetchItems(flags: settings.apiFlags, user: username, olderThanId: lastItemId)
            let newItems = apiResponse.items
            UserUploadsView.logger.info("Loaded \(newItems.count) more uploaded items from API (requesting older than \(lastItemId)).");
            var appendedItemCount = 0
            
            await MainActor.run {
                guard self.isLoadingMore else { UserUploadsView.logger.info("Load more cancelled before UI update."); return }
                if newItems.isEmpty {
                    UserUploadsView.logger.info("Reached end of uploads feed for \(username) because API returned 0 items for loadMore.")
                    self.canLoadMore = false // Wenn 0 Items geladen werden, gibt es nichts mehr.
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) };
                    if uniqueNewItems.isEmpty {
                        UserUploadsView.logger.warning("All loaded uploaded items (older than \(lastItemId)) were duplicates for \(username). Assuming end of actual new content.")
                        self.canLoadMore = false // Wenn nur Duplikate kommen, gibt es auch nichts Neues mehr.
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        UserUploadsView.logger.info("Appended \(uniqueNewItems.count) unique uploaded items for \(username). Total items: \(self.items.count)")

                        let atEnd = apiResponse.atEnd ?? false
                        let hasOlder = apiResponse.hasOlder ?? true // Default to true if nil
                        if atEnd {
                            self.canLoadMore = false
                            UserUploadsView.logger.info("API indicates atEnd=true after loadMore.")
                        } else if hasOlder == false { // Nur false, nicht nil
                            self.canLoadMore = false
                            UserUploadsView.logger.info("API indicates hasOlder=false after loadMore.")
                        } else {
                            self.canLoadMore = true
                            UserUploadsView.logger.info("API indicates more items might be available after loadMore (atEnd=\(atEnd), hasOlder=\(hasOlder)).")
                        }
                    }
                }
            }
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: cacheKey);
                await settings.updateCacheSizes()
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            UserUploadsView.logger.error("API fetch for more uploads failed: Authentication required (User: \(username)). Session might be invalid.");
            await MainActor.run {
                self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden.";
                self.canLoadMore = false;
            }
            await authService.logout()
        }
        catch is CancellationError { UserUploadsView.logger.info("Load more uploads API call cancelled.") }
        catch {
            UserUploadsView.logger.error("API fetch failed during loadMoreUploads for \(username): \(error.localizedDescription)");
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
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 123, name: "PreviewUser", registered: 1, score: 100, mark: 2, badges: []); return NavigationStack { UserUploadsView(username: "PreviewUser").environmentObject(previewSettings).environmentObject(previewAuthService) }
}
// --- END OF COMPLETE FILE ---
