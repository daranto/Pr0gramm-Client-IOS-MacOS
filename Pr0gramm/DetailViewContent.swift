// DetailViewContent.swift

import SwiftUI
import AVKit
import Combine
import os

struct DetailViewContent: View {
    let item: Item

    @EnvironmentObject var settings: AppSettings

    @State private var player: AVPlayer? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(guessAspectRatio(), contentMode: .fit)
                .overlay(mediaView())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

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
        .onDisappear {
            cleanupPlayerAndObservers()
        }
    }

    // MARK: - Media View & Player Logic

    @ViewBuilder
    private func mediaView() -> some View {
        if item.isVideo {
            if let url = item.imageUrl {
                VideoPlayer(player: player)
                    .onAppear { setupPlayer(url: url) }
            } else {
                Text("Video URL ungültig").foregroundColor(.red)
            }
        } else {
            AsyncImage(url: item.imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure(let error):
                    let _ = Self.logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)")
                    Text("Bild konnte nicht geladen werden").foregroundColor(.red)
                default:
                    ProgressView()
                }
            }
            .onAppear {
                 cleanupPlayerAndObservers()
            }
        }
    }

    // --- HIER SIND DIE FUNKTIONEN KORREKT DEFINIERT ---

    // Funktion zum Initialisieren und Konfigurieren des AVPlayers
    private func setupPlayer(url: URL) {
        Self.logger.debug("Setting up player for URL: \(url.absoluteString)")
        let needsNewPlayer = player == nil || player?.currentItem?.asset != AVURLAsset(url: url)

        if needsNewPlayer {
            cleanupPlayerAndObservers(keepPlayerInstance: true)
            player = AVPlayer(url: url)
        } else {
            Self.logger.debug("Reusing existing player.")
            if loopObserver == nil, let currentItem = player?.currentItem {
                 addLoopObserver(for: currentItem)
                 Self.logger.debug("Re-added missing loop observer.")
            }
        }

        guard let player = player else {
             Self.logger.error("Player instance is nil after setup attempt.")
             return
        }

        player.isMuted = settings.isVideoMuted
        Self.logger.info("Player initial mute state set to: \(self.settings.isVideoMuted)")

        if muteObserver == nil {
            self.muteObserver = player.observe(\.isMuted, options: [.new]) { observedPlayer, change in
                 guard let newMutedState = change.newValue else { return }
                 if self.settings.isVideoMuted != newMutedState {
                     Self.logger.info("User changed mute via player controls. New state: \(newMutedState)")
                     DispatchQueue.main.async {
                         self.settings.isVideoMuted = newMutedState
                     }
                 }
            }
             Self.logger.debug("Added mute KVO observer.")
        }

        if needsNewPlayer || loopObserver == nil, let currentItem = player.currentItem {
            addLoopObserver(for: currentItem)
        }

        player.play()
         Self.logger.debug("Player started (Autoplay)")
    }

    // Funktion zum Hinzufügen des Loop Observers
    private func addLoopObserver(for item: AVPlayerItem) {
        if let observer = self.loopObserver {
            NotificationCenter.default.removeObserver(observer)
            Self.logger.debug("Removed existing loop observer before adding new one.")
        }

        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] notification in
             Self.logger.debug("Video did play to end time. Seeking to zero.")
            player?.seek(to: .zero)
            player?.play()
        }
         Self.logger.debug("Added loop observer.")
    }

    // Funktion zum Aufräumen
    private func cleanupPlayerAndObservers(keepPlayerInstance: Bool = false) {
        Self.logger.debug("Cleaning up player and observers. Keep instance: \(keepPlayerInstance)")
        player?.pause()

        muteObserver?.invalidate()
        muteObserver = nil
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }

        if !keepPlayerInstance {
            player = nil
             Self.logger.debug("Player instance released.")
        }
    }

    // Hilfsfunktion für das Seitenverhältnis
    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 {
            return CGFloat(item.width) / CGFloat(item.height)
        }
        return 16.0 / 9.0 // Fallback
    }

} // Ende struct DetailViewContent

// --- KEINE extension DetailViewContent { ... } HIER MEHR ---

// MARK: - Preview für DetailViewContent (VOLLSTÄNDIG)
#Preview {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
     let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 1, up: 10, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 1200, audio: false, source: "http://example.com", flags: 2, user: "UserB", mark: 2)

    return NavigationStack {
        DetailViewContent(item: sampleVideoItem)
            .environmentObject(AppSettings())
    }
}
