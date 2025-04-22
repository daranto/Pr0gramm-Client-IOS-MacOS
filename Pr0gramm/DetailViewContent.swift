// DetailViewContent.swift

import SwiftUI
import AVKit
import Combine
import os

// --- DetailImageView (Annahme: Existiert und ist korrekt) ---
struct DetailImageView: View {
    let item: Item
    let logger: Logger
    let cleanupAction: () -> Void
    var body: some View {
        AsyncImage(url: item.imageUrl) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure(let error):
                let _ = logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)")
                Text("Bild konnte nicht geladen werden").foregroundColor(.red)
            default:
                ProgressView()
            }
        }
        .scaledToFit()
        .onAppear { logger.trace("Displaying image for item \(item.id). Ensuring player cleanup."); logger.debug("DetailImageView onAppear for item \(item.id). Performing cleanup."); cleanupAction() }
    }
}

// --- FlowLayout (Annahme: Existiert als eigene Struct) ---
// struct FlowLayout: Layout { /* ... */ }

// --- CommentsSection (Annahme: Existiert als eigene Struct) ---
// struct CommentsSection: View { /* ... */ }


struct DetailViewContent: View {
    let item: Item
    // Erhält Handler von PagedDetailView
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    @EnvironmentObject var settings: AppSettings
    @State private var player: AVPlayer? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    let tags: [ItemTag]
    let comments: [ItemComment]
    let infoLoadingStatus: InfoLoadingStatus // Verwendet globales Enum

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    // MARK: - Computed View Properties

    @ViewBuilder
    private var mediaContent: some View {
        Group {
            if item.isVideo {
                // --- Übergibt Handler an Representable ---
                // Annahme: CustomVideoPlayerRepresentable existiert
                CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler)
                    .scaledToFit()
                    .onAppear { Self.logger.debug("CustomVideoPlayerRepresentable container appeared for item \(item.id).") }
            } else {
                DetailImageView(item: item, logger: Self.logger, cleanupAction: { cleanupPlayerAndObservers() })
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
             if item.isVideo, let url = item.imageUrl { setupPlayer(url: url) }
             else if !item.isVideo { cleanupPlayerAndObservers() }
         }
    }

    @ViewBuilder
    private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
             HStack { Text("⬆️ \(item.up)"); Text("⬇️ \(item.down)"); Spacer() }
                 .font(.caption)
                 .padding(.bottom, 4)

             if infoLoadingStatus == .loaded {
                 if !tags.isEmpty {
                     // Annahme: FlowLayout existiert
                     FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                         ForEach(tags) { tag in
                             Text(tag.tag)
                                 .font(.caption)
                                 .padding(.horizontal, 8).padding(.vertical, 4)
                                 .background(Color.gray.opacity(0.3))
                                 .foregroundColor(.primary)
                                 .cornerRadius(5)
                                 .lineLimit(1)
                         }
                     }
                 } else {
                      Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                 }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var commentsContent: some View {
        // Annahme: CommentsSection existiert
        CommentsSection(comments: comments, status: infoLoadingStatus)
            .padding(.top, horizontalSizeClass == .compact ? 8 : 0)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // --- Breites Layout (VStack innen) ---
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                             mediaContent
                             infoAndTagsContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    ScrollView {
                        commentsContent
                            .padding(.top)
                    }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
                }
            } else {
                // --- Schmales Layout ---
                ScrollView {
                    VStack(spacing: 0) {
                        mediaContent
                        infoAndTagsContent
                        commentsContent
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
        .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing."); cleanupPlayerAndObservers() }
    }

    // MARK: - Player Logic
    private func setupPlayer(url: URL) {
        Self.logger.debug("SetupPlayer called for item \(item.id), URL: \(url.absoluteString)")
        Self.logger.debug("Cleaning up existing player/observers before creating new one...")
        cleanupPlayerAndObservers(keepPlayerInstance: false)
        Self.logger.debug("Creating new AVPlayer instance for item \(item.id).")
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.isMuted = settings.isVideoMuted
        Self.logger.info("Player initial mute state for item \(item.id) set to: \(settings.isVideoMuted)")
        self.muteObserver = newPlayer.observe(\.isMuted, options: [.new]) { _, change in
            guard let newMutedState = change.newValue else { return }
            if self.settings.isVideoMuted != newMutedState {
                Self.logger.info("User changed mute via player controls for item \(item.id). New state: \(newMutedState). Updating global setting.")
                DispatchQueue.main.async { self.settings.isVideoMuted = newMutedState }
            }
        }
        Self.logger.debug("Added mute KVO observer for item \(item.id).")
        guard let currentItem = newPlayer.currentItem else {
             Self.logger.error("Newly created player has no currentItem for item \(item.id). Cannot add loop observer.")
             return
        }
        addLoopObserver(for: currentItem)
        newPlayer.play()
        Self.logger.debug("Player started (Autoplay) for item \(item.id)")
    }

    private func addLoopObserver(for itemPlayerItem: AVPlayerItem) {
        if let observer = self.loopObserver {
            NotificationCenter.default.removeObserver(observer)
            Self.logger.debug("Removed existing loop observer before adding new one for item \(self.item.id).")
            self.loopObserver = nil
        }
        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: itemPlayerItem, queue: .main
        ) { notification in
            Self.logger.debug("Video did play to end time for item \(self.item.id). Seeking to zero.")
            self.player?.seek(to: .zero)
            self.player?.play()
        }
        Self.logger.debug("Added loop observer for item \(self.item.id).")
    }

    private func cleanupPlayerAndObservers(keepPlayerInstance: Bool = false) {
        guard player != nil || muteObserver != nil || loopObserver != nil else { return }
        Self.logger.debug("Cleanup called for item \(item.id). Keep instance: \(keepPlayerInstance)")
        let playerToPause = self.player
        playerToPause?.pause()
        Self.logger.debug("Player paused (if existed) for item \(item.id).")
        muteObserver?.invalidate()
        if muteObserver != nil { Self.logger.debug("Mute observer invalidated for item \(item.id).") }
        muteObserver = nil
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            Self.logger.debug("Loop observer removed for item \(item.id).")
            loopObserver = nil
        }
        if !keepPlayerInstance {
            self.player = nil
            Self.logger.debug("Player instance state set to nil for item \(item.id).")
        } else {
            Self.logger.debug("Keeping player instance state for item \(item.id).")
        }
    }

    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 { return CGFloat(item.width) / CGFloat(item.height) }
        return 16.0 / 9.0
    }

} // Ende struct DetailViewContent


// MARK: - Preview
#Preview("Compact") {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
     let previewHandler = KeyboardActionHandler() // Wird für die Preview benötigt
     let previewTags = [ ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag") ]
     let previewComments = [
         ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1),
         ItemComment(id: 2, parent: 1, content: "Antwort.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7)
    ]
    return NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler, // Übergeben für Preview
            tags: previewTags,
            comments: previewComments,
            infoLoadingStatus: .loaded
        )
        .environment(\.horizontalSizeClass, .compact)
        .environmentObject(AppSettings())
    }
}

#Preview("Regular") {
    let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
    let previewHandler = KeyboardActionHandler() // Wird für die Preview benötigt
    let previewTags = [ ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag"), ItemTag(id:4, confidence: 0.6, tag:"tag3"), ItemTag(id:5, confidence: 0.5, tag:"tag4")]
    let previewComments = [
         ItemComment(id: 1, parent: 0, content: "Erster Kommentar!", created: Int(Date().timeIntervalSince1970) - 300, up: 5, down: 0, confidence: 0.95, name: "UserA", mark: 1),
         ItemComment(id: 2, parent: 1, content: "Antwort.", created: Int(Date().timeIntervalSince1970) - 150, up: 2, down: 1, confidence: 0.8, name: "UserB", mark: 7),
         ItemComment(id: 3, parent: 0, content: "Zweiter Top-Level Kommentar mit etwas längerem Text, um zu sehen, wie er umbricht.", created: Int(Date().timeIntervalSince1970) - 60, up: 10, down: 3, confidence: 0.9, name: "UserC", mark: 3),
         ItemComment(id: 4, parent: 3, content: "Antwort auf zweiten.", created: Int(Date().timeIntervalSince1970) - 30, up: 1, down: 0, confidence: 0.7, name: "UserA", mark: 1)
    ]
    return NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler, // Übergeben für Preview
            tags: previewTags,
            comments: previewComments,
            infoLoadingStatus: .loaded
        )
        .environment(\.horizontalSizeClass, .regular)
        .environmentObject(AppSettings())
    }
    .previewDevice("iPad (10th generation)")
}
