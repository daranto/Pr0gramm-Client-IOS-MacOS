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

// --- FlowLayout (muss im Projekt vorhanden sein) ---
// struct FlowLayout: Layout { /* ... */ }

struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    @EnvironmentObject var settings: AppSettings
    @State private var player: AVPlayer? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    // --- NEU: Empfange Tags und Status von außen ---
    let tags: [ItemTag]
    let tagLoadingStatus: TagLoadingStatus // Verwende dasselbe Enum wie PagedDetailView

    // --- Entfernt: Eigene State-Variablen und API-Service ---
    // @State private var isLoadingTags = false // Nicht mehr benötigt
    // @State private var tagErrorMessage: String? = nil // Nicht mehr benötigt
    // private let apiService = APIService() // Nicht mehr benötigt

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")

    var body: some View {
        // --- NEU: Gesamten Inhalt in ScrollView packen ---
        ScrollView {
            VStack(spacing: 0) { // Bestehender VStack bleibt

                // --- Media View Container ---
                Group {
                    if item.isVideo {
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
                .frame(maxWidth: .infinity) // Max Breite ok, keine feste Höhe
                .clipped()
                .onAppear {
                     if item.isVideo, let url = item.imageUrl {
                         Self.logger.debug("Group onAppear for item \(item.id). Setting up player if video.")
                         setupPlayer(url: url)
                     } else if !item.isVideo {
                         Self.logger.debug("Group onAppear for item \(item.id). Ensuring cleanup if image.")
                         cleanupPlayerAndObservers()
                     }
                 }

                // --- Infos & Tags ---
                VStack(alignment: .leading, spacing: 8) { // Außen-VStack für Padding etc.
                    HStack { // Votes
                        Text("⬆️ \(item.up)")
                        Text("⬇️ \(item.down)")
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.bottom, 4) // Etwas Abstand zu den Tags

                    // --- Geändert: Tag-Anzeige verwendet übergebenen Status/Tags ---
                    switch tagLoadingStatus {
                    case .idle, .loading: // Zeige Ladeanzeige bei idle oder loading
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10) // Mehr Platz für Ladeanzeige
                    case .error(let errorMsg):
                        Text("Fehler beim Laden der Tags: \(errorMsg)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center) // Fehler zentriert
                    case .loaded:
                        if !tags.isEmpty {
                            // --- Verwende FlowLayout ---
                            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                ForEach(tags) { tag in
                                    Text(tag.tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.3))
                                        .foregroundColor(.primary)
                                        .cornerRadius(5)
                                        .lineLimit(1) // Sicherstellen, dass Tags nicht intern umbrechen
                                }
                            }
                            // --- Ende FlowLayout ---
                        } else {
                             // Optional: Platzhalter oder Text für keine Tags
                             Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    // --- Ende Tag-Anzeige ---

                }
                .padding(.vertical, 8)
                .padding(.horizontal) // Innenabstand für den Info/Tag-Bereich
                .frame(maxWidth: .infinity, alignment: .leading) // Nimmt volle Breite

            } // Ende äußerer VStack
        } // --- Ende ScrollView ---

        .frame(maxWidth: .infinity, maxHeight: .infinity) // Behält max. Größe
        .onAppear {
             Self.logger.debug("DetailViewContent for item \(item.id) appearing.")
             // Ladelogik wurde nach PagedDetailView verschoben
        }
        .onDisappear {
            Self.logger.debug("DetailViewContent for item \(item.id) disappearing.")
            cleanupPlayerAndObservers()
        }
    }

    // MARK: - Player Logic (unverändert)
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

// --- Preview (unverändert) ---
#Preview {
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1)
     let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 1, up: 10, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 1200, audio: false, source: "http://example.com", flags: 2, user: "UserB", mark: 2)

     let previewHandler = KeyboardActionHandler()
     previewHandler.selectNextAction = { print("Preview: Select Next") }
     previewHandler.selectPreviousAction = { print("Preview: Select Previous") }
     let previewTags = [
         ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"),
         ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag"),
         ItemTag(id: 3, confidence: 0.5, tag: "Noch ein Tag")
     ]

    return NavigationStack {
        DetailViewContent(
            item: sampleVideoItem,
            keyboardActionHandler: previewHandler,
            tags: previewTags,
            tagLoadingStatus: .loaded
        )
            .environmentObject(AppSettings())
    }
}
