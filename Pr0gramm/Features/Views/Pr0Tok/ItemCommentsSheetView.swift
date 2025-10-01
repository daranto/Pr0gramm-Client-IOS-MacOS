// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/ItemCommentsSheetView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct ItemCommentsSheetView: View {
    let itemId: Int
    let uploaderName: String
    // InitialComments und initialInfoStatusProp werden verwendet, um den anfänglichen Zustand zu setzen.
    // Die View wird dann selbstständig die Kommentare verwalten.
    private let initialCommentsProp: [ItemComment]
    private let initialInfoStatusProp: InfoLoadingStatus
    
    let onRetryLoadDetails: () -> Void // Callback, falls die Haupt-View Details neu laden soll

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ItemCommentsSheetView")
    private let apiService = APIService()

    // States für die Kommentarverwaltung
    @State private var allComments: [ItemComment] = []
    @State private var flatComments: [FlatCommentDisplayItem] = []
    @State private var commentInfoStatus: InfoLoadingStatus = .idle
    @State private var collapsedCommentIDs: Set<Int> = []
    @State private var targetCommentID: Int? = nil // Falls wir zu einem bestimmten Kommentar scrollen wollen
    
    @State private var commentReplyTarget: ReplyTarget? = nil
    @State private var previewLinkTarget: PreviewLinkTarget? = nil // Für Links in Kommentaren
    @State private var userProfileSheetTarget: UserProfileSheetTarget? = nil // Für User-Profile aus Kommentaren

    private let commentMaxDepth: Int = .max // Unbegrenzt: keine Begrenzung der Kommentar-Tiefe

    init(itemId: Int, uploaderName: String, initialComments: [ItemComment], initialInfoStatusProp: InfoLoadingStatus, onRetryLoadDetails: @escaping () -> Void) {
        self.itemId = itemId
        self.uploaderName = uploaderName
        self.initialCommentsProp = initialComments
        self.initialInfoStatusProp = initialInfoStatusProp
        self.onRetryLoadDetails = onRetryLoadDetails
        
        // Setze initiale Zustände basierend auf den Props
        _allComments = State(initialValue: initialComments)
        _commentInfoStatus = State(initialValue: initialInfoStatusProp)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if commentInfoStatus == .loading && flatComments.isEmpty {
                    ProgressView("Lade Kommentare...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .error(let msg) = commentInfoStatus, flatComments.isEmpty {
                    ContentUnavailableView {
                        Label("Fehler", systemImage: "exclamationmark.triangle")
                    } description: { Text(msg) } actions: {
                        Button("Erneut versuchen") { Task { await loadCommentsForItem() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            CommentsSection(
                                flatComments: flatComments,
                                totalCommentCount: allComments.count, // Zeigt die Gesamtzahl der geladenen Kommentare
                                status: commentInfoStatus,
                                uploaderName: uploaderName,
                                previewLinkTarget: $previewLinkTarget,
                                userProfileSheetTarget: $userProfileSheetTarget,
                                isCommentCollapsed: { commentID in collapsedCommentIDs.contains(commentID) },
                                toggleCollapseAction: toggleCollapse,
                                showCommentInputAction: { parentId in
                                    self.commentReplyTarget = ReplyTarget(itemId: itemId, parentId: parentId)
                                },
                                targetCommentID: targetCommentID,
                                onHighlightCompletedForCommentID: { _ in /* Optional: Implementieren falls nötig */ },
                                onUpvoteComment: { commentId in Task { await handleCommentVoteTap(commentId: commentId, voteType: 1) } },
                                onDownvoteComment: { commentId in Task { await handleCommentVoteTap(commentId: commentId, voteType: -1) } }
                            )
                            .padding(.horizontal) // Etwas Padding für die CommentsSection
                        }
                        .onChange(of: targetCommentID) { _, newID in
                            if let id = newID {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kommentare (\(allComments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task {
                // Wenn der initiale Status .loaded ist und Kommentare übergeben wurden, diese direkt verarbeiten
                if initialInfoStatusProp == .loaded && !initialCommentsProp.isEmpty {
                    ItemCommentsSheetView.logger.info("Using initially provided comments for item \(itemId).")
                    self.allComments = initialCommentsProp
                    prepareFlatComments()
                    self.commentInfoStatus = .loaded
                } else if initialInfoStatusProp == .error("") { // Oder ein anderer Fehlercode
                     ItemCommentsSheetView.logger.info("Initial status is error for item \(itemId).")
                     // Fehler wird bereits angezeigt
                } else {
                    // Andernfalls Kommentare laden
                    await loadCommentsForItem()
                }
            }
            .onChange(of: settings.commentSortOrder) { _, newOrder in
                ItemCommentsSheetView.logger.info("Comment sort order changed to \(newOrder.displayName) in sheet.")
                prepareFlatComments() // Kommentare neu aufbereiten und sortieren
            }
            .sheet(item: $commentReplyTarget) { target in
                CommentInputView(
                    itemId: target.itemId,
                    parentId: target.parentId,
                    onSubmit: { commentText in
                        try await submitComment(text: commentText, itemId: target.itemId, parentId: target.parentId)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $previewLinkTarget) { target in
                 LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
            .sheet(item: $userProfileSheetTarget) { target in
                UserProfileSheetView(username: target.username)
                    .environmentObject(authService)
                    .environmentObject(settings)
            }
        }
    }

    private func loadCommentsForItem() async {
        ItemCommentsSheetView.logger.info("Loading comments for item \(itemId) in sheet.")
        await MainActor.run { commentInfoStatus = .loading }
        do {
            let fetchedInfoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            await MainActor.run {
                allComments = fetchedInfoResponse.comments
                prepareFlatComments()
                commentInfoStatus = .loaded
            }
            ItemCommentsSheetView.logger.info("Successfully loaded \(allComments.count) comments for item \(itemId) in sheet.")
        } catch {
            ItemCommentsSheetView.logger.error("Failed to load comments for item \(itemId) in sheet: \(error.localizedDescription)")
            await MainActor.run { commentInfoStatus = .error(error.localizedDescription) }
        }
    }
    
    private func prepareFlatComments() {
        ItemCommentsSheetView.logger.debug("Preparing flat display comments for sheet (\(allComments.count) raw), sort: \(settings.commentSortOrder.displayName).")
        let prepared = CommentHelper.prepareFlatDisplayComments(
            from: allComments,
            sortedBy: settings.commentSortOrder,
            maxDepth: commentMaxDepth, // Verwende die gleiche Tiefe wie PagedDetailView
            collapsedIDs: collapsedCommentIDs, // Berücksichtige eingeklappte Kommentare
            logPrefix: "[CommentsSheet]" // Eigener Log-Präfix
        )
        self.flatComments = prepared
    }

    private func toggleCollapse(commentID: Int) {
        if collapsedCommentIDs.contains(commentID) {
            collapsedCommentIDs.remove(commentID)
        } else {
            collapsedCommentIDs.insert(commentID)
        }
        prepareFlatComments() // Neu aufbauen, da die Sichtbarkeit sich ändert
    }

    private func handleCommentVoteTap(commentId: Int, voteType: Int) async {
        guard authService.isLoggedIn else {
            ItemCommentsSheetView.logger.warning("Comment vote in sheet skipped: User not logged in.")
            return
        }
        ItemCommentsSheetView.logger.debug("Comment vote in sheet: commentId=\(commentId), voteType=\(voteType)")
        
        let previousVoteState = authService.votedCommentStates[commentId]
        await authService.performCommentVote(commentId: commentId, voteType: voteType)
        
        // UI Update für den spezifischen Kommentar
        if let index = allComments.firstIndex(where: { $0.id == commentId }) {
            var votedComment = allComments[index]
            let newVoteState = authService.votedCommentStates[commentId] ?? 0
            
            if newVoteState == 1 && previousVoteState != 1 {
                votedComment.up += 1
                if previousVoteState == -1 { votedComment.down -= 1 }
            } else if newVoteState == -1 && previousVoteState != -1 {
                votedComment.down += 1
                if previousVoteState == 1 { votedComment.up -= 1 }
            } else if newVoteState == 0 && previousVoteState == 1 {
                votedComment.up -= 1
            } else if newVoteState == 0 && previousVoteState == -1 {
                votedComment.down -= 1
            }
            allComments[index] = votedComment
            prepareFlatComments() // Neu aufbauen, um die Votes zu reflektieren
        }
    }
    
    private func submitComment(text: String, itemId: Int, parentId: Int) async throws {
        guard authService.isLoggedIn, let nonce = authService.userNonce else {
            ItemCommentsSheetView.logger.error("Cannot submit comment from sheet: User not logged in or nonce missing.")
            throw NSError(domain: "ItemCommentsSheetView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nicht angemeldet"])
        }

        ItemCommentsSheetView.logger.info("Submitting comment from sheet for itemId: \(itemId), parentId: \(parentId)")
        do {
            let updatedCommentsFromAPI = try await apiService.postComment(itemId: itemId, parentId: parentId, comment: text, nonce: nonce)
            
            // Konvertiere API-Kommentare
            let newFullComments = updatedCommentsFromAPI.map {
                ItemComment(id: $0.id, parent: $0.parent, content: $0.content, created: $0.created, up: $0.up, down: $0.down, confidence: $0.confidence, name: $0.name, mark: $0.mark, itemId: itemId)
            }
            
            await MainActor.run {
                self.allComments = newFullComments
                prepareFlatComments() // Aktualisiere die Anzeige
                // Scroll zum neuen Kommentar (optional, kann komplex sein, den neuen zu finden)
                if let newComment = newFullComments.first(where: {!self.initialCommentsProp.contains(where: {$0.id == $0.id}) && $0.content == text && $0.parent == parentId}) {
                     self.targetCommentID = newComment.id
                } else if let lastComment = newFullComments.last(where: {$0.parent == parentId && $0.content == text}) {
                     self.targetCommentID = lastComment.id // Fallback
                }
            }
            ItemCommentsSheetView.logger.info("Successfully updated comments in sheet after posting.")
        } catch {
            ItemCommentsSheetView.logger.error("Failed to submit comment from sheet for item \(itemId): \(error.localizedDescription)")
            throw error
        }
    }
}


// Helper für FlatCommentDisplayItem Erstellung (kann ausgelagert werden, wenn es woanders gebraucht wird)
struct CommentHelper {
    // --- MODIFICATION: logger Sichtbarkeit geändert ---
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentHelper")
    // --- END MODIFICATION ---

    static func prepareFlatDisplayComments(from comments: [ItemComment], sortedBy sortOrder: CommentSortOrder, maxDepth: Int, collapsedIDs: Set<Int>, logPrefix: String = "") -> [FlatCommentDisplayItem] {
        // --- MODIFICATION: Verwende den korrekten Logger ---
        CommentHelper.logger.debug("\(logPrefix) Preparing flat display comments (\(comments.count) raw), sort: \(sortOrder.displayName), depth: \(maxDepth).")
        // --- END MODIFICATION ---
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })

        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            let children = childrenByParentId[commentId] ?? []
            let hasChildren = !children.isEmpty
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren))
            
            guard !collapsedIDs.contains(commentId), currentLevel < maxDepth else { return }
            
            let sortedChildren: [ItemComment]
            switch sortOrder {
            case .date: sortedChildren = children.sorted { $0.created < $1.created }
            case .score: sortedChildren = children.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
            }
            sortedChildren.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
        }

        let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
        let sortedTopLevelComments: [ItemComment]
        switch sortOrder {
        case .date: sortedTopLevelComments = topLevelComments.sorted { $0.created < $1.created }
        case .score: sortedTopLevelComments = topLevelComments.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
        }
        sortedTopLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }
        
        // --- MODIFICATION: Verwende den korrekten Logger ---
        CommentHelper.logger.info("\(logPrefix) Finished flat comments (\(flatList.count) items).")
        // --- END MODIFICATION ---
        return flatList
    }
}


#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    authService.isLoggedIn = true
    
    let sampleComments = [
        ItemComment(id: 1, parent: 0, content: "Top Level 1 http://pr0gramm.com/new/123", created: 100, up: 10, down: 1, confidence: 0.9, name: "UserA", mark: 1, itemId: 999),
        ItemComment(id: 2, parent: 1, content: "Reply to 1", created: 110, up: 5, down: 0, confidence: 0.8, name: "UserB", mark: 2, itemId: 999),
        ItemComment(id: 3, parent: 0, content: "Top Level 2", created: 120, up: 8, down: 2, confidence: 0.7, name: "UserC", mark: 0, itemId: 999)
    ]

    return ItemCommentsSheetView(
        itemId: 999,
        uploaderName: "Uploader",
        initialComments: sampleComments,
        initialInfoStatusProp: .loaded,
        onRetryLoadDetails: { print("Retry load details called in preview") }
    )
    .environmentObject(settings)
    .environmentObject(authService)
}
// --- END OF COMPLETE FILE ---



