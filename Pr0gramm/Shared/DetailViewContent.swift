import SwiftUI
import AVKit
import Combine
import os
import Kingfisher // Import Kingfisher

// MARK: - Subviews

/// Displays an image for the detail view using Kingfisher, handling loading states and errors.
struct DetailImageView: View {
    let item: Item
    let logger: Logger
    let cleanupAction: () -> Void // Although declared, this seems unused currently.

    var body: some View {
        // Use Kingfisher's KFImage for loading and caching
        KFImage(item.imageUrl)
            .placeholder { // View shown while loading
                Rectangle().fill(.secondary.opacity(0.1)).overlay(ProgressView())
            }
            .onFailure { error in // Action on loading failure
                logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)")
            }
            .resizable()
            .scaledToFit()
            .onAppear { logger.trace("Displaying image for item \(item.id).") }
            .onDisappear(perform: cleanupAction) // Call cleanup when image disappears
            .background(Color.black) // Ensure background is black for letterboxing
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
    /// Comments associated with the item.
    let comments: [ItemComment]
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
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    /// State to temporarily disable the favorite button during API calls.
    @State private var isProcessingFavorite = false

    // MARK: - Computed View Properties

    /// Renders the appropriate media view (image or video player).
    @ViewBuilder private var mediaContentInternal: some View {
        Group {
            if item.isVideo {
                if let player = player {
                    // Use the custom representable to integrate AVPlayerViewController
                    CustomVideoPlayerRepresentable(
                        player: player,
                        handler: keyboardActionHandler,
                        onWillBeginFullScreen: onWillBeginFullScreen,
                        onWillEndFullScreen: onWillEndFullScreen
                    )
                    .id(item.id) // Ensure recreation if the item ID changes
                } else {
                    // Placeholder while the player is being set up
                     Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                         .aspectRatio(guessAspectRatio(), contentMode: .fit)
                }
            } else {
                // Display the image using DetailImageView
                DetailImageView(item: item, logger: Self.logger, cleanupAction: {})
            }
        }
    }

    /// Displays the upvote and downvote counts.
    @ViewBuilder private var voteCounterView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                    .symbolRenderingMode(.palette) // Allows separate colors for icon parts
                    .foregroundStyle(.white, .green)
                    .imageScale(.medium)
                Text("\(item.up)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false) // Prevent text wrapping
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .imageScale(.medium)
                Text("\(item.down)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// Displays the favorite button (heart icon).
    @ViewBuilder private var favoriteButton: some View {
        Button {
            // Perform the toggle action asynchronously
            Task {
                isProcessingFavorite = true // Disable button immediately
                await toggleFavoriteAction()
                // Short delay to prevent flickering if the action fails very quickly
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                isProcessingFavorite = false // Re-enable button
            }
        } label: {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .imageScale(.large) // Slightly larger icon
                .foregroundColor(isFavorited ? .pink : .secondary) // Pink when favorited
                .frame(width: 44, height: 44) // Increase tappable area
                .contentShape(Rectangle()) // Define the hit area explicitly
        }
        .buttonStyle(.plain) // Remove default button styling
        .disabled(isProcessingFavorite || !authService.isLoggedIn) // Disable during API call or if logged out
    }


    /// Displays the vote counts, favorite button (if logged in), and tags using a FlowLayout.
    @ViewBuilder
    private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
             HStack(alignment: .top, spacing: 15) { // Align items to the top
                 // Combine Votes and Favorite button horizontally
                 HStack(alignment: .center, spacing: 15) {
                     voteCounterView
                     if authService.isLoggedIn { // Only show favorite button when logged in
                         favoriteButton
                     }
                 }

                 // Tags Section
                 Group {
                     switch infoLoadingStatus {
                     case .loaded:
                         if !tags.isEmpty {
                             // Use FlowLayout for responsive tag wrapping
                             FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                 ForEach(tags) { tag in
                                     Button {
                                         // Request navigation to search for this tag
                                         navigationService.requestSearch(tag: tag.tag)
                                     } label: {
                                         Text(tag.tag)
                                             .font(.caption)
                                             .padding(.horizontal, 8)
                                             .padding(.vertical, 4)
                                             .background(Color.gray.opacity(0.2))
                                             .foregroundColor(.primary)
                                             .clipShape(Capsule())
                                             .lineLimit(1) // Prevent multi-line tags
                                             .contentShape(Capsule()) // Define hit area
                                     }
                                     .buttonStyle(.plain) // Remove default button styling
                                 }
                             }
                         } else {
                              Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                         }
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    case .error:
                        Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                     case .idle:
                         Text(" ").font(.caption) // Placeholder to maintain layout consistency
                             .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                     }
                 }
                 .layoutPriority(1) // Allow tags section to expand horizontally
             }
        }
        .frame(maxWidth: .infinity, alignment: .leading) // Take full available width
    }

    /// Displays the comments section.
    @ViewBuilder private var commentsContent: some View {
        CommentsSection(
            comments: comments,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget // Pass down the binding
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            // Adapt layout based on horizontal size class
            if horizontalSizeClass == .regular {
                // iPad / wider layouts: Side-by-side
                HStack(alignment: .top, spacing: 0) {
                    // Media content takes flexible space
                    GeometryReader { geometry in
                        mediaContentInternal
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped() // Clip media to its frame
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Expand fully

                    Divider()

                    // Info/Tags/Comments in a scrollable sidebar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            infoAndTagsContent.padding([.horizontal, .top])
                            commentsContent.padding([.horizontal, .bottom])
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600) // Constrain sidebar width
                    .background(Color(.secondarySystemBackground)) // Subtle background
                }
            } else {
                // iPhone / compact layouts: Vertical stack
                ScrollView {
                    VStack(spacing: 0) {
                        mediaContentInternal.scaledToFit() // Media on top
                        infoAndTagsContent.padding(.horizontal).padding(.vertical, 10) // Info/Tags below
                        commentsContent.padding(.horizontal).padding(.bottom, 10) // Comments at bottom
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure the group fills available space
         .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
         .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
    }

    // MARK: - Helper Methods

    /// Provides an estimated aspect ratio for video placeholders before the player is ready.
    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 {
            return CGFloat(item.width) / CGFloat(item.height)
        }
        // Default to 16:9 if dimensions are invalid
        return 16.0 / 9.0
    }
}

// MARK: - Previews

#Preview("Compact Favorited") {
     // Sample data setup
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true); // Marked as favorited
     let previewHandler = KeyboardActionHandler(); let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Cool"), ItemTag(id: 2, confidence: 0.7, tag: "Video"), ItemTag(id: 3, confidence: 0.8, tag: "Längerer Tag")]; let previewComments: [ItemComment] = [ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1)]; let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { // Setup logged-in auth service for preview
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true
         auth.favoritesCollectionId = 1234 // Need a dummy ID for preview
         return auth
     }()

     return NavigationStack { // Required for toolbar/navigation features
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: true, // Match item data
            toggleFavoriteAction: {} // Dummy action for preview
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .compact) // Force compact layout
    }
}

#Preview("Regular Not Favorited") {
    // Sample data setup
    let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false); // Not favorited
    let previewHandler = KeyboardActionHandler(); let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag"), ItemTag(id:4, confidence: 0.6, tag:"tag3"), ItemTag(id:5, confidence: 0.5, tag:"tag4")]; let previewComments: [ItemComment] = [ItemComment(id: 1, parent: 0, content: "Kommentar https://pr0gramm.com/top/123", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1)]; let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = { // Setup logged-in auth service for preview
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true
         auth.favoritesCollectionId = 1234 // Need a dummy ID for preview
         return auth
     }()

     return NavigationStack {
        DetailViewContent(
            item: sampleImageItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: {}, onWillEndFullScreen: {},
            tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded,
            previewLinkTarget: $previewLinkTarget,
            isFavorited: false, // Match item data
            toggleFavoriteAction: {} // Dummy action
        )
        .environmentObject(navService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environment(\.horizontalSizeClass, .regular) // Force regular layout
    }
    .previewDevice("iPad (10th generation)") // Simulate iPad for regular layout
}
