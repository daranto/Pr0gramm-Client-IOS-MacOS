// DetailViewContent.swift

import SwiftUI
import AVKit
import Combine
import os

// --- DetailImageView (unverändert) ---
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
        .onAppear {
            logger.trace("Displaying image for item \(item.id). Ensuring player cleanup.")
            logger.debug("DetailImageView onAppear for item \(item.id). Performing cleanup.")
            cleanupAction()
        }
    }
}

struct DetailViewContent: View {
    let item: Item
    // --- NEU: Handler von PagedDetailView ---
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler

    @EnvironmentObject var settings: AppSettings
    @State private var player: AVPlayer? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if item.isVideo {
                    // --- Geändert: Handler übergeben ---
                    CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler)
                        .onAppear {
                            Self.logger.debug("CustomVideoPlayerRepresentable container appeared for item \(item.id).")
                        }
                } else {
                    // AnyView kann wahrscheinlich entfernt werden, aber sicherheitshalber drinlassen
                    AnyView(
                        DetailImageView(item: item, logger: Self.logger, cleanupAction: { cleanupPlayerAndObservers() })
                    )
                }
            }
            .aspectRatio(guessAspectRatio(), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // --- NEU: .onAppear hier, um Player *vor* Representable zu erstellen ---
            .onAppear {
                 if item.isVideo, let url = item.imageUrl {
                     Self.logger.debug("Group onAppear for item \(item.id). Setting up player if video.")
                     setupPlayer(url: url)
                 } else if !item.isVideo {
                     // Wichtig: Auch beim Erscheinen eines Bildes den Player ggf. entfernen
                     Self.logger.debug("Group onAppear for item \(item.id). Ensuring cleanup if image.")
                     cleanupPlayerAndObservers()
                 }
             }

            // --- Unverändert: Item Infos ---
            HStack {
                Text("ID: \(item.id)").font(.caption).lineLimit(1)
                Spacer()
                Text("⬆️ \(item.up)").font(.caption)
                Text("⬇️ \(item.down)").font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
             Self.logger.debug("DetailViewContent for item \(item.id) appearing. IsVideo: \(item.isVideo)")
        }
        .onDisappear {
            Self.logger.debug("DetailViewContent for item \(item.id) disappearing.")
            // Dieser Cleanup bleibt als Fallback wichtig
            cleanupPlayerAndObservers()
        }
    }

    // MARK: - Player Logic

    // --- setupPlayer (unverändert) ---
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

    // --- addLoopObserver (unverändert, ohne weak self) ---
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

    // --- cleanupPlayerAndObservers (unverändert) ---
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

    // --- guessAspectRatio (unverändert) ---
    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 { return CGFloat(item.width) / CGFloat(item.height) }
        return 16.0 / 9.0
    }
} // Ende struct DetailViewContent

// --- Preview ANPASSEN (benötigt einen Dummy-Handler) ---
#Preview {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
     let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 1, up: 10, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 1200, audio: false, source: "http://example.com", flags: 2, user: "UserB", mark: 2)

     // Erstelle einen Dummy-Handler nur für die Preview
     let previewHandler = KeyboardActionHandler()
     // Optional: Füge Dummy-Aktionen hinzu, um im Preview zu testen
     previewHandler.selectNextAction = { print("Preview: Select Next") }
     previewHandler.selectPreviousAction = { print("Preview: Select Previous") }

    return NavigationStack {
        // Wähle Video oder Bild zum Testen
        DetailViewContent(item: sampleVideoItem, keyboardActionHandler: previewHandler)
        // DetailViewContent(item: sampleImageItem, keyboardActionHandler: previewHandler)
            .environmentObject(AppSettings())
    }
}
