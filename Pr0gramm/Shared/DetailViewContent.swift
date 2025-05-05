// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit
import Combine
import os
import Kingfisher
import UIKit // Für UIPasteboard

// MARK: - DetailImageView
@MainActor
struct DetailImageView: View {
    let item: Item
    let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailImageView")
    let horizontalSizeClass: UserInterfaceSizeClass?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?

    var body: some View {
        KFImage(item.imageUrl)
            .placeholder { Rectangle().fill(.secondary.opacity(0.1)).overlay(ProgressView()) }
            .onFailure { error in logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)") }
            .cancelOnDisappear(true)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .id(item.id)
            .background(Color.black)
            .clipped()
            .onTapGesture { if !item.isVideo { logger.info("Image tapped for item \(item.id), setting fullscreen target."); fullscreenImageTarget = FullscreenImageTarget(item: item) } }
            .disabled(item.isVideo)
    }
}

// InfoLoadingStatus enum
enum InfoLoadingStatus: Equatable { case idle; case loading; case loaded; case error(String) }


/// The main content area for the item detail view, arranging media, info, tags, and comments.
@MainActor
struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let currentSubtitleText: String?
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void

    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool

    let flatComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int

    let infoLoadingStatus: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void

    let isCommentCollapsed: (Int) -> Bool
    let toggleCollapseAction: (Int) -> Void

    let currentVote: Int
    let upvoteAction: () -> Void
    let downvoteAction: () -> Void
    // --- MODIFIED: Closure now takes itemId and parentId ---
    let showCommentInputAction: (Int, Int) -> Void // itemId, parentId
    // --- END MODIFICATION ---


    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")
    @State private var isProcessingFavorite = false
    @State private var showingShareOptions = false


    // MARK: - Computed View Properties
    @ViewBuilder private var mediaContentInternal: some View {
        ZStack(alignment: .bottom) {
            Group {
                if item.isVideo {
                    if let player = player {
                        CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler, onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen, horizontalSizeClass: horizontalSizeClass)
                            .id(item.id)
                    } else {
                        Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                    }
                } else {
                    DetailImageView(item: item, horizontalSizeClass: horizontalSizeClass, fullscreenImageTarget: $fullscreenImageTarget)
                }
            }

            if let subtitle = currentSubtitleText, !subtitle.isEmpty {
                 Text(subtitle)
                     .font(UIConstants.footnoteFont.weight(.medium))
                     .foregroundColor(.white)
                     .padding(.horizontal, 8)
                     .padding(.vertical, 4)
                     .background(.black.opacity(0.65))
                     .cornerRadius(4)
                     .multilineTextAlignment(.center)
                     .padding(.bottom, horizontalSizeClass == .compact ? 40 : 20)
                     .padding(.horizontal)
                     .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                     .id("subtitle_\(subtitle)")
            }
        }
    }

    private let actionIconFont: Font = .title

    @ViewBuilder private var voteCounterView: some View {
        let benis = item.up - item.down
        HStack(spacing: 6) {
            Button(action: upvoteAction) {
                Image(systemName: currentVote == 1 ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(currentVote == 1 ? Color.white : Color.secondary,
                                     currentVote == 1 ? Color.green : Color.secondary)
                    .font(actionIconFont)
            }
            .buttonStyle(.plain)
            .disabled(!authService.isLoggedIn)

            Text("\(benis)")
                .font(.title.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button(action: downvoteAction) {
                Image(systemName: currentVote == -1 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .symbolRenderingMode(.palette)
                     .foregroundStyle(currentVote == -1 ? Color.white : Color.secondary,
                                      currentVote == -1 ? Color.red : Color.secondary)
                    .font(actionIconFont)
            }
            .buttonStyle(.plain)
            .disabled(!authService.isLoggedIn)
        }
    }

    @ViewBuilder private var favoriteButton: some View {
        Button { Task { isProcessingFavorite = true; await toggleFavoriteAction(); try? await Task.sleep(for: .milliseconds(100)); isProcessingFavorite = false } }
        label: {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(actionIconFont)
                .foregroundColor(isFavorited ? .pink : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(isProcessingFavorite || !authService.isLoggedIn)
    }

    @ViewBuilder private var shareButton: some View {
        Button { showingShareOptions = true }
        label: {
            Image(systemName: "square.and.arrow.up")
                .font(actionIconFont)
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var addCommentButton: some View {
        // --- MODIFIED: Pass itemId and parentId=0 ---
        Button { showCommentInputAction(item.id, 0) }
        // --- END MODIFICATION ---
        label: {
            Image(systemName: "plus.message")
                .font(actionIconFont)
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!authService.isLoggedIn)
    }


    @ViewBuilder private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 15) {
                voteCounterView
                Spacer()
                if authService.isLoggedIn { addCommentButton }
                if authService.isLoggedIn { favoriteButton }
                shareButton
            }
            .frame(minHeight: 44)

            Group {
                switch infoLoadingStatus {
                case .loaded:
                    if !displayedTags.isEmpty {
                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(displayedTags) { tag in TagView(tag: tag).contentShape(Capsule()).onTapGesture { navigationService.requestSearch(tag: tag.tag) } }
                            if !showingAllTags && totalTagCount > displayedTags.count {
                                let remainingCount = totalTagCount - displayedTags.count
                                Button { showAllTagsAction() } label: { Text("+\(remainingCount) mehr").font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.accentColor.opacity(0.15)).foregroundColor(.accentColor).clipShape(Capsule()).contentShape(Capsule()).lineLimit(1) }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    }
                case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .error: Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .idle: Text(" ").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    struct TagView: View {
        let tag: ItemTag; private let characterLimit = 25
        private var displayText: String { tag.tag.count > characterLimit ? String(tag.tag.prefix(characterLimit - 1)) + "…" : tag.tag }
        var body: some View { Text(displayText).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.2)).foregroundColor(.primary).clipShape(Capsule()) }
    }

    @ViewBuilder private var commentsContent: some View {
        CommentsSection(
            flatComments: flatComments,
            totalCommentCount: totalCommentCount,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget,
            isCommentCollapsed: isCommentCollapsed,
            toggleCollapseAction: toggleCollapseAction,
            // --- MODIFIED: Pass itemId along with parentId ---
            showCommentInputAction: { parentId in showCommentInputAction(item.id, parentId) }
            // --- END MODIFICATION ---
        )
    }

    // MARK: - Body
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    mediaContentInternal
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            infoAndTagsContent.padding([.horizontal, .top]);
                            commentsContent.padding([.horizontal, .bottom])
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600).background(Color(.secondarySystemBackground))
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            let aspect = guessAspectRatio() ?? 1.0
                            mediaContentInternal
                                .frame(width: geo.size.width, height: geo.size.width / aspect)
                        }
                        .aspectRatio(guessAspectRatio() ?? 1.0, contentMode: .fit)
                        infoAndTagsContent.padding(.horizontal).padding(.vertical, 10)
                        commentsContent.padding(.horizontal).padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
        .confirmationDialog(
            "Link kopieren", isPresented: $showingShareOptions, titleVisibility: .visible
        ) {
            Button("Post-Link (pr0gramm.com)") { let urlString = "https://pr0gramm.com/new/\(item.id)"; UIPasteboard.general.string = urlString; Self.logger.info("Copied Post-Link to clipboard: \(urlString)") }
            Button("Direkter Medien-Link") { if let urlString = item.imageUrl?.absoluteString { UIPasteboard.general.string = urlString; Self.logger.info("Copied Media-Link to clipboard: \(urlString)") } else { Self.logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)") } }
        } message: { Text("Welchen Link möchtest du in die Zwischenablage kopieren?") }
    }


    // MARK: - Helper Methods
    private func guessAspectRatio() -> CGFloat? {
        guard item.width > 0, item.height > 0 else { return 1.0 }
        return CGFloat(item.width) / CGFloat(item.height)
    }
}

// Helper Extension
fileprivate extension UIFont {
    static func uiFont(from font: Font) -> UIFont {
        switch font {
            case .largeTitle: return UIFont.preferredFont(forTextStyle: .largeTitle)
            case .title: return UIFont.preferredFont(forTextStyle: .title1)
            case .title2: return UIFont.preferredFont(forTextStyle: .title2)
            case .title3: return UIFont.preferredFont(forTextStyle: .title3)
            case .headline: return UIFont.preferredFont(forTextStyle: .headline)
            case .subheadline: return UIFont.preferredFont(forTextStyle: .subheadline)
            case .body: return UIFont.preferredFont(forTextStyle: .body)
            case .callout: return UIFont.preferredFont(forTextStyle: .callout)
            case .footnote: return UIFont.preferredFont(forTextStyle: .footnote)
            case .caption: return UIFont.preferredFont(forTextStyle: .caption1)
            case .caption2: return UIFont.preferredFont(forTextStyle: .caption2)
            default: return UIFont.preferredFont(forTextStyle: .body)
        }
    }
}


// MARK: - Previews
#Preview("Compact - Limited Tags") {
    struct PreviewWrapper: View {
        @State var previewLinkTarget: PreviewLinkTarget? = nil
        @State var fullscreenTarget: FullscreenImageTarget? = nil
        @State var collapsedIDs: Set<Int> = []
        @StateObject var settings = AppSettings()
        @StateObject var authService = AuthService(appSettings: AppSettings())
        @StateObject var navService = NavigationService()
        @StateObject var playerManager = VideoPlayerManager()
        // --- MODIFIED: State for sheet presentation ---
        @State private var commentReplyTarget: ReplyTarget? = nil
        // --- END MODIFICATION ---

        func toggleCollapse(_ id: Int) { if collapsedIDs.contains(id) { collapsedIDs.remove(id) } else { collapsedIDs.insert(id) } }
        func isCollapsed(_ id: Int) -> Bool { collapsedIDs.contains(id) }

        var body: some View {
            // --- Use let for the item definition ---
            let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, subtitles: nil, favorited: true)
            // --- End modification ---
            let previewHandler = KeyboardActionHandler()
            let previewTags: [ItemTag] = [ ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"), ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt") ]
            let sampleComments = [ ItemComment(id: 1, parent: 0, content: "Kommentar 1 http://pr0gramm.com/new/54321", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1, itemId: 2), ItemComment(id: 2, parent: 1, content: "Antwort 1.1", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "User2", mark: 2, itemId: 2) ]
            let previewFlatComments = flattenHierarchyForPreview(comments: sampleComments)

            NavigationStack {
                DetailViewContent(
                    item: sampleVideoItem,
                    keyboardActionHandler: previewHandler,
                    player: nil,
                    currentSubtitleText: "Dies ist ein Test-Untertitel",
                    onWillBeginFullScreen: {}, onWillEndFullScreen: {},
                    displayedTags: Array(previewTags.prefix(4)),
                    totalTagCount: previewTags.count,
                    showingAllTags: false,
                    flatComments: previewFlatComments,
                    totalCommentCount: previewFlatComments.count,
                    infoLoadingStatus: .loaded,
                    previewLinkTarget: $previewLinkTarget,
                    fullscreenImageTarget: $fullscreenTarget,
                    isFavorited: true,
                    toggleFavoriteAction: {},
                    showAllTagsAction: {},
                    isCommentCollapsed: isCollapsed,
                    toggleCollapseAction: toggleCollapse,
                    currentVote: 1,
                    upvoteAction: { print("Preview Upvote Tapped") },
                    downvoteAction: { print("Preview Downvote Tapped") },
                    // --- MODIFIED: Provide the showCommentInputAction closure ---
                    showCommentInputAction: { itemId, parentId in
                         print("Preview Show Comment Input Tapped for itemId: \(itemId), parentId: \(parentId)")
                         // Create and set the ReplyTarget to show the sheet
                         self.commentReplyTarget = ReplyTarget(itemId: itemId, parentId: parentId)
                    }
                    // --- END MODIFICATION ---
                )
                .environmentObject(navService)
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(playerManager)
                .environment(\.horizontalSizeClass, .compact)
                .preferredColorScheme(.dark)
                .task {
                    playerManager.configure(settings: settings)
                    if authService.currentUser == nil {
                         authService.isLoggedIn = true
                         authService.favoritesCollectionId = 1234
                         authService.currentUser = UserInfo(id: 99, name: "PreviewUser", registered: 1, score: 100, mark: 1, badges: nil)
                         await settings.markItemsAsSeen(ids: [1,2])
                         print("Preview Task: AuthService configured and item marked as seen.")
                    }
                }
                 // --- MODIFIED: Add the sheet modifier ---
                 .sheet(item: $commentReplyTarget) { target in
                     // Dummy CommentInputView for preview
                     CommentInputView(
                         itemId: target.itemId,
                         parentId: target.parentId,
                         onSubmit: { commentText in
                             print("Preview Submit: \(commentText) for itemId \(target.itemId), parent \(target.parentId)")
                             try await Task.sleep(for: .seconds(1))
                         }
                     )
                     .environmentObject(authService) // Pass authService if needed inside
                 }
                 // --- END MODIFICATION ---
            }
        }
    }

    @MainActor func flattenHierarchyForPreview(comments: [ItemComment], maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            let children = childrenByParentId[commentId] ?? []
            let hasChildren = !children.isEmpty
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren))
            guard currentLevel < maxDepth else { return }
            children.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
        }
        let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
        topLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }
        return flatList
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
