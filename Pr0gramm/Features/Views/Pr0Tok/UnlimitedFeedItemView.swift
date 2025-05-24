// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/UnlimitedFeedItemView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

fileprivate struct UnlimitedVotableTagView: View {
    let tag: ItemTag
    let currentVote: Int
    let isVoting: Bool
    let truncateText: Bool
    let onUpvote: () -> Void
    let onDownvote: () -> Void
    let onTapTag: () -> Void

    @EnvironmentObject var authService: AuthService

    private let characterLimit = 10
    private var displayText: String {
        if truncateText && tag.tag.count > characterLimit {
            return String(tag.tag.prefix(characterLimit)) + "…"
        }
        return tag.tag
    }
    private let tagVoteButtonFont: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            if authService.isLoggedIn {
                Button(action: onDownvote) {
                    Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == -1 ? .red : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }

            Text(displayText)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, authService.isLoggedIn ? 2 : 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
                .onTapGesture(perform: onTapTag)


            if authService.isLoggedIn {
                Button(action: onUpvote) {
                    Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == 1 ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }
        }
        .padding(.horizontal, authService.isLoggedIn ? 6 : 0)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}


struct UnlimitedFeedItemView: View {
    let itemData: UnlimitedFeedItemDataModel
    @ObservedObject var playerManager: VideoPlayerManager
    @ObservedObject var keyboardActionHandlerForVideo: KeyboardActionHandler
    let isActive: Bool
    let isDummyItem: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UnlimitedFeedItemView")

    let onToggleShowAllTags: () -> Void
    let onUpvoteTag: (Int) -> Void
    let onDownvoteTag: (Int) -> Void
    let onTagTapped: (String) -> Void
    let onRetryLoadDetails: () -> Void
    let onShowAddTagSheet: () -> Void
    let onShowFullscreenImage: (Item) -> Void
    let onToggleFavorite: () -> Void
    let onShowCollectionSelection: () -> Void
    let onShareTapped: () -> Void
    let isProcessingFavorite: Bool


    var item: Item { itemData.item }
    
    @State private var showingCommentsSheet = false
    
    private let initialVisibleTagCountInItemView = 2


    var body: some View {
        ZStack {
            mediaContentLayer
                .zIndex(0)
                .onTapGesture {
                    if !item.isVideo && !isDummyItem {
                        onShowFullscreenImage(item)
                    }
                }
                .allowsHitTesting(!item.isVideo && !isDummyItem)

            if !isDummyItem {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("@\(item.user)")
                                .font(.headline).bold()
                                .foregroundColor(.white)
                            
                            tagSection
                        }
                        .padding(.leading)
                        .padding(.bottom, bottomSafeAreaPadding)

                        Spacer()

                        interactionButtons
                            .padding(.trailing)
                            .padding(.bottom, bottomSafeAreaPadding)
                    }
                    .padding(.bottom, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .zIndex(1)
            }
        }
        .background(Color.black)
        .clipped()
        .onChange(of: isActive) { oldValue, newValue in
            if isDummyItem { return }

            if newValue {
                if item.isVideo && playerManager.playerItemID == item.id {
                    if playerManager.player?.timeControlStatus != .playing {
                        playerManager.player?.play()
                        Self.logger.debug("UnlimitedFeedItemView: Player started via isActive change for item \(item.id)")
                    }
                } else if item.isVideo {
                    playerManager.setupPlayerIfNeeded(for: item, isFullscreen: false)
                    Self.logger.debug("UnlimitedFeedItemView: Player setup initiated via isActive for item \(item.id)")
                     Task {
                         try? await Task.sleep(for: .milliseconds(100))
                         if self.isActive && playerManager.playerItemID == item.id && playerManager.player?.timeControlStatus != .playing {
                             playerManager.player?.play()
                             Self.logger.debug("UnlimitedFeedItemView: Explicit play after setup for item \(item.id)")
                         }
                     }
                }
            } else {
                if item.isVideo && playerManager.playerItemID == item.id {
                     playerManager.player?.pause()
                     Self.logger.debug("UnlimitedFeedItemView: Player paused via isActive change for item \(item.id)")
                }
            }
        }
        .sheet(isPresented: $showingCommentsSheet) {
            ItemCommentsSheetView(
                itemId: itemData.item.id,
                uploaderName: itemData.item.user,
                initialComments: itemData.comments,
                initialInfoStatusProp: itemData.itemInfoStatus,
                onRetryLoadDetails: onRetryLoadDetails
            )
            .environmentObject(settings)
            .environmentObject(authService)
        }
    }
    
    private var bottomSafeAreaPadding: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }


    @ViewBuilder
    private var mediaContentLayer: some View {
        if isDummyItem {
            Image("pr0tok")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(50)
        } else if item.isVideo {
             if isActive, let player = playerManager.player, playerManager.playerItemID == item.id {
                 CustomVideoPlayerRepresentable(
                     player: player,
                     handler: keyboardActionHandlerForVideo,
                     onWillBeginFullScreen: { /* TODO */ },
                     onWillEndFullScreen: { /* TODO */ },
                     horizontalSizeClass: nil
                 )
                 .id("video_\(item.id)")
             } else {
                 KFImage(item.thumbnailUrl)
                     .resizable()
                     .aspectRatio(contentMode: .fill)
                     .overlay(Color.black.opacity(0.3))
                     .overlay(ProgressView().scaleEffect(1.5).tint(.white).opacity(isActive && playerManager.playerItemID != item.id ? 1 : 0))
             }
        } else {
            KFImage(item.imageUrl)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
        
    @ViewBuilder
    private var tagSection: some View {
        if isDummyItem { EmptyView() } else {
            switch itemData.itemInfoStatus {
            case .loading:
                ProgressView().tint(.white).scaleEffect(0.7)
            case .error(let msg):
                VStack(alignment: .leading) {
                    Text("Tags nicht geladen.")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Erneut versuchen") {
                        onRetryLoadDetails()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                }
            case .loaded:
                if !itemData.displayedTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(itemData.displayedTags) { tag in
                            UnlimitedVotableTagView(
                                tag: tag,
                                currentVote: authService.votedTagStates[tag.id] ?? 0,
                                isVoting: authService.isVotingTag[tag.id] ?? false,
                                truncateText: true,
                                onUpvote: { onUpvoteTag(tag.id) },
                                onDownvote: { onDownvoteTag(tag.id) },
                                onTapTag: { onTagTapped(tag.tag) }
                            )
                        }
                        if itemData.totalTagCount > itemData.displayedTags.count {
                            let remainingCount = itemData.totalTagCount - itemData.displayedTags.count
                            Button {
                                onToggleShowAllTags()
                            } label: {
                                Text("+\(remainingCount) mehr")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else if authService.isLoggedIn && itemData.totalTagCount == 0 {
                            Button {
                                onShowAddTagSheet()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.callout)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else if itemData.totalTagCount > 0 {
                    Text("Keine Tags (Filter?).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else if authService.isLoggedIn {
                     Button {
                        onShowAddTagSheet()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            default:
                Text("Lade Tags...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    @ViewBuilder
    private var interactionButtons: some View {
        if isDummyItem {
            EmptyView()
        } else {
            VStack(spacing: 25) {
                // Herz-Button (Favoriten)
                Button {
                    onToggleFavorite() // Klick auf Herz = Standardfavoriten
                } label: {
                    if isProcessingFavorite {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: itemData.isFavorited ? "heart.fill" : "heart")
                            .font(.title)
                            .foregroundColor(itemData.isFavorited ? .pink : .white)
                    }
                }
                .disabled(isProcessingFavorite || !authService.isLoggedIn)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            // --- DEBUG LOGS ---
                            Self.logger.debug("Long press detected on heart button for item \(item.id). Calling onShowCollectionSelection.")
                            if authService.isLoggedIn && !isProcessingFavorite {
                                Self.logger.debug("Conditions met (isLoggedIn: \(authService.isLoggedIn), !isProcessingFavorite: \(!isProcessingFavorite)), actually calling onShowCollectionSelection.")
                                onShowCollectionSelection()
                            } else {
                                Self.logger.debug("Conditions for onShowCollectionSelection NOT met. isLoggedIn: \(authService.isLoggedIn), isProcessingFavorite: \(isProcessingFavorite)")
                            }
                            // --- END DEBUG LOGS ---
                        }
                )
                
                // Kommentar-Button
                Button {
                    Self.logger.info("Kommentar-Button getippt für Item \(item.id)")
                    showingCommentsSheet = true
                } label: {
                    Image(systemName: "message.fill").font(.title).foregroundColor(.white)
                }

                // Teilen-Button
                Button {
                    onShareTapped()
                } label: {
                    Image(systemName: "arrowshape.turn.up.right.fill").font(.title).foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navService = NavigationService()
    settings.enableUnlimitedStyleFeed = true
    
    let dummyItem = Item(id: 1, promoted: nil, userId: 1, down: 0, up: 10, created: 0, image: "dummy.jpg", thumb: "dummy_thumb.jpg", fullsize: nil, preview: nil, width: 100, height: 100, audio: false, source: nil, flags: 1, user: "User", mark: 1, repost: false, variants: nil, subtitles: nil)
    let sampleItemData = UnlimitedFeedItemDataModel(
        item: dummyItem,
        displayedTags: [ItemTag(id: 1, confidence: 1, tag: "Tag1")],
        totalTagCount: 1,
        comments: [],
        itemInfoStatus: .loaded,
        isFavorited: false,
        currentVote: 0
    )
    
    let dummyKeyboardHandler = KeyboardActionHandler()
    
    return UnlimitedFeedItemView(
        itemData: sampleItemData,
        playerManager: VideoPlayerManager(),
        keyboardActionHandlerForVideo: dummyKeyboardHandler,
        isActive: true,
        isDummyItem: false,
        onToggleShowAllTags: {},
        onUpvoteTag: { _ in },
        onDownvoteTag: { _ in },
        onTagTapped: { _ in },
        onRetryLoadDetails: {},
        onShowAddTagSheet: {},
        onShowFullscreenImage: { _ in },
        onToggleFavorite: {},
        onShowCollectionSelection: {},
        onShareTapped: {},
        isProcessingFavorite: false
    )
    .environmentObject(settings)
    .environmentObject(authService)
    .environmentObject(navService)
}
// --- END OF COMPLETE FILE ---
