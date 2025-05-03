// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit
import Combine
import os
import Kingfisher
import UIKit // Für UIPasteboard

// MARK: - DetailImageView (Using KFImage with correct modifier order for stable layout)
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

// InfoLoadingStatus enum (unverändert)
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

    let flatComments: [FlatCommentDisplayItem] // Receives the filtered list
    let totalCommentCount: Int

    let infoLoadingStatus: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget?
    @Binding var fullscreenImageTarget: FullscreenImageTarget?
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    let showAllTagsAction: () -> Void

    // --- NEW: Receive state/action for comments ---
    let isCommentCollapsed: (Int) -> Bool // Function to check collapse state
    let toggleCollapseAction: (Int) -> Void // Action to toggle
    // --- END NEW ---

    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")
    @State private var isProcessingFavorite = false
    @State private var showingShareOptions = false

    // MARK: - Computed View Properties
    @ViewBuilder private var mediaContentInternal: some View {
        Group {
            if item.isVideo {
                if let player = player {
                    CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler, onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen, horizontalSizeClass: horizontalSizeClass).id(item.id)
                } else { Rectangle().fill(.black).overlay(ProgressView().tint(.white)) }
            } else {
                DetailImageView(item: item, horizontalSizeClass: horizontalSizeClass, fullscreenImageTarget: $fullscreenImageTarget)
            }
        }
    }
    @ViewBuilder private var voteCounterView: some View { /* ... unverändert ... */
        let benis = item.up - item.down
        VStack(alignment: .leading, spacing: 2) {
            Text("\(benis)").font(.largeTitle).fontWeight(.medium).foregroundColor(.primary).lineLimit(1)
            HStack(spacing: 8) {
                HStack(spacing: 3) { Image(systemName: "arrow.up.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .green).imageScale(.small); Text("\(item.up)").font(.caption).foregroundColor(.secondary) }
                HStack(spacing: 3) { Image(systemName: "arrow.down.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .red).imageScale(.small); Text("\(item.down)").font(.caption).foregroundColor(.secondary) }
            }
        }
    }
    @ViewBuilder private var favoriteButton: some View { /* ... unverändert ... */
        Button { Task { isProcessingFavorite = true; await toggleFavoriteAction(); try? await Task.sleep(for: .milliseconds(100)); isProcessingFavorite = false } }
        label: { Image(systemName: isFavorited ? "heart.fill" : "heart").imageScale(.large).foregroundColor(isFavorited ? .pink : .secondary).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .buttonStyle(.plain).disabled(isProcessingFavorite || !authService.isLoggedIn)
    }
    @ViewBuilder private var shareButton: some View { /* ... unverändert ... */
        Button { showingShareOptions = true } // Trigger the dialog
        label: {
            Image(systemName: "square.and.arrow.up")
                .imageScale(.large)
                .foregroundColor(.secondary) // Consistent styling with favorite button
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var infoAndTagsContent: some View { /* ... unverändert ... */
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    voteCounterView
                    if authService.isLoggedIn { favoriteButton.padding(.top, 5) }
                    shareButton.padding(.top, 5)
                    Spacer()
                }
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
                case .idle: Text(" ").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    struct TagView: View { /* ... unverändert ... */
        let tag: ItemTag; private let characterLimit = 25
        private var displayText: String { tag.tag.count > characterLimit ? String(tag.tag.prefix(characterLimit - 1)) + "…" : tag.tag }
        var body: some View { Text(displayText).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.2)).foregroundColor(.primary).clipShape(Capsule()) }
    }

    /// Instantiates CommentsSection, passing the flat list and total count.
    @ViewBuilder private var commentsContent: some View {
        // --- MODIFIED: Pass down collapse info/action ---
        CommentsSection(
            flatComments: flatComments, // Pass the already filtered list
            totalCommentCount: totalCommentCount,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget,
            isCommentCollapsed: isCommentCollapsed, // Pass down function
            toggleCollapseAction: toggleCollapseAction // Pass down action
        )
        // --- END MODIFICATION ---
    }

    // MARK: - Body
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                 // --- Regular Layout (Side-by-Side) ---
                HStack(alignment: .top, spacing: 0) {
                    mediaContentInternal
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            infoAndTagsContent.padding([.horizontal, .top]);
                            // Ensure commentsContent is correctly placed
                            commentsContent.padding([.horizontal, .bottom]) // Pass collapse info here too
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600).background(Color(.secondarySystemBackground))
                }
            } else {
                 // --- Compact Layout (Vertical Stack) ---
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            let aspect = guessAspectRatio() ?? 1.0
                            mediaContentInternal
                                .frame(width: geo.size.width, height: geo.size.width / aspect)
                        }
                        .aspectRatio(guessAspectRatio() ?? 1.0, contentMode: .fit)

                        infoAndTagsContent.padding(.horizontal).padding(.vertical, 10)
                        // Ensure commentsContent is correctly placed
                        commentsContent.padding(.horizontal).padding(.bottom, 10) // Pass collapse info here too
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
        .confirmationDialog(
            "Link kopieren",
            isPresented: $showingShareOptions,
            titleVisibility: .visible
        ) {
            Button("Post-Link (pr0gramm.com)") {
                let urlString = "https://pr0gramm.com/new/\(item.id)"
                UIPasteboard.general.string = urlString
                Self.logger.info("Copied Post-Link to clipboard: \(urlString)")
            }
            Button("Direkter Medien-Link") {
                if let urlString = item.imageUrl?.absoluteString {
                    UIPasteboard.general.string = urlString
                    Self.logger.info("Copied Media-Link to clipboard: \(urlString)")
                } else {
                    Self.logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)")
                }
            }
        } message: {
             Text("Welchen Link möchtest du in die Zwischenablage kopieren?")
        }
    }


    // MARK: - Helper Methods
    private func guessAspectRatio() -> CGFloat? { /* ... unverändert ... */
        guard item.width > 0, item.height > 0 else { return 1.0 } // Fallback to 1:1 if data missing
        return CGFloat(item.width) / CGFloat(item.height)
    }
}

// --- MODIFIED: Font helper extension needs to be here or globally available ---
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
// --- END MODIFICATION ---


// MARK: - Previews (Angepasst)

// Helper function for preview data (using FlatCommentDisplayItem)
@MainActor
private func flattenHierarchyForPreview(comments: [ItemComment], maxDepth: Int = 5) -> [FlatCommentDisplayItem] {
    var flatList: [FlatCommentDisplayItem] = []
    let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
    let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })

    func traverse(commentId: Int, currentLevel: Int) {
        guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
        let children = childrenByParentId[commentId] ?? []
        let hasChildren = !children.isEmpty
        flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren)) // Include hasChildren
        guard currentLevel < maxDepth else { return }
        // Preview doesn't need sorting, just traverse
        children.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
    }
    let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
    topLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }
    return flatList
}


#Preview("Compact - Limited Tags") {
    // --- MODIFIED: Use State wrapper for preview state ---
    struct PreviewWrapper: View {
        @State var previewLinkTarget: PreviewLinkTarget? = nil
        @State var fullscreenTarget: FullscreenImageTarget? = nil
        // --- NEW: Add state for collapsed comments ---
        @State var collapsedIDs: Set<Int> = []
        // --- END NEW ---

        // --- NEW: Toggle function for preview ---
        func toggleCollapse(_ id: Int) {
            if collapsedIDs.contains(id) { collapsedIDs.remove(id) } else { collapsedIDs.insert(id) }
        }
        // --- END NEW ---
        // --- NEW: isCollapsed function for preview ---
        func isCollapsed(_ id: Int) -> Bool {
            collapsedIDs.contains(id)
        }
        // --- END NEW ---


        var body: some View {
            let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true)
            let previewHandler = KeyboardActionHandler()
            let previewTags: [ItemTag] = [ ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"), ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt") ]
            // --- MODIFIED: Use ItemComment and flattenHierarchyForPreview ---
            let sampleComments = [ ItemComment(id: 1, parent: 0, content: "Kommentar 1 http://pr0gramm.com/new/54321", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), ItemComment(id: 2, parent: 1, content: "Antwort 1.1", created: Int(Date().timeIntervalSince1970)-50, up: 2, down: 0, confidence: 0.8, name: "User2", mark: 2) ]
            let previewFlatComments = flattenHierarchyForPreview(comments: sampleComments)
            // --- END MODIFICATION ---
            let navService = NavigationService()
            let settings = AppSettings()
            let authService = { let auth = AuthService(appSettings: settings); auth.isLoggedIn = true; auth.favoritesCollectionId = 1234; return auth }()

            return NavigationStack {
                DetailViewContent(
                    item: sampleVideoItem,
                    keyboardActionHandler: previewHandler,
                    player: nil,
                    onWillBeginFullScreen: {}, onWillEndFullScreen: {},
                    displayedTags: Array(previewTags.prefix(4)),
                    totalTagCount: previewTags.count,
                    showingAllTags: false,
                    flatComments: previewFlatComments, // Pass flat list
                    totalCommentCount: previewFlatComments.count,
                    infoLoadingStatus: .loaded,
                    previewLinkTarget: $previewLinkTarget,
                    fullscreenImageTarget: $fullscreenTarget,
                    isFavorited: true,
                    toggleFavoriteAction: {},
                    showAllTagsAction: {},
                    // --- NEW: Pass preview functions ---
                    isCommentCollapsed: isCollapsed,
                    toggleCollapseAction: toggleCollapse
                    // --- END NEW ---
                )
                .environmentObject(navService)
                .environmentObject(settings)
                .environmentObject(authService)
                .environment(\.horizontalSizeClass, .compact)
                .preferredColorScheme(.dark)
            }
        }
    }
    return PreviewWrapper() // Return the wrapper
    // --- END MODIFICATION ---
}

// --- END OF COMPLETE FILE ---
