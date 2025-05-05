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

    // Navigation State für Detailansichten
    @State private var itemToNavigate: Item? = nil
    @State private var profileToNavigate: String? = nil // Für Usernamen
    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetId: Int? = nil // Kann ItemID oder UserID sein, je nach Kontext

    @StateObject private var playerManager = VideoPlayerManager() // Für PagedDetailView

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "InboxView")

    var body: some View {
        NavigationStack { // Eigene NavigationStack für diese Ansicht
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
                playerManager.configure(settings: settings) // PlayerManager konfigurieren
                await refreshMessages()
            }
            // Navigation für Items (Kommentare, Follows)
            .navigationDestination(item: $itemToNavigate) { loadedItem in
                 PagedDetailViewWrapperForItem(item: loadedItem, playerManager: playerManager)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
            // Navigation für User-Profile (PMs, Follows)
            .navigationDestination(for: String.self) { username in
                 UserProfileViewWrapper(username: username) // Wrapper für Profilansicht
                      .environmentObject(settings)
                      .environmentObject(authService)
            }
            .overlay { // Ladeindikator für Navigation
                if isLoadingNavigationTarget {
                    ProgressView("Lade Ziel...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
        }
    }

    // MARK: - Content Views
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
                Button {
                    Task { await handleMessageTap(message) }
                } label: {
                    InboxMessageRow(message: message)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingNavigationTarget || message.type == "notification") // Deaktiviere Klick für reine Notifications
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
            } // Ende ForEach

            if isLoadingMore {
                HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                    .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .refreshable { await refreshMessages() }
    }

    // MARK: - Navigation Helper
    @MainActor
    private func handleMessageTap(_ message: InboxMessage) async {
        guard !isLoadingNavigationTarget else { return }
        errorMessage = nil // Clear previous errors

        switch message.type {
        case "comment":
            if let itemId = message.itemId {
                navigationTargetId = itemId // Track what we are loading
                isLoadingNavigationTarget = true
                do {
                    let fetchedItem = try await apiService.fetchItem(id: itemId, flags: settings.apiFlags)
                    guard navigationTargetId == itemId else { // Check if still relevant
                         InboxView.logger.info("Navigation target changed while item \(itemId) was loading.")
                         isLoadingNavigationTarget = false; navigationTargetId = nil; return
                    }
                    if let item = fetchedItem { itemToNavigate = item /* Trigger Navigation */ }
                    else { errorMessage = "Post \(itemId) konnte nicht geladen werden." }
                } catch { errorMessage = "Fehler beim Laden von Post \(itemId): \(error.localizedDescription)" }
                isLoadingNavigationTarget = false; navigationTargetId = nil
            } else { InboxView.logger.warning("Comment message type tapped, but itemId is nil.") }

        case "message", "follow":
             // Für PMs oder Follows wollen wir zum Profil des Senders navigieren
             if let senderName = message.name, !senderName.isEmpty {
                 profileToNavigate = senderName // Trigger Navigation via .navigationDestination(for: String.self)
             } else { InboxView.logger.warning("\(message.type) message type tapped, but sender name is nil or empty.") }

        case "notification":
             InboxView.logger.debug("Notification message tapped - no navigation action defined.")
             // Hier könnte man ggf. Links im Notification-Text parsen und öffnen
             break

        default:
            InboxView.logger.warning("Unhandled message type tapped: \(message.type)")
        }
    }

    // MARK: - Data Loading Methods
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

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let response = try await apiService.fetchInboxMessages(older: nil) // Initial load
            guard !Task.isCancelled else { return }
            self.messages = response.messages.sorted { $0.created > $1.created } // Sortiere nach Datum absteigend
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
                    // Füge neue Nachrichten hinzu und sortiere erneut
                    self.messages.append(contentsOf: uniqueNewMessages)
                    self.messages.sort { $0.created > $1.created } // Nach Datum absteigend sortieren
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

// MARK: - Inbox Message Row View
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

    // Bestimme den Titel basierend auf dem Typ
    private var title: String {
        switch message.type {
        case "comment": return message.name ?? "Kommentar"
        case "notification": return "Systemnachricht"
        case "message": return message.name ?? "Nachricht"
        case "follow": return "\(message.name ?? "Jemand") folgt dir"
        default: return "Unbekannt"
        }
    }

    // Bestimme die Farbe für den Titel oder den Mark-Indikator
    private var titleOrMarkColor: Color {
        if message.type == "comment" || message.type == "message" || message.type == "follow" {
            return Mark(rawValue: message.mark ?? -1).displayColor
        }
        return .secondary // Für Notifications
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Thumbnail (nur für Kommentare)
            if message.type == "comment" {
                KFImage(message.itemThumbnailUrl)
                    .resizable().placeholder { Color.gray.opacity(0.1) }
                    .aspectRatio(contentMode: .fill).frame(width: 50, height: 50)
                    .clipped().cornerRadius(4)
            } else if message.type == "follow" {
                // Platzhalter-Icon oder User-Icon (wenn verfügbar)
                 Image(systemName: "person.crop.circle.fill")
                     .resizable().scaledToFit().frame(width: 50, height: 50)
                     .foregroundColor(.secondary)
            } else {
                // Platzhalter für Notifications/Messages ohne Bild
                Rectangle().fill(Color.gray.opacity(0.1))
                     .frame(width: 50, height: 50).cornerRadius(4)
            }

            // Inhalt und Metadaten
            VStack(alignment: .leading, spacing: 4) {
                // Titelzeile (Username oder Typ)
                HStack {
                     if message.type != "notification" && message.type != "follow" {
                         // Zeige Mark-Punkt für User-Aktionen
                         Circle().fill(titleOrMarkColor)
                             .frame(width: 8, height: 8)
                             .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                     }
                     Text(title).font(.headline).lineLimit(1)
                     Spacer()
                     Text(relativeTime).font(.caption).foregroundColor(.secondary)
                     if message.read == 0 { // Ungelesen-Indikator
                         Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.leading, 4)
                     }
                }

                // Nachrichteninhalt (gekürzt)
                Text(message.message ?? "")
                    .font(.subheadline)
                    .foregroundColor(message.read == 1 ? .secondary : .primary) // Gelesene Nachrichten leicht ausgrauen
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 5)
        .opacity(message.read == 1 ? 0.8 : 1.0) // Gelesene Nachrichten leicht transparenter
    }
}

// MARK: - Wrapper View für User Profile Navigation
// Wird benötigt, falls ProfileView nicht direkt einen Usernamen annimmt
struct UserProfileViewWrapper: View {
    let username: String
    var body: some View {
        // Hier müsstest du eine View einfügen, die das Profil für den `username` anzeigt.
        // Beispiel: Text("Profil von \(username)")
        // Wenn deine ProfileView bereits so angepasst ist, dass sie einen Usernamen
        // annehmen kann (oder wenn sie nur das eingeloggte Profil anzeigt),
        // musst du hier entsprechend anpassen.
        // Vorerst ein Platzhalter:
        Text("Profilansicht für: \(username)")
             .navigationTitle(username)
    }
}


// MARK: - Preview
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
        let msg1 = InboxMessage(id: 1, type: "comment", itemId: 123, thumb: "thumb1.jpg", flags: 1, name: "UserA", mark: 2, senderId: 101, score: 5, created: Int(Date().timeIntervalSince1970 - 600), message: "Das ist ein Kommentar zur Benachrichtigung.", read: 0, blocked: 0)
        let msg2 = InboxMessage(id: 2, type: "notification", itemId: nil, thumb: nil, flags: nil, name: nil, mark: nil, senderId: 0, score: 0, created: Int(Date().timeIntervalSince1970 - 3600), message: "Systemnachricht: Dein pr0mium läuft bald ab!", read: 1, blocked: 0)
        let msg3 = InboxMessage(id: 3, type: "follow", itemId: nil, thumb: nil, flags: nil, name: "FollowerDude", mark: 1, senderId: 102, score: 0, created: Int(Date().timeIntervalSince1970 - 7200), message: nil, read: 0, blocked: 0)

        var view = InboxView()
        view.messages = [msg1, msg2, msg3]

        return NavigationStack {
            view
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }
}
// --- END OF COMPLETE FILE ---
