// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift

import SwiftUI
import os
import Kingfisher // <--- Import Kingfisher

// FeedItemThumbnail (KORRIGIERT)
struct FeedItemThumbnail: View {
    let item: Item
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    var body: some View {
        KFImage(item.thumbnailUrl) // <- Übergib die URL direkt an KFImage
            .placeholder { // Was angezeigt wird, während geladen wird
                Rectangle().fill(Material.ultraThin).overlay(ProgressView())
            }
            .onFailure { error in // Was passiert, wenn das Laden fehlschlägt
                Self.logger.error("KFImage failed to load thumbnail for item \(item.id): \(error.localizedDescription)")
            }
            // --- KORRIGIERT: cancelOnDisappear hier direkt an KFImage ---
            .cancelOnDisappear(true) // Wichtig: Bricht den Download ab, wenn die View verschwindet
            // --------------------------------------------------------
            .resizable() // Macht das Bild anpassbar
            .aspectRatio(contentMode: .fill) // Füllt den verfügbaren Platz (wird dann zugeschnitten)
            // Die äußeren Modifier bleiben gleich, um das quadratische, abgerundete Aussehen zu erhalten
            // --- KORRIGIERT: Punkt vor fit hinzugefügt ---
            .aspectRatio(1.0, contentMode: .fit)
            // --------------------------------------------
            .background(Material.ultraThin) // Hintergrund hinzufügen, falls Bild nicht lädt oder transparent ist
            .cornerRadius(5)
            .clipped() // Schneidet überstehende Teile ab
    }
}


// FeedView (Restlicher Code BLEIBT GLEICH wie in der letzten Version mit Cache-Merge)
struct FeedView: View {

    let popToRootTrigger: UUID

    @EnvironmentObject var settings: AppSettings
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false // Für Refresh
    @State private var canLoadMore = true
    @State private var isLoadingMore = false // Für Load More

    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private let loadMoreIdBuffer = 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                Group {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                FeedItemThumbnail(item: item) // Verwendet jetzt KFImage korrekt
                            }
                            .buttonStyle(.plain)
                        }

                        if canLoadMore && !isLoading && !isLoadingMore {
                             Color.clear.frame(height: 1)
                                .onAppear {
                                    Self.logger.info("End trigger element appeared.")
                                    Task { await loadMoreItems() }
                                }
                         }
                        if isLoadingMore { ProgressView("Lade mehr...").padding() }
                    }
                    .padding(.horizontal, 5).padding(.bottom)
                }
            }
             .refreshable { await refreshItems() }
            .navigationTitle(settings.feedType.displayName)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } } }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings) }
            .loadingOverlay(isLoading: isLoading && items.isEmpty)
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
            .onChange(of: settings.showPOL) { _, _ in Task { await refreshItems() } }
            .task { if items.isEmpty { await refreshItems() } }
            .onChange(of: popToRootTrigger) { if !navigationPath.isEmpty { navigationPath = NavigationPath() } }
        }
    }

    // --- refreshItems Funktion (BLEIBT GLEICH - Merge-Logik ist korrekt) ---
    func refreshItems() async {
        guard !isLoading else { return }
        Self.logger.info("Starting refresh process for feed: \(settings.feedType.displayName)...")
        await MainActor.run { isLoading = true; errorMessage = nil }
        canLoadMore = true; isLoadingMore = false

        // 1. Lade vorhandene Items aus dem Cache (falls vorhanden)
        var currentItemsFromCache: [Item] = []
        if let cachedItems = await settings.loadItemsFromCache(for: settings.feedType) {
            if !cachedItems.isEmpty {
                currentItemsFromCache = cachedItems
                await MainActor.run {
                    self.items = currentItemsFromCache
                    Self.logger.info("Successfully loaded \(currentItemsFromCache.count) items from data cache for initial display.")
                    if !navigationPath.isEmpty { navigationPath = NavigationPath() }
                }
            } else {
                 Self.logger.info("Data cache exists but is empty for \(settings.feedType.displayName).")
                 await MainActor.run { self.items = [] }
            }
        } else {
             Self.logger.info("No data cache found for \(settings.feedType.displayName).")
             await MainActor.run { self.items = [] }
        }

        // 2. Hole die *neuesten* Daten (erste Seite) von der API
        Self.logger.info("Performing API fetch for refresh...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted)
            Self.logger.info("API fetch completed: \(fetchedItemsFromAPI.count) fresh items.")

            // 3. Merge API-Daten mit Cache-Daten
            let mergedItems: [Item]
            if currentItemsFromCache.isEmpty {
                mergedItems = fetchedItemsFromAPI
                Self.logger.info("No data cache existed, using API items directly.")
            } else {
                let cachedItemIDs = Set(currentItemsFromCache.map { $0.id })
                let newUniqueItems = fetchedItemsFromAPI.filter { !cachedItemIDs.contains($0.id) }
                mergedItems = newUniqueItems + currentItemsFromCache
                Self.logger.info("Merged \(newUniqueItems.count) new unique items with \(currentItemsFromCache.count) cached items. Total: \(mergedItems.count)")
            }

            // 4. Aktualisiere UI und speichere gemergte Liste im Daten-Cache
            await MainActor.run {
                self.items = mergedItems
                if fetchedItemsFromAPI.isEmpty && currentItemsFromCache.isEmpty {
                    self.canLoadMore = false
                }
                if !fetchedItemsFromAPI.isEmpty && !navigationPath.isEmpty && !currentItemsFromCache.isEmpty {
                    navigationPath = NavigationPath()
                }
            }
            // Speichere die *gemergte* Liste im Daten-Cache
            await settings.saveItemsToCache(mergedItems, for: settings.feedType)
            await settings.updateCurrentCacheSize() // Größe aktualisieren (Daten + Bilder)

        } catch {
            Self.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            await MainActor.run {
                if self.items.isEmpty {
                    self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                } else {
                    Self.logger.warning("Showing cached data, but API refresh failed: \(error.localizedDescription)")
                }
            }
        }
        Self.logger.info("Finishing refresh process.")
        await MainActor.run { isLoading = false }
    }

    // --- getIdForLoadMore (BLEIBT GLEICH) ---
    private func getIdForLoadMore() -> Int? {
        let bufferIndex = max(0, items.count - loadMoreIdBuffer - 1)
        if items.indices.contains(bufferIndex) {
            let id = items[bufferIndex].id
            Self.logger.info("Using buffered ID (Buffer=\(loadMoreIdBuffer)) at index \(bufferIndex): \(id)")
            return id
        } else if let lastId = items.last?.id {
            Self.logger.info("Using last ID (fallback): \(lastId)")
            return lastId
        } else {
            Self.logger.warning("Cannot load more: No items to get ID from.")
            return nil
        }
    }

    // --- loadMoreItems Funktion (BLEIBT GLEICH) ---
    func loadMoreItems() async {
        guard !isLoadingMore && canLoadMore && !isLoading else {
             Self.logger.debug("Skipping loadMoreItems: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)")
             return
        }

        guard let lastItem = items.last else {
            Self.logger.warning("Skipping loadMoreItems: No last item found.")
            return
        }

        let olderValue: Int
        if settings.feedType == .promoted {
            guard let promotedId = lastItem.promoted else {
                 Self.logger.error("Skipping loadMoreItems: Promoted feed active but last item (ID: \(lastItem.id)) has no 'promoted' ID.")
                 await MainActor.run { canLoadMore = false }
                 return
            }
            olderValue = promotedId
            Self.logger.info("Using PROMOTED ID \(olderValue) from last item for 'older' parameter.")
        } else {
            olderValue = lastItem.id
            Self.logger.info("Using ITEM ID \(olderValue) from last item for 'older' parameter.")
        }

        Self.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")
        await MainActor.run { isLoadingMore = true }

        do {
            let newItems = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                olderThanId: olderValue
            )
            Self.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).")

            var appendedItemCount = 0
            await MainActor.run { // UI Update
                if newItems.isEmpty {
                    Self.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                    if uniqueNewItems.isEmpty {
                        Self.logger.warning("All loaded items (older than \(olderValue)) were duplicates.")
                        canLoadMore = false
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        appendedItemCount = uniqueNewItems.count
                        Self.logger.info("Appended \(uniqueNewItems.count) unique items. Total items: \(self.items.count)")
                    }
                }
            }

            // Speichere die *gesamte* aktuelle Liste im Daten-Cache nach dem Hinzufügen neuer Items
            if appendedItemCount > 0 {
                let itemsToSave = await MainActor.run { self.items }
                await settings.saveItemsToCache(itemsToSave, for: settings.feedType)
                await settings.updateCurrentCacheSize()
            }

        } catch {
            Self.logger.error("API fetch failed during loadMoreItems: \(error.localizedDescription)")
            await MainActor.run {
                if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                canLoadMore = false
            }
        }

        await MainActor.run { isLoadingMore = false }
        Self.logger.info("--- Finished loadMoreItems older than \(olderValue) ---")
    }
}

// MARK: - View Extension for Loading Overlay (BLEIBT GLEICH)
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

// MARK: - Preview (BLEIBT GLEICH)
#Preview {
    MainView()
        .environmentObject(AppSettings())
}
