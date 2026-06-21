// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Combine // Für Keyboard-Notifications

struct ConversationDetailView: View {
    let partnerUsername: String

    @Environment(AppSettings.self) var settings
    @Environment(AuthService.self) var authService
    @Environment(VideoPlayerManager.self) var playerManager
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var pendingAutoScrollToBottom = false
    // --- END NEUE STATE VARIABLEN ---

    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationDetailView")
    private let bottomAnchorID = "ConversationBottomAnchor"

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
        .background(chatBackground)
        .navigationTitle(partnerUsername)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Material.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                conversationHeader
            }
        }
        .task {
            await refreshMessages()
        }
        .navigationDestination(item: $itemNavigationValue) { navValue in
             PagedDetailViewWrapperForItem(
                 item: navValue.item,
                 playerManager: playerManager,
                 targetCommentID: navValue.targetCommentID
             )
             .environment(settings)
             .environment(authService)
        }
        .sheet(item: $previewLinkTargetFromMessage) { target in
            LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                .environment(settings)
                .environment(authService)
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
        .onChange(of: isTextEditorFocused) { _, focused in
            if focused {
                shouldScrollToBottom = true
                scrollToBottomIfNeeded(force: true)
            }
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
    
    private func scrollToBottomIfNeeded(force: Bool = false) {
        guard self.scrollViewProxy != nil else { return }
        
        // Nur scrollen wenn der User nicht gerade manuell scrollt
        let now = Date()
        if !force, now.timeIntervalSince(lastScrollTime) < 1.0 && isUserScrolling {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.smooth(duration: 0.3)) {
                self.scrollViewProxy?.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            ConversationDetailView.logger.debug("Scrolled to bottom anchor.")
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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if isLoadingMore {
                            ProgressView("Lade ältere...")
                                .font(.footnote)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.thinMaterial, in: Capsule())
                                .padding(.top, 8)
                        }

                        if let error = errorMessage {
                            inlineErrorBanner(error)
                        }

                        if messages.isEmpty && !isLoading && !isLoadingMore && errorMessage == nil {
                            Text("Keine Nachrichten in dieser Konversation.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                                .padding(.top, 24)
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
                                .padding(.top, index == 0 ? 8 : 0)
                            }
                        }

                        Color.clear
                            .frame(height: max(textFieldHeight * 0.2, 10))
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refreshMessages() }
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
                .onAppear {
                    self.scrollViewProxy = proxy
                    pendingAutoScrollToBottom = true
                    scrollToBottomIfNeeded(force: true)
                }
                .onChange(of: messages.last?.id) { oldValue, newValue in
                    guard newValue != nil else { return }
                    if pendingAutoScrollToBottom || (oldValue != newValue && oldValue != nil) {
                        shouldScrollToBottom = true
                        scrollToBottomIfNeeded(force: true)
                        pendingAutoScrollToBottom = false
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

        VStack(spacing: 8) {
            if let err = sendingError {
                Text("Senden fehlgeschlagen: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Nachricht eingeben...", text: $newMessageText, axis: .vertical)
                    .focused($isTextEditorFocused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .tint(settings.accentColorChoice.swiftUIColor)
                    .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
                    .background(
                        GeometryReader { geometry in
                            textFieldGlassBackground
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
                        if isTextEditorFocused && !newValue.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottomIfNeeded(force: true)
                            }
                        }
                    }

                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSendingMessage {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(sendButtonForegroundStyle)
                            .frame(width: 45, height: 45)
                            .background(sendButtonBackground)
                    }
                }
                .buttonStyle(.plain)
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingMessage)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, bottomPaddingForInput)
        }
        .background(inputBackground)
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                clearErrors()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fehler ausblenden")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            self.pendingAutoScrollToBottom = true
            ConversationDetailView.logger.info("Fetched \(response.messages.count) initial messages with \(partnerUsername). AtEnd: \(response.atEnd)")
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            handleAuthError(error: error, context: "refreshing messages")
        } catch {
            ConversationDetailView.logger.error("Failed to refresh messages with \(partnerUsername): \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
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
                self.pendingAutoScrollToBottom = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.scrollToBottomIfNeeded(force: true)
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

    private var chatBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                settings.accentColorChoice.swiftUIColor.opacity(0.06),
                Color(uiColor: .secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var conversationHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Mark(rawValue: conversationPartner?.mark ?? 0).displayColor)
                .frame(width: 10, height: 10)
            Text(conversationPartner?.name ?? partnerUsername)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(ConversationGlassCapsuleModifier())
    }

    private var inputBackground: some View {
        Rectangle()
            .fill(.clear)
    }

    private var sendButtonForegroundStyle: some ShapeStyle {
        newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white)
    }

    @ViewBuilder
    private var textFieldGlassBackground: some View {
        Capsule()
            .fill(.clear)
            .overlay {
                Capsule()
                    .strokeBorder(textFieldBorderColor, lineWidth: 0.8)
            }
    }

    private var textFieldBorderColor: Color {
        colorScheme == .light ? .black.opacity(0.22) : .white.opacity(0.18)
    }

    @ViewBuilder
    private var sendButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(
                    newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .regular.tint(.white.opacity(0.08))
                    : .regular.tint(settings.accentColorChoice.swiftUIColor).interactive(),
                    in: .circle
                )
        } else {
            Circle()
                .fill(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(uiColor: .systemGray4) : settings.accentColorChoice.swiftUIColor)
        }
    }
}

struct ConversationMessageRow: View {
    let message: PrivateMessage
    let isSentByCurrentUser: Bool
    let currentUserMark: Int
    let currentUsername: String
    let partnerMark: Int
    let partnerName: String

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationMessageRowLocal")

    private var bubbleTint: Color {
        isSentByCurrentUser ? Color.accentColor : Mark(rawValue: senderMarkValue).displayColor.opacity(0.16)
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
        HStack(alignment: .bottom, spacing: 8) {
            if !isSentByCurrentUser {
                avatarView
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: isSentByCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isSentByCurrentUser {
                    Text(senderDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                Text(attributedMessageContent)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(minWidth: 50, maxWidth: UIScreen.main.bounds.width * 0.75,
                           alignment: isSentByCurrentUser ? .trailing : .leading)
                
                HStack(spacing: 4) {
                    Text(formattedTimestamp(for: message.created))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
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

    @ViewBuilder
    private var bubbleBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    isSentByCurrentUser
                    ? .regular.tint(bubbleTint).interactive()
                    : .regular.tint(.white.opacity(0.6)),
                    in: .rect(cornerRadius: 24)
                )
                .overlay {
                    if !isSentByCurrentUser {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isSentByCurrentUser ? bubbleTint : Color(uiColor: .secondarySystemBackground))
        }
    }
}

private struct ConversationGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}


// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var settings = AppSettings()
        @State private var authService: AuthService
        @State private var playerManager = VideoPlayerManager()

        init() {
            let s = AppSettings()
            let a = AuthService(appSettings: s)
            a.isLoggedIn = true
            a.currentUser = UserInfo(id: 1, name: "CurrentUser", registered: 1, score: 100, mark: 0, badges: [])
            a.userNonce = "preview_nonce_123"
            _authService = State(wrappedValue: a)
            _settings = State(wrappedValue: s)
            let pm = VideoPlayerManager()
            pm.configure(settings: s)
            _playerManager = State(wrappedValue: pm)
        }

        var body: some View {
            NavigationStack {
                ConversationDetailView(partnerUsername: "PartnerUser")
                    .environment(settings)
                    .environment(authService)
                    .environment(playerManager)
            }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
