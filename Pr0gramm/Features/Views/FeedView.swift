// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

// FeedItemThumbnail
struct FeedItemThumbnail: View {
    let item: Item
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    var body: some View {
        KFImage(item.thumbnailUrl)
            .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
            .onFailure { error in Self.logger.error("KFImage failed to load thumbnail for item \(item.id): \(error.localizedDescription)") }
            .cancelOnDisappear(true)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .aspectRatio(1.0, contentMode: .fit)
            .background(Material.ultraThin)
            .cornerRadius(5)
            .clipped()
    }
}


struct FeedView: View {

    let popToRootTrigger: UUID

    @EnvironmentObject var settings: AppSettings
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false

    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private let loadMoreIdBuffer = 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    private var feedCacheKey: String {
        return "feed_\(settings.feedType == .new ? "new" : "promoted")"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if showNoFilterMessage {
                    noFilterContentView
                } else if isLoading && items.isEmpty { // Zeigt Ladeindikator nur, wenn Liste leer ist
                    ProgressView("Lade...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
                     Text("Keine Medien für aktuelle Filter gefunden.")
                         .foregroundColor(.secondary)
                         .multilineTextAlignment(.center)
                         .padding()
                         .frame(maxWidth: .infinity, maxHeight: .infinity)
                 } else {
                    scrollViewContent
                 }
            }
            .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) {
                     Text(settings.feedType.displayName)
                         .font(.title3)
                         .fontWeight(.bold)
                 }
                 ToolbarItem(placement: .primaryAction) {
                     Button { showingFilterSheet = true } label: {
                         Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                     }
                 }
            }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings) }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .navigationDestination(for: Item.self) { destinationItem in
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) { PagedDetailView(items: items, selectedIndex: index) } else { Text("Fehler: Item nicht im aktuellen Feed gefunden.") }
            }
            .onChange(of: settings.feedType) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await refreshItems() } }
            .task { await refreshItems() } // Initialer Load beim Erscheinen
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
        }
    }

    // Extrahierter ScrollView-Inhalt
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(item: item)
                    }
                    .buttonStyle(.plain)
                }

                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1)
                        .onAppear {
                            Self.logger.info("Feed: End trigger element appeared.")
                            Task { await loadMoreItems() }
                        }
                 }
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await refreshItems() } // Hier wird refreshItems aufgerufen
    }

    // View für "Kein Filter"-Meldung
    private var noFilterContentView: some View {
         VStack {
             Spacer()
             Image(systemName: "line.3.horizontal.decrease.circle")
                 .font(.largeTitle)
                 .foregroundColor(.secondary)
                 .padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt")
                 .font(.headline)
             Text("Bitte passe deine Filter an, um Inhalte zu sehen.")
                 .font(.subheadline)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal)
             Button("Filter anpassen") {
                 showingFilterSheet = true
             }
             .buttonStyle(.bordered)
             .padding(.top)
             Spacer()
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .refreshable { await refreshItems() } // Auch hier refreshable
     }


    // refreshItems Funktion (Korrigiert für Pull-to-Refresh)
    func refreshItems() async {
        // guard !isLoading else { return } // Entfernt!

        Self.logger.info("Pull-to-Refresh triggered or refreshItems called.")

        if !settings.hasActiveContentFilter {
             Self.logger.warning("Refresh blocked: No active content filter selected.")
             await MainActor.run {
                 if !self.showNoFilterMessage || !self.items.isEmpty {
                     self.items = []
                     self.showNoFilterMessage = true
                     self.canLoadMore = false
                     self.isLoadingMore = false
                     self.errorMessage = nil
                 }
             }
             return // Wichtig: Beenden
         }

        // Setze isLoading erst hier
        await MainActor.run {
             if self.showNoFilterMessage { self.showNoFilterMessage = false }
             self.isLoading = true
             self.errorMessage = nil
         }

        // Defer zum sicheren Zurücksetzen
        defer {
            Task { @MainActor in
                self.isLoading = false
                Self.logger.info("Finishing refresh process (isLoading set to false via defer).")
            }
        }

        let currentCacheKey = self.feedCacheKey
        let currentApiFlags = settings.apiFlags
        Self.logger.info("Starting refresh data fetch for feed: \(settings.feedType.displayName) (CacheKey: \(currentCacheKey), Flags: \(currentApiFlags))...")
        canLoadMore = true; isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        // Temporäre Cache-Anzeige (optional)
        if items.isEmpty {
            if let cachedItems = await settings.loadItemsFromCache(forKey: currentCacheKey), !cachedItems.isEmpty {
                initialItemsFromCache = cachedItems
                Self.logger.info("Found \(cachedItems.count) items in cache initially.")
            } else {
                 Self.logger.info("No usable data cache found or cache empty for key \(currentCacheKey).")
            }
        }

        Self.logger.info("Performing API fetch for refresh with flags: \(currentApiFlags)...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: currentApiFlags, promoted: settings.apiPromoted)
            Self.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh items received for flags \(currentApiFlags).")

            await MainActor.run {
                self.items = fetchedItemsFromAPI
                self.canLoadMore = !fetchedItemsFromAPI.isEmpty
                self.showNoFilterMessage = false
                Self.logger.info("FeedView updated with \(fetchedItemsFromAPI.count) items directly from API.")
                if !navigationPath.isEmpty && initialItemsFromCache != nil {
                    navigationPath = NavigationPath()
                    Self.logger.info("Popped navigation due to refresh overwriting cache.")
                }
            }

            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: currentCacheKey)
            await settings.updateCacheSizes()

        } catch {
            Self.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            await MainActor.run {
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                } else {
                    Self.logger.warning("Showing potentially stale cached data because API refresh failed: \(error.localizedDescription)")
                }
                self.canLoadMore = false
            }
        }
        // `defer` setzt isLoading zurück
    }


    // getIdForLoadMore Funktion
    private func getIdForLoadMore() -> Int? {
        guard let lastItem = items.last else {
            Self.logger.warning("Cannot load more: No items to get ID from.")
            return nil
        }
        if settings.feedType == .promoted {
             guard let promotedId = lastItem.promoted else {
                 Self.logger.error("Cannot load more: Promoted feed active but last item (ID: \(lastItem.id)) has no 'promoted' ID.")
                 Task { await MainActor.run { self.canLoadMore = false } }
                 return nil
             }
             Self.logger.info("Using PROMOTED ID \(promotedId) from last item for 'older' parameter.")
             return promotedId
         } else {
             Self.logger.info("Using ITEM ID \(lastItem.id) from last item for 'older' parameter.")
             return lastItem.id
         }
    }


    // loadMoreItems Funktion
    func loadMoreItems() async {
        guard settings.hasActiveContentFilter else {
             Self.logger.warning("Skipping loadMoreItems: No active content filter selected.")
             await MainActor.run { canLoadMore = false }
             return
         }

        // Wichtig: isLoadingMore UND isLoading prüfen, um Konflikte mit Refresh zu vermeiden
        guard !isLoadingMore && canLoadMore && !isLoading else {
             Self.logger.debug("Skipping loadMoreItems: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)")
             return
        }
        let currentCacheKey = self.feedCacheKey
        guard let olderValue = getIdForLoadMore() else {
            Self.logger.warning("Skipping loadMoreItems: Could not determine 'older' value.")
            await MainActor.run { canLoadMore = false }
            return
        }

        await MainActor.run { isLoadingMore = true }
        Self.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")

        defer {
            Task { @MainActor in
                 if self.isLoadingMore {
                     self.isLoadingMore = false
                     Self.logger.info("--- Finished loadMoreItems older than \(olderValue) (isLoadingMore set to false) ---")
                 }
            }
        }

        do {
            let newItems = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                olderThanId: olderValue
            )
            Self.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).")

            var appendedItemCount = 0
            await MainActor.run {
                 guard self.isLoadingMore else { Self.logger.info("Load more cancelled before UI update."); return }
                if newItems.isEmpty {
                    Self.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                    if uniqueNewItems.isEmpty {
                        Self.logger.warning("All loaded items (older than \(olderValue)) were duplicates.")
                        // Optional: canLoadMore auf false setzen oder erneut versuchen? Vorerst belassen.
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        Self.logger.info("Appended \(uniqueNewItems.count) unique items. Total items: \(self.items.count)")
                        self.canLoadMore = true // Weiter laden möglich
                    }
                }
            }

            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, forKey: currentCacheKey)
                await settings.updateCacheSizes()
            }

        } catch {
            Self.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                 guard self.isLoadingMore else { return }
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                canLoadMore = false // Bei Fehler kein weiteres Laden
            }
        }
        // `defer` setzt isLoadingMore zurück
    }
}

// View Extension loadingOverlay
extension View {
    func loadingOverlay(isLoading: Bool) -> some View {
        self.overlay {
             if isLoading {
                 ZStack {
                     ProgressView("Lade...")
                         .padding()
                         .background(Material.regular)
                         .cornerRadius(10)
                 }
             }
        }
    }
}

// Preview
#Preview {
    MainView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService())
}
// --- END OF COMPLETE FILE ---
