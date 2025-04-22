// FeedView.swift

import SwiftUI
import os

// FeedItemThumbnail (VOLLSTÄNDIG)
struct FeedItemThumbnail: View {
    let item: Item
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    var body: some View {
        AsyncImage(url: item.thumbnailUrl) { phase in // <- Verwendet thumbnailUrl von Item
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
            case .failure(let error):
                let _ = Self.logger.error("Failed to load thumbnail for item \(item.id): \(error.localizedDescription)")
                Rectangle().fill(Material.ultraThin).overlay(Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red))
            case .empty: Rectangle().fill(Material.ultraThin).overlay(ProgressView())
            @unknown default: EmptyView()
            }
        }
        .aspectRatio(1.0, contentMode: .fit).cornerRadius(5).clipped()
    }
}

// FeedView (VOLLSTÄNDIG - Korrigierter API Call und Typ-Handling)
struct FeedView: View {

    let popToRootTrigger: UUID

    @EnvironmentObject var settings: AppSettings
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private let loadMoreIdBuffer = 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                Group { // Zur Strukturierung
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                FeedItemThumbnail(item: item) // Verwendet korrigierte Struktur
                            }
                            .buttonStyle(.plain)
                        }

                        // Trigger-Element am Ende
                        if canLoadMore && !isLoading && !isLoadingMore {
                             Color.clear.frame(height: 1)
                                .onAppear {
                                    Self.logger.info("End trigger element appeared.")
                                    Task { await loadMoreItems() } // Ruft Version OHNE Parameter auf
                                }
                         }
                        // Ladeanzeige am Ende
                        if isLoadingMore { ProgressView("Lade mehr...").padding() }
                    }
                    .padding(.horizontal, 5).padding(.bottom)
                } // Ende Group
            } // Ende ScrollView
            // Modifikatoren
             .refreshable { await refreshItems() }
            .navigationTitle(settings.feedType.displayName)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") } } }
            .sheet(isPresented: $showingFilterSheet) { FilterView().environmentObject(settings) }
            .loadingOverlay(isLoading: isLoading)
            .alert("Fehler", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } }
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
        } // Ende NavigationStack
    }

    // --- refreshItems Funktion (VOLLSTÄNDIG) ---
    // Erwartet jetzt [Item] vom API-Call
    func refreshItems() async {
        guard !isLoading else { return }
        Self.logger.info("Starting refresh process...")
        await MainActor.run { isLoading = true }
        errorMessage = nil; canLoadMore = true; isLoadingMore = false
        await MainActor.run { if !navigationPath.isEmpty { navigationPath = NavigationPath() }; items = [] }
        Self.logger.info("Performing initial fetch...")
        do {
            // Erwartet [Item], kein Tupel mehr
            let fetchedItems = try await apiService.fetchItems(flags: settings.apiFlags, promoted: settings.apiPromoted)
            await MainActor.run {
                self.items = fetchedItems
                if fetchedItems.isEmpty { self.canLoadMore = false }
                Self.logger.info("Initial fetch completed: \(fetchedItems.count) items.")
            }
        } catch { /* Fehlerbehandlung */ }
        Self.logger.info("Finishing refresh process.")
        await MainActor.run { isLoading = false }
    }

    // --- Hilfsfunktion zur ID-Ermittlung (VOLLSTÄNDIG) ---
    // Gibt Int? zurück, entscheidet aber nicht mehr über promoted/id
    private func getIdForLoadMore() -> Int? {
        // Wir verwenden hier immer die Item-ID als Referenzpunkt für den Puffer,
        // da 'promoted' nicht bei allen Items vorhanden ist. Der API-Call
        // selbst wird dann aber den korrekten Wert senden (siehe loadMoreItems).
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

    // --- loadMoreItems Funktion (VOLLSTÄNDIG, OHNE Parameter, MIT korrekter ID/PromotedID für API Call) ---
    func loadMoreItems() async {
        guard !isLoadingMore && canLoadMore && !isLoading else { /* ... skip ... */ return }

        // Hole das Item, von dem wir die ID für den API Call brauchen
        // Wir nehmen hier das *letzte* Item, da die Logik dafür einfacher ist
        // und der Puffer in der API (`older=`) vielleicht doch besser funktioniert.
        guard let lastItem = items.last else {
            Self.logger.warning("Skipping loadMoreItems: No last item found.")
            return
        }

        // --- Logik: Wähle ID oder Promoted ID für den API Call ---
        let olderValue: Int
        if settings.feedType == .promoted {
            // Für Beliebt: Nutze die 'promoted' ID, falls vorhanden
            guard let promotedId = lastItem.promoted else {
                 Self.logger.error("Skipping loadMoreItems: Promoted feed active but last item (ID: \(lastItem.id)) has no 'promoted' ID.")
                 await MainActor.run { canLoadMore = false }
                 return
            }
            olderValue = promotedId
            Self.logger.info("Using PROMOTED ID \(olderValue) from last item for 'older' parameter.")
        } else {
            // Für Neu: Nutze die normale 'id' des letzten Items
            olderValue = lastItem.id
            Self.logger.info("Using ITEM ID \(olderValue) from last item for 'older' parameter.")
        }
        // --- Ende Logik ---


        Self.logger.info("--- Starting loadMoreItems older than \(olderValue) ---")
        await MainActor.run { isLoadingMore = true }

        do {
            // API Service gibt nur [Item] zurück und erwartet olderThanId
            let newItems = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                olderThanId: olderValue // Hier wird ID oder PromotedID übergeben
            )
            Self.logger.info("Loaded \(newItems.count) more items from API (requesting older than \(olderValue)).")

            await MainActor.run { // UI Update
                if newItems.isEmpty {
                    Self.logger.info("Reached end of feed (API returned empty list for older than \(olderValue)).")
                    canLoadMore = false
                } else {
                    let currentIDs = Set(self.items.map { $0.id })
                    let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                    if uniqueNewItems.isEmpty {
                        Self.logger.warning("All loaded items (older than \(olderValue)) were duplicates.")
                        canLoadMore = false // Stop bei Duplikaten aktiv!
                        Self.logger.notice("Setting canLoadMore to false.")
                    } else {
                        self.items.append(contentsOf: uniqueNewItems)
                        Self.logger.info("Appended \(uniqueNewItems.count) unique items. Total items: \(self.items.count)")
                    }
                }
            }
        } catch { /* Fehlerbehandlung & canLoadMore = false */ }

        await MainActor.run { isLoadingMore = false }
        Self.logger.info("--- Finished loadMoreItems older than \(olderValue) ---")
    }
}

// MARK: - View Extension for Loading Overlay (VOLLSTÄNDIG)
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

// MARK: - Preview (VOLLSTÄNDIG)
#Preview {
    MainView()
        .environmentObject(AppSettings())
}
