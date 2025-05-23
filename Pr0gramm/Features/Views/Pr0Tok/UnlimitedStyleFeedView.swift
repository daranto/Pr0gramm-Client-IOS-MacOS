// Pr0gramm/Pr0gramm/Features/Views/UnlimitedStyleFeedView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

// Datenmodell für die Übergabe an UnlimitedFeedItemView
struct UnlimitedFeedItemDataModel {
    let item: Item
    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool
    let comments: [ItemComment]
    let itemInfoStatus: InfoLoadingStatus
}

fileprivate struct UnlimitedVotableTagView: View {
    let tag: ItemTag
    let currentVote: Int
    let isVoting: Bool
    let truncateText: Bool
    let onUpvote: () -> Void
    let onDownvote: () -> Void
    let onTapTag: () -> Void

    @EnvironmentObject var authService: AuthService

    private let characterLimit = 10
    private var displayText: String {
        if truncateText && tag.tag.count > characterLimit {
            return String(tag.tag.prefix(characterLimit)) + "…"
        }
        return tag.tag
    }
    private let tagVoteButtonFont: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            if authService.isLoggedIn {
                Button(action: onDownvote) {
                    Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == -1 ? .red : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }

            Text(displayText)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, authService.isLoggedIn ? 2 : 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
                .onTapGesture(perform: onTapTag)


            if authService.isLoggedIn {
                Button(action: onUpvote) {
                    Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == 1 ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }
        }
        .padding(.horizontal, authService.isLoggedIn ? 6 : 0)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}


struct UnlimitedStyleFeedView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService

    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()

    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showingFilterSheet = false
    @State private var navigationPath = NavigationPath()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedStyleFeedView")
    
    @State private var activeItemID: Int? = nil
    @State private var scrolledItemID: Int? = nil

    @State private var cachedDetails: [Int: ItemsInfoResponse] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    @State private var showAllTagsForItem: Set<Int> = []
    
    @State private var showingTagSearchSheet = false
    @State private var tagForSearchSheet: String? = nil
    
    // --- NEW: State für Add Tag Sheet ---
    @State private var showingAddTagSheet = false
    @State private var newTagTextForSheet = ""
    @State private var addTagErrorForSheet: String? = nil
    @State private var isAddingTagsInSheet: Bool = false
    // --- END NEW ---
    
    private let initialVisibleTagCount = 2

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                feedControls
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
            .sheet(isPresented: $showingTagSearchSheet, onDismiss: { tagForSearchSheet = nil }) {
                if let tag = tagForSearchSheet {
                    NavigationStack {
                        TagSearchView(currentSearchTag: .constant(tag))
                            .environmentObject(settings)
                            .environmentObject(authService)
                            .navigationTitle("Suche: \(tag)")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Schließen") { showingTagSearchSheet = false }
                                }
                            }
                    }
                }
            }
            // --- NEW: Sheet für Add Tags ---
            .sheet(isPresented: $showingAddTagSheet) {
                addTagSheetContent() // Verwendet die neue @ViewBuilder Funktion
            }
            // --- END NEW ---
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
            .onChange(of: settings.apiFlags) { _, _ in Task { await refreshItems() } }
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
                        let itemData = prepareItemDataModel(for: item)
                        
                        UnlimitedFeedItemView(
                            itemData: itemData,
                            playerManager: playerManager,
                            keyboardActionHandler: keyboardActionHandler,
                            isActive: activeItemID == item.id,
                            onToggleShowAllTags: {
                                if showAllTagsForItem.contains(item.id) {
                                    showAllTagsForItem.remove(item.id)
                                } else {
                                    showAllTagsForItem.insert(item.id)
                                }
                            },
                            onUpvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: 1) } },
                            onDownvoteTag: { tagId in Task { await handleTagVoteTap(tagId: tagId, voteType: -1) } },
                            onTagTapped: { tagString in
                                self.tagForSearchSheet = tagString
                                self.showingTagSearchSheet = true
                            },
                            onRetryLoadDetails: {
                                Task { await loadItemDetailsIfNeeded(for: item, forceReload: true) }
                            },
                            // --- NEW: Callback für Add Tag Sheet ---
                            onShowAddTagSheet: {
                                newTagTextForSheet = ""
                                addTagErrorForSheet = nil
                                isAddingTagsInSheet = false
                                showingAddTagSheet = true
                            }
                            // --- END NEW ---
                        )
                        .id(item.id)
                        .containerRelativeFrame(.vertical)
                        .onAppear {
                            if item.id == items.last?.id && canLoadMore && !isLoadingMore {
                                Task { await loadMoreItems() }
                            }
                            if activeItemID == item.id {
                                Task { await loadItemDetailsIfNeeded(for: item) }
                            }
                        }
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.7)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.9)
                        }
                    }
                    if isLoadingMore {
                        ProgressView("Lade mehr...")
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                            .padding()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
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
                    Task { await loadItemDetailsIfNeeded(for: currentItem) }
                    Self.logger.info("Scrolled to item \(currentItem.id), setting active and marking as seen (if new). Details loading initiated.")
                }
            }
        }
    }

    private func prepareItemDataModel(for item: Item) -> UnlimitedFeedItemDataModel {
        let details = cachedDetails[item.id]
        let allItemTags = details?.tags.sorted { $0.confidence > $1.confidence } ?? []
        let shouldShowAll = showAllTagsForItem.contains(item.id)
        let tagsForDisplayLogic = shouldShowAll ? allItemTags : Array(allItemTags.prefix(initialVisibleTagCount))

        let commentsToDisplay = details?.comments ?? []
        let currentInfoStatus = infoLoadingStatus[item.id] ?? .idle

        return UnlimitedFeedItemDataModel(
            item: item,
            displayedTags: tagsForDisplayLogic,
            totalTagCount: allItemTags.count,
            showingAllTags: shouldShowAll,
            comments: commentsToDisplay,
            itemInfoStatus: currentInfoStatus
        )
    }
    
    private func selectNextItem() {
        guard let currentActiveID = activeItemID, let currentIndex = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        if currentIndex < items.count - 1 {
            let nextItemID = items[currentIndex + 1].id
            scrolledItemID = nextItemID
            Self.logger.debug("Keyboard: selectNextItem, scrolling to \(nextItemID)")
        }
    }

    private func selectPreviousItem() {
        guard let currentActiveID = activeItemID, let currentIndex = items.firstIndex(where: { $0.id == currentActiveID }) else { return }
        if currentIndex > 0 {
            let previousItemID = items[currentIndex - 1].id
            scrolledItemID = previousItemID
            Self.logger.debug("Keyboard: selectPreviousItem, scrolling to \(previousItemID)")
        }
    }

    @MainActor
    func refreshItems() async {
        guard !isLoading else { Self.logger.info("RefreshItems (Unlimited) skipped: isLoading is true."); return }
        Self.logger.info("RefreshItems (Unlimited) Task started.")
        
        guard settings.hasActiveContentFilter else {
            self.items = []; self.errorMessage = nil; self.isLoading = false; self.canLoadMore = false; self.isLoadingMore = false; self.cachedDetails = [:]; self.infoLoadingStatus = [:]
            Self.logger.info("Refresh (Unlimited) aborted: No active content filter.")
            return
        }
        
        isLoading = true
        errorMessage = nil
        canLoadMore = true
        isLoadingMore = false
        cachedDetails = [:]
        infoLoadingStatus = [:]
        
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

    private func loadItemDetailsIfNeeded(for item: Item, forceReload: Bool = false) async {
        let itemId = item.id
        if !forceReload && (infoLoadingStatus[itemId] == .loaded || infoLoadingStatus[itemId] == .loading) {
            return
        }
        
        Self.logger.info("Loading details for item \(itemId)... Force reload: \(forceReload)")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }

        do {
            let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            let sortedTags = fetchedInfoResponse.tags.sorted { $0.confidence > $1.confidence }
            let infoWithSortedTagsAndComments = ItemsInfoResponse(tags: sortedTags, comments: fetchedInfoResponse.comments)
            
            await MainActor.run {
                cachedDetails[itemId] = infoWithSortedTagsAndComments
                infoLoadingStatus[itemId] = .loaded
            }
            Self.logger.info("Successfully loaded details for item \(itemId). Tags: \(infoWithSortedTagsAndComments.tags.count), Comments: \(infoWithSortedTagsAndComments.comments.count)")
        } catch {
            Self.logger.error("Failed to load details for item \(itemId): \(error.localizedDescription)")
            await MainActor.run { infoLoadingStatus[itemId] = .error(error.localizedDescription) }
        }
    }

    private func handleTagVoteTap(tagId: Int, voteType: Int) async {
        guard authService.isLoggedIn else { return }
        await authService.performTagVote(tagId: tagId, voteType: voteType)
    }
    
    // --- NEW: Funktion zum Hinzufügen von Tags (ähnlich wie in PagedDetailView) ---
    private func handleAddTagsToActiveItem(tags: String) async -> String? {
        guard let currentActiveItemID = activeItemID else {
            return "Kein aktives Item ausgewählt."
        }
        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            Self.logger.warning("Tags hinzufügen übersprungen: Benutzer nicht eingeloggt oder Nonce fehlt.")
            return "Nicht eingeloggt."
        }

        let sanitizedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTags.isEmpty else {
            return "Bitte Tags eingeben."
        }

        Self.logger.info("Versuche, Tags '\(sanitizedTags)' zu Item \(currentActiveItemID) hinzuzufügen.")

        do {
            try await apiService.addTags(itemId: currentActiveItemID, tags: sanitizedTags, nonce: nonce)
            Self.logger.info("Tags erfolgreich zu Item \(currentActiveItemID) hinzugefügt. Lade Item-Infos neu.")
            
            // Finde das Item in der Liste und lade seine Details neu
            if let itemToReload = items.first(where: { $0.id == currentActiveItemID }) {
                await loadItemDetailsIfNeeded(for: itemToReload, forceReload: true)
            }
            return nil // Erfolg
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            Self.logger.error("Fehler beim Hinzufügen von Tags zu Item \(currentActiveItemID): Authentifizierung erforderlich.")
            await authService.logout()
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        } catch {
            Self.logger.error("Fehler beim Hinzufügen von Tags zu Item \(currentActiveItemID): \(error.localizedDescription)")
            if let nsError = error as NSError?, nsError.domain == "APIService.addTags" {
                return nsError.localizedDescription
            }
            return "Ein unbekannter Fehler ist aufgetreten."
        }
    }

    @ViewBuilder
    private func addTagSheetContent() -> some View {
        NavigationStack {
            VStack(spacing: 15) {
                Text("Neue Tags eingeben (kommasepariert):")
                    .font(UIConstants.headlineFont)
                    .padding(.top)

                TextEditor(text: $newTagTextForSheet)
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color.gray.opacity(0.3))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Neue Tags")
                
                Text("Es kann etwas dauern, bis die neuen Tags angezeigt werden und von anderen Nutzern bewertet werden können.")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                if let error = addTagErrorForSheet {
                    Text("Fehler: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                Spacer()
                if isAddingTagsInSheet {
                    ProgressView("Speichere Tags...")
                        .padding(.bottom)
                }
            }
            .padding()
            .navigationTitle("Tags hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showingAddTagSheet = false }
                        .disabled(isAddingTagsInSheet)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            isAddingTagsInSheet = true
                            addTagErrorForSheet = nil
                            if let errorMsg = await handleAddTagsToActiveItem(tags: newTagTextForSheet) {
                                addTagErrorForSheet = errorMsg
                                Self.logger.error("Fehler beim Hinzufügen von Tags (Sheet): \(errorMsg)")
                            } else {
                                showingAddTagSheet = false
                            }
                            isAddingTagsInSheet = false
                        }
                    }
                    .disabled(newTagTextForSheet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingTagsInSheet)
                }
            }
        }
        .interactiveDismissDisabled(isAddingTagsInSheet)
    }
    // --- END NEW ---
}

struct UnlimitedFeedItemView: View {
    let itemData: UnlimitedFeedItemDataModel
    @ObservedObject var playerManager: VideoPlayerManager
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let isActive: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedFeedItemView")

    let onToggleShowAllTags: () -> Void
    let onUpvoteTag: (Int) -> Void
    let onDownvoteTag: (Int) -> Void
    let onTagTapped: (String) -> Void
    let onRetryLoadDetails: () -> Void
    let onShowAddTagSheet: () -> Void // NEUER CALLBACK

    var item: Item { itemData.item }
    
    @State private var showingCommentsSheet = false
    
    private let initialVisibleTagCountInItemView = 2


    var body: some View {
        ZStack {
            mediaContentLayer
                .zIndex(0)

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("@\(item.user)")
                            .font(.headline).bold()
                            .foregroundColor(.white)
                        
                        tagSection
                    }
                    .padding(.leading)
                    .padding(.bottom, bottomSafeAreaPadding)

                    Spacer()

                    interactionButtons
                        .padding(.trailing)
                        .padding(.bottom, bottomSafeAreaPadding)
                }
                .padding(.bottom, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.6)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .zIndex(1)
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
        .sheet(isPresented: $showingCommentsSheet) {
            ItemCommentsSheetView(
                itemId: itemData.item.id,
                uploaderName: itemData.item.user,
                initialComments: itemData.comments,
                initialInfoStatusProp: itemData.itemInfoStatus,
                onRetryLoadDetails: onRetryLoadDetails
            )
            .environmentObject(settings)
            .environmentObject(authService)
        }
    }
    
    private var bottomSafeAreaPadding: CGFloat {
        UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.safeAreaInsets.bottom ?? 0
    }


    @ViewBuilder
    private var mediaContentLayer: some View {
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
    }
        
    @ViewBuilder
    private var tagSection: some View {
        switch itemData.itemInfoStatus {
        case .loading:
            ProgressView().tint(.white).scaleEffect(0.7)
        case .error(let msg):
            VStack(alignment: .leading) {
                Text("Tags nicht geladen.")
                    .font(.caption)
                    .foregroundColor(.orange)
                Button("Erneut versuchen") {
                    onRetryLoadDetails()
                }
                .font(.caption.bold())
                .foregroundColor(.white)
            }
        case .loaded:
            if !itemData.displayedTags.isEmpty || itemData.showingAllTags { // Auch leere FlowLayout anzeigen, wenn "alle Tags" aktiv ist, um den "+" Button zu sehen
                if itemData.showingAllTags {
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(itemData.displayedTags) { tag in
                            UnlimitedVotableTagView(
                                tag: tag,
                                currentVote: authService.votedTagStates[tag.id] ?? 0,
                                isVoting: authService.isVotingTag[tag.id] ?? false,
                                truncateText: false,
                                onUpvote: { onUpvoteTag(tag.id) },
                                onDownvote: { onDownvoteTag(tag.id) },
                                onTapTag: { onTagTapped(tag.tag) }
                            )
                        }
                        // --- NEW: Add Tag Button im ausgeklappten Zustand ---
                        if authService.isLoggedIn {
                            Button {
                                onShowAddTagSheet()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        // --- END NEW ---
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(itemData.displayedTags) { tag in
                            UnlimitedVotableTagView(
                                tag: tag,
                                currentVote: authService.votedTagStates[tag.id] ?? 0,
                                isVoting: authService.isVotingTag[tag.id] ?? false,
                                truncateText: true,
                                onUpvote: { onUpvoteTag(tag.id) },
                                onDownvote: { onDownvoteTag(tag.id) },
                                onTapTag: { onTagTapped(tag.tag) }
                            )
                        }
                        if itemData.totalTagCount > initialVisibleTagCountInItemView && itemData.displayedTags.count < itemData.totalTagCount {
                            let remainingCount = itemData.totalTagCount - itemData.displayedTags.count
                            Button {
                                onToggleShowAllTags()
                            } label: {
                                Text("+\(remainingCount) mehr")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            } else if itemData.totalTagCount > 0 {
                Text("Keine Tags (Filter?).")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            } else if authService.isLoggedIn { // Keine Tags vorhanden, aber eingeloggt -> "+" Button anbieten
                 Button {
                    onShowAddTagSheet()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.callout) // Etwas größer als Caption
                        .foregroundColor(.white.opacity(0.8))
                        .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        default:
            Text("Lade Tags...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private var interactionButtons: some View {
        VStack(spacing: 25) {
            Button { /* TODO: Like Action */ } label: { Image(systemName: "heart.fill").font(.title).foregroundColor(.white) }
            Button {
                Self.logger.info("Kommentar-Button getippt für Item \(item.id)")
                showingCommentsSheet = true
            } label: {
                Image(systemName: "message.fill").font(.title).foregroundColor(.white)
            }
            Button { /* TODO: Share Action */ } label: { Image(systemName: "arrowshape.turn.up.right.fill").font(.title).foregroundColor(.white) }
        }
    }
}


struct ItemCommentsSheetView: View {
    let itemId: Int
    let uploaderName: String
    let initialComments: [ItemComment]
    let initialInfoStatusProp: InfoLoadingStatus
    let onRetryLoadDetails: () -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    
    @State private var commentsToDisplay: [ItemComment]
    @State private var currentInfoStatus: InfoLoadingStatus

    init(itemId: Int, uploaderName: String, initialComments: [ItemComment], initialInfoStatusProp: InfoLoadingStatus, onRetryLoadDetails: @escaping () -> Void) {
        self.itemId = itemId
        self.uploaderName = uploaderName
        self.initialComments = initialComments
        _commentsToDisplay = State(initialValue: initialComments.sorted(by: { $0.confidence ?? 0 > $1.confidence ?? 0 }))
        self.initialInfoStatusProp = initialInfoStatusProp
        _currentInfoStatus = State(initialValue: initialInfoStatusProp)
        self.onRetryLoadDetails = onRetryLoadDetails
    }


    var body: some View {
        NavigationStack {
            VStack {
                switch currentInfoStatus {
                case .loading:
                    ProgressView("Lade Kommentare...")
                case .error(let msg):
                    Text("Fehler beim Laden der Kommentare: \(msg)")
                    Button("Erneut versuchen") { onRetryLoadDetails() }
                case .loaded:
                    if commentsToDisplay.isEmpty {
                        Text("Keine Kommentare vorhanden.")
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(commentsToDisplay) { comment in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(comment.name ?? "User").bold()
                                        Text("• \(comment.up - comment.down) • \(Date(timeIntervalSince1970: TimeInterval(comment.created)), style: .relative)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(comment.content)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                default:
                    Text("Kommentare werden geladen...")
                }
            }
            .navigationTitle("Kommentare (\(commentsToDisplay.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onChange(of: initialInfoStatusProp) { _, newStatus in
                currentInfoStatus = newStatus
                if newStatus == .loaded {
                    commentsToDisplay = initialComments.sorted(by: { $0.confidence ?? 0 > $1.confidence ?? 0 })
                }
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
