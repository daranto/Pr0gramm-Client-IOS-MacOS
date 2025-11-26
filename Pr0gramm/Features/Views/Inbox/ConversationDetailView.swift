// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Combine // Für Keyboard-Notifications

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
    
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardIsAnimating: Bool = false
    
    // --- NEUE STATE VARIABLEN FÜR VERBESSERTE SCROLL-FUNKTION ---
    @State private var textFieldHeight: CGFloat = 44 // Standard-Höhe für einzeiliges TextField
    @State private var previousTextFieldHeight: CGFloat = 44
    @State private var shouldScrollToBottom: Bool = false
    @State private var scrollViewContentOffset: CGFloat = 0
    @State private var isUserScrolling: Bool = false
    @State private var lastScrollTime: Date = Date()
    // --- END NEUE STATE VARIABLEN ---

    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationDetailView")

    @State private var scrollViewProxy: ScrollViewProxy? = nil

    var body: some View {
        VStack(spacing: 0) {
            buildMessageList()
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
        // --- VERBESSERTE KEYBOARD NOTIFICATIONS ---
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            handleKeyboardWillShow(notification: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { notification in
            handleKeyboardDidShow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            handleKeyboardWillHide(notification: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            handleKeyboardDidHide()
        }
        // --- END VERBESSERTE KEYBOARD NOTIFICATIONS ---
    }
    
    // --- NEUE KEYBOARD HANDLING METHODEN ---
    private func handleKeyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        
        let safeAreaBottom = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 0
        let newHeight = keyboardFrame.height - safeAreaBottom
        
        if self.keyboardHeight != newHeight {
            self.keyboardIsAnimating = true
            self.shouldScrollToBottom = true
            
            withAnimation(.linear(duration: animationDuration)) {
                self.keyboardHeight = newHeight
            }
            ConversationDetailView.logger.debug("Keyboard WILL SHOW. New height: \(newHeight)")
        }
    }
    
    private func handleKeyboardDidShow() {
        if keyboardIsAnimating && shouldScrollToBottom {
            scrollToBottomIfNeeded()
            keyboardIsAnimating = false
            shouldScrollToBottom = false
        }
    }
    
    private func handleKeyboardWillHide(notification: Notification) {
        guard let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        
        if self.keyboardHeight != 0 {
            self.keyboardIsAnimating = true
            withAnimation(.linear(duration: animationDuration)) {
                self.keyboardHeight = 0
            }
            ConversationDetailView.logger.debug("Keyboard WILL HIDE")
        }
    }
    
    private func handleKeyboardDidHide() {
        if keyboardIsAnimating {
            keyboardIsAnimating = false
            // Nach dem Verstecken der Tastatur nur scrollen wenn nötig
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.scrollToBottomIfNeeded()
            }
        }
    }
    
    private func scrollToBottomIfNeeded() {
        guard let lastMessageId = messages.last?.id,
              let proxy = self.scrollViewProxy else { return }
        
        // Nur scrollen wenn der User nicht gerade manuell scrollt
        let now = Date()
        if now.timeIntervalSince(lastScrollTime) < 1.0 && isUserScrolling {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.smooth(duration: 0.3)) {
                proxy.scrollTo(lastMessageId, anchor: .bottom)
            }
            ConversationDetailView.logger.debug("Scrolled to bottom message ID: \(lastMessageId)")
        }
    }
    
    private func handleTextFieldSizeChange() {
        let heightDifference = textFieldHeight - previousTextFieldHeight
        
        // Wenn das Textfeld wächst, nach unten scrollen
        if heightDifference > 0 && isTextEditorFocused {
            shouldScrollToBottom = true
            scrollToBottomIfNeeded()
        }
        
        previousTextFieldHeight = textFieldHeight
    }
    // --- END NEUE KEYBOARD HANDLING METHODEN ---
    
    @ViewBuilder
    private func buildMessageList() -> some View {
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
        } else {
            ScrollViewReader { proxy in
                List {
                    if isLoadingMore {
                        HStack { Spacer(); ProgressView("Lade ältere..."); Spacer() }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 8)
                    }
                    
                    if messages.isEmpty && !isLoading && !isLoadingMore && errorMessage == nil {
                        Section {
                            Text("Keine Nachrichten in dieser Konversation.")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            ConversationMessageRow(
                                message: message,
                                isSentByCurrentUser: message.sent == 1,
                                currentUserMark: authService.currentUser?.mark ?? 0,
                                currentUsername: authService.currentUser?.name ?? "Ich",
                                partnerMark: conversationPartner?.mark ?? 0,
                                partnerName: conversationPartner?.name ?? partnerUsername
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: index == 0 ? 15 : 3,
                                leading: 10,
                                bottom: 3,
                                trailing: 10
                            ))
                            .listRowBackground(Color.clear)
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
                    
                    // --- VERBESSERTER KEYBOARD SPACER MIT DYNAMISCHER HÖHE ---
                    Color.clear
                        .frame(height: max(keyboardHeight, 0))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .id("KeyboardSpacer")
                    // --- END VERBESSERTER KEYBOARD SPACER ---
                }
                .listStyle(.plain)
                .background(Color(UIColor.systemGroupedBackground))
                .scrollContentBackground(.hidden)
                .refreshable { await refreshMessages() }
                // --- VERBESSERTE SCROLL DETECTION ---
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            isUserScrolling = true
                            lastScrollTime = Date()
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isUserScrolling = false
                            }
                        }
                )
                // --- END VERBESSERTE SCROLL DETECTION ---
                .onAppear {
                    self.scrollViewProxy = proxy
                    if let lastMessageId = messages.last?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: messages.count) { oldValue, newValue in
                    // Nur bei neuen Nachrichten automatisch scrollen
                    if newValue > oldValue {
                        shouldScrollToBottom = true
                        scrollToBottomIfNeeded()
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
                // --- VERBESSERTES TEXTFIELD MIT HÖHEN-TRACKING ---
                TextField("Nachricht eingeben...", text: $newMessageText, axis: .vertical)
                    .focused($isTextEditorFocused)
                    .textFieldStyle(.plain)
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
                    .background(
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(uiColor: .systemGray5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color(uiColor: .systemGray3), lineWidth: 0.5)
                                )
                                .onAppear {
                                    textFieldHeight = geometry.size.height
                                }
                                .onChange(of: geometry.size.height) { oldHeight, newHeight in
                                    if abs(newHeight - textFieldHeight) > 1 {
                                        textFieldHeight = newHeight
                                        handleTextFieldSizeChange()
                                    }
                                }
                        }
                    )
                    .lineLimit(1...6)
                    .accessibilityLabel("Nachricht eingeben")
                    .onChange(of: newMessageText) { oldValue, newValue in
                        // Bei Textänderungen nach kurzer Verzögerung scrollen
                        if isTextEditorFocused && !newValue.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottomIfNeeded()
                            }
                        }
                    }
                // --- END VERBESSERTES TEXTFIELD ---
                
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
        // --- ÄNDERUNG: Material.bar statt .thinMaterial für konsistentes Liquid Glass Design ---
        .background(Material.bar)
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
                // Nach dem Senden automatisch nach unten scrollen
                shouldScrollToBottom = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.scrollToBottomIfNeeded()
                }
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

// MARK: - ConversationMessageRow bleibt unverändert
struct ConversationMessageRow: View {
    let message: PrivateMessage
    let isSentByCurrentUser: Bool
    let currentUserMark: Int
    let currentUsername: String
    let partnerMark: Int
    let partnerName: String

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationMessageRowLocal")

    private var backgroundColor: Color {
        isSentByCurrentUser ? Color.accentColor : Color(uiColor: .systemGray5)
    }

    private var textColorForBubble: Color {
        isSentByCurrentUser ? .white : .primary
    }
    
    private var senderDisplayName: String {
        isSentByCurrentUser ? currentUsername : partnerName
    }
    
    private var senderMarkValue: Int {
        isSentByCurrentUser ? currentUserMark : partnerMark
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
        let initials = getInitials(from: senderDisplayName)
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
        HStack(alignment: .bottom, spacing: 6) {
            if !isSentByCurrentUser {
                avatarView
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: isSentByCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(attributedMessageContent)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(minWidth: 50, maxWidth: UIScreen.main.bounds.width * 0.75,
                           alignment: isSentByCurrentUser ? .trailing : .leading)
                
                HStack(spacing: 4) {
                    Text(formattedTimestamp(for: message.created))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 0)
                .frame(maxWidth: .infinity, alignment: isSentByCurrentUser ? .trailing : .leading)
            }
            
            if isSentByCurrentUser {
                avatarView
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isSentByCurrentUser ? .trailing : .leading)
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
