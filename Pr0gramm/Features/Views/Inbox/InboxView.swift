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
    case notifications = 2
    case privateMessages = 3

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .comments: return "Kommentare"
        case .notifications: return "System"
        case .privateMessages: return "Privat"
        }
    }
    
    var apiTypeStringForFilter: String? {
        switch self {
        case .comments: return "comment"
        case .notifications: return "notification"
        case .privateMessages: return nil
        }
    }
    
    @MainActor
    func unreadCount(from authService: AuthService) -> Int {
        switch self {
        case .comments:
            return authService.unreadCommentCount
        case .notifications:
            return authService.unreadSystemNotificationCount
        case .privateMessages:
            return authService.unreadPrivateMessageCount
        }
    }
}

// --- NEW: Label View für den Picker ---
@MainActor
struct InboxPickerSegmentLabel: View {
    let type: InboxViewMessageType
    let isSelected: Bool
    @EnvironmentObject var authService: AuthService // Zugriff auf AuthService für die Zähler

    private var unreadCount: Int {
        type.unreadCount(from: authService)
    }

    private var displayText: String {
        if unreadCount > 0 {
            return "\(type.displayName) (\(unreadCount))"
        }
        return type.displayName
    }

    private var textColor: Color {
        if isSelected {
            // Wenn ausgewählt, verwendet der Picker normalerweise eine Kontrastfarbe (oft weiß oder schwarz, je nach Akzentfarbe)
            // Wir können versuchen, dies zu respektieren oder eine feste Farbe zu setzen.
            // Für den Standard-SegmentedControl ist es am besten, die Systemfarbe zu lassen oder .primary/.white.
            return Color(UIColor.label) // Passt sich Hell/Dunkel-Modus an, aber Akzentfarbe überschreibt es oft.
                                        // Oder .white, wenn der Picker-Hintergrund immer dunkel ist.
        } else {
            // Wenn nicht ausgewählt und ungelesen, dann rot. Sonst Standard.
            return unreadCount > 0 ? .red : Color(UIColor.label)
        }
    }

    var body: some View {
        Text(displayText)
            .foregroundColor(textColor)
            // Wichtig: .tag hier im Picker-Loop setzen, nicht im Label selbst,
            // damit der Picker die Auswahl korrekt verwalten kann.
    }
}
// --- END NEW ---


struct InboxView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
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
            VStack(spacing: 0) {
                // --- MODIFIED: Standard-Picker mit custom Label View ---
                Picker("Nachrichten Typ", selection: $selectedMessageType) {
                    ForEach(InboxViewMessageType.allCases) { type in
                        InboxPickerSegmentLabel(type: type, isSelected: selectedMessageType == type)
                            .tag(type) // Das .tag muss hier sein!
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                // --- END MODIFICATION ---

                contentView
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
            .onChange(of: selectedMessageType) { _, newType in
                currentRefreshTask?.cancel()
                currentLoadMoreTask?.cancel()
                Task {
                    itemNavigationValue = nil
                    conversationNavigationValue = nil
                    profileNavigationValue = nil
                    
                    messages = []
                    conversations = []
                    await refreshCurrentTabData()
                }
            }
            .task(id: authService.isLoggedIn) {
                 currentRefreshTask?.cancel()
                 currentLoadMoreTask?.cancel()
                 await refreshCurrentTabData()
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
        
    private func isCancellationError(_ message: String?) -> Bool {
        return message?.lowercased().contains("cancelled") == true
    }
    
    private func refreshCurrentTabData() async {
        currentRefreshTask?.cancel()
        currentLoadMoreTask?.cancel()

        if authService.isLoggedIn {
            await authService.fetchUnreadCounts()
            if selectedMessageType == .privateMessages {
                currentRefreshTask = Task { await refreshConversations() }
            } else {
                currentRefreshTask = Task { await refreshMessages() }
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
                    currentRefreshTask = Task { await refreshConversations() }
                },
                onSelectConversation: { username in
                    self.conversationNavigationValue = ConversationNavigationValue(conversationPartnerName: username)
                }
            )
        case .comments, .notifications:
            generalMessagesListView
        }
    }

    private var generalMessagesListView: some View {
        Group {
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
                         currentRefreshTask = Task { await refreshMessages() }
                    }
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty && !isLoading && errorMessage == nil {
                Text("Keine Nachrichten für Filter '\(selectedMessageType.displayName)' vorhanden.")
                    .foregroundColor(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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
                            if messages.count >= 2 && message.id == messages[messages.count - 2].id && canLoadMore && !isLoadingMore {
                                InboxView.logger.info("End trigger appeared for message ID: \(message.id).")
                                currentLoadMoreTask?.cancel()
                                currentLoadMoreTask = Task { await loadMoreMessages() }
                            } else if messages.count == 1 && message.id == messages.first?.id && canLoadMore && !isLoadingMore {
                                InboxView.logger.info("End trigger appeared for the only message ID: \(message.id).")
                                currentLoadMoreTask?.cancel()
                                currentLoadMoreTask = Task { await loadMoreMessages() }
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
                    currentRefreshTask?.cancel()
                    currentLoadMoreTask?.cancel()
                    currentRefreshTask = Task { await refreshMessages() }
                }
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
        InboxView.logger.info("Handling tap for message ID: \(message.id), Type: \(message.type ?? "nil")")

        switch selectedMessageType {
        case .comments:
            if message.type == "comment", let itemId = message.itemId {
                InboxView.logger.info("Comment message tapped, preparing navigation for item \(itemId), target comment ID: \(message.id)")
                await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
            } else {
                InboxView.logger.warning("Tapped on message with type '\(message.type ?? "nil")' while on Comments tab. ItemId: \(message.itemId ?? -1)")
            }
        case .notifications:
            if message.type == "follow", let senderName = message.name, !senderName.isEmpty {
                InboxView.logger.info("Follow message tapped on System tab, setting profileNavigationValue: \(senderName)")
                self.profileNavigationValue = ProfileNavigationValue(username: senderName)
            } else if message.type == "notification" {
                 InboxView.logger.debug("Tapped on a 'notification' type message on System tab. No specific navigation action defined.")
            } else if message.type == "comment", let itemId = message.itemId {
                InboxView.logger.warning("Comment message tapped while on System tab, preparing navigation for item \(itemId), target comment ID: \(message.id)")
                await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
            }
            else {
                InboxView.logger.warning("Tapped on message with type '\(message.type ?? "nil")' while on System tab. This might be an unexpected message type for this tab.")
            }
        case .privateMessages:
            InboxView.logger.error("handleMessageTap called for privateMessages type, which should be handled by ConversationsListView.")
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
    func refreshMessages() async {
        guard selectedMessageType != .privateMessages else {
            InboxView.logger.info("refreshMessages called, but privateMessages selected. Skipping general refresh.")
            return
        }
        currentRefreshTask?.cancel()

        InboxView.logger.info("Refreshing inbox messages for selected type: \(selectedMessageType.displayName)...")

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
                switch selectedMessageType {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: nil)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: nil)
                case .privateMessages:
                    InboxView.logger.error("refreshMessages called unexpectedly for .privateMessages type.")
                    return
                }
                
                guard !Task.isCancelled else {
                    InboxView.logger.info("Refresh task for \(selectedMessageType.displayName) was cancelled during API call.")
                    return
                }

                let fetchedMessageTypes = Dictionary(grouping: response.messages, by: { $0.type ?? "unknown" }).mapValues { $0.count }
                InboxView.logger.debug("API Response for \(selectedMessageType.displayName): Fetched \(response.messages.count) messages. Types: \(fetchedMessageTypes). AtEnd: \(response.atEnd)")

                await MainActor.run {
                    self.messages = response.messages.sorted { $0.created > $1.created }
                    self.canLoadMore = !response.atEnd
                }
                InboxView.logger.info("Fetched \(response.messages.count) initial messages for tab \(selectedMessageType.displayName). AtEnd: \(response.atEnd)")

            } catch is CancellationError {
                InboxView.logger.info("API fetch for \(selectedMessageType.displayName) cancelled.")
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Inbox API fetch failed for \(selectedMessageType.displayName): Authentication required.")
                await MainActor.run {
                    self.errorMessage = "Sitzung abgelaufen."; self.messages = []; self.canLoadMore = false
                }
                await authService.logout()
            } catch {
                InboxView.logger.error("Inbox API fetch failed for \(selectedMessageType.displayName): \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"; self.messages = []; self.canLoadMore = false
                }
            }
        }
    }

    @MainActor
    func loadMoreMessages() async {
        guard selectedMessageType != .privateMessages else {
            InboxView.logger.info("loadMoreMessages called, but privateMessages selected. Skipping.")
            return
        }
        currentLoadMoreTask?.cancel()

        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let oldestMessageTimestamp = messages.last?.created else {
             InboxView.logger.warning("Cannot load more messages for \(selectedMessageType.displayName): No last message found.")
             self.canLoadMore = false; return
        }

        InboxView.logger.info("--- Starting loadMoreMessages for \(selectedMessageType.displayName) older than timestamp \(oldestMessageTimestamp) ---")
        self.isLoadingMore = true

        currentLoadMoreTask = Task {
            defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; InboxView.logger.info("--- Finished loadMoreMessages for \(selectedMessageType.displayName) ---") } } }

            do {
                let response: InboxResponse
                switch selectedMessageType {
                case .comments:
                    response = try await apiService.fetchInboxCommentsApi(older: oldestMessageTimestamp)
                case .notifications:
                    response = try await apiService.fetchInboxNotificationsApi(older: oldestMessageTimestamp)
                case .privateMessages:
                    InboxView.logger.error("loadMoreMessages called unexpectedly for .privateMessages type.")
                    return
                }

                guard !Task.isCancelled else {
                    InboxView.logger.info("LoadMore task for \(selectedMessageType.displayName) was cancelled during API call.")
                    return
                }
                guard self.isLoadingMore else {
                    InboxView.logger.info("Load more for \(selectedMessageType.displayName) cancelled before UI update (isLoadingMore became false).");
                    return
                }
                
                let fetchedMessageTypes = Dictionary(grouping: response.messages, by: { $0.type ?? "unknown" }).mapValues { $0.count }
                InboxView.logger.debug("API Response for \(selectedMessageType.displayName) (loadMore): Fetched \(response.messages.count) messages. Types: \(fetchedMessageTypes). AtEnd: \(response.atEnd)")

                await MainActor.run {
                    if response.messages.isEmpty {
                        InboxView.logger.info("Reached end of inbox feed for \(selectedMessageType.displayName).")
                        self.canLoadMore = false
                    } else {
                        let currentIDs = Set(self.messages.map { $0.id })
                        let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }

                        if uniqueNewMessages.isEmpty {
                            InboxView.logger.warning("All loaded messages for \(selectedMessageType.displayName) were duplicates.")
                            self.canLoadMore = !response.atEnd
                        } else {
                            self.messages.append(contentsOf: uniqueNewMessages)
                            self.messages.sort { $0.created > $1.created }
                            InboxView.logger.info("Appended \(uniqueNewMessages.count) unique messages for \(selectedMessageType.displayName). Total: \(self.messages.count)")
                            self.canLoadMore = !response.atEnd
                        }
                    }
                }
            } catch is CancellationError {
                InboxView.logger.info("Load more API call for \(selectedMessageType.displayName) cancelled.")
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(selectedMessageType.displayName): Authentication required.")
                await MainActor.run { self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false }
                await authService.logout()
            } catch {
                InboxView.logger.error("Inbox API fetch failed during loadMore for \(selectedMessageType.displayName): \(error.localizedDescription)")
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

    private var title: String {
        switch message.type {
        case "comment": return message.name ?? "Kommentar"
        case "notification": return "Systemnachricht"
        case "message": return message.name ?? "Nachricht"
        case "follow": return "\(message.name ?? "Jemand") folgt dir"
        default: return "Unbekannt (\(message.type ?? "N/A"))"
        }
    }

    private var titleOrMarkColor: Color {
        if message.type == "comment" || message.type == "follow" {
            return Mark(rawValue: message.mark ?? -1).displayColor
        }
        return .secondary
    }

    private var attributedMessageContent: AttributedString {
        var attributedString = AttributedString(message.message ?? "")
        let baseUIFont = UIFont.uiFont(from: UIConstants.subheadlineFont)
        attributedString.font = baseUIFont

        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: message.message ?? "", options: [], range: NSRange(location: 0, length: (message.message ?? "").utf16.count))
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
            if message.type == "comment", let thumbUrl = message.itemThumbnailUrl {
                KFImage(thumbUrl)
                    .resizable().placeholder { Color.gray.opacity(0.1) }
                    .aspectRatio(contentMode: .fill).frame(width: 50, height: 50)
                    .clipped().cornerRadius(4)
            } else if message.type == "follow" {
                 Image(systemName: "person.crop.circle.fill")
                     .resizable().scaledToFit().frame(width: 50, height: 50)
                     .foregroundColor(.secondary)
            } else {
                 Image(systemName: "bell.circle.fill")
                    .resizable().scaledToFit().frame(width: 50, height: 50)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                     if message.type != "notification" && message.type != "follow" {
                         Circle().fill(titleOrMarkColor)
                             .frame(width: 8, height: 8)
                             .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                     }
                     Text(title).font(.headline).lineLimit(1)
                     Spacer()
                     Text(relativeTime).font(.caption).foregroundColor(.secondary)
                     if message.read == 0 {
                         Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.leading, 4)
                     }
                }
                if message.type != "follow" || !(message.message?.isEmpty ?? true) {
                    Text(attributedMessageContent)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

struct ConversationMessageRow: View {
    let message: PrivateMessage
    let isSentByCurrentUser: Bool
    let currentUserMark: Int
    let partnerMark: Int
    let partnerName: String

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationMessageRowGlobal")
    @EnvironmentObject var authService: AuthService

    private var backgroundColor: Color {
        isSentByCurrentUser ? Color.accentColor : Color(uiColor: .systemGray5)
    }

    private var textColorForBubble: Color {
        isSentByCurrentUser ? .white : .primary
    }
    
    private var senderDisplayName: String {
        return message.name
    }
    private var senderMarkValue: Int {
        return message.mark
    }
    
    private func getInitials(from name: String) -> String {
        let parts = name.uppercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var initials = ""
        if let first = parts.first?.first {
            initials.append(first)
        }
        if parts.count > 1, let second = parts.last?.first {
            initials.append(second)
        } else if initials.count == 1 && (parts.first?.count ?? 0) > 1, let secondChar = parts.first?.dropFirst().first {
             initials.append(secondChar)
        }
        if initials.count > 2 {
            initials = String(initials.prefix(2))
        }
        if initials.count == 1 && (parts.first?.count ?? 0) == 1 {
        }
        return initials.isEmpty ? "?" : initials
    }

    private func isColorLight(_ color: Color) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return false
        }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6
    }

    @ViewBuilder
    private var avatarView: some View {
        let nameForAvatar = isSentByCurrentUser ? (authService.currentUser?.name ?? "Ich") : partnerName
        let initials = getInitials(from: nameForAvatar)
        let avatarBackgroundColor = Mark(rawValue: senderMarkValue).displayColor
        let initialsColor: Color = isColorLight(avatarBackgroundColor) ? .black : .white
        
        ZStack {
            Circle()
                .fill(avatarBackgroundColor)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
            Text(initials)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(initialsColor)
        }
    }

    private var attributedMessageContent: AttributedString {
        var attributedString = AttributedString(message.message ?? "")
        let baseUIFont = UIFont.uiFont(from: UIConstants.footnoteFont)
        attributedString.font = baseUIFont
        attributedString.foregroundColor = textColorForBubble

        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: message.message ?? "", options: [], range: NSRange(location: 0, length: (message.message ?? "").utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url
                attributedString[range].foregroundColor = isSentByCurrentUser ? .white.opacity(0.85) : Color.accentColor
                attributedString[range].underlineStyle = .single
                attributedString[range].font = baseUIFont
            }
        } catch {
            Self.logger.error("Error creating NSDataDetector in ConversationMessageRow: \(error.localizedDescription)")
        }
        return attributedString
    }

    private func formattedTimestamp(for created: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(created))
        let calendar = Calendar.current

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return timeString
        } else if calendar.isDateInYesterday(date) {
            return "Gestern, \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
                dateFormatter.dateFormat = "d. MMMM"
            } else {
                dateFormatter.dateFormat = "dd.MM.yy"
            }
            let dateString = dateFormatter.string(from: date)
            return "\(dateString), \(timeString)"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !isSentByCurrentUser {
                avatarView
                    .padding(.trailing, 6)
            } else {
                Spacer(minLength: 36 + 6)
            }

            VStack(alignment: isSentByCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(attributedMessageContent)
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(minWidth: 40)

                HStack(spacing: 4) {
                    Text(formattedTimestamp(for: message.created))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 0)
                .padding(.top, 2)
            }
            
            if isSentByCurrentUser {
                 Spacer().frame(width: 36 + 6, height: 0)
            } else {
                Spacer(minLength: 36 + 6)
            }
        }
    }
}

#Preview {
    InboxPreviewWrapper()
}

private struct InboxPreviewWrapper: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var authService: AuthService

    init() {
        let settings = AppSettings()
        let authService = AuthService(appSettings: settings)
        authService.isLoggedIn = true
        authService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: 1, score: 1, mark: 1, badges: [])
        _authService = StateObject(wrappedValue: authService)
        _settings = StateObject(wrappedValue: settings)
    }

    var body: some View {
        let sampleConversations = [
            InboxConversation(name: "UserAlpha", mark: 2, lastMessage: Int(Date().timeIntervalSince1970 - 300), unreadCount: 2, blocked: 0, canReceiveMessages: 1),
            InboxConversation(name: "UserBeta", mark: 10, lastMessage: Int(Date().timeIntervalSince1970 - 36000), unreadCount: 0, blocked: 0, canReceiveMessages: 1)
        ]
        
        let msg1 = InboxMessage(id: 1, type: "comment", itemId: 123, thumb: "thumb1.jpg", flags: 1, name: "UserA", mark: 2, senderId: 101, score: 5, created: Int(Date().timeIntervalSince1970 - 600), message: "Das ist ein Kommentar http://pr0gramm.com/new/543210:comment123 zur Benachrichtigung.", read: 0, blocked: 0, sent: 0)
        let msg2 = InboxMessage(id: 2, type: "notification", itemId: nil, thumb: nil, flags: nil, name: nil, mark: nil, senderId: 0, score: 0, created: Int(Date().timeIntervalSince1970 - 3600), message: "Systemnachricht: Dein pr0mium läuft bald ab!", read: 1, blocked: 0, sent: nil)
        let msg3 = InboxMessage(id: 3, type: "follow", itemId: nil, thumb: nil, flags: nil, name: "FollowerUser", mark: 1, senderId: 102, score: 0, created: Int(Date().timeIntervalSince1970 - 7200), message: nil, read: 0, blocked: 0, sent: nil)


        return InboxView(
            initialMessagesForPreview: [msg1, msg2, msg3],
            initialConversationsForPreview: sampleConversations
        )
            .environmentObject(settings)
            .environmentObject(authService)
    }
}
// --- END OF COMPLETE FILE ---
