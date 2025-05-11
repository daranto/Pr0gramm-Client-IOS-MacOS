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

struct ShareableItemWrapper: Identifiable {
    let id = UUID()
    let itemsToShare: [Any]
    // --- NEW: Optional URL of a temporary file to be deleted after sharing ---
    let temporaryFileUrlToDelete: URL?

    init(itemsToShare: [Any], temporaryFileUrlToDelete: URL? = nil) {
        self.itemsToShare = itemsToShare
        self.temporaryFileUrlToDelete = temporaryFileUrlToDelete
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

    @ViewBuilder private var mediaContentInternal: some View {
        ZStack(alignment: .bottom) {
            Group {
                if item.isVideo {
                    if let actualPlayer = playerManager.player, playerManager.playerItemID == item.id {
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
            Button(action: upvoteAction) {
                Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
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
                Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
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


    @ViewBuilder private var shareButton: some View {
        Button { showingShareOptions = true; sharePreparationError = nil }
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

    @ViewBuilder private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 15) {
                voteCounterView
                Spacer()
                if authService.isLoggedIn { addCommentButton }
                if authService.isLoggedIn { favoriteButton }
                shareButton
            }
            .frame(minHeight: 44)

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
            uploaderName: item.user,
            previewLinkTarget: $previewLinkTarget,
            userProfileSheetTarget: $userProfileSheetTarget,
            isCommentCollapsed: isCommentCollapsed,
            toggleCollapseAction: toggleCollapseAction,
            showCommentInputAction: { parentId in showCommentInputAction(item.id, parentId) }
        )
    }

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
        .onAppear { DetailViewContent.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { DetailViewContent.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
        .confirmationDialog(
            "Teilen & Kopieren", isPresented: $showingShareOptions, titleVisibility: .visible
        ) {
            Button("Medium teilen/speichern") {
                Task { await prepareAndShareMedia() }
            }
            Button("Post-Link (pr0gramm.com)") { let urlString = "https://pr0gramm.com/new/\(item.id)"; UIPasteboard.general.string = urlString; DetailViewContent.logger.info("Copied Post-Link to clipboard: \(urlString)") }
            Button("Direkter Medien-Link") { if let urlString = item.imageUrl?.absoluteString { UIPasteboard.general.string = urlString; DetailViewContent.logger.info("Copied Media-Link to clipboard: \(urlString)") } else { DetailViewContent.logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)") } }
        } message: { Text("Wähle eine Aktion:") }
        .sheet(item: $itemToShare, onDismiss: { // --- NEW: Cleanup on dismiss ---
            if let tempUrl = itemToShare?.temporaryFileUrlToDelete {
                deleteTemporaryFile(at: tempUrl)
            }
        }) { shareableItemWrapper in
            ShareSheet(activityItems: shareableItemWrapper.itemsToShare)
        }
    }

    private func guessAspectRatio() -> CGFloat? {
        guard item.width > 0, item.height > 0 else { return 1.0 }
        return CGFloat(item.width) / CGFloat(item.height)
    }

    // --- MODIFIED: prepareAndShareMedia for Video Download ---
    private func prepareAndShareMedia() async {
        guard let mediaUrl = item.imageUrl else {
            DetailViewContent.logger.error("Cannot share media: URL is nil for item \(item.id)")
            sharePreparationError = "Medien-URL nicht verfügbar."
            return
        }

        isPreparingShare = true
        sharePreparationError = nil
        var temporaryFileToDelete: URL? = nil // To store URL of downloaded video

        defer {
            isPreparingShare = false
            // Important: Do not delete temporaryFileToDelete here.
            // It needs to exist while the ShareSheet is presented.
            // Deletion will be handled in the .onDismiss of the sheet.
        }

        if item.isVideo {
            DetailViewContent.logger.info("Attempting to download video for sharing from URL: \(mediaUrl.absoluteString)")
            do {
                // Create a temporary file URL
                let temporaryDirectory = FileManager.default.temporaryDirectory
                let fileName = mediaUrl.lastPathComponent
                let localUrl = temporaryDirectory.appendingPathComponent(fileName)
                temporaryFileToDelete = localUrl // Store for later deletion

                // Download the video file
                let (downloadedUrl, response) = try await URLSession.shared.download(from: mediaUrl)
                
                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    DetailViewContent.logger.error("Video download failed with status code: \(statusCode)")
                    sharePreparationError = "Video-Download fehlgeschlagen (Code: \(statusCode))."
                    return
                }
                
                // Move the downloaded file from its temporary location to our desired localUrl
                // Ensure previous file is removed if it exists
                if FileManager.default.fileExists(atPath: localUrl.path) {
                    try FileManager.default.removeItem(at: localUrl)
                }
                try FileManager.default.moveItem(at: downloadedUrl, to: localUrl)

                DetailViewContent.logger.info("Video downloaded successfully to: \(localUrl.path)")
                itemToShare = ShareableItemWrapper(itemsToShare: [localUrl], temporaryFileUrlToDelete: localUrl)

            } catch {
                DetailViewContent.logger.error("Failed to download video for sharing (item \(item.id)): \(error.localizedDescription)")
                sharePreparationError = "Video-Download fehlgeschlagen."
                // Fallback to sharing the remote URL if download fails
                itemToShare = ShareableItemWrapper(itemsToShare: [mediaUrl])
            }
        } else { // Image
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
    // --- END MODIFICATION ---

    // --- NEW: Function to delete temporary file ---
    private func deleteTemporaryFile(at url: URL) {
        Task(priority: .background) { // Perform deletion in background
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
    // --- END NEW ---
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    // --- NEW: Completion handler ---
    var completionHandler: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil
    // --- END NEW ---

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        // --- NEW: Set completion handler ---
        controller.completionWithItemsHandler = completionHandler
        // --- END NEW ---
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update here
    }
}

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
                }
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

#Preview("Compact - Limited Tags (Logged In)") {
    PreviewWrapper(isLoggedIn: true)
}

#Preview("Compact - Limited Tags (Logged Out)") {
     PreviewWrapper(isLoggedIn: false)
}
// --- END OF COMPLETE FILE ---
