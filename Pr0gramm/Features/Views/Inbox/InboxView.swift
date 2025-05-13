// Pr0gramm/Pr0gramm/Features/Views/Inbox/InboxView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

struct InboxView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State var messages: [InboxMessage] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    // --- MODIFIED: Separate state for item and target comment ID ---
    @State private var itemForNavigation: Item? = nil // Renamed from itemToNavigate
    @State private var targetCommentIDForNavigation: Int? = nil
    // --- END MODIFICATION ---

    @State private var profileToNavigate: String? = nil
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetId: Int? = nil // This is the itemID being loaded

    @State private var previewLinkTargetFromMessage: PreviewLinkTarget? = nil

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "InboxView")

    // --- NEW: NavigationLinkValue struct ---
    struct ItemNavigationValue: Hashable, Identifiable {
        let item: Item
        let targetCommentID: Int?
        var id: Int { item.id } // Main identifier for navigation is the item itself
    }
    @State private var itemNavigationValue: ItemNavigationValue? = nil
    // --- END NEW ---

    var body: some View {
        NavigationStack {
            Group {
                contentView
            }
            .navigationTitle("Nachrichten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil; isLoadingNavigationTarget = false; navigationTargetId = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
            .task {
                playerManager.configure(settings: settings)
                await refreshMessages()
            }
            // --- MODIFIED: Use ItemNavigationValue for navigation ---
            .navigationDestination(item: $itemNavigationValue) { navValue in
                 PagedDetailViewWrapperForItem(
                     item: navValue.item,
                     playerManager: playerManager,
                     targetCommentID: navValue.targetCommentID
                 )
                 .environmentObject(settings)
                 .environmentObject(authService)
            }
            // --- END MODIFICATION ---
            .navigationDestination(for: String.self) { username in
                 UserProfileSheetView(username: username)
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
                    ProgressView("Lade Post \(navigationTargetId ?? 0)...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        Group {
            if isLoading && messages.isEmpty {
                ProgressView("Lade Nachrichten...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, messages.isEmpty {
                 ContentUnavailableView { Label("Fehler", systemImage: "exclamationmark.triangle") }
                 description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await refreshMessages() } } }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty && !isLoading && errorMessage == nil {
                Text("Keine Nachrichten vorhanden.")
                    .foregroundColor(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(messages) { message in
                InboxMessageRow(message: message)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLoadingNavigationTarget, message.type != "notification" else {
                            InboxView.logger.debug("Tap ignored for message \(message.id): isLoadingNavigationTarget=\(isLoadingNavigationTarget) or type=\(message.type)")
                            return
                        }
                        Task { await handleMessageTap(message) }
                    }
                .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                .id(message.id)
                .onAppear {
                     if messages.count >= 2 && message.id == messages[messages.count - 2].id && canLoadMore && !isLoadingMore {
                         InboxView.logger.info("End trigger appeared for message \(message.id).")
                         Task { await loadMoreMessages() }
                     } else if messages.count == 1 && message.id == messages.first?.id && canLoadMore && !isLoadingMore {
                         InboxView.logger.info("End trigger appeared for the only message \(message.id).")
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
        errorMessage = nil
        InboxView.logger.info("Handling tap for message ID: \(message.id), Type: \(message.type)")

        switch message.type {
        case "comment":
            if let itemId = message.itemId {
                InboxView.logger.info("Message type is 'comment', preparing navigation for item \(itemId), target comment ID: \(message.id)")
                // --- MODIFIED: Set targetCommentIDForNavigation ---
                await prepareAndNavigateToItem(itemId, targetCommentID: message.id)
                // --- END MODIFICATION ---
            } else { InboxView.logger.warning("Comment message type tapped, but itemId is nil.") }

        case "message", "follow":
             if let senderName = message.name, !senderName.isEmpty {
                 InboxView.logger.info("Message type is '\(message.type)', navigating to profile: \(senderName)")
                 self.profileToNavigate = senderName
             } else { InboxView.logger.warning("\(message.type) message type tapped, but sender name is nil or empty.") }

        case "notification":
             InboxView.logger.debug("Notification message tapped - no navigation action defined.")
             break

        default:
            InboxView.logger.warning("Unhandled message type tapped: \(message.type)")
        }
    }

    @MainActor
    // --- MODIFIED: Add targetCommentID parameter ---
    private func prepareAndNavigateToItem(_ itemId: Int?, targetCommentID: Int? = nil) async {
    // --- END MODIFICATION ---
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
        self.navigationTargetId = id // This is the itemID being loaded
        self.errorMessage = nil
        // --- NEW: Reset targetCommentIDForNavigation before setting itemNavigationValue ---
        self.targetCommentIDForNavigation = targetCommentID
        // --- END NEW ---

        do {
            // For direct navigation to a post (e.g., from a comment notification),
            // we should try to load it with broad flags, as the user's current global filters
            // might hide it. flags=31 usually means SFW+NSFW+NSFL+NSFP+POL.
            let flagsToFetchWith = 31
            InboxView.logger.debug("Fetching item \(id) for navigation using flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard self.navigationTargetId == id else {
                 InboxView.logger.info("Navigation target changed while item \(id) was loading. Discarding result.")
                 self.isLoadingNavigationTarget = false; self.navigationTargetId = nil; self.targetCommentIDForNavigation = nil; return
            }
            if let item = fetchedItem {
                 InboxView.logger.info("Successfully fetched item \(id) for navigation.")
                 // --- MODIFIED: Set itemNavigationValue ---
                 self.itemNavigationValue = ItemNavigationValue(item: item, targetCommentID: self.targetCommentIDForNavigation)
                 // --- END MODIFICATION ---
            } else {
                 InboxView.logger.warning("Could not fetch item \(id) for navigation (API returned nil or filter mismatch).")
                 self.errorMessage = "Post \(id) konnte nicht geladen werden oder entspricht nicht den Filtern."
                 self.targetCommentIDForNavigation = nil // Reset if fetch fails
            }
        } catch is CancellationError {
             InboxView.logger.info("Item fetch for navigation cancelled (ID: \(id)).")
             self.targetCommentIDForNavigation = nil // Reset on cancellation
        } catch {
            InboxView.logger.error("Failed to fetch item \(id) for navigation: \(error.localizedDescription)")
            if self.navigationTargetId == id { // Check if this error is still relevant
                self.errorMessage = "Post \(id) konnte nicht geladen werden: \(error.localizedDescription)"
            }
            self.targetCommentIDForNavigation = nil // Reset on error
        }
        // Reset loading state only if this was the active target
        if self.navigationTargetId == id {
             self.isLoadingNavigationTarget = false
             self.navigationTargetId = nil
             // Do NOT reset self.targetCommentIDForNavigation here, it's used by itemNavigationValue
        }
    }

      @MainActor
      func refreshMessages() async {
          InboxView.logger.info("Refreshing inbox messages...")
          guard authService.isLoggedIn else {
              InboxView.logger.warning("Cannot refresh inbox: User not logged in.")
              self.messages = []; self.errorMessage = "Bitte anmelden."
              return
          }

          self.isLoadingNavigationTarget = false; self.navigationTargetId = nil
          self.isLoading = true; self.errorMessage = nil
          // --- NEW: Reset navigation values on refresh ---
          self.itemNavigationValue = nil
          self.targetCommentIDForNavigation = nil
          // --- END NEW ---


          defer { Task { @MainActor in self.isLoading = false } }

          do {
              let response = try await apiService.fetchInboxMessages(older: nil)
              guard !Task.isCancelled else { return }

              self.messages = response.messages.sorted { $0.created > $1.created }
              self.canLoadMore = !response.atEnd
              InboxView.logger.info("Fetched \(response.messages.count) initial inbox messages. AtEnd: \(response.atEnd)")

          } catch let error as URLError where error.code == .userAuthenticationRequired {
              InboxView.logger.error("Inbox API fetch failed: Authentication required.")
              self.errorMessage = "Sitzung abgelaufen."; self.messages = []; self.canLoadMore = false
              await authService.logout()
          } catch {
              InboxView.logger.error("Inbox API fetch failed: \(error.localizedDescription)")
              self.errorMessage = "Fehler: \(error.localizedDescription)"; self.messages = []; self.canLoadMore = false
          }
      }

    @MainActor
    func loadMoreMessages() async {
        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else { return }
        guard let oldestMessageTimestamp = messages.last?.created else {
             InboxView.logger.warning("Cannot load more inbox messages: No last message found.")
             self.canLoadMore = false; return
        }

        InboxView.logger.info("--- Starting loadMoreMessages older than timestamp \(oldestMessageTimestamp) ---")
        self.isLoadingMore = true

        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; InboxView.logger.info("--- Finished loadMoreMessages ---") } } }

        do {
            let response = try await apiService.fetchInboxMessages(older: oldestMessageTimestamp)
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { return }

            if response.messages.isEmpty {
                InboxView.logger.info("Reached end of inbox feed.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.messages.map { $0.id })
                let uniqueNewMessages = response.messages.filter { !currentIDs.contains($0.id) }

                if uniqueNewMessages.isEmpty {
                    InboxView.logger.warning("All loaded inbox messages were duplicates.")
                    self.canLoadMore = !response.atEnd
                } else {
                    self.messages.append(contentsOf: uniqueNewMessages)
                    self.messages.sort { $0.created > $1.created }
                    InboxView.logger.info("Appended \(uniqueNewMessages.count) unique inbox messages. Total: \(self.messages.count)")
                    self.canLoadMore = !response.atEnd
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            InboxView.logger.error("Inbox API fetch failed during loadMore: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."; self.canLoadMore = false
            await authService.logout()
        } catch {
            InboxView.logger.error("Inbox API fetch failed during loadMore: \(error.localizedDescription)")
            guard self.isLoadingMore else { return }
            if self.messages.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false
        }
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
        default: return "Unbekannt"
        }
    }

    private var titleOrMarkColor: Color {
        if message.type == "comment" || message.type == "message" || message.type == "follow" {
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
                Text(attributedMessageContent)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    var body: some View {
        let msg1 = InboxMessage(id: 1, type: "comment", itemId: 123, thumb: "thumb1.jpg", flags: 1, name: "UserA", mark: 2, senderId: 101, score: 5, created: Int(Date().timeIntervalSince1970 - 600), message: "Das ist ein Kommentar http://pr0gramm.com/new/543210 zur Benachrichtigung. Und noch ein Link https://example.com", read: 0, blocked: 0)
        let msg2 = InboxMessage(id: 2, type: "notification", itemId: nil, thumb: nil, flags: nil, name: nil, mark: nil, senderId: 0, score: 0, created: Int(Date().timeIntervalSince1970 - 3600), message: "Systemnachricht: Dein pr0mium läuft bald ab!", read: 1, blocked: 0)
        let msg3 = InboxMessage(id: 3, type: "follow", itemId: nil, thumb: nil, flags: nil, name: "FollowerDude", mark: 1, senderId: 102, score: 0, created: Int(Date().timeIntervalSince1970 - 7200), message: nil, read: 0, blocked: 0)
        let msg4 = InboxMessage(id: 4, type: "message", itemId: nil, thumb: nil, flags: nil, name: "ChattyCathy", mark: 7, senderId: 103, score: 0, created: Int(Date().timeIntervalSince1970 - 86400), message: "Hallo! Wie geht es dir? Schau mal hier: www.pr0gramm.com/new/112233 .", read: 0, blocked: 0)


        let view = InboxView()
        view.messages = [msg1, msg2, msg3, msg4].sorted { $0.created > $1.created }

        return NavigationStack {
            view
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }
}
// --- END OF COMPLETE FILE ---
