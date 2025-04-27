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

    // --- Modified Tag Properties ---
    /// Tags associated with the item (potentially limited to top 4).
    let displayedTags: [ItemTag]
    /// The total number of tags available for the item.
    let totalTagCount: Int
    /// Flag indicating if all tags are currently being displayed.
    let showingAllTags: Bool
    // -----------------------------

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
    /// Action to request showing all tags for the current item.
    let showAllTagsAction: () -> Void

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
                     Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                }
            } else {
                DetailImageView(
                    item: item,
                    logger: Self.logger,
                    cleanupAction: {},
                    horizontalSizeClass: horizontalSizeClass // Pass down size class
                )
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
                try? await Task.sleep(nanoseconds: 100_000_000) // Short delay to allow UI update
                isProcessingFavorite = false
            }
        } label: {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .imageScale(.large)
                .foregroundColor(isFavorited ? .pink : .secondary)
                .frame(width: 44, height: 44) // Ensure consistent tap area
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessingFavorite || !authService.isLoggedIn)
    }


    /// Displays the vote counts, favorite button (if logged in), and tags using a FlowLayout.
    /// Includes logic for displaying limited tags and a "Show More" button.
    /// Handles long tags by truncating with ellipsis.
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
             .fixedSize(horizontal: true, vertical: false) // Prevent vote counter from expanding horizontally

             Group { // Use Group for conditional content
                 switch infoLoadingStatus {
                 case .loaded:
                     if !displayedTags.isEmpty {
                         // Use FlowLayout for tags
                         FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                             // Display the tags passed in (might be limited)
                             ForEach(displayedTags) { tag in
                                 Button {
                                     navigationService.requestSearch(tag: tag.tag)
                                 } label: {
                                     TagView(tag: tag) // Use reusable TagView
                                 }
                                 .buttonStyle(.plain)
                             }

                             // "Show More" button logic
                             if !showingAllTags && totalTagCount > displayedTags.count {
                                 let remainingCount = totalTagCount - displayedTags.count
                                 Button {
                                     showAllTagsAction() // Call the action passed from PagedDetailView
                                 } label: {
                                     // Use TagView styling for consistency
                                     Text("+\(remainingCount) mehr")
                                         .font(.caption)
                                         .padding(.horizontal, 8)
                                         .padding(.vertical, 4)
                                         .background(Color.accentColor.opacity(0.15))
                                         .foregroundColor(.accentColor)
                                         .clipShape(Capsule())
                                         .contentShape(Capsule())
                                         .lineLimit(1) // Ensure "Show More" button text doesn't wrap either
                                 }
                                 .buttonStyle(.plain)
                             }
                         }
                     } else {
                         // Handle case where loading finished but API returned no tags
                         Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary)
                             .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                     }
                 case .loading:
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                 case .error:
                    Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red)
                         .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                 case .idle:
                     // Placeholder for spacing consistency before loading starts
                     Text(" ").font(.caption)
                         .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                 }
             }
             .frame(maxWidth: .infinity, alignment: .leading) // Ensure tag area takes remaining space
        }
        .frame(maxWidth: .infinity, alignment: .leading) // Overall alignment for the HStack
    }

    /// **MODIFIED:** Reusable view for a single tag button. Truncates long text.
    struct TagView: View {
        let tag: ItemTag
        var body: some View {
            Text(tag.tag)
                .font(.caption)
                .lineLimit(1) // <--- Force single line, enabling truncation
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .clipShape(Capsule())
                .contentShape(Capsule())
                // REMOVED .fixedSize and .frame(maxWidth: .infinity)
        }
    }


    /// Displays the comments section.
    @ViewBuilder private var commentsContent: some View {
        CommentsSection(
            comments: comments,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget
        )
    }

    // MARK: - Body (Layout logic remains unchanged)

    var body: some View {
        Group {
            // Adapt layout based on horizontal size class
            if horizontalSizeClass == .regular {
                // iPad / wider layouts: Side-by-side
                HStack(alignment: .top, spacing: 0) {
                    GeometryReader { geometry in
                        mediaContentInternal
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
                        GeometryReader { geometry in
                            let availableWidth = geometry.size.width
                            let aspectRatio = guessAspectRatio() ?? (16.0/9.0)
                            let calculatedHeight = availableWidth / aspectRatio

                            mediaContentInternal
                                .frame(width: availableWidth, height: calculatedHeight)
                        }
                        .aspectRatio(guessAspectRatio() ?? (16.0/9.0), contentMode: .fit)

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

// MARK: - Previews (Unchanged, but should show truncation now)

#Preview("Compact - Limited Tags") {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true);
     let previewHandler = KeyboardActionHandler();
     // Provide more than 4 tags for the preview, including a long one
     let previewTags: [ItemTag] = [
         ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"),
         ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt"), // Example from user
         ItemTag(id: 5, confidence: 0.5, tag: "OtherTag1"), ItemTag(id: 6, confidence: 0.4, tag: "OtherTag2")
     ];
     let previewComments: [DisplayComment] = [ DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: []) ]
     let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { let auth = AuthService(appSettings: settings); auth.isLoggedIn = true; auth.favoritesCollectionId = 1234; return auth }()

     NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            displayedTags: Array(previewTags.prefix(4)), // Simulate limited tags
            totalTagCount: previewTags.count,          // Provide total count
            showingAllTags: false,                     // Simulate not showing all
            comments: previewComments, infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: true,
            toggleFavoriteAction: {},
            showAllTagsAction: {}                      // Dummy action for preview
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .compact)
        .preferredColorScheme(.dark) // Added for better preview matching screenshot
    }
}

#Preview("Compact - All Tags Shown") {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 9, up: 203, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true);
     let previewHandler = KeyboardActionHandler();
     let previewTags: [ItemTag] = [
         ItemTag(id: 1, confidence: 0.9, tag: "TopTag1"), ItemTag(id: 2, confidence: 0.8, tag: "TopTag2"),
         ItemTag(id: 3, confidence: 0.7, tag: "TopTag3"), ItemTag(id: 4, confidence: 0.6, tag: "beim lesen programmieren gelernt"),
         ItemTag(id: 5, confidence: 0.5, tag: "OtherTag1"), ItemTag(id: 6, confidence: 0.4, tag: "OtherTag2")
     ];
     let previewComments: [DisplayComment] = [ DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: []) ]
     let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { let auth = AuthService(appSettings: settings); auth.isLoggedIn = true; auth.favoritesCollectionId = 1234; return auth }()

     NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            displayedTags: previewTags,           // Simulate ALL tags
            totalTagCount: previewTags.count,
            showingAllTags: true,                 // Simulate showing all
            comments: previewComments, infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: true,
            toggleFavoriteAction: {},
            showAllTagsAction: {}
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .compact)
        .preferredColorScheme(.dark) // Added for better preview matching screenshot
    }
}


#Preview("Regular - Limited Tags") {
    let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false);
    let previewHandler = KeyboardActionHandler();
    let previewTags: [ItemTag] = [
        ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag mit mehr Text"),
        ItemTag(id: 4, confidence: 0.6, tag: "tag3"), ItemTag(id: 5, confidence: 0.5, tag: "tag4"),
        ItemTag(id: 6, confidence: 0.4, tag: "beim lesen programmieren gelernt"), ItemTag(id: 7, confidence: 0.3, tag: "tag6")
    ];
    let previewComments: [DisplayComment] = [ DisplayComment(id: 1, comment: ItemComment(id: 1, parent: 0, content: "Kommentar https://pr0gramm.com/top/123", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1), children: []) ];
    let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { let auth = AuthService(appSettings: settings); auth.isLoggedIn = true; auth.favoritesCollectionId = 1234; return auth }()

     NavigationStack {
        DetailViewContent(
            item: sampleImageItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            displayedTags: Array(previewTags.prefix(4)), // Limited
            totalTagCount: previewTags.count,
            showingAllTags: false,                     // Not showing all
            comments: previewComments, infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: false,
            toggleFavoriteAction: {},
            showAllTagsAction: {}
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .regular)
        .preferredColorScheme(.dark) // Added for better preview matching screenshot
    }
    .previewDevice("iPad (10th generation)")
}
// --- END OF COMPLETE FILE ---
