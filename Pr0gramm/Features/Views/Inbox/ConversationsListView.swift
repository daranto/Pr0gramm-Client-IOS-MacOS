// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationsListView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view to display a list of conversations for the "Private Messages" tab in the Inbox.
/// Fetches conversations from the API and allows navigation to a specific conversation's detail view.
struct ConversationsListView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService

    @Binding var conversations: [InboxConversation]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    let onRefresh: () async -> Void
    let onSelectConversation: (String) -> Void


    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationsListView")

    var body: some View {
        Group {
            if isLoading && conversations.isEmpty {
                ProgressView("Lade Konversationen...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, conversations.isEmpty {
                ContentUnavailableView {
                    Label("Fehler", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") {
                        Task { await onRefresh() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversations.isEmpty && !isLoading && errorMessage == nil {
                Text("Keine privaten Nachrichten vorhanden.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .refreshable { await onRefresh() }
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    ConversationsListView.logger.info("Conversation with '\(conversation.name)' selected.")
                    onSelectConversation(conversation.name)
                } label: {
                    InboxConversationRow(conversation: conversation)
                        // --- MODIFIED: Ensure the whole row is tappable ---
                        .contentShape(Rectangle())
                        // --- END MODIFICATION ---
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
            }
        }
        .listStyle(.plain)
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService
        
        @State private var sampleConversations: [InboxConversation] = [
            InboxConversation(name: "UserAlpha", mark: 2, lastMessage: Int(Date().timeIntervalSince1970 - 300), unreadCount: 2, blocked: 0, canReceiveMessages: 1),
            InboxConversation(name: "UserBeta", mark: 10, lastMessage: Int(Date().timeIntervalSince1970 - 36000), unreadCount: 0, blocked: 0, canReceiveMessages: 1),
            InboxConversation(name: "UserGamma", mark: 1, lastMessage: Int(Date().timeIntervalSince1970 - 86400 * 2), unreadCount: 5, blocked: 1, canReceiveMessages: 0)
        ]
        @State private var isLoadingPreview = false
        @State private var errorMessagePreview: String? = nil

        init() {
            let s = AppSettings()
            let a = AuthService(appSettings: s)
            a.isLoggedIn = true
            a.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: 1, score: 100, mark: 1, badges: [])
            _authService = StateObject(wrappedValue: a)
            _settings = StateObject(wrappedValue: s)
        }

        var body: some View {
            NavigationStack {
                ConversationsListView(
                    conversations: $sampleConversations,
                    isLoading: $isLoadingPreview,
                    errorMessage: $errorMessagePreview,
                    onRefresh: {
                        print("Preview: Refresh conversations triggered")
                        isLoadingPreview = true
                        errorMessagePreview = nil
                        try? await Task.sleep(for: .seconds(1))
                        isLoadingPreview = false
                    },
                    onSelectConversation: { username in
                        print("Preview: Selected conversation with \(username)")
                    }
                )
                .navigationTitle("Private Nachrichten")
                .environmentObject(settings)
                .environmentObject(authService)
            }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
