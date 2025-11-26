// Pr0gramm/Pr0gramm/Features/Views/Inbox/InboxView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

struct ItemNavigationValue: Hashable, Identifiable {
    let item: Item
    let targetCommentID: Int?
    var id: Int { item.id }
}

struct ConversationNavigationValue: Hashable, Identifiable {
    let conversationPartnerName: String
    var id: String { conversationPartnerName }
}

struct ProfileNavigationValue: Hashable, Identifiable {
    let username: String
    var id: String { username }
}


enum InboxViewMessageType: Int, CaseIterable, Identifiable {
    case comments = 1
    case stelzes = 4
    case notifications = 2
    case privateMessages = 3


    var id: Int { self.rawValue }

    var baseDisplayName: String {
        switch self {
        case .comments: return "Kommentare"
        case .stelzes: return "Stelzes"
        case .notifications: return "System"
        case .privateMessages: return "Privat"
        }
    }
    
    @MainActor
    func displayNameForPicker(authService: AuthService) -> String {
        let count = self.unreadCount(from: authService)
        if count > 0 {
            return "\(baseDisplayName) (\(count))"
        }
        return baseDisplayName
    }
    
    var apiTypeStringForFilter: String? {
        switch self {
        case .comments: return "comment"
        case .stelzes: return "follow"
        case .notifications: return "notification"
        case .privateMessages: return nil
        }
    }
    
    @MainActor
    func unreadCount(from authService: AuthService) -> Int {
        switch self {
        case .comments:
            return authService.unreadCommentCount
        case .stelzes:
            return authService.unreadFollowCount
        case .notifications:
            return authService.unreadSystemNotificationCount
        case .privateMessages:
            return authService.unreadPrivateMessageCount
        }
    }
}


struct InboxView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService
    
    @State var messages: [InboxMessage] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    @State private var targetCommentIDForNavigation: Int? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetId: Int? = nil

    @State private var previewLinkTargetFromMessage: PreviewLinkTarget? = nil

    @StateObject private var playerManager = VideoPlayerManager()

    @State private var selectedMessageType: InboxViewMessageType = .comments
    
    @State private var conversations: [InboxConversation] = []
    @State private var isLoadingConversations = false
    @State private var conversationsError: String? = nil


    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "InboxView")
    
    @State private var itemNavigationValue: ItemNavigationValue? = nil
    @State private var conversationNavigationValue: ConversationNavigationValue? = nil
    @State private var profileNavigationValue: ProfileNavigationValue? = nil

    @State private var currentRefreshTask: Task<Void, Never>? = nil
    @State private var currentLoadMoreTask: Task<Void, Never>? = nil


    init(
        initialMessagesForPreview: [InboxMessage]? = nil,
        initialConversationsForPreview: [InboxConversation]? = nil
    ) {
        if let messages = initialMessagesForPreview {
            _messages = State(initialValue: messages)
        }
        if let conversations = initialConversationsForPreview {
            _conversations = State(initialValue: conversations)
        }
    }


    var body: some View {
        NavigationStack {
            inboxContent
            .navigationDestination(item: $itemNavigationValue) { navValue in
                 PagedDetailViewWrapperForItem(
                     item: navValue.item,
                     playerManager: playerManager,
                     targetCommentID: navValue.targetCommentID
                 )
                 .environmentObject(settings)
                 .environmentObject(authService)
            }
            .navigationDestination(item: $profileNavigationValue) { navValue in
                 UserProfileSheetView(username: navValue.username)
                      .environmentObject(settings)
                      .environmentObject(authService)
                      .environmentObject(playerManager)
            }
            .navigationDestination(item: $conversationNavigationValue) { navValue in
                ConversationDetailView(partnerUsername: navValue.conversationPartnerName)
                    .environmentObject(settings)
                    .environmentObject(authService)
                    .environmentObject(playerManager)
            }
            .sheet(item: $previewLinkTargetFromMessage) { target in
                NavigationStack {
                    LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                        .navigationTitle("Vorschau")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") {
                                    previewLinkTargetFromMessage = nil
                                }
                            }
                        }
                }
                .environmentObject(settings)
                .environmentObject(authService)
            }
            .overlay {
                if isLoadingNavigationTarget {
                    ProgressView("Lade Post \(navigationTargetId ?? 0)...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
            .onDisappear {
                currentRefreshTask?.cancel()
                currentLoadMoreTask?.cancel()
                InboxView.logger.debug("InboxView disappeared. Cancelled ongoing refresh/loadMore tasks.")
            }
        }
    }
    
    var inboxContent: some View {
        VStack(spacing: 0) {
            Picker("Nachrichten Typ", selection: $selectedMessageType) {
                ForEach(InboxViewMessageType.allCases) { type in
                    Text(type.displayNameForPicker(authService: authService))
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            contentView
        }
        .safeAreaInset(edge: .bottom) {
            // Create invisible spacer that matches tab bar height
            Color.clear
                .frame(height: 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8))
        }
        .navigationTitle("Nachrichten")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
            .alert("Fehler", isPresented: .constant(alertErrorMessage != nil && !isLoading && !isLoadingConversations && !isCancellationError(alertErrorMessage))) {
                Button("OK") { clearErrors() }
            } message: { Text(alertErrorMessage ?? "Unbekannter Fehler") }
            .task {
                playerManager.configure(settings: settings)
            }
            .onChange(of: selectedMessageType) { oldType, newType in
                InboxView.logger.info("Selected message type changed to: \(newType.baseDisplayName)")
                currentRefreshTask?.cancel()
                currentLoadMoreTask?.cancel()
                Task {
                    itemNavigationValue = nil
                    conversationNavigationValue = nil
                    profileNavigationValue = nil
                    
                    messages = [] // Clear previous messages
                    conversations = [] // Clear previous conversations
                    await refreshCurrentTabData()
                    // --- MODIFIED: Zähler nach Typ-Wechsel aktualisieren ---
                    await updateCountsAfterViewingType(newType)
                    // --- END MODIFICATION ---
                }
            }
            .task(id: authService.isLoggedIn) { // Wird bei Login-Status-Änderung und beim Erscheinen getriggert
                 InboxView.logger.info("InboxView .task(id: authService.isLoggedIn) triggered. isLoggedIn: \(authService.isLoggedIn)")
                 currentRefreshTask?.cancel()
                 currentLoadMoreTask?.cancel()
                 await refreshCurrentTabData()
                 
                 if authService.isLoggedIn && navigationService.selectedTab == .inbox {
                     // --- MODIFIED: Zähler nach initialem Laden des aktuellen Typs aktualisieren ---
                     await updateCountsAfterViewingType(selectedMessageType)
                     // --- END MODIFICATION ---
                 } else if !authService.isLoggedIn {
                     await BackgroundNotificationManager.shared.appDidBecomeActiveOrInboxViewed(currentTotalUnread: 0)
                 }
            }
            .onChange(of: navigationService.selectedTab) { oldTab, newTab in
                if newTab == .inbox {
                    InboxView.logger.info("InboxView became active tab.")
                    // --- MODIFIED: Zähler beim Aktivwerden des Tabs aktualisieren ---
                    Task {
                        // Kurze Verzögerung, um sicherzustellen, dass die Daten für den aktuellen Typ geladen sind,
                        // bevor die Zähler aktualisiert werden.
                        try? await Task.sleep(for: .milliseconds(300))
                        await updateCountsAfterViewingType(selectedMessageType)
                    }
                    // --- END MODIFICATION ---
                }
            }
    }
        
    private func isCancellationError(_ message: String?) -> Bool {
        return message?.lowercased().contains("cancelled") == true
    }
    
    // --- NEW: Helper zum Aktualisieren der Zähler nach dem Anzeigen eines Typs ---
    private func updateCountsAfterViewingType(_ viewedType: InboxViewMessageType) async {
        InboxView.logger.info("Updating counts after viewing type: \(viewedType.baseDisplayName)")
        // Der Server markiert beim Abrufen als gelesen. Ein erneuter fetchUnreadCounts holt den neuesten Stand.
        await authService.fetchUnreadCounts()
        // Den BackgroundManager informieren, damit der Badge und der interne Zähler korrekt sind.
        await BackgroundNotificationManager.shared.appDidBecomeActiveOrInboxViewed(currentTotalUnread: authService.unreadInboxTotal)
        InboxView.logger.info("Finished updating counts. Total unread: \(authService.unreadInboxTotal)")
    }
    // --- END NEW ---

    private func refreshCurrentTabData() async {
        currentRefreshTask?.cancel()
        currentLoadMoreTask?.cancel()

        if authService.isLoggedIn {
            // `fetchUnreadCounts` wird jetzt in `updateCountsAfterViewingType` aufgerufen,
            // nachdem die spezifischen Daten geladen wurden.
            // await authService.fetchUnreadCounts() // Entfernt von hier

            if selectedMessageType == .privateMessages {
                currentRefreshTask = Task {
                    await refreshConversations()
                    // --- NEW: Zähler nach Laden der Konversationen aktualisieren ---
                    if Task.isCancelled { return } // Frühzeitiger Abbruch prüfen
                    await updateCountsAfterViewingType(.privateMessages) // Oder allgemein den aktuellen Typ
                    // --- END NEW ---
                }
            } else {
                currentRefreshTask = Task {
                    await refreshMessages(forType: selectedMessageType)
                    // --- NEW: Zähler nach Laden der Nachrichten aktualisieren ---
                    if Task.isCancelled { return } // Frühzeitiger Abbruch prüfen
                    await updateCountsAfterViewingType(selectedMessageType)
                    // --- END NEW ---
                }
            }
        } else {
            messages = []
            conversations = []
            errorMessage = "Bitte anmelden."
            conversationsError = nil
            canLoadMore = true
        }
    }
    
    private var alertErrorMessage: String? {
        if selectedMessageType == .privateMessages {
            return conversationsError
        }
        return errorMessage
    }

    private func clearErrors() {
        errorMessage = nil
        conversationsError = nil
        isLoadingNavigationTarget = false
        navigationTargetId = nil
    }


    @ViewBuilder private var contentView: some View {
        switch selectedMessageType {
        case .privateMessages:
            ConversationsListView(
                conversations: $conversations,
                isLoading: $isLoadingConversations,
                errorMessage: $conversationsError,
                onRefresh: {
                    currentRefreshTask?.cancel()
                    currentLoadMoreTask?.cancel()
                    currentRefreshTask = Task {
                        await refreshConversations()
                        if Task.isCancelled { return }
                        await updateCountsAfterViewingType(.privateMessages)
                    }
                },
                onSelectConversation: { username in
                    self.conversationNavigationValue = ConversationNavigationValue(conversationPartnerName: username)
                }
            )
        case .comments, .notifications, .stelzes:
            buildGeneralMessagesList()
        }
    }

    @ViewBuilder
    private func buildGeneralMessagesList() -> some View {
        if isLoading && messages.isEmpty {
            ProgressView("Lade Nachrichten...").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, messages.isEmpty, !isCancellationError(error) {
             ContentUnavailableView {
                 Label("Fehler", systemImage: "exclamationmark.triangle")
             } description: {
                 Text(error)
             } actions: {
                 Button("Erneut versuchen") {
                     currentRefreshTask?.cancel()
                     currentLoadMoreTask?.cancel()
                     currentRefreshTask = Task {
                         await refreshMessages(forType: selectedMessageType)
                         if Task.isCancelled { return }
                         await updateCountsAfterViewingType(selectedMessageType)
                     }
                }
             }
             .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if messages.isEmpty && !isLoading && !isLoadingMore && errorMessage == nil {
                     Section {
                         Text(emptyListMessage())
                             .foregroundColor(.secondary)
                             .padding()
                             .multilineTextAlignment(.center)
                             .frame(maxWidth: .infinity, alignment: .center)
                             .listRowSeparator(.hidden)
                     }
                } else {
                    ForEach(messages) { message in
                        InboxMessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isLoadingNavigationTarget else {
                                    InboxView.logger.debug("Tap ignored for message \(message.id): isLoadingNavigationTarget=\(isLoadingNavigationTarget)")
                                    return
                                }
                                Task { await handleMessageTap(message) }
                            }
                        .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                        .id(message.id)
                        .onAppear {
                            if !messages.isEmpty && message.id == messages.last?.id && canLoadMore && !isLoadingMore {
                                 InboxView.logger.info("End trigger (last item) appeared for message ID: \(message.id).")
                                 currentLoadMoreTask?.cancel()
                                 currentLoadMoreTask = Task { await loadMoreMessages(forType: selectedMessageType) }
                            } else if messages.count > 5 && messages.count < 100 && messages.firstIndex(where: {$0.id == message.id}) == (messages.count - 5) && canLoadMore && !isLoadingMore {
                                 InboxView.logger.info("End trigger (near end) appeared for message ID: \(message.id).")
                                 currentLoadMoreTask?.cancel()
                                 currentLoadMoreTask = Task { await loadMoreMessages(forType: selectedMessageType) }
                            }
                        }
                    }
                }

                if isLoadingMore {
                    HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                        .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .refreshable { // Pull-to-Refresh
                currentRefreshTask?.cancel()
                currentLoadMoreTask?.cancel()
                currentRefreshTask = Task {
                    await refreshMessages(forType: selectedMessageType)
                    if Task.isCancelled { return }
                    await updateCountsAfterViewingType(selectedMessageType)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                if let (itemID, commentID) = parsePr0grammLink(url: url) {
                    InboxView.logger.info("Pr0gramm link tapped in inbox message, attempting to preview item ID: \(itemID), commentID: \(commentID ?? -1)")
                    self.previewLinkTargetFromMessage = PreviewLinkTarget(itemID: itemID, commentID: commentID)
                    return .handled
                } else {
                    InboxView.logger.info("Non-pr0gramm link tapped in inbox: \(url). Opening in system browser.")
                    return .systemAction
                }
            })
        }
    }
        
    private func emptyListMessage() -> String {
        let tabName = selectedMessageType.baseDisplayName
        switch selectedMessageType {
        case .stelzes:
            return "\(authService.currentUser?.name ?? "Du") folgst niemandem oder die Posts der gefolgten User entsprechen nicht den Filtern."
        default:
            return "Keine \(tabName.lowercased()) vorhanden."
        }
    }
    
    private func parsePr0grammLink(url: URL) -> (itemID: Int, commentID: Int?)? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }

        let path = url.path
        let components = path.components(separatedBy: "/")
        var itemID: Int? = nil
        var commentID: Int? = nil

        if let lastPathComponent = components.last {
            if lastPathComponent.contains(":comment") {
                let parts = lastPathComponent.split(separator: ":")
                if parts.count == 2, let idPart = Int(parts[0]), parts[1].starts(with: "comment"), let cID = Int(parts[1].dropFirst("comment".count)) {
                    itemID = idPart
                    commentID = cID
                }
            } else {
                var potentialItemIDIndex: Int? = nil
                if let idx = components.lastIndex(where: { $0 == "new" || $0 == "top" }), idx + 1 < components.count {
                    potentialItemIDIndex = idx + 1
                } else if components.count > 1 && Int(components.last!) != nil {
                    potentialItemIDIndex = components.count - 1
                }
                
                if let idx = potentialItemIDIndex, let id = Int(components[idx]) {
                    itemID = id
                }
            }
        }
        
        if itemID == nil, let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let id = Int(value) {
                    itemID = id
                    break
                }
            }
        }
        
        if let itemID = itemID {
            return (itemID, commentID)
        }

        InboxView.logger.warning("Could not parse item or comment ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }

    @MainActor
    private func handleMessageTap(_ message: InboxMessage) async {
        guard !isLoadingNavigationTarget else {
            InboxView.logger.debug("handleMessageTap skipped for \(message.id): Already loading target.")
            return
        }
        clearErrors()
        InboxView.logger.info("Handling tap for message ID: \(message.id), Type: \(message.type ?? "nil"), ItemID: \(message.itemId ?? -1)")

        if message.type == "comment", let itemId = message.itemId {
            InboxView.logger.info("Comment message tapped, preparing navigation for item \(itemId), target comment ID: \(message.id)")
            await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
        } else if message.type == "follow" || message.type == "follows", let itemId = message.itemId {
            InboxView.logger.info("Follow message (with item, type: \(message.type ?? "")) tapped, preparing navigation for item \(itemId). User: \(message.name ?? "Unbekannt")")
            await prepareAndNavigateToItem(itemId, targetCommentID: nil)
        } else if message.type == "follow" || message.type == "follows" {
             if let senderName = message.name, !senderName.isEmpty {
                InboxView.logger.info("Follow message (no item, fallback to profile, type: \(message.type ?? "")) tapped, setting profileNavigationValue: \(senderName)")
                self.profileNavigationValue = ProfileNavigationValue(username: senderName)
            } else {
                 InboxView.logger.warning("Follow message (type: \(message.type ?? "")) tapped but no itemId and no senderName for profile navigation.")
            }
        } else if message.type == "notification" {
             InboxView.logger.debug("Tapped on a 'notification' type message. No specific navigation action defined.")
        } else {
            InboxView.logger.warning("Tapped on message with unhandled type '\(message.type ?? "nil")' or missing itemId. ItemId: \(message.itemId ?? -1)")
        }
    }

    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?, targetCommentID: Int? = nil) async {
        guard let id = itemId else {
            InboxView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !self.isLoadingNavigationTarget else {
            InboxView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        InboxView.logger.info("Preparing navigation for item ID: \(id), targetCommentID: \(targetCommentID ?? -1)")
        self.isLoadingNavigationTarget = true
        self.navigationTargetId = id
        self.errorMessage = nil
        self.targetCommentIDForNavigation = targetCommentID

        do {
            let flagsToFetchWith = 31
            InboxView.logger.debug("Fetching item \(id) for navigation using flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard self.navigationTargetId == id else {
                 InboxView.logger.info("Navigation target changed while item \(id) was loading (current target: \(String(describing: self.navigationTargetId))). Discarding result.")
                 self.isLoadingNavigationTarget = false; self.navigationTargetId = nil; self.targetCommentIDForNavigation = nil; return
            }
            if let item = fetchedItem {
                 InboxView.logger.info("Successfully fetched item \(id) for navigation.")
                 self.itemNavigationValue = ItemNavigationValue(item: item, targetCommentID: self.targetCommentIDForNavigation)
            } else {
                 InboxView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                 self.errorMessage = "Post \(id) konnte nicht geladen werden oder entspricht nicht den Filtern."
                 self.targetCommentIDForNavigation = nil
            }
        } catch is CancellationError {
             InboxView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
             self.targetCommentIDForNavigation = nil
        } catch {
            InboxView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
            if self.navigationTargetId == id {
                self.errorMessage = "Post \(id) konnte nicht geladen werden: \(error.localizedDescription)"
            }
            self.targetCommentIDForNavigation = nil
        }
        if self.navigationTargetId == id {
             self.isLoadingNavigationTarget = false
             self.navigationTargetId = nil
        }
    }

    @MainActor
    func refreshMessages(forType type: InboxViewMessageType) async {
        guard type != .privateMessages else {
            InboxView.logger.info("refreshMessages called, but privateMessages selected. Skipping general refresh.")
            return
        }
        currentRefreshTask?.cancel()

        InboxView.logger.info("Refreshing inbox messages for type: \(type.baseDisplayName)...")

        guard authService.isLoggedIn else {
            InboxView.logger.warning("Cannot refresh inbox: User not logged in.")
            self.messages = []; self.errorMessage = "Bitte anmelden."; self.canLoadMore = true
            return
        }

        self.isLoadingNavigationTarget = false; self.navigationTargetId = nil
        self.itemNavigationValue = nil; self.targetCommentIDForNavigation = nil
        self.isLoading = true; self.errorMessage = nil
        self.messages = []


        currentRefreshTask = Task {
            defer { Task { @MainActor in self.isLoading = false } }
            do {
                let response: InboxResponse
                switch type {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: nil)
                case .stelzes:
                    response = try await apiService.fetchInboxFollowsApi(older: nil)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: nil)
                default:
                    InboxView.logger.error("refreshMessages called with unhandled type: \(type.baseDisplayName)")
                    await MainActor.run { self.canLoadMore = false; self.messages = [] }
                    return
                }
                
                guard !Task.isCancelled else {
                    InboxView.logger.info("Refresh task for \(type.baseDisplayName) was cancelled during API call.")
                    return
                }

                await MainActor.run {
                    self.messages = response.messages.sorted { $0.created > $1.created }
                    self.canLoadMore = !response.atEnd
                }
                InboxView.logger.info("Fetched \(response.messages.count) initial messages for type \(type.baseDisplayName). AtEnd: \(response.atEnd)")

            } catch is CancellationError {
                InboxView.logger.info("API fetch for \(type.baseDisplayName) cancelled.")
                 await MainActor.run { self.messages = [] }
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Inbox API fetch failed for \(type.baseDisplayName): Authentication required.")
                await MainActor.run {
                    self.errorMessage = "Sitzung abgelaufen."; self.messages = []; self.canLoadMore = false
                }
                await authService.logout()
            } catch {
                InboxView.logger.error("Inbox API fetch failed for \(type.baseDisplayName): \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"; self.messages = []; self.canLoadMore = false
                }
            }
        }
    }

    @MainActor
    func loadMoreMessages(forType type: InboxViewMessageType) async {
         guard type != .privateMessages else {
            InboxView.logger.info("loadMoreMessages called, but privateMessages selected. Skipping.")
            return
        }
        currentLoadMoreTask?.cancel()

        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let oldestMessageTimestamp = messages.last?.created else {
             InboxView.logger.warning("Cannot load more messages for \(type.baseDisplayName): No last message found.")
             self.canLoadMore = false; return
        }

        InboxView.logger.info("--- Starting loadMoreMessages for \(type.baseDisplayName) older than timestamp \(oldestMessageTimestamp) ---")
        self.isLoadingMore = true

        currentLoadMoreTask = Task {
            defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; InboxView.logger.info("--- Finished loadMoreMessages for \(type.baseDisplayName) ---") } } }
            do {
                let response: InboxResponse
                switch type {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: oldestMessageTimestamp)
                case .stelzes:
                    response = try await apiService.fetchInboxFollowsApi(older: oldestMessageTimestamp)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: oldestMessageTimestamp)
                default:
                    InboxView.logger.error("loadMoreMessages called with unhandled type: \(type.baseDisplayName)")
                    self.canLoadMore = false
                    return
                }

                guard !Task.isCancelled else {
                    InboxView.logger.info("LoadMore task for \(type.baseDisplayName) was cancelled during API call.")
                    return
                }
                guard self.isLoadingMore else {
                    InboxView.logger.info("Load more for \(type.baseDisplayName) cancelled before UI update (isLoadingMore became false).");
                    return
                }
                
                await MainActor.run {
                    if response.messages.isEmpty {
                        InboxView.logger.info("Reached end of inbox feed for \(type.baseDisplayName).")
                        self.canLoadMore = false
                    } else {
                        let currentIDs = Set(self.messages.map { $0.id })
                        let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }

                        if uniqueNewMessages.isEmpty {
                            InboxView.logger.warning("All loaded messages for \(type.baseDisplayName) were duplicates.")
                            self.canLoadMore = !response.atEnd
                        } else {
                            self.messages.append(contentsOf: uniqueNewMessages.sorted { $0.created > $1.created })
                            InboxView.logger.info("Appended \(uniqueNewMessages.count) unique messages for \(type.baseDisplayName). Total: \(self.messages.count)")
                            self.canLoadMore = !response.atEnd
                        }
                    }
                }
            } catch is CancellationError {
                InboxView.logger.info("Load more API call for \(type.baseDisplayName) cancelled.")
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(type.baseDisplayName): Authentication required.")
                await MainActor.run { self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false }
                await authService.logout()
            } catch {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(type.baseDisplayName): \(error.localizedDescription)")
                guard self.isLoadingMore else { return }
                await MainActor.run {
                    if self.messages.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                    self.canLoadMore = false
                }
            }
        }
    }
        
    @MainActor
    func refreshConversations() async {
        currentRefreshTask?.cancel()
        InboxView.logger.info("Refreshing inbox conversations...")
        guard authService.isLoggedIn else {
            InboxView.logger.warning("Cannot refresh conversations: User not logged in.")
            self.conversations = []; self.conversationsError = "Bitte anmelden."
            return
        }
        self.isLoadingConversations = true
        self.conversationsError = nil
        
        currentRefreshTask = Task {
            defer { Task { @MainActor in self.isLoadingConversations = false } }

            do {
                let response = try await apiService.fetchInboxConversations()
                guard !Task.isCancelled else {
                    InboxView.logger.info("Refresh conversations task was cancelled during API call.")
                    return
                }
                await MainActor.run {
                    self.conversations = response.conversations.sorted { $0.lastMessage > $1.lastMessage }
                }
                InboxView.logger.info("Fetched \(response.conversations.count) conversations.")
            } catch is CancellationError {
                InboxView.logger.info("Conversations API fetch cancelled.")
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Conversations API fetch failed: Authentication required.")
                await MainActor.run {
                    self.conversationsError = "Sitzung abgelaufen."
                    self.conversations = []
                }
                await authService.logout()
            } catch {
                InboxView.logger.error("Conversations API fetch failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.conversationsError = "Fehler: \(error.localizedDescription)"
                    self.conversations = []
                }
            }
        }
    }
}

// MARK: - InboxContentOnlyView for use within other NavigationStacks
/// A wrapper that displays inbox content without its own NavigationStack
struct InboxContentOnlyView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var navigationService: NavigationService
    @StateObject private var playerManager = VideoPlayerManager()
    
    @State var messages: [InboxMessage] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var selectedMessageType: InboxViewMessageType = .comments
    @State private var conversations: [InboxConversation] = []
    @State private var isLoadingConversations = false
    @State private var conversationsError: String? = nil
    @State private var currentRefreshTask: Task<Void, Never>? = nil
    @State private var currentLoadMoreTask: Task<Void, Never>? = nil
    
    // Navigation states
    @State private var selectedConversationPartner: String? = nil
    @State private var itemNavigationValue: ItemNavigationValue? = nil
    @State private var profileNavigationValue: ProfileNavigationValue? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetId: Int? = nil
    @State private var targetCommentIDForNavigation: Int? = nil
    @State private var previewLinkTargetFromMessage: PreviewLinkTarget? = nil
    
    private let apiService = APIService()
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Nachrichten Typ", selection: $selectedMessageType) {
                ForEach(InboxViewMessageType.allCases) { type in
                    Text(type.displayNameForPicker(authService: authService))
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            contentView
        }
        .navigationTitle("Nachrichten")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            playerManager.configure(settings: settings)
            await refreshCurrentTabData()
        }
        .onChange(of: selectedMessageType) { _, newType in
            Task {
                currentRefreshTask?.cancel()
                currentLoadMoreTask?.cancel()
                messages = []
                conversations = []
                await refreshCurrentTabData()
            }
        }
        .navigationDestination(item: $selectedConversationPartner) { partnerUsername in
            ConversationDetailView(partnerUsername: partnerUsername)
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(playerManager)
        }
        .navigationDestination(item: $itemNavigationValue) { navValue in
             PagedDetailViewWrapperForItem(
                 item: navValue.item,
                 playerManager: playerManager,
                 targetCommentID: navValue.targetCommentID
             )
             .environmentObject(settings)
             .environmentObject(authService)
        }
        .navigationDestination(item: $profileNavigationValue) { navValue in
             UserProfileSheetView(username: navValue.username)
                  .environmentObject(settings)
                  .environmentObject(authService)
                  .environmentObject(playerManager)
        }
        .sheet(item: $previewLinkTargetFromMessage) { target in
            NavigationStack {
                LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                    .navigationTitle("Vorschau")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") {
                                previewLinkTargetFromMessage = nil
                            }
                        }
                    }
            }
            .environmentObject(settings)
            .environmentObject(authService)
        }
        .overlay {
            if isLoadingNavigationTarget {
                ProgressView("Lade Post \(navigationTargetId ?? 0)...")
                    .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let (itemID, commentID) = parsePr0grammLink(url: url) {
                InboxView.logger.info("Pr0gramm link tapped in inbox message, attempting to preview item ID: \(itemID), commentID: \(commentID ?? -1)")
                self.previewLinkTargetFromMessage = PreviewLinkTarget(itemID: itemID, commentID: commentID)
                return .handled
            } else {
                InboxView.logger.info("Non-pr0gramm link tapped in inbox: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }
    
    @ViewBuilder private var contentView: some View {
        if isLoading && messages.isEmpty && conversations.isEmpty {
            ProgressView("Lade Nachrichten...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedMessageType == .privateMessages {
            List {
                if conversations.isEmpty {
                    Text("Keine Konversationen vorhanden.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(conversations, id: \.name) { conversation in
                        Button {
                            selectedConversationPartner = conversation.name
                        } label: {
                            InboxConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await refreshCurrentTabData()
            }
        } else {
            List {
                if messages.isEmpty && !isLoading {
                    Text("Keine Nachrichten vorhanden.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(messages) { message in
                        InboxMessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isLoadingNavigationTarget else {
                                    InboxView.logger.debug("Tap ignored for message \(message.id): isLoadingNavigationTarget=\(isLoadingNavigationTarget)")
                                    return
                                }
                                Task { await handleMessageTap(message) }
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                            .id(message.id)
                            .onAppear {
                                if !messages.isEmpty && message.id == messages.last?.id && canLoadMore && !isLoadingMore {
                                     InboxView.logger.info("End trigger (last item) appeared for message ID: \(message.id).")
                                     currentLoadMoreTask?.cancel()
                                     currentLoadMoreTask = Task { await loadMoreMessages(forType: selectedMessageType) }
                                } else if messages.count > 5 && messages.count < 100 && messages.firstIndex(where: {$0.id == message.id}) == (messages.count - 5) && canLoadMore && !isLoadingMore {
                                     InboxView.logger.info("End trigger (near end) appeared for message ID: \(message.id).")
                                     currentLoadMoreTask?.cancel()
                                     currentLoadMoreTask = Task { await loadMoreMessages(forType: selectedMessageType) }
                                }
                            }
                    }
                }
                
                if isLoadingMore {
                    HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                        .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .refreshable {
                await refreshCurrentTabData()
            }
        }
    }
    
    private func refreshCurrentTabData() async {
        currentRefreshTask?.cancel()
        currentLoadMoreTask?.cancel()

        guard authService.isLoggedIn else {
            messages = []
            conversations = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if selectedMessageType == .privateMessages {
                let response = try await apiService.fetchInboxConversations()
                conversations = response.conversations.sorted { $0.lastMessage > $1.lastMessage }
            } else {
                let response: InboxResponse
                switch selectedMessageType {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: nil)
                case .stelzes:
                    response = try await apiService.fetchInboxFollowsApi(older: nil)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: nil)
                default:
                    return
                }
                messages = response.messages.sorted { $0.created > $1.created }
                canLoadMore = !response.atEnd
            }
            
            // Update unread counts after loading messages
            await updateCountsAfterViewingType(selectedMessageType)
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func updateCountsAfterViewingType(_ viewedType: InboxViewMessageType) async {
        // Der Server markiert beim Abrufen als gelesen. Ein erneuter fetchUnreadCounts holt den neuesten Stand.
        await authService.fetchUnreadCounts()
        // Den BackgroundManager informieren, damit der Badge und der interne Zähler korrekt sind.
        await BackgroundNotificationManager.shared.appDidBecomeActiveOrInboxViewed(currentTotalUnread: authService.unreadInboxTotal)
    }
    
    private func parsePr0grammLink(url: URL) -> (itemID: Int, commentID: Int?)? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }

        let path = url.path
        let components = path.components(separatedBy: "/")
        var itemID: Int? = nil
        var commentID: Int? = nil

        if let lastPathComponent = components.last {
            if lastPathComponent.contains(":comment") {
                let parts = lastPathComponent.split(separator: ":")
                if parts.count == 2, let idPart = Int(parts[0]), parts[1].starts(with: "comment"), let cID = Int(parts[1].dropFirst("comment".count)) {
                    itemID = idPart
                    commentID = cID
                }
            } else {
                var potentialItemIDIndex: Int? = nil
                if let idx = components.lastIndex(where: { $0 == "new" || $0 == "top" }), idx + 1 < components.count {
                    potentialItemIDIndex = idx + 1
                } else if components.count > 1 && Int(components.last!) != nil {
                    potentialItemIDIndex = components.count - 1
                }
                
                if let idx = potentialItemIDIndex, let id = Int(components[idx]) {
                    itemID = id
                }
            }
        }
        
        if itemID == nil, let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let id = Int(value) {
                    itemID = id
                    break
                }
            }
        }
        
        if let itemID = itemID {
            return (itemID, commentID)
        }

        InboxView.logger.warning("Could not parse item or comment ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }

    @MainActor
    private func handleMessageTap(_ message: InboxMessage) async {
        guard !isLoadingNavigationTarget else {
            InboxView.logger.debug("handleMessageTap skipped for \(message.id): Already loading target.")
            return
        }
        errorMessage = nil
        InboxView.logger.info("Handling tap for message ID: \(message.id), Type: \(message.type ?? "nil"), ItemID: \(message.itemId ?? -1)")

        if message.type == "comment", let itemId = message.itemId {
            InboxView.logger.info("Comment message tapped, preparing navigation for item \(itemId), target comment ID: \(message.id)")
            await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
        } else if message.type == "follow" || message.type == "follows", let itemId = message.itemId {
            InboxView.logger.info("Follow message (with item, type: \(message.type ?? "")) tapped, preparing navigation for item \(itemId). User: \(message.name ?? "Unbekannt")")
            await prepareAndNavigateToItem(itemId, targetCommentID: nil)
        } else if message.type == "follow" || message.type == "follows" {
             if let senderName = message.name, !senderName.isEmpty {
                InboxView.logger.info("Follow message (no item, fallback to profile, type: \(message.type ?? "")) tapped, setting profileNavigationValue: \(senderName)")
                self.profileNavigationValue = ProfileNavigationValue(username: senderName)
            } else {
                 InboxView.logger.warning("Follow message (type: \(message.type ?? "")) tapped but no itemId and no senderName for profile navigation.")
            }
        } else if message.type == "notification" {
             InboxView.logger.debug("Tapped on a 'notification' type message. No specific navigation action defined.")
        } else {
            InboxView.logger.warning("Tapped on message with unhandled type '\(message.type ?? "nil")' or missing itemId. ItemId: \(message.itemId ?? -1)")
        }
    }

    @MainActor
    private func prepareAndNavigateToItem(_ itemId: Int?, targetCommentID: Int? = nil) async {
        guard let id = itemId else {
            InboxView.logger.warning("Attempted to navigate, but itemId was nil.")
            return
        }
        guard !self.isLoadingNavigationTarget else {
            InboxView.logger.debug("Skipping navigation preparation for \(id): Already loading another target.")
            return
        }

        InboxView.logger.info("Preparing navigation for item ID: \(id), targetCommentID: \(targetCommentID ?? -1)")
        self.isLoadingNavigationTarget = true
        self.navigationTargetId = id
        self.errorMessage = nil
        self.targetCommentIDForNavigation = targetCommentID

        do {
            let flagsToFetchWith = 31
            InboxView.logger.debug("Fetching item \(id) for navigation using flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard self.navigationTargetId == id else {
                 InboxView.logger.info("Navigation target changed while item \(id) was loading (current target: \(String(describing: self.navigationTargetId))). Discarding result.")
                 self.isLoadingNavigationTarget = false; self.navigationTargetId = nil; self.targetCommentIDForNavigation = nil; return
            }
            if let item = fetchedItem {
                 InboxView.logger.info("Successfully fetched item \(id) for navigation.")
                 self.itemNavigationValue = ItemNavigationValue(item: item, targetCommentID: self.targetCommentIDForNavigation)
            } else {
                 InboxView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                 self.errorMessage = "Post \(id) konnte nicht geladen werden oder entspricht nicht den Filtern."
                 self.targetCommentIDForNavigation = nil
            }
        } catch is CancellationError {
             InboxView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
             self.targetCommentIDForNavigation = nil
        } catch {
            InboxView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
            if self.navigationTargetId == id {
                self.errorMessage = "Post \(id) konnte nicht geladen werden: \(error.localizedDescription)"
            }
            self.targetCommentIDForNavigation = nil
        }
        if self.navigationTargetId == id {
             self.isLoadingNavigationTarget = false
             self.navigationTargetId = nil
        }
    }

    @MainActor
    func loadMoreMessages(forType type: InboxViewMessageType) async {
         guard type != .privateMessages else {
            InboxView.logger.info("loadMoreMessages called, but privateMessages selected. Skipping.")
            return
        }
        currentLoadMoreTask?.cancel()

        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let oldestMessageTimestamp = messages.last?.created else {
             InboxView.logger.warning("Cannot load more messages for \(type.baseDisplayName): No last message found.")
             self.canLoadMore = false; return
        }

        InboxView.logger.info("--- Starting loadMoreMessages for \(type.baseDisplayName) older than timestamp \(oldestMessageTimestamp) ---")
        self.isLoadingMore = true

        currentLoadMoreTask = Task {
            defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; InboxView.logger.info("--- Finished loadMoreMessages for \(type.baseDisplayName) ---") } } }
            do {
                let response: InboxResponse
                switch type {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: oldestMessageTimestamp)
                case .stelzes:
                    response = try await apiService.fetchInboxFollowsApi(older: oldestMessageTimestamp)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: oldestMessageTimestamp)
                default:
                    InboxView.logger.error("loadMoreMessages called with unhandled type: \(type.baseDisplayName)")
                    self.canLoadMore = false
                    return
                }

                guard !Task.isCancelled else {
                    InboxView.logger.info("LoadMore task for \(type.baseDisplayName) was cancelled during API call.")
                    return
                }
                guard self.isLoadingMore else {
                    InboxView.logger.info("Load more for \(type.baseDisplayName) cancelled before UI update (isLoadingMore became false).");
                    return
                }
                
                await MainActor.run {
                    if response.messages.isEmpty {
                        InboxView.logger.info("Reached end of inbox feed for \(type.baseDisplayName).")
                        self.canLoadMore = false
                    } else {
                        let currentIDs = Set(self.messages.map { $0.id })
                        let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }

                        if uniqueNewMessages.isEmpty {
                            InboxView.logger.warning("All loaded messages for \(type.baseDisplayName) were duplicates.")
                            self.canLoadMore = !response.atEnd
                        } else {
                            self.messages.append(contentsOf: uniqueNewMessages.sorted { $0.created > $1.created })
                            InboxView.logger.info("Appended \(uniqueNewMessages.count) unique messages for \(type.baseDisplayName). Total: \(self.messages.count)")
                            self.canLoadMore = !response.atEnd
                        }
                    }
                }
            } catch is CancellationError {
                InboxView.logger.info("Load more API call for \(type.baseDisplayName) cancelled.")
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(type.baseDisplayName): Authentication required.")
                await MainActor.run { self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false }
                await authService.logout()
            } catch {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(type.baseDisplayName): \(error.localizedDescription)")
                guard self.isLoadingMore else { return }
                await MainActor.run {
                    if self.messages.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                    self.canLoadMore = false
                }
            }
        }
    }
}

struct InboxConversationRow: View {
    let conversation: InboxConversation
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(conversation.lastMessage))
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var userMarkColor: Color { Mark(rawValue: conversation.mark).displayColor }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(userMarkColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))

            Text(conversation.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            
            Text(relativeTime)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}


struct InboxMessageRow: View {
    let message: InboxMessage
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(message.created))
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var titleText: String {
        let messageType = message.type?.lowercased()
        switch messageType {
        case "comment": return message.name ?? "Kommentar"
        case "notification": return "Systemnachricht"
        case "message": return message.name ?? "Nachricht"
        case "follow", "follows": return message.name ?? "Unbekannter User"
        default: return "Unbekannt (\(message.type ?? "N/A"))"
        }
    }
    
    private var senderNameText: String? {
        let messageType = message.type?.lowercased()
        if messageType == "follow" || messageType == "follows" || messageType == "comment" || messageType == "message" {
            return message.name
        }
        return nil
    }

    private var titleOrMarkColor: Color {
        let messageType = message.type?.lowercased()
        if messageType == "comment" || messageType == "follow" || messageType == "follows" || messageType == "message" {
            return Mark(rawValue: message.mark ?? -1).displayColor
        }
        return .secondary
    }

    private var attributedMessageContent: AttributedString {
        let messageType = message.type?.lowercased()
        guard messageType != "follow" && messageType != "follows", let msgText = message.message, !msgText.isEmpty else {
            return AttributedString("")
        }
        
        var attributedString = AttributedString(msgText)
        let baseUIFont = UIFont.uiFont(from: UIConstants.subheadlineFont)
        attributedString.font = baseUIFont

        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: msgText, options: [], range: NSRange(location: 0, length: msgText.utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url
                attributedString[range].foregroundColor = .accentColor
                attributedString[range].font = baseUIFont
            }
        } catch {
            InboxView.logger.error("Error creating NSDataDetector in InboxMessageRow: \(error.localizedDescription)")
        }
        return attributedString
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let messageType = message.type?.lowercased()
            if (messageType == "comment" || messageType == "follow" || messageType == "follows"), let thumbUrl = message.itemThumbnailUrl {
                KFImage(thumbUrl)
                    .resizable().placeholder { Color.gray.opacity(0.1) }
                    .aspectRatio(contentMode: .fill).frame(width: 50, height: 50)
                    .clipped().cornerRadius(4)
            } else {
                 Image(systemName: "bell.circle.fill")
                    .resizable().scaledToFit().frame(width: 50, height: 50)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if messageType == "comment" || messageType == "follow" || messageType == "follows" || messageType == "message" {
                         Circle().fill(titleOrMarkColor)
                             .frame(width: 8, height: 8)
                             .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                     }
                     Text(titleText).font(.headline).lineLimit(1)
                     Spacer()
                     Text(relativeTime).font(.caption).foregroundColor(.secondary)
                     if message.read == 0 && messageType != "follow" && messageType != "follows" {
                         Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.leading, 4)
                     }
                }
                
                if messageType != "follow" && messageType != "follows", let msg = message.message, !msg.isEmpty {
                    Text(attributedMessageContent)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(messageType == "notification" ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else if messageType == "follow" || messageType == "follows" {
                    Text("hat einen neuen Post")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }
}


#Preview {
    InboxPreviewWrapper()
}

private struct InboxPreviewWrapper: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var authService: AuthService
    @StateObject private var navigationService = NavigationService()


    init() {
        let settings = AppSettings()
        let authService = AuthService(appSettings: settings)
        authService.isLoggedIn = true
        authService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: 1, score: 1, mark: 1, badges: [])
        _authService = StateObject(wrappedValue: authService)
        _settings = StateObject(wrappedValue: settings)
        _navigationService = StateObject(wrappedValue: NavigationService())
    }

    var body: some View {
        let sampleConversations = [
            InboxConversation(name: "UserAlpha", mark: 2, lastMessage: Int(Date().timeIntervalSince1970 - 300), unreadCount: 2, blocked: 0, canReceiveMessages: 1),
            InboxConversation(name: "UserBeta", mark: 10, lastMessage: Int(Date().timeIntervalSince1970 - 36000), unreadCount: 0, blocked: 0, canReceiveMessages: 1)
        ]
        
        let msg1 = InboxMessage(id: 1, type: "comment", itemId: 123, thumb: "thumb1.jpg", flags: 1, name: "UserA", mark: 2, senderId: 101, score: 5, created: Int(Date().timeIntervalSince1970 - 600), message: "Das ist ein Kommentar http://pr0gramm.com/new/543210:comment123 zur Benachrichtigung.", read: 0, blocked: 0, sent: 0)
        let msg2 = InboxMessage(id: 2, type: "notification", itemId: nil, thumb: nil, flags: nil, name: nil, mark: nil, senderId: 0, score: 0, created: Int(Date().timeIntervalSince1970 - 3600), message: "Systemnachricht: Dein pr0mium läuft bald ab!", read: 1, blocked: 0, sent: nil)
        let msg3 = InboxMessage(id: 3, type: "follows", itemId: 6625472, thumb: "2025/05/21/1001c9dcd15d8324.jpg", flags: 8, name: "Vollzeitdieb", mark: 9, senderId: 363088, score: 7, created: Int(Date().timeIntervalSince1970 - 7200), message: nil, read: 0, blocked: 0, sent: nil)


        return InboxView(
            initialMessagesForPreview: [msg1, msg2, msg3],
            initialConversationsForPreview: sampleConversations
        )
            .environmentObject(settings)
            .environmentObject(authService)
            .environmentObject(navigationService)
    }
}
// --- END OF COMPLETE FILE ---
