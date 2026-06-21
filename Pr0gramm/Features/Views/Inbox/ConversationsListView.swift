// Pr0gramm/Pr0gramm/Features/Views/Inbox/ConversationsListView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view to display a list of conversations for the "Private Messages" tab in the Inbox.
/// Fetches conversations from the API and allows navigation to a specific conversation's detail view.
struct ConversationsListView: View {
    @Environment(AppSettings.self) var settings
    @Environment(AuthService.self) var authService

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
        ScrollView {
            LazyVStack(spacing: 12) {
                if let error = errorMessage {
                    inlineErrorBanner(error)
                }

                ForEach(conversations) { conversation in
                    Button {
                        ConversationsListView.logger.info("Conversation with '\(conversation.name)' selected.")
                        onSelectConversation(conversation.name)
                    } label: {
                        InboxConversationRow(conversation: conversation)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .refreshable {
            await onRefresh()
        }
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
                errorMessage = nil
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
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var settings = AppSettings()
        @State private var authService: AuthService
        
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
            _authService = State(wrappedValue: a)
            _settings = State(wrappedValue: s)
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
                .environment(settings)
                .environment(authService)
            }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
