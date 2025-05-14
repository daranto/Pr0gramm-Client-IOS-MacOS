// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// Displays the messages within a specific private conversation and allows the user to send new messages.
struct ConversationDetailView: View {
    let partnerUsername: String

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var playerManager: VideoPlayerManager

    @State private var messages: [PrivateMessage] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    
    @State private var newMessageText: String = ""
    @State private var isSendingMessage = false
    @State private var sendingError: String? = nil

    @State private var conversationPartner: InboxConversationUser? = nil
    
    @State private var itemNavigationValue: InboxView.ItemNavigationValue? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    // --- MODIFIED: Deklaration von navigationTargetItemId hinzugefügt/sichergestellt ---
    @State private var navigationTargetItemId: Int? = nil // ItemID für Ladeanzeige des Navigationsziels
    // --- END MODIFICATION ---
    @State private var previewLinkTargetFromMessage: PreviewLinkTarget? = nil

    @FocusState private var isTextEditorFocused: Bool


    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationDetailView")

    var body: some View {
        VStack(spacing: 0) {
            messageListContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    isTextEditorFocused = false
                }
            messageInputView
        }
        .navigationTitle(partnerUsername)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(
            Material.bar,
            for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading && !isSendingMessage)) {
            Button("OK") { clearErrors() }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task {
            await refreshMessages()
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
        .sheet(item: $previewLinkTargetFromMessage) { target in
            LinkedItemPreviewView(itemID: target.id)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .overlay {
            if isLoadingNavigationTarget {
                // --- MODIFIED: Verwende navigationTargetItemId korrekt ---
                ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
                // --- END MODIFICATION ---
                    .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var messageListContentView: some View {
        if isLoading && messages.isEmpty {
            ProgressView("Lade Nachrichten mit \(partnerUsername)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, messages.isEmpty {
            ContentUnavailableView {
                Label("Fehler", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("Erneut versuchen") { Task { await refreshMessages() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty && !isLoading && errorMessage == nil {
            VStack {
                Spacer()
                Text("Keine Nachrichten in dieser Konversation.")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable { await refreshMessages() }
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                if isLoadingMore {
                    HStack { Spacer(); ProgressView("Lade ältere..."); Spacer() }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                }
                ForEach(messages) { message in
                    ConversationMessageRow(
                        message: message,
                        isSentByCurrentUser: message.sent == 1,
                        currentUserMark: authService.currentUser?.mark ?? 0,
                        partnerMark: conversationPartner?.mark ?? 0,
                        partnerName: conversationPartner?.name ?? partnerUsername
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                    .id(message.id)
                    .onAppear {
                        if message.id == messages.first?.id && canLoadMore && !isLoadingMore && !isLoading {
                            ConversationDetailView.logger.info("Near top of conversation (message \(message.id)), loading older messages.")
                            Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                await loadMoreMessages()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .refreshable { await refreshMessages() }
            .onAppear {
                if let lastMessageId = messages.last?.id {
                    proxy.scrollTo(lastMessageId, anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { oldValue, newValue in
                if newValue > oldValue, let lastMessageId = messages.last?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.smooth(duration: 0.2)) {
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                } else if newValue < oldValue {
                     if let lastMessageId = messages.last?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.smooth(duration: 0.2)) {
                                proxy.scrollTo(lastMessageId, anchor: .bottom)
                            }
                        }
                     }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                if let itemID = parsePr0grammLink(url: url) {
                    ConversationDetailView.logger.info("Pr0gramm link tapped in conversation, attempting to preview item ID: \(itemID)")
                    self.previewLinkTargetFromMessage = PreviewLinkTarget(id: itemID)
                    return .handled
                } else {
                    ConversationDetailView.logger.info("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                    return .systemAction
                }
            })
        }
    }
    
    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() { if let itemID = Int(component) { return itemID } }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems { if item.name == "id", let value = item.value, let itemID = Int(value) { return itemID } }
        }
        ConversationDetailView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }

    @ViewBuilder
    private var messageInputView: some View {
        let bottomPaddingForInput: CGFloat = UIConstants.isRunningOnMac ? 0 : 5

        VStack(spacing: 4) {
             if let err = sendingError {
                Text("Senden fehlgeschlagen: \(err)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $newMessageText)
                    .focused($isTextEditorFocused)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .systemGray5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(uiColor: .systemGray3), lineWidth: 0.5)
                            )
                    )
                    .frame(minHeight: 38, maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Nachricht eingeben")
                
                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSendingMessage {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .foregroundColor(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                    }
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingMessage)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, bottomPaddingForInput)
        }
    }

    private func clearErrors() {
        errorMessage = nil
        sendingError = nil
        isLoadingNavigationTarget = false
        // --- MODIFIED: navigationTargetItemId auch hier zurücksetzen ---
        navigationTargetItemId = nil
        // --- END MODIFICATION ---
    }

    @MainActor
    func refreshMessages() async {
        ConversationDetailView.logger.info("Refreshing messages for conversation with \(partnerUsername)")
        guard authService.isLoggedIn else {
            ConversationDetailView.logger.warning("Cannot refresh messages: User not logged in.")
            self.errorMessage = "Bitte anmelden."
            return
        }
        self.isLoading = true
        self.errorMessage = nil
        self.canLoadMore = true

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let response = try await apiService.fetchInboxMessagesWithUser(username: partnerUsername)
            guard !Task.isCancelled else { return }
            
            self.messages = response.messages.sorted { $0.created < $1.created }
            self.canLoadMore = !response.atEnd
            self.conversationPartner = response.with
            ConversationDetailView.logger.info("Fetched \(response.messages.count) initial messages with \(partnerUsername). AtEnd: \(response.atEnd)")
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            handleAuthError(error: error, context: "refreshing messages")
        } catch {
            ConversationDetailView.logger.error("Failed to refresh messages with \(partnerUsername): \(error.localizedDescription)")
            self.errorMessage = "Fehler: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadMoreMessages() async {
        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let oldestMessageTimestamp = messages.first?.created else {
            ConversationDetailView.logger.warning("Cannot load more messages with \(partnerUsername): No oldest message found.")
            self.canLoadMore = false; return
        }

        ConversationDetailView.logger.info("Loading more messages with \(partnerUsername) older than timestamp \(oldestMessageTimestamp)")
        self.isLoadingMore = true

        defer { Task { @MainActor in self.isLoadingMore = false } }

        do {
            let response = try await apiService.fetchInboxMessagesWithUser(username: partnerUsername, older: oldestMessageTimestamp)
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { return }

            if response.messages.isEmpty {
                ConversationDetailView.logger.info("Reached end of message history with \(partnerUsername).")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.messages.map { $0.id })
                let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }
                
                if !uniqueNewMessages.isEmpty {
                    let combinedMessages = (uniqueNewMessages + self.messages).sorted { $0.created < $1.created }
                    self.messages = combinedMessages
                    ConversationDetailView.logger.info("Prepended \(uniqueNewMessages.count) older messages with \(partnerUsername). Total: \(self.messages.count)")
                }
                self.canLoadMore = !response.atEnd
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            handleAuthError(error: error, context: "loading more messages")
        } catch {
            ConversationDetailView.logger.error("Failed to load more messages with \(partnerUsername): \(error.localizedDescription)")
            if self.messages.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
    }
    
    @MainActor
    func sendMessage() async {
        let textToSend = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty, authService.isLoggedIn, let nonce = authService.userNonce else {
            ConversationDetailView.logger.warning("Cannot send message: Not logged in, no nonce, or message empty.")
            self.sendingError = "Senden nicht möglich."
            return
        }
        
        self.isSendingMessage = true
        self.sendingError = nil
        isTextEditorFocused = false
        
        do {
            let response: PostPrivateMessageAPIResponse = try await apiService.postPrivateMessage(to: partnerUsername, messageText: textToSend, nonce: nonce)
            guard !Task.isCancelled else { return }
            
            if response.success {
                ConversationDetailView.logger.info("Successfully sent message to \(partnerUsername). API returned success. Updating messages from response.")
                self.newMessageText = ""
                self.messages = response.messages.sorted { $0.created < $1.created }
            } else {
                let apiError = "Unbekannter Fehler beim Senden (API success:false)."
                ConversationDetailView.logger.error("Failed to send message to \(partnerUsername): \(apiError)")
                self.sendingError = apiError
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            handleAuthError(error: error, context: "sending message")
            self.sendingError = "Sitzung abgelaufen."
        } catch {
            ConversationDetailView.logger.error("Error sending message to \(partnerUsername): \(error.localizedDescription)")
            self.sendingError = error.localizedDescription
        }
        self.isSendingMessage = false
    }
    
    @MainActor
    private func handleAuthError(error: Error, context: String) {
        ConversationDetailView.logger.error("Authentication error while \(context) for \(partnerUsername): \(error.localizedDescription)")
        self.errorMessage = "Sitzung abgelaufen."
        self.messages = []
        self.canLoadMore = false
        Task { await authService.logout() }
    }
}


struct ConversationMessageRow: View {
    let message: PrivateMessage
    let isSentByCurrentUser: Bool
    let currentUserMark: Int
    let partnerMark: Int
    let partnerName: String

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationMessageRow")
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
            ConversationMessageRow.logger.error("Error creating NSDataDetector in ConversationMessageRow: \(error.localizedDescription)")
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


// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService
        @StateObject private var playerManager = VideoPlayerManager()

        init() {
            let s = AppSettings()
            let a = AuthService(appSettings: s)
            a.isLoggedIn = true
            a.currentUser = UserInfo(id: 1, name: "CurrentUser", registered: 1, score: 100, mark: 0, badges: [])
            a.userNonce = "preview_nonce_123"
            _authService = StateObject(wrappedValue: a)
            _settings = StateObject(wrappedValue: s)
            let pm = VideoPlayerManager()
            pm.configure(settings: s)
            _playerManager = StateObject(wrappedValue: pm)
        }

        var body: some View {
            NavigationStack {
                ConversationDetailView(partnerUsername: "PartnerUser")
                    .environmentObject(settings)
                    .environmentObject(authService)
                    .environmentObject(playerManager)
            }
        }
    }
    return PreviewWrapper()
}

// --- END OF COMPLETE FILE ---
