// Pr0gramm/Pr0gramm/Features/Views/Profile/UserFavoritedCommentsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// Zeigt die vom Benutzer favorisierten ("Favorisierte") Kommentare an.
/// Erfordert, dass der Benutzer angemeldet ist. Handhabt Laden, Paginierung und Filterung.
struct UserFavoritedCommentsView: View {
    let username: String // Benutzername, dessen gelikete Kommentare angezeigt werden sollen

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var comments: [ItemComment] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    // State für die Link-Vorschau
    @State private var previewLinkTarget: PreviewLinkTarget? = nil

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserFavoritedCommentsView")

    var body: some View {
        Group { commentsContentView }
        .navigationTitle("Gelikete Kommentare")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task { await refreshComments() } // Lade beim Erscheinen
        .onChange(of: settings.showSFW) { _, _ in Task { await refreshComments() } } // Bei Filteränderung neu laden
        .onChange(of: settings.showNSFW) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showNSFL) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showNSFP) { _, _ in Task { await refreshComments() } }
        .onChange(of: settings.showPOL) { _, _ in Task { await refreshComments() } }
        // Sheet für Link-Vorschau
        .sheet(item: $previewLinkTarget) { targetWrapper in
            LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }

    // MARK: - Content Views

    @ViewBuilder private var commentsContentView: some View {
        Group {
            if isLoading && comments.isEmpty {
                ProgressView("Lade Kommentare...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, comments.isEmpty {
                 ContentUnavailableView {
                     Label("Fehler", systemImage: "exclamationmark.triangle")
                 } description: { Text(error) } actions: {
                     Button("Erneut versuchen") { Task { await refreshComments() } }
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty && !isLoading && errorMessage == nil {
                Text("\(username) hat noch keine Kommentare geliket (oder sie passen nicht zu deinen Filtern).")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(comments) { comment in
                // Verwende die bestehende CommentView, aber ohne Collapse/Reply-Funktion
                CommentView(
                    comment: comment,
                    previewLinkTarget: $previewLinkTarget,
                    hasChildren: false, // Gelikete Kommentare haben hier keinen Kontext für Kinder
                    isCollapsed: false, // Nicht kollabierbar in dieser Ansicht
                    onToggleCollapse: {}, // Keine Aktion
                    onReply: { /* Kein Reply aus dieser Liste */ } // Keine Aktion
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15)) // Standard List Padding
                .id(comment.id) // Wichtig für List-Identifikation
                // Lade mehr, wenn das vorletzte Element erscheint
                .onAppear {
                     if comment.id == comments.last?.id, canLoadMore, !isLoadingMore {
                         UserFavoritedCommentsView.logger.info("End trigger appeared for comment \(comment.id).")
                         Task { await loadMoreComments() }
                     }
                }
            } // Ende ForEach

            // Ladeindikator am Ende
            if isLoadingMore {
                HStack { Spacer(); ProgressView("Lade mehr..."); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain) // Einfacher Listenstil
        .refreshable { await refreshComments() }
    }


    // MARK: - Data Loading Methods

    @MainActor
    func refreshComments() async {
        UserFavoritedCommentsView.logger.info("Refreshing favorited comments for user: \(username)")
        guard authService.isLoggedIn else {
            UserFavoritedCommentsView.logger.warning("Cannot refresh liked comments: User not logged in.")
            self.comments = []; self.errorMessage = "Bitte anmelden."
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        // Verwende einen sehr großen Timestamp für den ersten Abruf, um die neuesten zuerst zu bekommen
        let initialTimestamp = Int(Date.distantFuture.timeIntervalSince1970)

        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let response = try await apiService.fetchFavoritedComments(username: username, flags: settings.apiFlags, before: initialTimestamp)
            guard !Task.isCancelled else { return }

            self.comments = response.comments
            self.canLoadMore = response.hasOlder
            UserFavoritedCommentsView.logger.info("Fetched \(response.comments.count) initial liked comments. HasOlder: \(response.hasOlder)")

        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserFavoritedCommentsView.logger.error("API fetch failed: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.comments = []
            self.canLoadMore = false
            await authService.logout()
        } catch {
            UserFavoritedCommentsView.logger.error("API fetch failed: \(error.localizedDescription)")
            self.errorMessage = "Fehler: \(error.localizedDescription)"
            self.comments = []
            self.canLoadMore = false
        }
    }

    @MainActor
    func loadMoreComments() async {
        guard authService.isLoggedIn else { return }
        guard !isLoadingMore && canLoadMore && !isLoading else {
            UserFavoritedCommentsView.logger.debug("Skipping loadMoreComments: State prevents loading (isLoadingMore: \(isLoadingMore), canLoadMore: \(canLoadMore), isLoading: \(isLoading))")
            return
        }
        // Verwende den 'created'-Timestamp des ältesten Kommentars für die Paginierung
        guard let oldestCommentTimestamp = comments.last?.created else {
            UserFavoritedCommentsView.logger.warning("Cannot load more liked comments: No last comment found to get timestamp.")
            self.canLoadMore = false
            return
        }

        UserFavoritedCommentsView.logger.info("--- Starting loadMoreComments before timestamp \(oldestCommentTimestamp) ---")
        self.isLoadingMore = true

        defer { Task { @MainActor in if self.isLoadingMore { self.isLoadingMore = false; UserFavoritedCommentsView.logger.info("--- Finished loadMoreComments ---") } } }

        do {
            let response = try await apiService.fetchFavoritedComments(username: username, flags: settings.apiFlags, before: oldestCommentTimestamp)
            guard !Task.isCancelled else { return }
            guard self.isLoadingMore else { UserFavoritedCommentsView.logger.info("Load more cancelled before UI update."); return } // Check again

            if response.comments.isEmpty {
                UserFavoritedCommentsView.logger.info("Reached end of liked comments feed.")
                self.canLoadMore = false
            } else {
                let currentIDs = Set(self.comments.map { $0.id })
                let uniqueNewComments = response.comments.filter { !currentIDs.contains($0.id) }

                if uniqueNewComments.isEmpty {
                    UserFavoritedCommentsView.logger.warning("All loaded liked comments were duplicates.")
                    // Potenziell canLoadMore auf response.hasOlder setzen, falls API das liefert?
                    // Fürs Erste: Wenn Duplikate kommen, erstmal annehmen, dass Ende erreicht ist.
                    self.canLoadMore = response.hasOlder // Vertraue der API
                } else {
                    self.comments.append(contentsOf: uniqueNewComments)
                    UserFavoritedCommentsView.logger.info("Appended \(uniqueNewComments.count) unique liked comments. Total: \(self.comments.count)")
                    self.canLoadMore = response.hasOlder // Update based on API response
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            UserFavoritedCommentsView.logger.error("API fetch failed during loadMore: Authentication required.")
            self.errorMessage = "Sitzung abgelaufen."
            self.canLoadMore = false
            await authService.logout()
        } catch {
            UserFavoritedCommentsView.logger.error("API fetch failed during loadMore: \(error.localizedDescription)")
            // Behalte bestehende Kommentare bei, zeige aber keinen Fehler an, wenn schon welche da sind.
            if self.comments.isEmpty { self.errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
            self.canLoadMore = false // Verhindere weitere Versuche bei Fehler
        }
    }
}

// MARK: - Preview
#Preview {
    let previewSettings = AppSettings()
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewAuthService.currentUser = UserInfo(id: 1, name: "Daranto", registered: 1, score: 1337, mark: 2, badges: [])

    return NavigationStack {
        UserFavoritedCommentsView(username: "Daranto")
            .environmentObject(previewSettings)
            .environmentObject(previewAuthService)
    }
}
// --- END OF COMPLETE FILE ---
