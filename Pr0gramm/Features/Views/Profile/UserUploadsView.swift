// Pr0gramm/Pr0gramm/Features/Views/Profile/UserUploadsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher
// import UIKit // Nicht mehr benötigt

/// Displays the items uploaded by a specific user in a grid.
/// Handles loading, pagination, filtering (based on global settings), and navigation.
struct UserUploadsView: View {
    let username: String // Username whose uploads to display

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService // Needed for settings/playerManager config
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    // Filters are applied globally, no need for local filter sheet state

    @State private var navigationPath = NavigationPath()
    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserUploadsView")

    // Computed property for adaptive columns
     private var gridColumns: [GridItem] {
         // Use ProcessInfo to detect if the iPad app is running ON macOS
         let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
         // Verwende 250 auf dem Mac für deutlich weniger Spalten
         let minWidth: CGFloat = isRunningOnMac ? 250 : 100 // Set to 250 for Mac
         return [GridItem(.adaptive(minimum: minWidth), spacing: 3)]
     }

    private var userUploadsCacheKey: String { return "uploads_\(username.lowercased())" }

    var body: some View {
        Group { uploadsContentView }
        .navigationTitle("Uploads von \(username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .navigationDestination(for: Item.self) { destinationItem in
            if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                PagedDetailView(items: items, selectedIndex: index, playerManager: playerManager)
            } else { Text("Fehler: Item nicht in Uploads gefunden.") }
        }
        .task { await playerManager.configure(settings: settings); await refreshUploads() }
        .onChange(of: settings.showSFW) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showNSFW) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showNSFL) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showNSFP) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.showPOL) { _, _ in Task { await refreshUploads() } }
        .onChange(of: settings.seenItemIDs) { _, _ in UserUploadsView.logger.trace("UserUploadsView detected change in seenItemIDs, body will update.") }
    }

    // MARK: - Extracted Content Views

    @ViewBuilder private var uploadsContentView: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Lade Uploads...")
                    .font(UIConstants.bodyFont) // Use adaptive font
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty {
                 ContentUnavailableView {
                     Label("Fehler", systemImage: "exclamationmark.triangle")
                        .font(UIConstants.headlineFont) // Use adaptive font
                 } description: {
                     Text(error)
                        .font(UIConstants.bodyFont) // Use adaptive font
                 } actions: {
                     Button("Erneut versuchen") { Task { await refreshUploads() } }
                        .font(UIConstants.bodyFont) // Use adaptive font
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading && errorMessage == nil {
                Text("\(username) hat noch nichts hochgeladen (oder nichts passt zu deinen Filtern).")
                    .font(UIConstants.bodyFont) // Use adaptive font
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollViewContent // Grid uses adaptive columns internally
            }
        }
    }
    private var scrollViewContent: some View {
        ScrollView {
            // Use computed gridColumns
            LazyVGrid(columns: gridColumns, spacing: 3) {
                 ForEach(items) { item in
                     NavigationLink(value: item) { FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id)) }.buttonStyle(.plain)
                 }
                 if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1).onAppear { UserUploadsView.logger.info("Uploads: End trigger appeared."); Task { await loadMoreUploads() } }
                 }
                 if isLoadingMore {
                     ProgressView("Lade mehr...")
                        .font(UIConstants.bodyFont) // Use adaptive font
                        .padding()
                 }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await refreshUploads() }
    }

    // MARK: - Data Loading Methods

    func refreshUploads() async {
        UserUploadsView.logger.info("Refreshing uploads for user: \(username)")
        let cacheKey = userUploadsCacheKey
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in self.isLoading = false; UserUploadsView.logger.info("Finished uploads refresh process for \(username).") } }
        UserUploadsView.logger.info("Starting refresh data fetch for uploads (User: \(username), Flags: \(settings.apiFlags))..."); canLoadMore = true; isLoadingMore = false; var initialItemsFromCache: [Item]? = nil
        if items.isEmpty { if let cachedItems = await settings.loadItemsFromCache(forKey: cacheKey), !cachedItems.isEmpty { initialItemsFromCache = cachedItems; UserUploadsView.logger.info("Found \(cachedItems.count) uploaded items in cache initially for \(username)."); await MainActor.run { self.items = cachedItems } } else { UserUploadsView.logger.info("No usable data cache found for uploads for \(username).") } }
        UserUploadsView.logger.info("Performing API fetch for uploads refresh (User: \(username), Flags: \(settings.apiFlags))...");
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: settings.apiFlags, user: username)
            UserUploadsView.logger.info("API fetch for uploads completed: \(fetchedItemsFromAPI.count) items for user \(username).")
            await MainActor.run {
                self.items = fetchedItemsFromAPI
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty
                UserUploadsView.logger.info("UserUploadsView updated with \(fetchedItemsFromAPI.count) items directly from API for \(username).")
                if !navigationPath.isEmpty && initialItemsFromCache != nil && initialItemsFromCache != fetchedItemsFromAPI { navigationPath = NavigationPath(); UserUploadsView.logger.info("Popped navigation due to uploads refresh overwriting cache.") }
            }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey); await settings.updateCacheSizes()
        }
        catch let error as URLError where error.code == .userAuthenticationRequired { UserUploadsView.logger.error("API fetch for uploads failed: Authentication required (User: \(username)). Session might be invalid."); await MainActor.run { self.items = []; self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false }; await settings.saveItemsToCache([], forKey: cacheKey); await authService.logout() }
        catch { UserUploadsView.logger.error("API fetch for uploads failed (User: \(username)): \(error.localizedDescription)"); await MainActor.run { if self.items.isEmpty { self.errorMessage = "Fehler beim Laden der Uploads: \(error.localizedDescription)" } else { UserUploadsView.logger.warning("Showing potentially stale cached uploads data because API refresh failed for \(username).") }; self.canLoadMore = false } }
    }

    func loadMoreUploads() async {
        guard !isLoadingMore && canLoadMore && !isLoading else { UserUploadsView.logger.debug("Skipping loadMoreUploads: State prevents loading."); return }
        guard let lastItemId = items.last?.id else { UserUploadsView.logger.warning("Skipping loadMoreUploads: No last item found."); return }
        let cacheKey = userUploadsCacheKey; UserUploadsView.logger.info("--- Starting loadMoreUploads for user \(username) older than \(lastItemId) ---"); await MainActor.run { isLoadingMore = true }; defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserUploadsView.logger.info("--- Finished loadMoreUploads for user \(username) ---") } } }
        do {
            let newItems = try await apiService.fetchItems(flags: settings.apiFlags, user: username, olderThanId: lastItemId)
            UserUploadsView.logger.info("Loaded \(newItems.count) more uploaded items from API (requesting older than \(lastItemId))."); var appendedItemCount = 0
            await MainActor.run {
                guard self.isLoadingMore else { UserUploadsView.logger.info("Load more cancelled before UI update."); return }
                if newItems.isEmpty { UserUploadsView.logger.info("Reached end of uploads feed for \(username)."); canLoadMore = false }
                else { let currentIDs = Set(self.items.map { $0.id }); let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }; if uniqueNewItems.isEmpty { UserUploadsView.logger.warning("All loaded uploaded items (older than \(lastItemId)) were duplicates for \(username)."); canLoadMore = false } else { self.items.append(contentsOf: uniqueNewItems); appendedItemCount = uniqueNewItems.count; UserUploadsView.logger.info("Appended \(uniqueNewItems.count) unique uploaded items for \(username). Total items: \(self.items.count)"); self.canLoadMore = true } }
            }
            if appendedItemCount > 0 { let itemsToSave = await MainActor.run { self.items }; await settings.saveItemsToCache(itemsToSave, forKey: cacheKey); await settings.updateCacheSizes() }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired { UserUploadsView.logger.error("API fetch for more uploads failed: Authentication required (User: \(username)). Session might be invalid."); await MainActor.run { self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."; self.canLoadMore = false; Task { await authService.logout() } } }
        catch { UserUploadsView.logger.error("API fetch failed during loadMoreUploads for \(username): \(error.localizedDescription)"); await MainActor.run { guard self.isLoadingMore else { return }; if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }; canLoadMore = false } }
    }
}

// MARK: - Previews
#Preview {
    let previewSettings = AppSettings(); let previewAuthService = AuthService(appSettings: previewSettings); previewAuthService.isLoggedIn = true; previewAuthService.currentUser = UserInfo(id: 123, name: "PreviewUser", registered: 1, score: 100, mark: 2, badges: []); return NavigationStack { UserUploadsView(username: "PreviewUser").environmentObject(previewSettings).environmentObject(previewAuthService) }
}
// --- END OF COMPLETE FILE ---
