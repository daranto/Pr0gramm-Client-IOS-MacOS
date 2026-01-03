// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit
import Combine
import os
import Kingfisher
import UIKit // Für UIPasteboard und UIImage

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
            .cancelOnDisappear(false)
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

struct ShareableItemWrapper: Identifiable {
    let id = UUID()
    let itemsToShare: [Any]
    let temporaryFileUrlToDelete: URL?

    init(itemsToShare: [Any], temporaryFileUrlToDelete: URL? = nil) {
        self.itemsToShare = itemsToShare
        self.temporaryFileUrlToDelete = temporaryFileUrlToDelete
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    var completionHandler: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = completionHandler
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}


/// The main content area for the item detail view, arranging media, info, tags, and comments.
@MainActor
struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    @ObservedObject var playerManager: VideoPlayerManager
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
    @Binding var userProfileSheetTarget: UserProfileSheetTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showCollectionSelectionAction: () -> Void
    let showAllTagsAction: () -> Void

    let isCommentCollapsed: (Int) -> Bool
    let toggleCollapseAction: (Int) -> Void

    let currentVote: Int
    let upvoteAction: () -> Void
    let downvoteAction: () -> Void
    let showCommentInputAction: (Int, Int) -> Void

    let targetCommentID: Int?
    let onHighlightCompletedForCommentID: (Int) -> Void
    
    let upvoteTagAction: (Int) -> Void
    let downvoteTagAction: (Int) -> Void
    let addTagsAction: (String) async -> String?
    let upvoteCommentAction: (Int) -> Void
    let downvoteCommentAction: (Int) -> Void
    let cycleSubtitleModeAction: () -> Void
    
    let onTagTappedInSheetCallback: ((String) -> Void)?


    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")
    @State private var isProcessingFavorite = false
    @State private var showingShareOptions = false
    @State private var itemToShare: ShareableItemWrapper? = nil
    @State private var isPreparingShare = false
    @State private var sharePreparationError: String? = nil
    @State private var didAttemptScrollToTarget = false
    
    @State private var showingAddTagSheet = false
    @State private var newTagText = ""
    @State private var addTagError: String? = nil
    @State private var isAddingTags: Bool = false

    @State private var tagForSheetSearch: String? = nil
    @State private var wasPlayingBeforeAnySheet: Bool = false
    
    // Feedback States
    @State private var copyFeedbackMessage: String? = nil

    init(
        item: Item,
        keyboardActionHandler: KeyboardActionHandler,
        playerManager: VideoPlayerManager,
        currentSubtitleText: String?,
        onWillBeginFullScreen: @escaping () -> Void,
        onWillEndFullScreen: @escaping () -> Void,
        displayedTags: [ItemTag],
        totalTagCount: Int,
        showingAllTags: Bool,
        flatComments: [FlatCommentDisplayItem],
        totalCommentCount: Int,
        infoLoadingStatus: InfoLoadingStatus,
        previewLinkTarget: Binding<PreviewLinkTarget?>,
        userProfileSheetTarget: Binding<UserProfileSheetTarget?>,
        fullscreenImageTarget: Binding<FullscreenImageTarget?>,
        isFavorited: Bool,
        toggleFavoriteAction: @escaping () async -> Void,
        showCollectionSelectionAction: @escaping () -> Void,
        showAllTagsAction: @escaping () -> Void,
        isCommentCollapsed: @escaping (Int) -> Bool,
        toggleCollapseAction: @escaping (Int) -> Void,
        currentVote: Int,
        upvoteAction: @escaping () -> Void,
        downvoteAction: @escaping () -> Void,
        showCommentInputAction: @escaping (Int, Int) -> Void,
        targetCommentID: Int?,
        onHighlightCompletedForCommentID: @escaping (Int) -> Void,
        upvoteTagAction: @escaping (Int) -> Void,
        downvoteTagAction: @escaping (Int) -> Void,
        addTagsAction: @escaping (String) async -> String?,
        upvoteCommentAction: @escaping (Int) -> Void,
        downvoteCommentAction: @escaping (Int) -> Void,
        cycleSubtitleModeAction: @escaping () -> Void,
        onTagTappedInSheetCallback: ((String) -> Void)? = nil
    ) {
        self.item = item
        self.keyboardActionHandler = keyboardActionHandler
        self.playerManager = playerManager
        self.currentSubtitleText = currentSubtitleText
        self.onWillBeginFullScreen = onWillBeginFullScreen
        self.onWillEndFullScreen = onWillEndFullScreen
        self.displayedTags = displayedTags
        self.totalTagCount = totalTagCount
        self.showingAllTags = showingAllTags
        self.flatComments = flatComments
        self.totalCommentCount = totalCommentCount
        self.infoLoadingStatus = infoLoadingStatus
        self._previewLinkTarget = previewLinkTarget
        self._userProfileSheetTarget = userProfileSheetTarget
        self._fullscreenImageTarget = fullscreenImageTarget
        self.isFavorited = isFavorited
        self.toggleFavoriteAction = toggleFavoriteAction
        self.showCollectionSelectionAction = showCollectionSelectionAction
        self.showAllTagsAction = showAllTagsAction
        self.isCommentCollapsed = isCommentCollapsed
        self.toggleCollapseAction = toggleCollapseAction
        self.currentVote = currentVote
        self.upvoteAction = upvoteAction
        self.downvoteAction = downvoteAction
        self.showCommentInputAction = showCommentInputAction
        self.targetCommentID = targetCommentID
        self.onHighlightCompletedForCommentID = onHighlightCompletedForCommentID
        self.upvoteTagAction = upvoteTagAction
        self.downvoteTagAction = downvoteTagAction
        self.addTagsAction = addTagsAction
        self.upvoteCommentAction = upvoteCommentAction
        self.downvoteCommentAction = downvoteCommentAction
        self.cycleSubtitleModeAction = cycleSubtitleModeAction
        self.onTagTappedInSheetCallback = onTagTappedInSheetCallback
    }


    @ViewBuilder private var mediaContentInternal: some View {
        ZStack(alignment: .bottom) {
            Group {
                if item.isVideo {
                    if playerManager.showRetryButton && playerManager.playerItemID == item.id {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(playerManager.playerError ?? "Video konnte nicht geladen werden")
                                .foregroundColor(.white)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            Button("Erneut versuchen") {
                                playerManager.forceRetry()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    } else if let actualPlayer = playerManager.player, playerManager.playerItemID == item.id {
                        CustomVideoPlayerRepresentable(player: actualPlayer, handler: keyboardActionHandler, onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen, horizontalSizeClass: horizontalSizeClass)
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

    private let actionIconFont: Font = .title2

    @ViewBuilder private var voteCounterView: some View {
        let benis = item.up - item.down
        HStack(spacing: 6) {
            Button(action: downvoteAction) {
                Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                    .symbolRenderingMode(.palette)
                     .foregroundStyle(currentVote == -1 ? Color.white : Color.secondary,
                                      currentVote == -1 ? Color.red : Color.secondary)
                    .font(actionIconFont)
            }
            .buttonStyle(.plain)
            .disabled(!authService.isLoggedIn)

            Text(formatBenisCount(benis))
                .font(.title.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: upvoteAction) {
                Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(currentVote == 1 ? Color.white : Color.secondary,
                                     currentVote == 1 ? Color.green : Color.secondary)
                    .font(actionIconFont)
            }
            .buttonStyle(.plain)
            .disabled(!authService.isLoggedIn)
        }
    }
    
    private func formatBenisCount(_ count: Int) -> String {
        let absCount = abs(count)
        
        if absCount >= 10000 {
            // Für Zahlen >= 10000: zeige mit "k" (z.B. 10.5k, 123k)
            let thousands = Double(count) / 1000.0
            if absCount >= 100000 {
                // Ab 100k keine Dezimalstelle (z.B. 123k)
                return String(format: "%.0fk", thousands)
            } else {
                // 10k-99k mit einer Dezimalstelle (z.B. 10.5k)
                return String(format: "%.1fk", thousands)
            }
        } else {
            // Für Zahlen < 10000: volle Zahl anzeigen
            return "\(count)"
        }
    }

    @ViewBuilder private var voteDistributionView: some View {
        let up = max(0, item.up)
        let down = max(0, item.down)
        let total = up + down
        if total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, CGFloat(up) / CGFloat(total)) * geo.size.width, height: 4)
                    }
                }
                .frame(height: 4)
                Text("\(up) up / \(down) down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var favoriteButton: some View {
        let buttonLabel = Image(systemName: isFavorited ? "heart.fill" : "heart")
            .font(actionIconFont)
            .foregroundColor(isFavorited ? .pink : .secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

        buttonLabel
            .onTapGesture {
                Task {
                    isProcessingFavorite = true
                    await toggleFavoriteAction()
                    try? await Task.sleep(for: .milliseconds(100))
                    isProcessingFavorite = false
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                DetailViewContent.logger.info("Long press on favorite button for item \(item.id).")
                showCollectionSelectionAction()
            }
            .disabled(isProcessingFavorite || !authService.isLoggedIn)
    }

    @ViewBuilder
    private var subtitleToggleButton: some View {
        if item.isVideo, let subtitles = item.subtitles, !subtitles.isEmpty {
            Button(action: cycleSubtitleModeAction) {
                Image(systemName: "captions.bubble")
                    .font(actionIconFont)
                    .foregroundColor(settings.subtitleActivationMode == .disabled ? .secondary : .accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }


    @ViewBuilder private var shareButton: some View {
        Button {
            pausePlayerForSheet()
            showingShareOptions = true
            sharePreparationError = nil
        }
        label: {
            if isPreparingShare {
                ProgressView()
                    .frame(width: 24, height: 24)
                    .padding(10)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(actionIconFont)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
    }

    @ViewBuilder private var addCommentButton: some View {
        Button { showCommentInputAction(item.id, 0) }
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


    @ViewBuilder private var uploaderInfoView: some View {
        HStack(spacing: 6) {
            UserMarkView(markValue: item.mark, showName: false)
            Text(item.user)
                .font(UIConstants.subheadlineFont.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
            Text(item.creationDate, style: .relative)
                .font(UIConstants.captionFont)
                .foregroundColor(.secondary)
            Text("ago")
                .font(UIConstants.captionFont)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard authService.isLoggedIn else {
                DetailViewContent.logger.info("Uploader info tapped, but user is not logged in. Ignoring.")
                return
            }
            DetailViewContent.logger.info("Uploader info tapped for user: \(item.user)")
            self.userProfileSheetTarget = UserProfileSheetTarget(username: item.user)
        }
    }
    
    @ViewBuilder
    private var tagsFlowLayoutView: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(displayedTags) { tag in
                VotableTagView(
                    tag: tag,
                    currentVote: authService.votedTagStates[tag.id] ?? 0,
                    isVoting: authService.isVotingTag[tag.id] ?? false,
                    onUpvote: { upvoteTagAction(tag.id) },
                    onDownvote: { downvoteTagAction(tag.id) },
                    onTapTag: {
                        if let sheetCallback = onTagTappedInSheetCallback {
                            DetailViewContent.logger.info("Tag '\(tag.tag)' tapped IN SHEET. Calling sheetCallback.")
                            pausePlayerForSheet()
                            sheetCallback(tag.tag)
                        } else {
                            DetailViewContent.logger.info("Tag '\(tag.tag)' tapped (standard). Setting tagForSheetSearch.")
                            pausePlayerForSheet()
                            self.tagForSheetSearch = tag.tag
                        }
                    }
                )
            }
            if !showingAllTags && totalTagCount > displayedTags.count {
                let remainingCount = totalTagCount - displayedTags.count
                Button { showAllTagsAction() } label: { Text("+\(remainingCount) mehr").font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.accentColor.opacity(0.15)).foregroundColor(.accentColor).clipShape(Capsule()).contentShape(Capsule()).lineLimit(1) }
                .buttonStyle(.plain)
            }
            if authService.isLoggedIn && infoLoadingStatus == .loaded {
                Button {
                    newTagText = ""
                    addTagError = nil
                    isAddingTags = false
                    showingAddTagSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }


    @ViewBuilder private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                voteCounterView
                Spacer()
                subtitleToggleButton
                if authService.isLoggedIn { addCommentButton }
                if authService.isLoggedIn { favoriteButton }
                shareButton
            }
            .frame(minHeight: 44)

            voteDistributionView

            uploaderInfoView

            if let shareError = sharePreparationError {
                Text("Fehler beim Vorbereiten: \(shareError)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 2)
            }

            Group {
                switch infoLoadingStatus {
                case .loaded:
                    tagsFlowLayoutView
                case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .error: Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .idle: Text(" ").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct VotableTagView: View {
        let tag: ItemTag
        let currentVote: Int
        let isVoting: Bool
        let onUpvote: () -> Void
        let onDownvote: () -> Void
        let onTapTag: () -> Void

        @EnvironmentObject var authService: AuthService

        private let characterLimit = 25
        private var displayText: String { tag.tag.count > characterLimit ? String(tag.tag.prefix(characterLimit - 1)) + "…" : tag.tag }
        private let tagVoteButtonFont: Font = .caption

        var body: some View {
            HStack(spacing: 4) {
                if authService.isLoggedIn {
                    Button(action: onDownvote) {
                        Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                            .font(tagVoteButtonFont)
                            .foregroundColor(currentVote == -1 ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isVoting)
                }

                Text(displayText)
                    .font(.caption)
                    .padding(.horizontal, authService.isLoggedIn ? 2 : 8)
                    .padding(.vertical, 4)
                    .contentShape(Capsule())
                    .onTapGesture(perform: onTapTag)


                if authService.isLoggedIn {
                    Button(action: onUpvote) {
                        Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                            .font(tagVoteButtonFont)
                            .foregroundColor(currentVote == 1 ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isVoting)
                }
            }
            .padding(.horizontal, authService.isLoggedIn ? 6 : 0)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .clipShape(Capsule())
        }
    }


    @ViewBuilder
    private var commentsWrapper: some View {
        if horizontalSizeClass == .regular && !settings.forcePhoneLayoutOnPadAndMac {
            regularLayout
        } else {
            compactLayout
        }
    }
    
    @ViewBuilder
    private var regularLayout: some View {
         HStack(alignment: .top, spacing: 0) {
            mediaContentInternal
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(spacing: 0) {
                infoAndTagsContent
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if authService.isLoggedIn {
                    commentsContentSectionWithScrollReader(proxyEnabled: true)
                        .padding([.horizontal, .bottom])
                } else {
                    loginHintView()
                        .padding(.horizontal)
                        .padding(.bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            // Create invisible spacer that matches tab bar height (for iPad with tab bar)
            Color.clear
                .frame(height: 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8))
        }
    }
    
    @ViewBuilder
    private var compactLayout: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        let aspect = guessAspectRatio() ?? 1.0
                        mediaContentInternal
                            .frame(width: geo.size.width, height: geo.size.width / aspect)
                    }
                    .aspectRatio(guessAspectRatio() ?? 1.0, contentMode: .fit)
                    infoAndTagsContent.padding(.horizontal).padding(.vertical, 10)
                    if authService.isLoggedIn {
                        commentsContentSection(scrollViewProxy: proxy)
                            .padding(.horizontal).padding(.bottom, 10)
                    } else {
                        loginHintView()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // Create invisible spacer that matches tab bar height
                    Color.clear
                        .frame(height: 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8))
                }
            }
            .onChange(of: infoLoadingStatus) { _, newStatus in
                if newStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                     attemptScrollToComment(proxy: proxy, targetID: tid)
                }
            }
            .onChange(of: flatComments.count) { _, _ in
                if infoLoadingStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                    attemptScrollToComment(proxy: proxy, targetID: tid)
                }
            }
            .onAppear {
                if infoLoadingStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                    attemptScrollToComment(proxy: proxy, targetID: tid)
                }
            }
        }
    }
    
    @ViewBuilder
    private func commentsContentSectionWithScrollReader(proxyEnabled: Bool) -> some View {
        if proxyEnabled {
            ScrollViewReader { proxy in
                ScrollView {
                    commentsContentSection(scrollViewProxy: proxy)
                }
                .onChange(of: infoLoadingStatus) { _, newStatus in
                    if newStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                         attemptScrollToComment(proxy: proxy, targetID: tid)
                    }
                }
                .onChange(of: flatComments.count) { _, _ in
                    if infoLoadingStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                        attemptScrollToComment(proxy: proxy, targetID: tid)
                    }
                }
                .onAppear {
                    if infoLoadingStatus == .loaded, let tid = targetCommentID, !didAttemptScrollToTarget {
                        attemptScrollToComment(proxy: proxy, targetID: tid)
                    }
                }
            }
        } else {
            commentsContentSection(scrollViewProxy: nil)
        }
    }


    @ViewBuilder
    private func commentsContentSection(scrollViewProxy: ScrollViewProxy?) -> some View {
        CommentsSection(
            flatComments: self.flatComments,
            totalCommentCount: self.totalCommentCount,
            status: self.infoLoadingStatus,
            uploaderName: self.item.user,
            previewLinkTarget: self.$previewLinkTarget,
            userProfileSheetTarget: self.$userProfileSheetTarget,
            isCommentCollapsed: self.isCommentCollapsed,
            toggleCollapseAction: self.toggleCollapseAction,
            showCommentInputAction: { parentId in self.showCommentInputAction(self.item.id, parentId) },
            targetCommentID: self.targetCommentID,
            onHighlightCompletedForCommentID: self.onHighlightCompletedForCommentID,
            onUpvoteComment: { commentId in self.upvoteCommentAction(commentId) },
            onDownvoteComment: { commentId in self.downvoteCommentAction(commentId) }
        )
    }
    
    private func attemptScrollToComment(proxy: ScrollViewProxy?, targetID: Int) {
        guard let proxy = proxy else {
            DetailViewContent.logger.warning("AttemptScroll: ScrollViewProxy is nil.")
            return
        }
        guard flatComments.contains(where: { $0.id == targetID }) else {
            DetailViewContent.logger.info("AttemptScroll: Target comment ID \(targetID) not found in current flatComments. Scroll not attempted yet.")
            return
        }

        DetailViewContent.logger.info("Attempting to scroll to comment ID: \(targetID)")
        didAttemptScrollToTarget = true

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation {
                proxy.scrollTo(targetID, anchor: .top)
            }
            DetailViewContent.logger.info("Scroll to comment ID \(targetID) requested with anchor: .top")
        }
    }
    
    private func pausePlayerForSheet() {
        if playerManager.player?.timeControlStatus == .playing {
            wasPlayingBeforeAnySheet = true
            playerManager.player?.pause()
            DetailViewContent.logger.debug("Player paused because a sheet is about to open.")
        } else {
            wasPlayingBeforeAnySheet = false
            DetailViewContent.logger.debug("Player was not playing when sheet was triggered.")
        }
    }

    private func resumePlayerIfNeeded() {
        if wasPlayingBeforeAnySheet {
            let appIsActive = UIApplication.shared.applicationState == .active
            if item.isVideo, item.id == playerManager.playerItemID, !onWillBeginFullScreenCalledRecently, appIsActive {
                playerManager.player?.play()
                DetailViewContent.logger.debug("Player resumed after sheet dismissed (not fullscreen, app active).")
            } else {
                DetailViewContent.logger.debug("Not resuming player: conditions not met (item not video/player changed, or fullscreen, or app not active).")
            }
        }
        wasPlayingBeforeAnySheet = false
    }
    private var onWillBeginFullScreenCalledRecently: Bool { false }


    var body: some View {
        ZStack {
            commentsWrapper
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                DetailViewContent.logger.debug("DetailViewContent for item \(item.id) appearing. TargetCommentID: \(targetCommentID ?? -1)")
                didAttemptScrollToTarget = false
            }
            .onDisappear {
                DetailViewContent.logger.debug("DetailViewContent for item \(item.id) disappearing.")
            }
            .confirmationDialog(
                "Teilen & Kopieren", isPresented: $showingShareOptions, titleVisibility: .visible
            ) {
                Button("Medium teilen/speichern") {
                    Task { await prepareAndShareMedia() }
                }
                Button("Post-Link (pr0gramm.com)") {
                    let urlString = "https://pr0gramm.com/new/\(item.id)"
                    UIPasteboard.general.string = urlString
                    DetailViewContent.logger.info("Copied Post-Link to clipboard: \(urlString)")
                    triggerCopyFeedback(message: "Post-Link kopiert")
                }
                Button("Direkter Medien-Link") {
                    if let urlString = item.imageUrl?.absoluteString {
                        UIPasteboard.general.string = urlString
                        DetailViewContent.logger.info("Copied Media-Link to clipboard: \(urlString)")
                        triggerCopyFeedback(message: "Direkter Link kopiert")
                    } else {
                        DetailViewContent.logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)")
                    }
                }
            } message: { Text("Wähle eine Aktion:") }
            .sheet(item: $itemToShare, onDismiss: {
                if let tempUrl = itemToShare?.temporaryFileUrlToDelete {
                    deleteTemporaryFile(at: tempUrl)
                }
                resumePlayerIfNeeded()
            }) { shareableItemWrapper in
                ShareSheet(activityItems: shareableItemWrapper.itemsToShare)
            }
            .onChange(of: targetCommentID) { _, newTargetID in
                DetailViewContent.logger.debug("targetCommentID in DetailViewContent changed to: \(newTargetID ?? -1). Resetting didAttemptScrollToTarget.")
                didAttemptScrollToTarget = false
            }
            .onChange(of: authService.votedTagStates) { _, _ in
                DetailViewContent.logger.trace("Detected change in authService.votedTagStates")
            }
            .sheet(isPresented: $showingAddTagSheet) {
                addTagSheetContent()
            }
            .sheet(item: $tagForSheetSearch, onDismiss: resumePlayerIfNeeded) { tappedTagString in
                 TagSearchViewWrapper(initialTag: tappedTagString, onNewTagSelected: { newTagFromSheet in
                     DetailViewContent.logger.info("Received new tag '\(newTagFromSheet)' from TagSearchViewWrapper. Updating tagForSheetSearch.")
                     pausePlayerForSheet()
                     self.tagForSheetSearch = newTagFromSheet
                 })
                 .environmentObject(settings)
                 .environmentObject(authService)
             }
            
            // Visual Copy Feedback Overlay (Zentriert)
            if let message = copyFeedbackMessage {
                Text(message)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.black.opacity(0.85)).shadow(radius: 4))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
    
    private func triggerCopyFeedback(message: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copyFeedbackMessage = message
        }
        
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) {
                if copyFeedbackMessage == message {
                    copyFeedbackMessage = nil
                }
            }
        }
    }
    
    struct TagSearchViewWrapper: View {
        @State var currentTag: String
        let onNewTagSelected: (String) -> Void

        @StateObject private var localPlayerManager = VideoPlayerManager()
        @EnvironmentObject var settings: AppSettings
        @EnvironmentObject var authService: AuthService

        init(initialTag: String, onNewTagSelected: @escaping (String) -> Void) {
            self._currentTag = State(initialValue: initialTag)
            self.onNewTagSelected = onNewTagSelected
            DetailViewContent.logger.debug("TagSearchViewWrapper init. initialTag: \(initialTag), onNewTagSelected closure is set.")
        }
        
        var body: some View {
            TagSearchView(
                currentSearchTag: $currentTag,
                onNewTagSelectedInSheet: { newTagClickedInSheet in
                    DetailViewContent.logger.debug("TagSearchViewWrapper: Tag '\(newTagClickedInSheet)' clicked inside sheet's PagedDetailView. Calling onNewTagSelected (outer callback).")
                    self.onNewTagSelected(newTagClickedInSheet)
                }
            )
                .task { localPlayerManager.configure(settings: settings) }
                .environmentObject(localPlayerManager)
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }


    @ViewBuilder
    private func addTagSheetContent() -> some View {
        NavigationStack {
            VStack(spacing: 15) {
                Text("Neue Tags eingeben (kommasepariert):")
                    .font(UIConstants.headlineFont)
                    .padding(.top)

                TextEditor(text: $newTagText)
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color.gray.opacity(0.3))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Neue Tags")
                
                Text("Es kann etwas dauern, bis die neuen Tags angezeigt werden und von anderen Nutzern bewertet werden können.")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                if let error = addTagError {
                    Text("Fehler: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()
                
                if isAddingTags {
                    ProgressView("Speichere Tags...")
                        .padding(.bottom)
                }
            }
            .padding()
            .navigationTitle("Tags hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showingAddTagSheet = false }
                        .disabled(isAddingTags)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            isAddingTags = true
                            addTagError = nil
                            if let errorMsg = await addTagsAction(newTagText) {
                                addTagError = errorMsg
                                DetailViewContent.logger.error("Fehler beim Hinzufügen von Tags: \(errorMsg)")
                            } else {
                                showingAddTagSheet = false
                            }
                            isAddingTags = false
                        }
                    }
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingTags)
                }
            }
        }
        .interactiveDismissDisabled(isAddingTags)
    }


    private func guessAspectRatio() -> CGFloat? {
        guard item.width > 0, item.height > 0 else { return 1.0 }
        return CGFloat(item.width) / CGFloat(item.height)
    }

    private func prepareAndShareMedia() async {
        guard let mediaUrl = item.imageUrl else {
            DetailViewContent.logger.error("Cannot share media: URL is nil for item \(item.id)")
            sharePreparationError = "Medien-URL nicht verfügbar."
            return
        }

        isPreparingShare = true
        sharePreparationError = nil
        var temporaryFileToDelete: URL? = nil

        defer {
            isPreparingShare = false
        }

        if item.isVideo {
            DetailViewContent.logger.info("Attempting to download video for sharing from URL: \(mediaUrl.absoluteString)")
            do {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                let fileName = mediaUrl.lastPathComponent
                let localUrl = temporaryDirectory.appendingPathComponent(fileName)
                temporaryFileToDelete = localUrl

                let (downloadedUrl, response) = try await URLSession.shared.download(from: mediaUrl)
                
                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    DetailViewContent.logger.error("Video download failed with status code: \(statusCode)")
                    sharePreparationError = "Video-Download fehlgeschlagen (Code: \(statusCode))."
                    return
                }
                
                if FileManager.default.fileExists(atPath: localUrl.path) {
                    try FileManager.default.removeItem(at: localUrl)
                }
                try FileManager.default.moveItem(at: downloadedUrl, to: localUrl)

                DetailViewContent.logger.info("Video downloaded successfully to: \(localUrl.path)")
                itemToShare = ShareableItemWrapper(itemsToShare: [localUrl], temporaryFileUrlToDelete: localUrl)

            } catch {
                DetailViewContent.logger.error("Failed to download video for sharing (item \(item.id)): \(error.localizedDescription)")
                sharePreparationError = "Video-Download fehlgeschlagen."
                itemToShare = ShareableItemWrapper(itemsToShare: [mediaUrl])
            }
        } else {
            DetailViewContent.logger.info("Attempting to download image for sharing from URL: \(mediaUrl.absoluteString)")
            do {
                let result: Result<ImageLoadingResult, KingfisherError> = await withCheckedContinuation { continuation in
                    KingfisherManager.shared.downloader.downloadImage(with: mediaUrl, options: nil) { result in
                        continuation.resume(returning: result)
                    }
                }
                
                switch result {
                case .success(let imageLoadingResult):
                    let downloadedImage = imageLoadingResult.image
                    DetailViewContent.logger.info("Image downloaded and prepared successfully for sharing.")
                    itemToShare = ShareableItemWrapper(itemsToShare: [downloadedImage])
                case .failure(let error):
                    if error.isTaskCancelled || error.isNotCurrentTask {
                        DetailViewContent.logger.info("Image download for sharing cancelled (item \(item.id)).")
                    } else {
                        DetailViewContent.logger.error("Failed to download image for sharing (item \(item.id)): \(error.localizedDescription)")
                        sharePreparationError = "Bild-Download fehlgeschlagen."
                    }
                }
            }
        }
    }

    private func deleteTemporaryFile(at url: URL) {
        Task(priority: .background) {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    DetailViewContent.logger.info("Successfully deleted temporary shared file: \(url.path)")
                }
            } catch {
                DetailViewContent.logger.error("Error deleting temporary shared file \(url.path): \(error.localizedDescription)")
            }
        }
    }


    @ViewBuilder
    private func loginHintView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundColor(.accentColor)
            Text("Bitte logge dich ein, um Kommentare zu sehen.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }
}

// --- Preview Code ---
@MainActor
struct PreviewWrapper: View {
    @State var previewLinkTarget: PreviewLinkTarget? = nil
    @State var userProfileSheetTarget: UserProfileSheetTarget? = nil
    @State var fullscreenTarget: FullscreenImageTarget? = nil
    @State var collapsedIDs: Set<Int> = []
    @StateObject var settings = AppSettings()
    @StateObject var authService: AuthService
    @StateObject var navService = NavigationService()
    @StateObject var playerManager = VideoPlayerManager()
    @State private var commentReplyTarget: ReplyTarget? = nil
    @State private var collectionSelectionSheetTarget: CollectionSelectionSheetTarget? = nil
    @State private var previewTargetCommentID: Int? = 2

    let sampleItem: Item

    init(isLoggedIn: Bool = true) {
        let tempSettings = AppSettings()
        _settings = StateObject(wrappedValue: tempSettings)
        let tempAuthService = AuthService(appSettings: tempSettings)

        tempAuthService.isLoggedIn = isLoggedIn
        if isLoggedIn {
            let collections = [
                ApiCollection(id: 1, name: "Standard", keyword: "standard", isPublic: 0, isDefault: 1, itemCount: 10),
                ApiCollection(id: 2, name: "Lustig", keyword: "lustig", isPublic: 0, isDefault: 0, itemCount: 5)
            ]
            tempAuthService.currentUser = UserInfo(id: 99, name: "PreviewUser", registered: 1, score: 100, mark: 1, badges: nil, collections: collections)
            #if DEBUG
            tempAuthService.setUserCollectionsForPreview(collections)
            #endif
            tempAuthService.userNonce = "preview_nonce"
            tempAuthService.favoritedItemIDs = [2]
            tempAuthService.votedItemStates = [1: 1]
            tempAuthService.votedTagStates = [1:1, 3:-1]
            tempSettings.selectedCollectionIdForFavorites = 1
        }
         _authService = StateObject(wrappedValue: tempAuthService)
         self.sampleItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, subtitles: nil, favorited: isLoggedIn ? true : false)
    }

    func toggleCollapse(_ id: Int) { if collapsedIDs.contains(id) { collapsedIDs.remove(id) } else { collapsedIDs.insert(id) } }
    func isCollapsed(_ id: Int) -> Bool { collapsedIDs.contains(id) }

    var body: some View {
        let previewHandler = KeyboardActionHandler()
        let previewTags: [ItemTag] = [ ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"), ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt") ]
        let sampleComments = [ ItemComment(id: 1, parent: 0, content: "Kommentar 1 http://pr0gramm.com/new/54321", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1, itemId: 2), ItemComment(id: 2, parent: 1, content: "Antwort 1.1", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "User2", mark: 2, itemId: 2) ]
        let previewFlatComments = flattenHierarchyForPreview(comments: sampleComments)

        NavigationStack {
            DetailViewContent(
                item: sampleItem,
                keyboardActionHandler: previewHandler,
                playerManager: playerManager,
                currentSubtitleText: "Dies ist ein Test-Untertitel",
                onWillBeginFullScreen: {}, onWillEndFullScreen: {},
                displayedTags: Array(previewTags.prefix(4)),
                totalTagCount: previewTags.count,
                showingAllTags: false,
                flatComments: previewFlatComments,
                totalCommentCount: previewFlatComments.count,
                infoLoadingStatus: .loaded,
                previewLinkTarget: $previewLinkTarget,
                userProfileSheetTarget: $userProfileSheetTarget,
                fullscreenImageTarget: $fullscreenTarget,
                isFavorited: authService.favoritedItemIDs.contains(sampleItem.id),
                toggleFavoriteAction: { Task { print("Preview Toggle Fav (Standard Collection)") } },
                showCollectionSelectionAction: {
                    print("Preview: Show Collection Selection Tapped")
                    self.collectionSelectionSheetTarget = CollectionSelectionSheetTarget(item: sampleItem)
                },
                showAllTagsAction: {},
                isCommentCollapsed: isCollapsed,
                toggleCollapseAction: toggleCollapse,
                currentVote: authService.votedItemStates[sampleItem.id] ?? 0,
                upvoteAction: { print("Preview Upvote Tapped") },
                downvoteAction: { print("Preview Downvote Tapped") },
                showCommentInputAction: { itemId, parentId in
                     print("Preview Show Comment Input Tapped for itemId: \(itemId), parentId: \(parentId)")
                     self.commentReplyTarget = ReplyTarget(itemId: itemId, parentId: parentId)
                },
                targetCommentID: previewTargetCommentID,
                onHighlightCompletedForCommentID: { completedID in
                    print("Preview: Highlight completed for comment \(completedID), clearing previewTargetCommentID.")
                    if previewTargetCommentID == completedID {
                        previewTargetCommentID = nil
                    }
                },
                upvoteTagAction: { tagId in print("Preview: Upvote Tag \(tagId)") },
                downvoteTagAction: { tagId in print("Preview: Downvote Tag \(tagId)") },
                addTagsAction: { tagsToAdd in
                    print("Preview: Add tags action called with: \(tagsToAdd)")
                    try? await Task.sleep(for: .seconds(1))
                    return nil
                },
                upvoteCommentAction: { commentId in print("Preview: Upvote comment \(commentId)") },
                downvoteCommentAction: { commentId in print("Preview: Downvote comment \(commentId)") },
                cycleSubtitleModeAction: {
                    print("Preview: Cycle subtitle mode tapped.")
                    settings.cycleSubtitleMode()
                },
                onTagTappedInSheetCallback: nil
            )
            .sheet(item: $commentReplyTarget) { target in CommentInputView(itemId: target.itemId, parentId: target.parentId, onSubmit: { _ in }) }
            .sheet(item: $userProfileSheetTarget) { target in Text("Preview: User Profile Sheet for \(target.username)") }
            .sheet(item: $fullscreenTarget) { target in FullscreenImageView(item: target.item) }
            .sheet(item: $collectionSelectionSheetTarget) { target in
                CollectionSelectionView(item: target.item) { selectedCollection in
                     print("Preview: Collection '\(selectedCollection.name)' selected.")
                }
                .environmentObject(authService)
                .environmentObject(settings)
            }
            .environmentObject(navService)
            .environmentObject(settings)
            .environmentObject(authService)
            .environment(\.horizontalSizeClass, .compact)
            .preferredColorScheme(.dark)
            .task { playerManager.configure(settings: settings) }
        }
    }
}

@MainActor func flattenHierarchyForPreview(comments: [ItemComment], maxDepth: Int = .max) -> [FlatCommentDisplayItem] {
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

#Preview("Compact - Limited Tags (Logged In)") {
    PreviewWrapper(isLoggedIn: true)
}

#Preview("Compact - Limited Tags (Logged Out)") {
     PreviewWrapper(isLoggedIn: false)
}
// --- END OF COMPLETE FILE ---

