// DetailViewContent.swift

import SwiftUI
import AVKit
import Combine
import os

// --- DetailImageView ---
struct DetailImageView: View {
    let item: Item
    let logger: Logger
    let cleanupAction: () -> Void
    var body: some View {
        AsyncImage(url: item.imageUrl) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
            case .failure(let error):
                let _ = logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)")
                Text("Bild konnte nicht geladen werden").foregroundColor(.red)
            default:
                ProgressView()
            }
        }
        .onAppear { logger.trace("Displaying image for item \(item.id).") }
    }
}


// --- FlowLayout (Annahme: Existiert) ---
// struct FlowLayout: Layout { /* ... */ }

// --- CommentsSection (Annahme: Existiert) ---
// struct CommentsSection: View { /* ... */ }


struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    // Callbacks werden wieder benötigt
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    let tags: [ItemTag]
    let comments: [ItemComment]
    let infoLoadingStatus: InfoLoadingStatus

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    // MARK: - Computed View Properties

    @ViewBuilder
    private var mediaContent: some View {
        Group {
            if item.isVideo {
                if let player = player {
                    // Callbacks werden wieder übergeben
                    CustomVideoPlayerRepresentable(
                        player: player,
                        handler: keyboardActionHandler,
                        onWillBeginFullScreen: onWillBeginFullScreen, // Übergeben
                        onWillEndFullScreen: onWillEndFullScreen      // Übergeben
                    )
                         .id(item.id)
                } else {
                     Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                }
            } else {
                DetailImageView(item: item, logger: Self.logger, cleanupAction: { })
            }
        }
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // --- Vote View ---
    // ... (bleibt gleich)
    @ViewBuilder
    private var voteCounterView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .imageScale(.medium)
                Text("\(item.up)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
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


    // --- infoAndTagsContent ---
    // ... (bleibt gleich)
     @ViewBuilder
    private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
             HStack(alignment: .top, spacing: 15) {
                 voteCounterView
                 Group {
                     if infoLoadingStatus == .loaded {
                         if !tags.isEmpty {
                             FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                 ForEach(tags) { tag in
                                     Text(tag.tag)
                                         .font(.caption)
                                         .padding(.horizontal, 8).padding(.vertical, 4)
                                         .background(Color.gray.opacity(0.2))
                                         .foregroundColor(.primary)
                                         .clipShape(Capsule())
                                         .lineLimit(1)
                                 }
                             }
                         } else {
                              Text("Keine Tags vorhanden")
                                  .font(.caption).foregroundColor(.secondary)
                                  .frame(maxWidth: .infinity, alignment: .leading)
                                  .padding(.vertical, 5)
                         }
                    } else if infoLoadingStatus == .loading {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    } else if case .error(let msg) = infoLoadingStatus {
                        Text("Fehler Tags: \(msg)")
                            .font(.caption).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                    }
                 }
                 .layoutPriority(1)
             }
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    @ViewBuilder
    private var commentsContent: some View {
        CommentsSection(comments: comments, status: infoLoadingStatus)
            .padding(.top)
    }

    // MARK: - Body
     var body: some View {
       // ... (bleibt gleich)
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { VStack(spacing: 0) { mediaContent; infoAndTagsContent; Spacer() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView { commentsContent }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
                }
            } else {
                ScrollView { VStack(spacing: 0) { mediaContent; infoAndTagsContent; commentsContent } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
    }


    // --- Player Logic Methoden ENTFERNT ---

    // --- guessAspectRatio (unverändert) ---
    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 { return CGFloat(item.width) / CGFloat(item.height) }
        return 16.0 / 9.0
    }
} // Ende struct DetailViewContent

// MARK: - Preview (Angepasst: Übergibt leere Closures)
// ... (Previews wie im vorherigen Schritt, mit leeren Closures für Callbacks)
#Preview("Compact") {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
     let previewHandler = KeyboardActionHandler()
     let previewTags: [ItemTag] = [ /* ... */ ]
     let previewComments: [ItemComment] = [ /* ... */ ]
     let previewPlayer: AVPlayer? = sampleVideoItem.isVideo ? AVPlayer(url: URL(string: "https://example.com/dummy.mp4")!) : nil

     NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: { print("Preview: Begin Fullscreen") },
            onWillEndFullScreen: { print("Preview: End Fullscreen") },
            tags: previewTags,
            comments: previewComments,
            infoLoadingStatus: .loaded
        )
        .environment(\.horizontalSizeClass, .compact)
    }
}
#Preview("Regular") {
     let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1)
    let previewHandler = KeyboardActionHandler()
    let previewTags: [ItemTag] = [ /* ... */ ]
    let previewComments: [ItemComment] = [ /* ... */ ]
    let previewPlayer: AVPlayer? = sampleImageItem.isVideo ? AVPlayer(url: URL(string: "https://example.com/dummy.mp4")!) : nil

     NavigationStack {
        DetailViewContent(
            item: sampleImageItem,
            keyboardActionHandler: previewHandler,
            player: previewPlayer,
            onWillBeginFullScreen: { print("Preview: Begin Fullscreen") },
            onWillEndFullScreen: { print("Preview: End Fullscreen") },
            tags: previewTags,
            comments: previewComments,
            infoLoadingStatus: .loaded
        )
        .environment(\.horizontalSizeClass, .regular)
    }
    .previewDevice("iPad (10th generation)")
}
