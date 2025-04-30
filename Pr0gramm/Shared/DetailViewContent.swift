// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit
import Combine
import os
import Kingfisher // <-- Wieder benötigt
// import SDWebImageSwiftUI // Wird nicht mehr verwendet
import UIKit // Für UIFont extension

// MARK: - DetailImageView (Using KFImage with correct modifier order for stable layout)
@MainActor
struct DetailImageView: View {
    let item: Item
    let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailImageView")
    let horizontalSizeClass: UserInterfaceSizeClass?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?

    var body: some View {
        KFImage(item.imageUrl)
            // KFImage specific modifiers first
            .placeholder { Rectangle().fill(.secondary.opacity(0.1)).overlay(ProgressView()) }
            .onFailure { error in logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)") }
            .cancelOnDisappear(true)
            // Sizing modifiers
            .resizable()
            .aspectRatio(contentMode: .fit) // Use ContentMode.fit
            // General view modifiers last
            .id(item.id) // Keep ID modifier
            .background(Color.black)
            .clipped()
            .onTapGesture { if !item.isVideo { logger.info("Image tapped for item \(item.id), setting fullscreen target."); fullscreenImageTarget = FullscreenImageTarget(item: item) } }
            .disabled(item.isVideo)
    }
}


// InfoLoadingStatus enum (unchanged)
enum InfoLoadingStatus: Equatable { case idle; case loading; case loaded; case error(String) }


/// The main content area for the item detail view, arranging media, info, tags, and comments.
@MainActor
struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void

    let displayedTags: [ItemTag]
    let totalTagCount: Int
    let showingAllTags: Bool

    let flatComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int // Receive total count

    let infoLoadingStatus: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void

    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")
    @State private var isProcessingFavorite = false

    // MARK: - Computed View Properties
    @ViewBuilder private var mediaContentInternal: some View {
        Group {
            if item.isVideo {
                if let player = player {
                    CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler, onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen, horizontalSizeClass: horizontalSizeClass).id(item.id)
                } else { Rectangle().fill(.black).overlay(ProgressView().tint(.white)) }
            } else {
                // Using DetailImageView with KFImage (layout stable, GIF static)
                DetailImageView(item: item, horizontalSizeClass: horizontalSizeClass, fullscreenImageTarget: $fullscreenImageTarget)
            }
        }
    }
    @ViewBuilder private var voteCounterView: some View {
        let benis = item.up - item.down
        VStack(alignment: .leading, spacing: 2) {
            Text("\(benis)").font(.largeTitle).fontWeight(.medium).foregroundColor(.primary).lineLimit(1)
            HStack(spacing: 8) {
                HStack(spacing: 3) { Image(systemName: "arrow.up.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .green).imageScale(.small); Text("\(item.up)").font(.caption).foregroundColor(.secondary) }
                HStack(spacing: 3) { Image(systemName: "arrow.down.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .red).imageScale(.small); Text("\(item.down)").font(.caption).foregroundColor(.secondary) }
            }
        }
    }
    @ViewBuilder private var favoriteButton: some View {
        Button { Task { isProcessingFavorite = true; await toggleFavoriteAction(); try? await Task.sleep(for: .milliseconds(100)); isProcessingFavorite = false } }
        label: { Image(systemName: isFavorited ? "heart.fill" : "heart").imageScale(.large).foregroundColor(isFavorited ? .pink : .secondary).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .buttonStyle(.plain).disabled(isProcessingFavorite || !authService.isLoggedIn)
    }
    @ViewBuilder private var infoAndTagsContent: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 15) { voteCounterView; if authService.isLoggedIn { favoriteButton.padding(.top, 5) }; Spacer() }
            }.fixedSize(horizontal: true, vertical: false)
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
                    } else { Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }
                case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .error: Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .idle: Text(" ").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) // Placeholder to maintain layout consistency
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    struct TagView: View {
        let tag: ItemTag; private let characterLimit = 25
        private var displayText: String { tag.tag.count > characterLimit ? String(tag.tag.prefix(characterLimit - 1)) + "…" : tag.tag }
        var body: some View { Text(displayText).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.2)).foregroundColor(.primary).clipShape(Capsule()) }
    }

    /// Instantiates CommentsSection, passing the flat list and total count.
    @ViewBuilder private var commentsContent: some View {
        CommentsSection(
            flatComments: flatComments,
            totalCommentCount: totalCommentCount, // Pass total count
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget
        )
    }

    // MARK: - Body
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                 // --- Regular Layout (Side-by-Side) --- (Unchanged)
                HStack(alignment: .top, spacing: 0) {
                    mediaContentInternal
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView { VStack(alignment: .leading, spacing: 15) { infoAndTagsContent.padding([.horizontal, .top]); commentsContent.padding([.horizontal, .bottom]) } }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600).background(Color(.secondarySystemBackground))
                }
            } else {
                 // --- Compact Layout (Vertical Stack) --- (Using KFImage, layout should be correct)
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            let aspect = guessAspectRatio() ?? 1.0
                            mediaContentInternal // Contains DetailImageView -> KFImage
                                .frame(width: geo.size.width, height: geo.size.width / aspect)
                        }
                        .aspectRatio(guessAspectRatio() ?? 1.0, contentMode: .fit) // Keep aspectRatio on GeometryReader

                        infoAndTagsContent.padding(.horizontal).padding(.vertical, 10)
                        commentsContent.padding(.horizontal).padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
    }


    // MARK: - Helper Methods
    private func guessAspectRatio() -> CGFloat? {
        guard item.width > 0, item.height > 0 else { return 1.0 } // Fallback to 1:1 if data missing
        return CGFloat(item.width) / CGFloat(item.height)
    }
}

// Helper extension (unchanged)
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

// MARK: - Previews (unchanged)

@MainActor
fileprivate func flattenHierarchy(comments: [DisplayComment], previewMaxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    var flatList: [FlatCommentDisplayItem] = []
    let maxDepth = previewMaxDepth
    func traverse(nodes: [DisplayComment], currentLevel: Int) {
        guard currentLevel <= maxDepth else { return }
        for node in nodes {
            flatList.append(FlatCommentDisplayItem(id: node.id, comment: node.comment, level: currentLevel))
            if currentLevel < maxDepth { traverse(nodes: node.children, currentLevel: currentLevel + 1) }
        }
    }
    traverse(nodes: comments, currentLevel: 0)
    return flatList
}


#Preview("Compact - Limited Tags") {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true);
     let previewHandler = KeyboardActionHandler();
     let previewTags: [ItemTag] = [ ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"), ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt"), ItemTag(id: 5, confidence: 0.5, tag: "OtherTag1"), ItemTag(id: 6, confidence: 0.4, tag: "OtherTag2") ];
     let sampleDisplayComment = DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: [])
     let previewFlatComments = flattenHierarchy(comments: [sampleDisplayComment])
     let previewTotalCommentCount = previewFlatComments.count
     let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     @State var fullscreenTarget: FullscreenImageTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { let auth = AuthService(appSettings: settings); auth.isLoggedIn = true; auth.favoritesCollectionId = 1234; return auth }()

     return NavigationStack {
        DetailViewContent(
            item: sampleVideoItem, keyboardActionHandler: previewHandler, player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            displayedTags: Array(previewTags.prefix(4)), totalTagCount: previewTags.count, showingAllTags: false,
            flatComments: previewFlatComments,
            totalCommentCount: previewTotalCommentCount, // Pass total count
            infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget, fullscreenImageTarget: $fullscreenTarget,
            isFavorited: true, toggleFavoriteAction: {}, showAllTagsAction: {}
        )
        .environmentObject(navService).environmentObject(settings).environmentObject(authService)
        .environment(\.horizontalSizeClass, .compact).preferredColorScheme(.dark)
    }
}

// --- END OF COMPLETE FILE ---
