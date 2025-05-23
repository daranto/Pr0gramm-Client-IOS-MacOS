// Pr0gramm/Pr0gramm/Features/Views/UnlimitedStyleFeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher // Für KFImage, falls direkt hier verwendet

struct UnlimitedStyleFeedView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService // Für Tab-Wechsel etc.

    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var keyboardActionHandler = KeyboardActionHandler() // Für Keyboard-Navigation

    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath() // Für interne Navigation, falls benötigt

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedStyleFeedView")
    
    @State private var activeItemID: Int? = nil
    @State private var scrolledItemID: Int? = nil // Für .scrollPosition

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                feedControls // Filter etc.
                feedContent
            }
            .navigationTitle("Feed (Vertikal)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingFilterSheet = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterView(relevantFeedTypeForFilterBehavior: settings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .onAppear {
                playerManager.configure(settings: settings)
                keyboardActionHandler.selectNextAction = selectNextItem
                keyboardActionHandler.selectPreviousAction = selectPreviousItem
                keyboardActionHandler.seekForwardAction = playerManager.seekForward
                keyboardActionHandler.seekBackwardAction = playerManager.seekBackward

                if items.isEmpty {
                    Task { await refreshItems() }
                }
            }
            .onChange(of: settings.feedType) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await refreshItems() } }
            .onChange(of: settings.hideSeenItems) { _, _ in Task { await refreshItems() } }
        }
    }

    @ViewBuilder
    private var feedControls: some View {
        Picker("Feed Typ", selection: $settings.feedType) {
            ForEach(FeedType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var feedContent: some View {
        if isLoading && items.isEmpty {
            ProgressView("Lade Feed...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, items.isEmpty {
            VStack {
                Text("Fehler: \(error)").foregroundColor(.red)
                Button("Erneut versuchen") { Task { await refreshItems() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && !isLoading {
            Text(settings.hideSeenItems && settings.enableExperimentalHideSeen ? "Keine neuen Posts, die den Filtern entsprechen." : "Keine Posts für die aktuellen Filter gefunden.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        UnlimitedFeedItemView(
                            item: item,
                            playerManager: playerManager,
                            keyboardActionHandler: keyboardActionHandler,
                            isActive: activeItemID == item.id
                        )
                        .id(item.id)
                        // --- MODIFIED: Verwende .containerRelativeFrame für die Höhe ---
                        .containerRelativeFrame(.vertical) // Jedes Item füllt die Höhe des ScrollView-Containers
                        // --- END MODIFICATION ---
                        .onAppear {
                            if item.id == items.last?.id && canLoadMore && !isLoadingMore {
                                Task { await loadMoreItems() }
                            }
                        }
                        // --- NEW: Scroll Transition Effekt ---
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.7)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.9)
                        }
                        // --- END NEW ---
                    }
                    if isLoadingMore {
                        ProgressView("Lade mehr...")
                            .frame(maxWidth: .infinity) // Nimmt die Breite des ScrollViews
                            .frame(height: 100) // Feste Höhe für den Ladeindikator
                            .padding()
                    }
                }
                // --- NEW: .scrollTargetLayout() für präziseres Paging ---
                .scrollTargetLayout() // Definiert, dass die Kinder des LazyVStacks die Scroll-Ziele sind
                // --- END NEW ---
            }
            .scrollTargetBehavior(.paging) // Stellt sicher, dass zum nächsten/vorherigen Item gesnappt wird
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
            .background(KeyCommandView(handler: keyboardActionHandler))
            .scrollPosition(id: $scrolledItemID)
            .onChange(of: scrolledItemID) { oldValue, newValue in
                guard let newId = newValue else { return }
                if let index = items.firstIndex(where: { $0.id == newId }) {
                    let currentItem = items[index]
                    activeItemID = currentItem.id
                    if oldValue != newValue || (oldValue == nil && newId != items.first?.id) {
                        settings.markItemAsSeen(id: currentItem.id)
                    }
                    playerManager.setupPlayerIfNeeded(for: currentItem, isFullscreen: false)
                    Self.logger.info("Scrolled to item \(currentItem.id), setting active and marking as seen (if new).")
                }
            }
        }
    }
    
    private func selectNextItem() {
        guard let currentActiveID = activeItemID, let currentIndex = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        if currentIndex < items.count - 1 {
            let nextItemID = items[currentIndex + 1].id
            // activeItemID wird durch onChange(of: scrolledItemID) gesetzt
            scrolledItemID = nextItemID
            Self.logger.debug("Keyboard: selectNextItem, scrolling to \(nextItemID)")
        }
    }

    private func selectPreviousItem() {
        guard let currentActiveID = activeItemID, let currentIndex = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        if currentIndex > 0 {
            let previousItemID = items[currentIndex - 1].id
            // activeItemID wird durch onChange(of: scrolledItemID) gesetzt
            scrolledItemID = previousItemID
            Self.logger.debug("Keyboard: selectPreviousItem, scrolling to \(previousItemID)")
        }
    }

    // Die Funktion safeAreaInsetsAndToolbarHeight() wird nicht mehr benötigt,
    // da .containerRelativeFrame(.vertical) dies implizit handhabt.
    // private func safeAreaInsetsAndToolbarHeight() -> CGFloat { ... }


    @MainActor
    func refreshItems() async {
        guard !isLoading else { Self.logger.info("RefreshItems (Unlimited) skipped: isLoading is true."); return }
        Self.logger.info("RefreshItems (Unlimited) Task started.")
        
        guard settings.hasActiveContentFilter else {
            self.items = []; self.errorMessage = nil; self.isLoading = false; self.canLoadMore = false; self.isLoadingMore = false
            Self.logger.info("Refresh (Unlimited) aborted: No active content filter.")
            return
        }
        
        isLoading = true
        errorMessage = nil
        canLoadMore = true
        isLoadingMore = false
        
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                showJunkParameter: settings.apiShowJunk
            )
            let fetchedItemsFromAPI = apiResponse.items
            Self.logger.info("API fetch (Unlimited) completed: \(fetchedItemsFromAPI.count) items received for refresh.")
            
            if Task.isCancelled { Self.logger.info("RefreshItems (Unlimited) Task cancelled after API fetch."); return }

            self.items = fetchedItemsFromAPI
            
            if fetchedItemsFromAPI.isEmpty {
                self.canLoadMore = false
                activeItemID = nil
            } else {
                // Setze das erste Item als `scrolledItemID`, was dann `activeItemID` setzt
                // und das Video startet etc. via .onChange
                scrolledItemID = fetchedItemsFromAPI.first?.id
                
                let atEnd = apiResponse.atEnd ?? false
                let hasOlder = apiResponse.hasOlder ?? true
                self.canLoadMore = !atEnd && hasOlder
            }
        } catch {
            Self.logger.error("API fetch (Unlimited) failed during refresh: \(error.localizedDescription)")
            if Task.isCancelled { Self.logger.info("RefreshItems (Unlimited) Task cancelled after API error."); return }
            self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
            self.canLoadMore = false
            self.items = []
            activeItemID = nil
        }
    }

    @MainActor
    func loadMoreItems() async {
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        
        let olderThanId: Int?
        if settings.feedType == .promoted {
            olderThanId = items.last?.promoted ?? items.last?.id
        } else {
            olderThanId = items.last?.id
        }
        guard let finalOlderThanId = olderThanId else {
            Self.logger.warning("Cannot load more (Unlimited): Could not determine 'older' value.")
            canLoadMore = false
            return
        }
        
        isLoadingMore = true
        Self.logger.info("--- Starting loadMoreItems (Unlimited) older than \(finalOlderThanId) ---")
        defer { Task { @MainActor in self.isLoadingMore = false } }

        do {
            let apiResponse = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted,
                olderThanId: finalOlderThanId,
                showJunkParameter: settings.apiShowJunk
            )
            let newItems = apiResponse.items
            
            if Task.isCancelled { Self.logger.info("LoadMoreItems (Unlimited) Task cancelled after API fetch."); return }
            
            if newItems.isEmpty {
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.items.map { $0.id })
                let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }
                if uniqueNewItems.isEmpty {
                    self.canLoadMore = false
                } else {
                    self.items.append(contentsOf: uniqueNewItems)
                    let atEnd = apiResponse.atEnd ?? false
                    let hasOlder = apiResponse.hasOlder ?? true
                    self.canLoadMore = !atEnd && hasOlder
                }
            }
        } catch {
            Self.logger.error("API fetch (Unlimited) failed during loadMore: \(error.localizedDescription)")
             if Task.isCancelled { Self.logger.info("LoadMoreItems (Unlimited) Task cancelled after API error."); return }
            if self.items.isEmpty {
                self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)"
            }
            self.canLoadMore = false
        }
    }
}

struct UnlimitedFeedItemView: View {
    let item: Item
    @ObservedObject var playerManager: VideoPlayerManager
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let isActive: Bool

    @EnvironmentObject var settings: AppSettings
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedFeedItemView")

    var body: some View {
        ZStack {
            if item.isVideo {
                 if isActive, let player = playerManager.player, playerManager.playerItemID == item.id {
                     CustomVideoPlayerRepresentable(
                         player: player,
                         handler: keyboardActionHandler,
                         onWillBeginFullScreen: { /* TODO */ },
                         onWillEndFullScreen: { /* TODO */ },
                         horizontalSizeClass: nil
                     )
                     .id("video_\(item.id)")
                 } else {
                     KFImage(item.thumbnailUrl)
                         .resizable()
                         .aspectRatio(contentMode: .fill)
                         .overlay(Color.black.opacity(0.3))
                         .overlay(ProgressView().scaleEffect(1.5).tint(.white).opacity(isActive && playerManager.playerItemID != item.id ? 1 : 0))
                 }
            } else {
                KFImage(item.imageUrl)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading) {
                        Text("@\(item.user)")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Tags: (kommen noch)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    Spacer()
                    VStack(spacing: 20) {
                        Button { /* Like Action */ } label: { Image(systemName: "heart.fill").font(.title2).foregroundColor(.white) }
                        Button { /* Comment Action */ } label: { Image(systemName: "message.fill").font(.title2).foregroundColor(.white) }
                        Button { /* Share Action */ } label: { Image(systemName: "arrowshape.turn.up.right.fill").font(.title2).foregroundColor(.white) }
                    }
                    .padding(.leading, 10)
                }
                .padding()
                .background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.5)]), startPoint: .top, endPoint: .bottom))
            }
            .shadow(radius: 3)
        }
        .background(Color.black)
        .clipped()
        .onChange(of: isActive) { oldValue, newValue in
            if newValue && item.isVideo && playerManager.playerItemID == item.id && playerManager.player?.timeControlStatus != .playing {
                 playerManager.player?.play()
                 Self.logger.debug("Player started for active item \(item.id)")
            } else if !newValue && item.isVideo && playerManager.playerItemID == item.id {
                 playerManager.player?.pause()
                 Self.logger.debug("Player paused for inactive item \(item.id)")
            }
        }
    }
}

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navService = NavigationService()
    settings.enableUnlimitedStyleFeed = true
    
    return UnlimitedStyleFeedView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navService)
}
