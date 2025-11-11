// Pr0gramm/Pr0gramm/Features/Views/FeedView.swift
// --- KORRIGIERTE VERSION ---

import SwiftUI
import os
import Kingfisher

// --- OPTIMIERUNG: Equatable für bessere Render-Performance ---
struct FeedItemThumbnail: View, Equatable {
    let item: Item
    let isSeen: Bool
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedItemThumbnail")

    static func == (lhs: FeedItemThumbnail, rhs: FeedItemThumbnail) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSeen == rhs.isSeen
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.thumbnailUrl)
                .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
                .onFailure { error in FeedItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") }
                .cancelOnDisappear(true)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .aspectRatio(1.0, contentMode: .fit)
                .background(Material.ultraThin)
                .cornerRadius(5)
                .clipped()
            
            if isSeen {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
                    .padding(4)
            }
        }
    }
}


struct FeedView: View {
    let popToRootTrigger: UUID
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()
    @State private var didLoadInitially = false
    
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var refreshTask: Task<Void, Never>?
    
    @State private var nextOlderThanIdForApiCall: Int?

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedView")

    private let initialLoadDelay: Duration = .milliseconds(300)
    private let refreshIndicatorDelay: Duration = .milliseconds(250)
    private let preloadRowsAhead: Int = 5
    
    // --- KORREKTUR: Zurück zur berechneten Eigenschaft ---
    // Dies stellt sicher, dass die View neu gezeichnet wird, wenn sich die gridSize in den Einstellungen ändert.
    private var gridColumns: [GridItem] {
        let isMac = ProcessInfo.processInfo.isiOSAppOnMac
        let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact
        let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
        let minItemWidth: CGFloat = isMac ? 400 : (numberOfColumns <= 3 ? 100 : 80)
        return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Basis-Content der den ganzen Screen füllt
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Eigentlicher Content
                feedContentView
                
                // Header-Bar als fixiertes Overlay oben
                VStack {
                    headerControls
                        .ignoresSafeArea(edges: .horizontal)
                    Spacer()
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView(relevantFeedTypeForFilterBehavior: settings.feedType, hideFeedOptions: true, showHideSeenItemsToggle: true)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .navigationDestination(for: Item.self) { destinationItem in
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                    PagedDetailView(
                        items: $items,
                        selectedIndex: index,
                        playerManager: playerManager,
                        loadMoreAction: loadMoreItems
                    )
                } else {
                    Text("Fehler: Item nicht im aktuellen Feed gefunden.")
                }
            }
            .onChange(of: settings.feedType) { triggerRefreshTask() }
            // --- OPTIMIERUNG: `onChange`-Handler zusammengefasst ---
            .onChange(of: settings.apiFlags) { triggerRefreshTask() }
            .onChange(of: settings.hideSeenItems) { triggerRefreshTask() }
            .task {
                 FeedView.logger.debug("FeedView task started.")
                 playerManager.configure(settings: settings)
                 if !didLoadInitially {
                     FeedView.logger.info("FeedView task: Initial load required.")
                     try? await Task.sleep(for: initialLoadDelay)
                     guard !Task.isCancelled else { return }
                     await refreshItems()
                 }
             }
            .onDisappear {
                refreshTask?.cancel()
            }
            .onChange(of: popToRootTrigger) {
                if !navigationPath.isEmpty { navigationPath = NavigationPath() }
            }
        }
    }
    
    // MARK: - View Components

    @ViewBuilder
    private var headerControls: some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass Design für iOS 26+ - mit vergrößertem Rahmen und runderen Ecken
            HStack(spacing: 8) {
                Picker("Feed Typ", selection: $settings.feedType) {
                    ForEach(FeedType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                
                // Filter Button mit Liquid Glass Hintergrund
                Button { showingFilterSheet = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            // Elegantes Design für iOS < 26 - mit vergrößertem Rahmen und runderen Ecken
            HStack(spacing: 8) {
                Picker("Feed Typ", selection: $settings.feedType) {
                    ForEach(FeedType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                
                // Filter Button mit Material Hintergrund
                Button { showingFilterSheet = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder private var feedContentView: some View {
        if showNoFilterMessage {
            noFilterContentView
        } else if isLoading && items.isEmpty {
            ProgressView("Lade...").frame(maxHeight: .infinity)
        } else if items.isEmpty && !isLoading && errorMessage == nil {
             let message = settings.hideSeenItems ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden."
             Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
        } else {
            scrollViewContent
        }
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        // Prefetch thumbnails for the next rows when we reach the beginning of a row
                        if gridColumns.count > 0, index % gridColumns.count == 0 {
                            let nextPrefetchCount = gridColumns.count * 2 // prefetch two rows ahead
                            let start = min(index + gridColumns.count, items.count)
                            let end = min(start + nextPrefetchCount, items.count)
                            if start < end {
                                let urls: [URL] = items[start..<end].compactMap { $0.thumbnailUrl }
                                if !urls.isEmpty {
                                    let prefetcher = ImagePrefetcher(urls: urls)
                                    prefetcher.start()
                                }
                            }
                        }

                        // Trigger early load more when reaching a threshold several rows before the end
                        let offset = max(1, gridColumns.count) * preloadRowsAhead
                        let thresholdIndex = max(0, items.count - offset)
                        if index >= thresholdIndex && canLoadMore && !isLoadingMore && !isLoading && settings.hasActiveContentFilter {
                            Task { await loadMoreItems() }
                        }
                    }
                }

                if canLoadMore && !isLoadingMore && !items.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await loadMoreItems() }
                        }
                }

                if isLoadingMore {
                    ProgressView("Lade mehr...")
                        .padding()
                        .gridCellColumns(gridColumns.count)
                }
            }
            .padding(.horizontal, 5)
            .padding(.top, 76) // Angepasst für höhere Bar
            .padding(.bottom)
        }
        .refreshable { await refreshItems() }
    }
    
    @ViewBuilder private var noFilterContentView: some View {
        VStack {
             Spacer()
             Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt").font(UIConstants.headlineFont)
             Text("Bitte passe deine Filter an, um Inhalte zu sehen.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button("Filter anpassen") { showingFilterSheet = true }.buttonStyle(.bordered).padding(.top)
             Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refreshItems() }
    }

    // MARK: - Data Loading
    
    private func triggerRefreshTask() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await refreshItems()
        }
    }

    @MainActor
    private func refreshItems() async {
        guard !isLoading else { return }
        
        items = []
        nextOlderThanIdForApiCall = nil
        canLoadMore = true
        errorMessage = nil
        showNoFilterMessage = !settings.hasActiveContentFilter
        
        if showNoFilterMessage { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await findUnseenItems(startingFrom: nil)
            guard !Task.isCancelled else { return }
            
            items = result.items
            nextOlderThanIdForApiCall = result.nextOlderThanId
            canLoadMore = !result.apiReachedEnd
            didLoadInitially = true
            
            if !navigationPath.isEmpty { navigationPath = NavigationPath() }
            
        } catch is CancellationError {
            FeedView.logger.info("Refresh task was cancelled.")
        } catch {
            FeedView.logger.error("API fetch failed during refresh: \(error.localizedDescription)")
            errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
            canLoadMore = false
            didLoadInitially = true
        }
    }

    @MainActor
    private func loadMoreItems() async {
        guard !isLoadingMore && canLoadMore && !isLoading && settings.hasActiveContentFilter else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await findUnseenItems(startingFrom: nextOlderThanIdForApiCall)
            guard !Task.isCancelled else { return }

            if !result.items.isEmpty {
                items.append(contentsOf: result.items)
            }
            nextOlderThanIdForApiCall = result.nextOlderThanId
            canLoadMore = !result.apiReachedEnd
            
        } catch is CancellationError {
            FeedView.logger.info("Load more task was cancelled.")
        } catch {
            FeedView.logger.error("API fetch failed during loadMore: \(error.localizedDescription)")
            if items.isEmpty {
                errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)"
            }
            canLoadMore = false
        }
    }
    
    // --- OPTIMIERUNG: Die ausgelagerte, zentrale Ladelogik ---
    private struct FetchResult {
        let items: [Item]
        let nextOlderThanId: Int?
        let apiReachedEnd: Bool
    }
    
    private func findUnseenItems(startingFrom olderThanId: Int?) async throws -> FetchResult {
        var fetchedItems: [Item] = []
        var lastRawItemFromApiResponse: Item?
        var apiSaysNoMoreItems = false
        var currentOlderForLoop: Int? = olderThanId

        if settings.hideSeenItems {
            var pagesAttempted = 0
            while fetchedItems.isEmpty && !apiSaysNoMoreItems {
                guard !Task.isCancelled else { throw CancellationError() }
                pagesAttempted += 1
                
                let apiResponse = try await apiService.fetchItems(
                    flags: settings.apiFlags, promoted: settings.apiPromoted,
                    olderThanId: currentOlderForLoop, showJunkParameter: settings.apiShowJunk
                )

                let rawPageItems = apiResponse.items
                lastRawItemFromApiResponse = rawPageItems.last
                
                let currentItemIDs = await MainActor.run { Set(self.items.map { $0.id }) }
                let uniqueUnseenItems = rawPageItems.filter { !settings.seenItemIDs.contains($0.id) && !currentItemIDs.contains($0.id) }
                
                fetchedItems.append(contentsOf: uniqueUnseenItems)
                apiSaysNoMoreItems = apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil)
                
                if let lastItem = rawPageItems.last, !apiSaysNoMoreItems {
                    currentOlderForLoop = settings.feedType == .promoted ? lastItem.promoted ?? lastItem.id : lastItem.id
                } else if rawPageItems.isEmpty {
                    apiSaysNoMoreItems = true
                }
            }
        } else {
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags, promoted: settings.apiPromoted,
                olderThanId: olderThanId, showJunkParameter: settings.apiShowJunk
            )
            let currentItemIDs = await MainActor.run { Set(self.items.map { $0.id }) }
            fetchedItems = apiResponse.items.filter { !currentItemIDs.contains($0.id) }
            lastRawItemFromApiResponse = apiResponse.items.last
            apiSaysNoMoreItems = apiResponse.atEnd == true || (apiResponse.hasOlder == false && apiResponse.hasOlder != nil)
        }
        
        let nextIdToUse = settings.feedType == .promoted ? lastRawItemFromApiResponse?.promoted ?? lastRawItemFromApiResponse?.id : lastRawItemFromApiResponse?.id
        let finalNextOlderId = nextIdToUse ?? currentOlderForLoop

        return FetchResult(items: fetchedItems, nextOlderThanId: finalNextOlderId, apiReachedEnd: apiSaysNoMoreItems)
    }
}

