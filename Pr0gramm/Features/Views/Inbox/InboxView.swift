// Pr0gramm/Pr0gramm/Features/Views/Inbox/InboxView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

// --- MODIFIED: InboxViewMessageType Enum ---
enum InboxViewMessageType: Int, CaseIterable, Identifiable {
    case comments = 1 // Start with comments if 'all' is removed
    case notifications = 2
    case privateMessages = 3

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        // case .all: return "Alle" // Removed
        case .comments: return "Kommentare"
        case .notifications: return "System"
        case .privateMessages: return "Privat"
        }
    }

    var apiTypeString: String? {
        switch self {
        // case .all: return nil // Removed
        case .comments: return "comment"
        case .notifications: return "notification"
        case .privateMessages: return nil // Private messages handled differently
        }
    }
}
// --- END MODIFICATION ---


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

    // --- MODIFIED: Default selectedMessageType ---
    @State private var selectedMessageType: InboxViewMessageType = .comments // Default to comments
    // --- END MODIFICATION ---
    
    @State private var conversations: [InboxConversation] = []
    @State private var isLoadingConversations = false
    @State private var conversationsError: String? = nil


    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "InboxView")

    struct ItemNavigationValue: Hashable, Identifiable {
        let item: Item
        let targetCommentID: Int?
        var id: Int { item.id }
    }
    @State private var itemNavigationValue: ItemNavigationValue? = nil
    
    struct ConversationNavigationValue: Hashable, Identifiable {
        let conversationPartnerName: String
        var id: String { conversationPartnerName }
    }
    @State private var conversationNavigationValue: ConversationNavigationValue? = nil

    struct ProfileNavigationValue: Hashable, Identifiable {
        let username: String
        var id: String { username }
    }
    @State private var profileNavigationValue: ProfileNavigationValue? = nil


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
                Picker("Nachrichten Typ", selection: $selectedMessageType) {
                    ForEach(InboxViewMessageType.allCases) { type in // Iterates over remaining cases
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                contentView
            }
            .navigationTitle("Nachrichten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Fehler", isPresented: .constant(alertErrorMessage != nil && !isLoading && !isLoadingConversations)) {
                Button("OK") { clearErrors() }
            } message: { Text(alertErrorMessage ?? "Unbekannter Fehler") }
            .task {
                playerManager.configure(settings: settings)
            }
            .onChange(of: selectedMessageType) { _, newType in
                Task {
                    itemNavigationValue = nil
                    conversationNavigationValue = nil
                    profileNavigationValue = nil
                    
                    // --- MODIFIED: Logic for changing tabs ---
                    messages = [] // Clear messages when switching tabs to force refresh
                    conversations = [] // Clear conversations as well
                    if newType == .privateMessages {
                        await refreshConversations()
                    } else {
                        await refreshMessages() // This will now fetch based on the new selectedMessageType
                    }
                    // --- END MODIFICATION ---
                }
            }
            .task(id: authService.isLoggedIn) { // Handles initial load and login/logout changes
                 if authService.isLoggedIn {
                     // --- MODIFIED: Initial load logic ---
                     if selectedMessageType == .privateMessages {
                         await refreshConversations()
                     } else {
                         await refreshMessages() // Default load for comments or notifications
                     }
                     // --- END MODIFICATION ---
                 } else {
                     messages = []
                     conversations = []
                     errorMessage = "Bitte anmelden."
                     conversationsError = nil
                 }
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
                LinkedItemPreviewView(itemID: target.id)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
            .overlay {
                if isLoadingNavigationTarget {
                    ProgressView("Lade Post \(navigationTargetId ?? 0)...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
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
                onRefresh: refreshConversations,
                onSelectConversation: { username in
                    self.conversationNavigationValue = ConversationNavigationValue(conversationPartnerName: username)
                }
            )
        // --- MODIFIED: Cases for comments and notifications ---
        case .comments, .notifications:
            generalMessagesListView // Use the same list view for these types
        // --- END MODIFICATION ---
        }
    }

    private var filteredMessages: [InboxMessage] {
        // --- MODIFIED: Logic for filteredMessages ---
        // Since .all is removed, we directly filter by the selected type's apiTypeString.
        // This implicitly handles .comments and .notifications.
        // Private messages are handled by a different view.
        guard selectedMessageType != .privateMessages, let apiType = selectedMessageType.apiTypeString else {
            return [] // Should not happen if privateMessages has its own view
        }
        return messages.filter { $0.type == apiType || ($0.type == "follow" && selectedMessageType == .notifications) } // Show "follow" under "System" (notifications)
        // --- END MODIFICATION ---
    }

    private var generalMessagesListView: some View {
        Group {
            if isLoading && messages.isEmpty { // Use messages here, not filteredMessages for initial loading state
                ProgressView("Lade Nachrichten...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, filteredMessages.isEmpty {
                 ContentUnavailableView {
                     Label("Fehler", systemImage: "exclamationmark.triangle")
                 } description: {
                     Text(error)
                 } actions: {
                     Button("Erneut versuchen") { Task { await refreshMessages() } }
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMessages.isEmpty && !isLoading && errorMessage == nil {
                Text("Keine Nachrichten für Filter '\(selectedMessageType.displayName)' vorhanden.")
                    .foregroundColor(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredMessages) { message in // Iterate over filteredMessages
                        InboxMessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isLoadingNavigationTarget else {
                                    InboxView.logger.debug("Tap ignored for message \(message.id): isLoadingNavigationTarget=\(isLoadingNavigationTarget)")
                                    return
                                }
                                if message.type == "notification" && selectedMessageType == .notifications { // Allow tap only if on "System" tab
                                    InboxView.logger.debug("Notification message tapped on System tab, no navigation action.")
                                    return
                                }
                                Task { await handleMessageTap(message) }
                            }
                        .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                        .id(message.id)
                        .onAppear {
                            let currentList = filteredMessages // Use filteredMessages for pagination trigger
                            if currentList.count >= 2 && message.id == currentList[currentList.count - 2].id && canLoadMore && !isLoadingMore {
                                InboxView.logger.info("End trigger appeared for message ID: \(message.id).")
                                Task { await loadMoreMessages() }
                            } else if currentList.count == 1 && message.id == currentList.first?.id && canLoadMore && !isLoadingMore {
                                InboxView.logger.info("End trigger appeared for the only message ID: \(message.id).")
                                Task { await loadMoreMessages() }
                            }
                        }
                    }

                    if isLoadingMore {
                        HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                            .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .refreshable { await refreshMessages() }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                InboxView.logger.info("Pr0gramm link tapped in inbox message, attempting to preview item ID: \(itemID)")
                self.previewLinkTargetFromMessage = PreviewLinkTarget(id: itemID)
                return .handled
            } else {
                InboxView.logger.info("Non-pr0gramm link tapped in inbox: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }
    

    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if let itemID = Int(component) { return itemID }
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let itemID = Int(value) {
                    return itemID
                }
            }
        }
        InboxView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
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

        switch message.type {
        case "comment":
            if let itemId = message.itemId {
                InboxView.logger.info("Message type is 'comment', preparing navigation for item \(itemId), target comment ID: \(message.id)")
                await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
            } else { InboxView.logger.warning("Comment message type tapped, but itemId is nil.") }
        case "follow":
             if let senderName = message.name, !senderName.isEmpty {
                 InboxView.logger.info("Message type is 'follow', setting profileNavigationValue: \(senderName)")
                 self.profileNavigationValue = ProfileNavigationValue(username: senderName)
             } else { InboxView.logger.warning("Follow message type tapped, but sender name is nil or empty.") }
        default:
            InboxView.logger.warning("Unhandled message type tapped in handleMessageTap: \(message.type ?? "nil")")
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
            let flagsToFetchWith = 31 // Fetch with all flags for detail view consistency
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
          // --- MODIFIED: Logic for refreshMessages ---
          // This function now always fetches ALL message types (/inbox/all)
          // The filtering to specific types (comments, notifications) happens in `filteredMessages`.
          // Private messages are handled by refreshConversations.
          guard selectedMessageType != .privateMessages else {
              InboxView.logger.info("refreshMessages called, but privateMessages selected. Skipping general refresh.")
              return
          }

          InboxView.logger.info("Refreshing general inbox messages (/inbox/all) for selected type: \(selectedMessageType.displayName)...")
          // --- END MODIFICATION ---

          guard authService.isLoggedIn else {
              InboxView.logger.warning("Cannot refresh general inbox: User not logged in.")
              self.messages = []; self.errorMessage = "Bitte anmelden."; self.canLoadMore = true
              return
          }

          self.isLoadingNavigationTarget = false; self.navigationTargetId = nil
          self.itemNavigationValue = nil; self.targetCommentIDForNavigation = nil
          self.isLoading = true; self.errorMessage = nil

          defer { Task { @MainActor in self.isLoading = false } }

          do {
              let response = try await apiService.fetchInboxMessages(older: nil) // Always fetch all for general tabs
              guard !Task.isCancelled else { return }

              // Store all fetched messages, filtering happens in `filteredMessages`
              self.messages = response.messages.sorted { $0.created > $1.created }
              self.canLoadMore = !response.atEnd
              InboxView.logger.info("Fetched \(response.messages.count) initial general inbox messages (all types). AtEnd: \(response.atEnd)")

          } catch let error as URLError where error.code == .userAuthenticationRequired {
              InboxView.logger.error("General inbox API fetch failed: Authentication required.")
              self.errorMessage = "Sitzung abgelaufen."; self.messages = []; self.canLoadMore = false
              await authService.logout()
          } catch {
              InboxView.logger.error("General inbox API fetch failed: \(error.localizedDescription)")
              self.errorMessage = "Fehler: \(error.localizedDescription)"; self.messages = []; self.canLoadMore = false
          }
      }

    @MainActor
    func loadMoreMessages() async {
        // --- MODIFIED: Logic for loadMoreMessages ---
        guard selectedMessageType != .privateMessages else {
            InboxView.logger.info("loadMoreMessages called, but privateMessages selected. Skipping general load more.")
            return
        }
        // --- END MODIFICATION ---

        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        // --- MODIFIED: Use the full 'messages' list for pagination ---
        guard let oldestMessageTimestamp = messages.last?.created else {
             InboxView.logger.warning("Cannot load more general messages: No last message found in the full list.")
             self.canLoadMore = false; return
        }
        // --- END MODIFICATION ---

        InboxView.logger.info("--- Starting loadMoreMessages (general) older than timestamp \(oldestMessageTimestamp) ---")
        self.isLoadingMore = true

        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; InboxView.logger.info("--- Finished loadMoreMessages (general) ---") } } }

        do {
            let response = try await apiService.fetchInboxMessages(older: oldestMessageTimestamp) // Fetch all types
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { return }

            if response.messages.isEmpty {
                InboxView.logger.info("Reached end of general inbox feed.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.messages.map { $0.id })
                let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }

                if uniqueNewMessages.isEmpty {
                    InboxView.logger.warning("All loaded general inbox messages were duplicates.")
                    self.canLoadMore = !response.atEnd
                } else {
                    // Append to the main 'messages' list, sorting will be applied if needed or handled by filteredMessages
                    self.messages.append(contentsOf: uniqueNewMessages)
                    self.messages.sort { $0.created > $1.created } // Re-sort after appending
                    InboxView.logger.info("Appended \(uniqueNewMessages.count) unique general inbox messages. Total: \(self.messages.count)")
                    self.canLoadMore = !response.atEnd
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            InboxView.logger.error("General inbox API fetch failed during loadMore: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false
            await authService.logout()
        } catch {
            InboxView.logger.error("General inbox API fetch failed during loadMore: \(error.localizedDescription)")
            guard self.isLoadingMore else { return }
            if self.messages.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }
    
    @MainActor
    func refreshConversations() async {
        InboxView.logger.info("Refreshing inbox conversations...")
        guard authService.isLoggedIn else {
            InboxView.logger.warning("Cannot refresh conversations: User not logged in.")
            self.conversations = []; self.conversationsError = "Bitte anmelden."
            return
        }
        self.isLoadingConversations = true
        self.conversationsError = nil
        defer { Task { @MainActor in self.isLoadingConversations = false } }

        do {
            let response = try await apiService.fetchInboxConversations()
            guard !Task.isCancelled else { return }
            self.conversations = response.conversations.sorted { $0.lastMessage > $1.lastMessage }
            InboxView.logger.info("Fetched \(response.conversations.count) conversations.")
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            InboxView.logger.error("Conversations API fetch failed: Authentication required.")
            self.conversationsError = "Sitzung abgelaufen."
            self.conversations = []
            await authService.logout()
        } catch {
            InboxView.logger.error("Conversations API fetch failed: \(error.localizedDescription)")
            self.conversationsError = "Fehler: \(error.localizedDescription)"
            self.conversations = []
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
        case "message": return message.name ?? "Nachricht" // Should not be displayed by this row if private messages have their own tab
        case "follow": return "\(message.name ?? "Jemand") folgt dir"
        default: return "Unbekannt (\(message.type ?? "N/A"))"
        }
    }

    private var titleOrMarkColor: Color {
        if message.type == "comment" || message.type == "follow" { // Removed "message"
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
            } else { // Default for "notification" or other types handled by this row
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
        
        let msg1 = InboxMessage(id: 1, type: "comment", itemId: 123, thumb: "thumb1.jpg", flags: 1, name: "UserA", mark: 2, senderId: 101, score: 5, created: Int(Date().timeIntervalSince1970 - 600), message: "Das ist ein Kommentar http://pr0gramm.com/new/543210 zur Benachrichtigung.", read: 0, blocked: 0, sent: 0)
        let msg2 = InboxMessage(id: 2, type: "notification", itemId: nil, thumb: nil, flags: nil, name: nil, mark: nil, senderId: 0, score: 0, created: Int(Date().timeIntervalSince1970 - 3600), message: "Systemnachricht: Dein pr0mium läuft bald ab!", read: 1, blocked: 0, sent: nil)
        let msg3 = InboxMessage(id: 3, type: "follow", itemId: nil, thumb: nil, flags: nil, name: "FollowerUser", mark: 1, senderId: 102, score: 0, created: Int(Date().timeIntervalSince1970 - 7200), message: nil, read: 0, blocked: 0, sent: nil)


        return InboxView(
            initialMessagesForPreview: [msg1, msg2, msg3], // Include follow message
            initialConversationsForPreview: sampleConversations
        )
            .environmentObject(settings)
            .environmentObject(authService)
    }
}
// --- END OF COMPLETE FILE ---
