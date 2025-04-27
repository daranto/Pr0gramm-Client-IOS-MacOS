// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import AVKit
import Combine
import os
import Kingfisher // Import Kingfisher

// MARK: - Subviews

/// Displays an image for the detail view using Kingfisher, handling loading states and errors.
/// Now considers horizontalSizeClass for scaling.
struct DetailImageView: View { // Defined within DetailViewContent.swift
    let item: Item
    let logger: Logger
    let cleanupAction: () -> Void
    let horizontalSizeClass: UserInterfaceSizeClass?

    var body: some View {
        KFImage(item.imageUrl)
            .placeholder {
                Rectangle().fill(.secondary.opacity(0.1)).overlay(ProgressView())
            }
            .onFailure { error in
                logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)")
            }
            .resizable()
            .aspectRatio(contentMode: horizontalSizeClass == .compact ? .fill : .fit) // Use the property
            .onAppear { logger.trace("Displaying image for item \(item.id).") }
            .onDisappear(perform: cleanupAction)
            .background(Color.black) // Background needed for .fit
            .clipped() // Ensure content is clipped if .fill is used
    }
}


/// Represents the loading status for item details (tags, comments).
enum InfoLoadingStatus: Equatable { case idle; case loading; case loaded; case error(String) }


/// The main content area for the item detail view, arranging media, info, tags, and comments.
/// Adapts layout based on horizontal size class (Compact vs. Regular).
struct DetailViewContent: View {
    let item: Item
    /// Handles keyboard events (left/right arrow) passed down to the underlying video player if applicable.
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    /// The AVPlayer instance for video items (nil for images).
    let player: AVPlayer?
    /// Callback executed just before the video player enters fullscreen.
    let onWillBeginFullScreen: () -> Void
    /// Callback executed just after the video player exits fullscreen.
    let onWillEndFullScreen: () -> Void
    /// Tags associated with the item.
    let tags: [ItemTag]
    /// Comments associated with the item, structured hierarchically.
    let comments: [DisplayComment] // Accepts DisplayComment
    /// Loading status for tags and comments.
    let infoLoadingStatus: InfoLoadingStatus
    /// Binding to trigger the preview sheet for linked items in comments.
    @Binding var previewLinkTarget: PreviewLinkTarget?
    /// Indicates if the current user has favorited this item.
    let isFavorited: Bool
    /// Action to toggle the favorite status of the item.
    let toggleFavoriteAction: () async -> Void

    // MARK: - Injected Services & Environment
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass // Keep this

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    /// State to temporarily disable the favorite button during API calls.
    @State private var isProcessingFavorite = false

    // MARK: - Computed View Properties

    /// Renders the appropriate media view (image or video player),
    /// passing the size class down for scaling adjustments.
    @ViewBuilder private var mediaContentInternal: some View {
        Group {
            if item.isVideo {
                if let player = player {
                    CustomVideoPlayerRepresentable(
                        player: player,
                        handler: keyboardActionHandler,
                        onWillBeginFullScreen: onWillBeginFullScreen,
                        onWillEndFullScreen: onWillEndFullScreen,
                        horizontalSizeClass: horizontalSizeClass // Pass down size class
                    )
                    .id(item.id)
                } else {
                     // Placeholder needs frame defined by parent
                     Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                }
            } else {
                // Use the DetailImageView defined above in this file
                DetailImageView(
                    item: item,
                    logger: Self.logger,
                    cleanupAction: {},
                    horizontalSizeClass: horizontalSizeClass // Pass down size class
                )
                // Scaling/Clipping handled inside DetailImageView
            }
        }
    }

    /// Displays the calculated "Benis" score prominently,
    /// with smaller upvote and downvote counts below.
    @ViewBuilder private var voteCounterView: some View {
        let benis = item.up - item.down
        VStack(alignment: .leading, spacing: 2) {
            Text("\(benis)")
                .font(.largeTitle)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .imageScale(.small)
                    Text("\(item.up)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .imageScale(.small)
                    Text("\(item.down)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Displays the favorite button (heart icon).
    @ViewBuilder private var favoriteButton: some View {
        Button {
            Task {
                isProcessingFavorite = true
                await toggleFavoriteAction()
                try? await Task.sleep(nanoseconds: 100_000_000)
                isProcessingFavorite = false
            }
        } label: {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .imageScale(.large)
                .foregroundColor(isFavorited ? .pink : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessingFavorite || !authService.isLoggedIn)
    }


    /// Displays the vote counts, favorite button (if logged in), and tags using a FlowLayout.
    @ViewBuilder
    private var infoAndTagsContent: some View {
        HStack(alignment: .top, spacing: 15) {
             VStack(alignment: .leading, spacing: 8) {
                 HStack(alignment: .firstTextBaseline, spacing: 15) {
                     voteCounterView
                     if authService.isLoggedIn {
                         favoriteButton
                             .padding(.top, 5)
                     }
                     Spacer()
                 }
             }
             .fixedSize(horizontal: true, vertical: false)

             Group {
                 switch infoLoadingStatus {
                 case .loaded:
                     if !tags.isEmpty {
                         FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                             ForEach(tags) { tag in
                                 Button {
                                     navigationService.requestSearch(tag: tag.tag)
                                 } label: {
                                     Text(tag.tag)
                                         .font(.caption)
                                         .padding(.horizontal, 8)
                                         .padding(.vertical, 4)
                                         .background(Color.gray.opacity(0.2))
                                         .foregroundColor(.primary)
                                         .clipShape(Capsule())
                                         .lineLimit(1)
                                         .contentShape(Capsule())
                                 }
                                 .buttonStyle(.plain)
                             }
                         }
                     } else {
                          if infoLoadingStatus == .loaded { Spacer() }
                          else {
                              Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                          }
                     }
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                case .error:
                    Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                 case .idle:
                     Text(" ").font(.caption)
                         .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                 }
             }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    /// Displays the comments section.
    @ViewBuilder private var commentsContent: some View {
        CommentsSection(
            comments: comments,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            // Adapt layout based on horizontal size class
            if horizontalSizeClass == .regular {
                // iPad / wider layouts: Side-by-side
                HStack(alignment: .top, spacing: 0) {
                    GeometryReader { geometry in
                        mediaContentInternal // Handles its own scaling
                            // Fit the media content within the geometry reader space
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            infoAndTagsContent.padding([.horizontal, .top])
                            commentsContent.padding([.horizontal, .bottom])
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600)
                    .background(Color(.secondarySystemBackground))
                }
            } else {
                // iPhone / compact layouts: Vertical stack
                ScrollView {
                    VStack(spacing: 0) {
                        // --- MODIFIED Compact Layout Media ---
                        GeometryReader { geometry in
                            let availableWidth = geometry.size.width
                            // Calculate height based on aspect ratio, default to 16:9 if invalid
                            let aspectRatio = guessAspectRatio() ?? (16.0/9.0)
                            let calculatedHeight = availableWidth / aspectRatio

                            mediaContentInternal // Image/Video Player (will fill/clip based on size class)
                                .frame(width: availableWidth, height: calculatedHeight)
                                // Clipping is handled inside DetailImageView / Video Player should clip automatically
                        }
                        // Apply the calculated aspect ratio to the GeometryReader itself
                        .aspectRatio(guessAspectRatio() ?? (16.0/9.0), contentMode: .fit)
                        // --------------------------------------

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

    /// Provides an estimated aspect ratio for video placeholders before the player is ready.
    private func guessAspectRatio() -> CGFloat? {
        guard item.width > 0, item.height > 0 else { return nil } // Return nil if invalid
        return CGFloat(item.width) / CGFloat(item.height)
    }
}

// MARK: - Previews

#Preview("Compact Favorited") {
     // Sample data setup
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true); // Adjusted votes
     let previewHandler = KeyboardActionHandler();
     let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Cool"), ItemTag(id: 2, confidence: 0.7, tag: "Video"), ItemTag(id: 3, confidence: 0.8, tag: "Längerer Tag")];
     let previewComments: [DisplayComment] = [ // Use DisplayComment for preview
        DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: [])
     ]
     let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = {
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true
         auth.favoritesCollectionId = 1234
         return auth
     }()

     NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded, // Pass DisplayComment
            previewLinkTarget: $previewLinkTarget,
            isFavorited: true,
            toggleFavoriteAction: {}
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .compact) // Simulate compact
        // Removed outer padding/background for more realistic preview
    }
}

#Preview("Regular Not Favorited") {
    // Sample data setup
    let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false);
    let previewHandler = KeyboardActionHandler(); let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag"), ItemTag(id:4, confidence: 0.6, tag:"tag3"), ItemTag(id:5, confidence: 0.5, tag:"tag4")];
    let previewComments: [DisplayComment] = [ // Use DisplayComment for preview
        DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar https://pr0gramm.com/top/123", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: [])
    ];
    let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = {
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true
         auth.favoritesCollectionId = 1234
         return auth
     }()

     NavigationStack {
        DetailViewContent(
            item: sampleImageItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded, // Pass DisplayComment
            previewLinkTarget: $previewLinkTarget,
            isFavorited: false,
            toggleFavoriteAction: {}
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .regular) // Simulate regular
    }
    .previewDevice("iPad (10th generation)")
}
// --- END OF COMPLETE FILE ---
