import SwiftUI
import os
import Kingfisher

// MARK: - Search History Components
struct SearchHistoryView: View {
    let searchHistory: [String]
    let onSelectTerm: (String) -> Void
    let onDeleteTerm: (String) -> Void
    let onClearAll: () -> Void
    
    var body: some View {
        if !searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Zuletzt gesucht")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClearAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                            Text("Alle löschen")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                // History Items - Show all entries
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(searchHistory.enumerated()), id: \.element) { index, term in
                        SearchHistoryRow(
                            term: term,
                            onSelect: { onSelectTerm(term) },
                            onDelete: { onDeleteTerm(term) }
                        )
                        
                        if index < searchHistory.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct SearchHistoryRow: View {
    let term: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            
            Text(term)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.red.opacity(isHovered ? 1.0 : 0.8))
                    .clipShape(Circle())
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(isHovered ? .gray.opacity(0.05) : .clear)
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct SystemBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: style)
        return UIVisualEffectView(effect: blurEffect)
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let blurEffect = UIBlurEffect(style: style)
        uiView.effect = blurEffect
    }
}

struct SearchItemThumbnail: View, Equatable {
    let item: Item
    let isSeen: Bool
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchItemThumbnail")

    static func == (lhs: SearchItemThumbnail, rhs: SearchItemThumbnail) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSeen == rhs.isSeen
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.thumbnailUrl)
                .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
                .onFailure { error in SearchItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") }
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

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService
    @Environment(\.dismissSearch) private var dismissSearch

    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    @StateObject private var playerManager = VideoPlayerManager()
    @State private var helpPostPreviewTarget: PreviewLinkTarget? = nil
    @State private var isLoadingHelpPost = false

    private let helpPostId = 2782197

    private let preloadRowsAhead: Int = 5

    @State private var searchText = ""
    @State private var currentSearchTagForAPI: String? = nil
    @State private var hasAttemptedSearchSinceAppear = false

    @State private var searchHistory: [String] = []
    @State private var isSearchActive = true
    @State private var wasPlayingBeforeTabSwitch = false

    @State private var minBenisFilter: Int = 0
    @State private var scrollResetCounter: Int = 0

    private static let searchHistoryKey = "searchHistory_v1"
    private static let maxSearchHistoryCount = 100

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchView")

    private var gridColumns: [GridItem] {
        let isMac = ProcessInfo.processInfo.isiOSAppOnMac
        let currentHorizontalSizeClass: UserInterfaceSizeClass? = isMac ? .regular : .compact
        let numberOfColumns = settings.gridSize.columns(for: currentHorizontalSizeClass, isMac: isMac)
        let minItemWidth: CGFloat = isMac ? 150 : (numberOfColumns <= 3 ? 100 : 80)
        return Array(repeating: GridItem(.adaptive(minimum: minItemWidth), spacing: 3), count: numberOfColumns)
    }

    private var apiFlagsForSearch: Int {
        let loggedIn = authService.isLoggedIn
        if !loggedIn { return 1 }

        var flags = 0
        if settings.showSFW { flags |= 1; flags |= 8 }
        if settings.showNSFW { flags |= 2 }
        if settings.showNSFL { flags |= 4 }
        if settings.showPOL { flags |= 16 }
        return flags == 0 ? 1 : flags
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            searchContentView
                .safeAreaInset(edge: .bottom) {
                    // Create invisible spacer that matches tab bar height
                    Color.clear
                        .frame(height: calculateTabBarHeight())
                }
                .navigationDestination(for: Item.self) { destinationItem in
                    if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                        PagedDetailView(
                            items: $items,
                            selectedIndex: index,
                            playerManager: playerManager,
                            loadMoreAction: { Task { await loadMoreSearch() } }
                        )
                        .environmentObject(settings)
                        .environmentObject(authService)
                    } else {
                        Text("Fehler: Item nicht in Suchergebnissen gefunden.")
                            .onAppear { SearchView.logger.warning("Navigation destination item \(destinationItem.id) not found in search results.") }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await loadAndShowHelpPost() }
                        } label: {
                            if isLoadingHelpPost {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "questionmark.circle")
                            }
                        }
                        .disabled(isLoadingHelpPost)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingFilterSheet = true } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .navigationTitle("Suche")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tags suchen…")
                .onChange(of: searchText) { _, newValue in  // ✅ Aktualisiert
                    // Wenn der Benutzer anfängt zu tippen, Verlauf wieder anzeigen
                    if !isSearchActive {
                        isSearchActive = true
                    }
                    // Wenn das Suchfeld geleert wird, alles zurücksetzen (inkl. Benis-Filter)
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        currentSearchTagForAPI = nil
                        minBenisFilter = 0
                        items = []
                        errorMessage = nil
                        canLoadMore = false
                        isLoadingMore = false
                        isLoading = false
                        hasAttemptedSearchSinceAppear = false
                    }
                }
                .onSubmit(of: .search) {
                    SearchView.logger.info("Search submitted with: \(searchText)")
                    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    isSearchActive = false
                    
                    if !trimmed.isEmpty { addTermToSearchHistory(trimmed) }
                    dismissSearch()
                    #if os(iOS)
                    dismissKeyboard()
                    #endif
                    Task { await performSearchLogic(isInitialSearch: true) }
                }
                .searchSuggestions {
                    if isSearchActive {
                        SearchHistoryView(
                            searchHistory: searchHistory,
                            onSelectTerm: { term in
                                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task.detached {
                                    await MainActor.run {
                                        searchText = trimmed
                                        isSearchActive = false
                                        addTermToSearchHistory(trimmed)
                                        dismissSearch()
                                        dismissKeyboard()
                                    }
                                    try? await Task.sleep(nanoseconds: 150_000_000)
                                    await performSearchLogic(isInitialSearch: true)
                                }
                            },
                            onDeleteTerm: { term in
                                deleteTermFromSearchHistory(term)
                            },
                            onClearAll: {
                                clearSearchHistory()
                            }
                        )
                    }
                }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .sheet(item: $helpPostPreviewTarget) { targetWrapper in
            LinkedItemPreviewWrapperView(itemID: targetWrapper.itemID, targetCommentID: targetWrapper.commentID)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .onAppear {
            loadSearchHistory()
            playerManager.configure(settings: settings)
            hasAttemptedSearchSinceAppear = false
            isSearchActive = true
        }
        .onChange(of: settings.showSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFW) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showNSFL) { _, _ in handleApiFlagsChange() }
        .onChange(of: settings.showPOL) { _, _ in handleApiFlagsChange() }
        .task(id: navigationService.selectedTab) {
            let newTab = navigationService.selectedTab
            if newTab == .search {
                if wasPlayingBeforeTabSwitch {
                    // Small delay to ensure Search is fully active
                    try? await Task.sleep(for: .milliseconds(150))
                    if playerManager.player?.timeControlStatus != .playing {
                        playerManager.player?.play()
                        SearchView.logger.info("Resumed player after returning to Search tab.")
                    }
                    wasPlayingBeforeTabSwitch = false
                }
            } else {
                if let player = playerManager.player, player.timeControlStatus == .playing {
                    player.pause()
                    wasPlayingBeforeTabSwitch = true
                    SearchView.logger.info("Paused player because user switched away from Search tab.")
                } else {
                    // Keep previous intent to resume; do NOT reset the flag here when hopping between other tabs
                    SearchView.logger.debug("Search not active and player not playing; preserving wasPlayingBeforeTabSwitch=\(wasPlayingBeforeTabSwitch).")
                }
            }
        }
    }

    private func handleApiFlagsChange() {
        SearchView.logger.info("SearchView: Relevant global filter flag changed. Not auto-triggering search (awaiting explicit submit).")
    }
    
    /// Sanitizes search terms by escaping special characters that could cause API errors
    private func sanitizeSearchTerm(_ term: String) -> String {
        // The pr0gramm API uses certain characters as special search operators:
        // "!" = search operator prefix
        // ":" = used for special filters (e.g., "s:1000" for benis filter)
        // "|" = OR operator
        
        // If the term contains special characters, wrap it in quotes to search literally
        // This tells the API to treat these characters as part of the search term, not operators
        let specialCharacters = CharacterSet(charactersIn: "!:|")
        
        if term.rangeOfCharacter(from: specialCharacters) != nil {
            // Wrap in quotes and escape any existing quotes
            let escapedTerm = term.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escapedTerm)\""
        }
        
        return term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadAndShowHelpPost() async {
        guard !isLoadingHelpPost else { return }
        isLoadingHelpPost = true
        errorMessage = nil
        SearchView.logger.info("Loading help post with ID: \(helpPostId)")
        do {
            let item = try await apiService.fetchItem(id: helpPostId, flags: 1)
            if let fetchedItem = item {
                helpPostPreviewTarget = PreviewLinkTarget(itemID: fetchedItem.id, commentID: nil)
            } else {
                errorMessage = "Suchhilfe konnte nicht geladen werden."
                SearchView.logger.warning("Could not fetch help post \(helpPostId). API returned nil.")
            }
        } catch {
            errorMessage = "Fehler beim Laden der Suchhilfe: \(error.localizedDescription)"
            SearchView.logger.error("Failed to fetch help post \(helpPostId): \(error.localizedDescription)")
        }
        isLoadingHelpPost = false
    }

    @ViewBuilder
    private var searchContentView: some View {
        ZStack(alignment: .top) {
            scrollViewContent
        }
    }

    @ViewBuilder
    private var benisFilterSlider: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 12) {
                Text("Benis:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(
                    value: Binding(
                        get: { Double(minBenisFilter) },
                        set: { minBenisFilter = Int($0.rounded()) }
                    ),
                    in: 0...5000,
                    step: 100,
                    onEditingChanged: { editing in
                        if !editing {
                            Task { await performSearchLogic(isInitialSearch: true) }
                        }
                    }
                ) {
                    Text("Benis Filter")
                }
                .accentColor(.accentColor)
                
                Text("\(minBenisFilter)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 40, alignment: .trailing)
                
                if minBenisFilter > 0 {
                    Button {
                        minBenisFilter = 0
                        Task { await performSearchLogic(isInitialSearch: true) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary, .quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            HStack(spacing: 12) {
                Text("Benis:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(
                    value: Binding(
                        get: { Double(minBenisFilter) },
                        set: { minBenisFilter = Int($0.rounded()) }
                    ),
                    in: 0...5000,
                    step: 100,
                    onEditingChanged: { editing in
                        if !editing {
                            Task { await performSearchLogic(isInitialSearch: true) }
                        }
                    }
                ) {
                    Text("Benis Filter")
                }
                .accentColor(.accentColor)
                
                Text("\(minBenisFilter)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 40, alignment: .trailing)
                
                if minBenisFilter > 0 {
                    Button {
                        minBenisFilter = 0
                        Task { await performSearchLogic(isInitialSearch: true) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary, .quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var searchEmptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("Suche nach Tags oder verwende den Benis-Filter")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollViewContent: some View {
        ScrollView {
            LazyVStack(pinnedViews: [.sectionHeaders]) {
                Section {
                    if isLoading && items.isEmpty {
                        ProgressView("Suche läuft…")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else if let error = errorMessage, items.isEmpty {
                        VStack {
                            Text("Fehler: \(error)").foregroundColor(.red)
                            Button("Erneut versuchen") { Task { await performSearchLogic(isInitialSearch: true) } }
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else if items.isEmpty && !isLoading && (currentSearchTagForAPI?.isEmpty ?? true) && !hasAttemptedSearchSinceAppear {
                        searchEmptyStateView
                    } else if items.isEmpty && !isLoading && errorMessage == nil {
                        ContentUnavailableView {
                            Label("Keine Ergebnisse", systemImage: "magnifyingglass")
                        } description: {
                            Text("Keine Posts für den Suchbegriff gefunden.")
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 3) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: item) {
                                    SearchItemThumbnail(
                                        item: item,
                                        isSeen: settings.seenItemIDs.contains(item.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if gridColumns.count > 0, index % gridColumns.count == 0 {
                                        let nextPrefetchCount = gridColumns.count * 2
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

                                    let offset = max(1, gridColumns.count) * preloadRowsAhead
                                    let thresholdIndex = max(0, items.count - offset)
                                    if index >= thresholdIndex && canLoadMore && !isLoadingMore && !isLoading {
                                        Task { await loadMoreSearch() }
                                    }
                                }
                            }
                            if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                                Color.clear.frame(height: 1)
                                    .onAppear {
                                        Task { await loadMoreSearch() }
                                    }
                            }
                            if isLoadingMore { ProgressView("Lade mehr...").padding().gridCellColumns(gridColumns.count) }
                        }
                        .padding(.horizontal, 5)
                        .padding(.bottom)
                    }
                } header: {
                    benisFilterSlider
                }
            }
        }
        .id(scrollResetCounter)
    }

    @MainActor
    private func performSearchLogic(isInitialSearch: Bool) async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow search if we have a search term OR a benis filter is set
        let hasBenisFilter = minBenisFilter > 0
        let hasSearchTerm = !trimmedSearchText.isEmpty || (currentSearchTagForAPI != nil && !currentSearchTagForAPI!.isEmpty)
        
        if !hasSearchTerm && !hasBenisFilter {
            // Reset to initial state: show the hint "Suche nach Tags oder verwende den Benis-Filter"
            currentSearchTagForAPI = nil
            items = []
            errorMessage = nil
            canLoadMore = false
            isLoadingMore = false
            isLoading = false
            hasAttemptedSearchSinceAppear = false
            return
        }

        currentSearchTagForAPI = trimmedSearchText.isEmpty ? nil : trimmedSearchText
        SearchView.logger.info("performSearchLogic: isInitial=\(isInitialSearch). API Tag: '\(currentSearchTagForAPI ?? "nil")', Benis: \(minBenisFilter)")
        if isInitialSearch { scrollResetCounter += 1 }
        await refreshSearch()
        hasAttemptedSearchSinceAppear = true
    }

    @MainActor
    private func refreshSearch() async {
        SearchView.logger.info("Refreshing search…")
        guard !isLoading else { return }

        let currentApiFlags = apiFlagsForSearch
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBenisFilter = minBenisFilter > 0
        
        // Build the complete tags string including benis filter
        var finalTags: String? = nil
        var tagComponents: [String] = []
        
        if let searchTerm = effectiveSearchTerm, !searchTerm.isEmpty {
            // Sanitize the search term to remove special characters that cause API errors
            let sanitized = sanitizeSearchTerm(searchTerm)
            if !sanitized.isEmpty {
                tagComponents.append(sanitized)
            }
        }
        
        if hasBenisFilter {
            tagComponents.append("s:\(minBenisFilter)")
        }
        
        if !tagComponents.isEmpty {
            // Join search terms with spaces (no ! prefix for normal search)
            finalTags = tagComponents.joined(separator: " ")
        }
        
        // Allow search if we have content filters, search term, or benis filter
        if currentApiFlags == 0 && (finalTags == nil || finalTags!.isEmpty) {
            SearchView.logger.warning("Refresh search blocked: No active content filter and no tags (including benis filter).")
            self.items = []
            self.errorMessage = nil
            self.isLoading = false
            self.canLoadMore = false
            self.isLoadingMore = false
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        self.canLoadMore = true
        self.isLoadingMore = false

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let apiResponse = try await apiService.fetchItems(
                flags: currentApiFlags,
                promoted: nil,
                tags: finalTags,
                showJunkParameter: false
            )
            let fetchedItems = apiResponse.items
            self.items = fetchedItems

            if fetchedItems.isEmpty {
                self.canLoadMore = false
            } else {
                let atEnd = apiResponse.atEnd ?? false
                let hasOlder = apiResponse.hasOlder ?? true
                self.canLoadMore = !(atEnd || !hasOlder)
            }
            self.errorMessage = nil
            SearchView.logger.info("Search updated with tags: '\(finalTags ?? "nil")'. Total: \(self.items.count). Can load more: \(self.canLoadMore)")
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            SearchView.logger.error("API fetch failed: Authentication required.")
            self.items = []
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { SearchView.logger.info("API call cancelled.") }
        catch {
            SearchView.logger.error("API fetch failed: \(error.localizedDescription)")
            if self.items.isEmpty { self.errorMessage = "Fehler: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }

    @MainActor
    private func loadMoreSearch() async {
        let currentApiFlags = apiFlagsForSearch
        let effectiveSearchTerm = currentSearchTagForAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBenisFilter = minBenisFilter > 0
        
        // Build the complete tags string including benis filter
        var finalTags: String? = nil
        var tagComponents: [String] = []
        
        if let searchTerm = effectiveSearchTerm, !searchTerm.isEmpty {
            // Sanitize the search term to remove special characters that cause API errors
            let sanitized = sanitizeSearchTerm(searchTerm)
            if !sanitized.isEmpty {
                tagComponents.append(sanitized)
            }
        }
        
        if hasBenisFilter {
            tagComponents.append("s:\(minBenisFilter)")
        }
        
        if !tagComponents.isEmpty {
            // Join search terms with spaces (no ! prefix for normal search)
            finalTags = tagComponents.joined(separator: " ")
        }
        
        if currentApiFlags == 0 && (finalTags == nil || finalTags!.isEmpty) {
            SearchView.logger.warning("Skipping loadMore: No active filter and no tags (including benis filter).")
            self.canLoadMore = false
            return
        }

        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let lastItemId = items.last?.id else { return }

        SearchView.logger.info("--- Starting loadMoreSearch older than \(lastItemId) with tags: '\(finalTags ?? "nil")' ---")
        self.isLoadingMore = true
        defer { Task { @MainActor in self.isLoadingMore = false } }

        do {
            let apiResponse = try await apiService.fetchItems(
                flags: currentApiFlags,
                promoted: nil,
                tags: finalTags,
                olderThanId: lastItemId,
                showJunkParameter: false
            )
            let newItems = apiResponse.items
            SearchView.logger.info("Loaded \(newItems.count) more search items from API.")

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
                    self.canLoadMore = !(atEnd || !hasOlder)
                }
            }
        }
        catch let error as URLError where error.code == .userAuthenticationRequired {
            SearchView.logger.error("API fetch failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        }
        catch is CancellationError { SearchView.logger.info("Load more cancelled.") }
        catch {
            SearchView.logger.error("API fetch failed: \(error.localizedDescription)")
            if items.isEmpty { errorMessage = "Fehler: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }

#if os(iOS)
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
#endif

    private func loadSearchHistory() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.searchHistoryKey) ?? []
        self.searchHistory = saved
        SearchView.logger.info("Loaded search history: \(saved.count) items")
    }

    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: Self.searchHistoryKey)
    }

    private func addTermToSearchHistory(_ term: String) {
        var updated = searchHistory
        updated.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        updated.insert(term, at: 0)
        if updated.count > Self.maxSearchHistoryCount {
            updated = Array(updated.prefix(Self.maxSearchHistoryCount))
        }
        searchHistory = updated
        saveSearchHistory()
        SearchView.logger.info("Added term to search history: '\(term)'. Count: \(searchHistory.count)")
    }
    
    private func deleteTermFromSearchHistory(_ term: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        saveSearchHistory()
        SearchView.logger.info("Deleted term from search history: '\(term)'. Count: \(searchHistory.count)")
    }

    private func clearSearchHistory() {
        searchHistory = []
        saveSearchHistory()
        SearchView.logger.info("Cleared search history.")
    }
    
    // Calculate tab bar height to match MainView
    private func calculateTabBarHeight() -> CGFloat {
        let verticalPadding: CGFloat = 32 // 16 top + 16 bottom
        let buttonHeight: CGFloat = 40
        let bottomMargin: CGFloat = UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8
        return verticalPadding + buttonHeight + bottomMargin
    }
}

