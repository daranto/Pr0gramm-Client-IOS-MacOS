// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

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
    
    @State private var itemNavigationValue: ItemNavigationValue? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil
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
            LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                .environmentObject(settings)
                .environmentObject(authService)
        }
        .overlay {
            if isLoadingNavigationTarget {
                ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
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
            messageList // Verwendet jetzt die aufgeteilte View-Funktion
        }
    }

    // --- MODIFIED: messageList in eine eigene Funktion ausgelagert ---
    @ViewBuilder
    private func messageListBody(proxy: ScrollViewProxy) -> some View {
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
            if let (itemID, commentID) = parsePr0grammLink(url: url) {
                ConversationDetailView.logger.info("Pr0gramm link tapped in conversation, attempting to preview item ID: \(itemID), commentID: \(commentID ?? -1)")
                self.previewLinkTargetFromMessage = PreviewLinkTarget(itemID: itemID, commentID: commentID)
                return .handled
            } else {
                ConversationDetailView.logger.info("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            messageListBody(proxy: proxy) // Aufruf der neuen Funktion
        }
    }
    // --- END MODIFICATION ---
    
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

        ConversationDetailView.logger.warning("Could not parse item or comment ID from pr0gramm link: \(url.absoluteString)")
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
        navigationTargetItemId = nil
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

// ConversationMessageRow sollte jetzt global in InboxView.swift definiert sein.

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
